import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Optional on-device language model ("Smart AI") that turns a message into an `Interpretation`.
/// When it isn't downloaded or loaded, the assistant falls back to `CommandParser`.
@Observable @MainActor
final class LocalModel {
    static let shared = LocalModel()

    private static let repo = Repo.ID(namespace: "mlx-community", name: "Qwen3-1.7B-4bit")
    private static let filePatterns = ["*.safetensors", "*.json", "*.jinja"]

    private(set) var isDownloaded = false
    /// Fraction from 0 to 1 while downloading, otherwise nil.
    private(set) var downloadProgress: Double?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var container: ModelContainer?
    private var downloadTask: Task<Void, Never>?

    var isReady: Bool { container != nil }

    private init() {
        isDownloaded = localSnapshot() != nil
    }

    func download() {
        guard downloadProgress == nil else { return }
        downloadProgress = 0
        errorMessage = nil
        downloadTask = Task {
            do {
                _ = try await HubClient.default.downloadSnapshot(of: Self.repo, matching: Self.filePatterns) { progress in
                    self.downloadProgress = progress.fractionCompleted
                }
                isDownloaded = localSnapshot() != nil
            } catch is CancellationError {
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
            downloadProgress = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func load() async {
        guard container == nil, !isLoading, let directory = localSnapshot() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            Memory.cacheLimit = 20 * 1024 * 1024
            container = try await LLMModelFactory.shared.loadContainer(from: directory, using: TokenizerLoader())
        } catch {
            errorMessage = "Couldn't load Smart AI: \(error.localizedDescription)"
        }
    }

    func unload() {
        container = nil
        Memory.clearCache()
    }

    func delete() {
        cancelDownload()
        unload()
        try? FileManager.default.removeItem(at: HubCache.default.repoDirectory(repo: Self.repo, kind: .model))
        isDownloaded = false
    }

    /// The downloaded snapshot folder, once the weights are fully on disk.
    private func localSnapshot() -> URL? {
        let snapshots = HubCache.default.snapshotsDirectory(repo: Self.repo, kind: .model)
        let folders = (try? FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)) ?? []
        return folders.first { folder in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return files.contains { $0.hasSuffix(".safetensors") }
        }
    }

    /// Returns nil when the model isn't loaded or its reply isn't valid JSON.
    func interpret(_ text: String, categories: [String], lastQuestion: String?) async -> Interpretation? {
        guard let container else { return nil }

        let session = ChatSession(
            container,
            instructions: Self.instructions(categories: categories),
            generateParameters: GenerateParameters(maxTokens: 150, temperature: 0),
            additionalContext: ["enable_thinking": false]
        )
        let prompt = lastQuestion.map { "The app asked: \"\($0)\"\nMessage: \"\(text)\"" } ?? "Message: \"\(text)\""

        guard let output = try? await session.respond(to: prompt),
              let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"),
              start < end,
              var result = try? JSONDecoder().decode(Interpretation.self, from: Data(output[start...end].utf8))
        else { return nil }

        // Small models sometimes write "null" as a string instead of JSON null.
        for field in [\Interpretation.category, \.note, \.source, \.topic] {
            if let value = result[keyPath: field], ["", "null", "none"].contains(value.lowercased()) {
                result[keyPath: field] = nil
            }
        }
        return result
    }

    private static func instructions(categories: [String]) -> String {
        let categoryList = categories.isEmpty ? "(none yet)" : categories.joined(separator: ", ")
        return """
        You read messages sent to a budgeting app and reply with one JSON object and nothing else:
        {"intent": "spend" | "income" | "remaining" | "whatif" | "calculate" | "confirm" | "cancel" | "offtopic" | "none", "amount": number or null, "category": string or null, "note": string or null, "daysAgo": integer or null, "source": string or null, "topic": string or null}

        - spend: the user spent money. category must be one of: \(categoryList). Use null if it isn't clear which one. note is a short description of what it was for, or null.
        - income: the user adds a monthly income. source is its name, like "Salary".
        - remaining: the user asks how much is left or how much they spent. category is optional.
        - confirm: the user agrees (yes, ok, sure). cancel: the user declines or stops (no, cancel, never mind).
        - whatif: the user asks what would be left if they spent an amount, like "if I spend 500 on food, how much is left?" or "can I afford 3000?". Nothing gets logged. amount is what they would spend; category is optional.
        - calculate: the user only wants arithmetic worked out, like "what's 1500 minus 320?".
        - offtopic: the message has nothing to do with the user's own budget, like politics, corruption, law, education, religion, health or investing advice, news, sports, coding, jokes, or general knowledge. topic is a short name for the subject, like "politics". A message with an amount, a category, or money the user spent or earned is never offtopic.
        - none: anything else, including a short answer to the app's question. Fill in only the fields the answer gives.
        - If the app asked whether it was spending or income, the intent is spend or income.
        - "1.5k" means 1500. daysAgo is 0 for today and 1 for yesterday.
        - Use null for anything the message doesn't say. Never invent an amount or category.

        Examples, assuming the categories are Food and Transport:
        Message: "spent 250 on lunch yesterday" -> {"intent":"spend","amount":250,"category":"Food","note":"Lunch","daysAgo":1,"source":null,"topic":null}
        Message: "i spent 200" -> {"intent":"spend","amount":200,"category":null,"note":null,"daysAgo":null,"source":null,"topic":null}
        Message: "add my salary, 25k a month" -> {"intent":"income","amount":25000,"category":null,"note":null,"daysAgo":null,"source":"Salary","topic":null}
        Message: "create a side hustle as income with the amount of 3000" -> {"intent":"income","amount":3000,"category":null,"note":null,"daysAgo":null,"source":"Side Hustle","topic":null}
        Message: "how much do I have left for transport?" -> {"intent":"remaining","amount":null,"category":"Transport","note":null,"daysAgo":null,"source":null,"topic":null}
        Message: "if i spend 300 on lunch how much will be left?" -> {"intent":"whatif","amount":300,"category":"Food","note":null,"daysAgo":null,"source":null,"topic":null}
        Message: "who should I vote for president?" -> {"intent":"offtopic","amount":null,"category":null,"note":null,"daysAgo":null,"source":null,"topic":"politics"}
        Message: "what is the capital of France?" -> {"intent":"offtopic","amount":null,"category":null,"note":null,"daysAgo":null,"source":null,"topic":"general knowledge"}
        The app asked: "What category was that for?" Message: "the food one" -> {"intent":"none","amount":null,"category":"Food","note":null,"daysAgo":null,"source":null,"topic":null}
        The app asked: "Was that an expense or income?" Message: "it was income" -> {"intent":"income","amount":null,"category":null,"note":null,"daysAgo":null,"source":null,"topic":null}
        """
    }
}

private struct TokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    }
}