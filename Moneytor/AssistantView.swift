import AVFoundation
import SwiftData
import SwiftUI

struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("assistantSpeaksReplies") private var speaksReplies = false
    @State private var assistant = Assistant()
    @State private var speech = SpeechRecognizer()
    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var input = ""
    @State private var isShowingSmartAI = false
    /// True while the mic button is held down, which can be before recording actually starts.
    @State private var isHoldingMic = false
    @GestureState private var isPressingMic = false
    @State private var recordingStart = Date.now
    @State private var isShowingHoldHint = false
    @FocusState private var inputFocused: Bool
    private let localModel = LocalModel.shared

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Button { isShowingSmartAI = true } label: {
                            Label(smartAIStatus, systemImage: "cpu")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.bottom, 4)

                        ForEach(assistant.messages) { message in
                            MessageBubble(message: message)
                        }
                        if assistant.isThinking {
                            AIIcon(size: 22, isAnimating: true)
                                .padding(12)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistant.messages.count) {
                    withAnimation { proxy.scrollTo(assistant.messages.last?.id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        AIIcon(size: 18, isAnimating: assistant.isThinking)
                        Text("Assistant")
                            .font(.headline)
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $speaksReplies) {
                        Label("Spoken Replies", systemImage: speaksReplies ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .toggleStyle(.button)
                    Button("Smart AI", systemImage: "cpu") { isShowingSmartAI = true }
                }
            }
            .sheet(isPresented: $isShowingSmartAI) { SmartAISettings() }
        }
        // Otherwise a slight downward move while holding the mic can start closing the sheet.
        .interactiveDismissDisabled(isHoldingMic || speech.isRecording)
        .task { await localModel.load() }
        .onChange(of: localModel.isDownloaded) { _, isDownloaded in
            if isDownloaded { Task { await localModel.load() } }
        }
        .onChange(of: speaksReplies) { _, isOn in
            if !isOn { synthesizer.stopSpeaking(at: .immediate) }
        }
        .onChange(of: speech.isRecording) { wasRecording, isRecording in
            if wasRecording && !isRecording { send(speech.transcript) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: speech.isRecording)
        .onChange(of: assistant.messages.count) {
            guard speaksReplies, let last = assistant.messages.last, !last.fromUser else { return }
            let utterance = AVSpeechUtterance(string: last.text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
        }
        .onDisappear {
            speech.stop()
            synthesizer.stopSpeaking(at: .immediate)
            localModel.unload()
        }
    }

    private var smartAIStatus: String {
        if localModel.isReady { return "Smart AI is on" }
        if localModel.isLoading { return "Loading Smart AI…" }
        if localModel.isDownloaded { return "Smart AI couldn't load. Tap for details." }
        return "Basic mode. Tap to get Smart AI for more flexible understanding."
    }

    private var inputBar: some View {
        VStack(spacing: 10) {
            if let last = assistant.messages.last, !last.fromUser, !last.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(last.suggestions, id: \.self) { suggestion in
                            Button(suggestion) { send(suggestion) }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .tint(suggestion == "Cancel" ? .red : .accentColor)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if speech.isRecording {
                // Live subtitle above the waveform. It only goes into the chat once the mic is released.
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                            .id("subtitle")
                    }
                    // Grows with the words up to about three lines, then keeps the latest ones in view.
                    .frame(maxHeight: 90)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: speech.transcript) {
                        proxy.scrollTo("subtitle", anchor: .bottom)
                    }
                }
                .transition(.opacity)
                .accessibilityLabel(speech.transcript.isEmpty ? "Listening" : "You're saying: \(speech.transcript)")
            } else if let error = speech.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if isShowingHoldHint {
                Text("Hold the mic while you talk, then let go to send.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            // The mic button stays in one place in this stack so its hold gesture survives the layout switch.
            HStack(spacing: 8) {
                if speech.isRecording {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        TimelineView(.periodic(from: recordingStart, by: 1)) { timeline in
                            Text(Duration.seconds(max(timeline.date.timeIntervalSince(recordingStart), 0)),
                                 format: .time(pattern: .minuteSecond))
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                        Waveform(levels: speech.levels)
                            .frame(height: 28)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                } else {
                    TextField("Message", text: $input)
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .onSubmit { send(input) }
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }

                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background {
                        // Pulses with the voice so it's clear the mic is picking you up.
                        Circle()
                            .fill(Color.red.opacity(0.25))
                            .scaleEffect(speech.isRecording ? 1.2 + CGFloat(speech.levels.last ?? 0) * 0.6 : 1)
                            .animation(.easeOut(duration: 0.1), value: speech.levels.last)
                    }
                    .background(isHoldingMic ? Color.red : Color.accentColor, in: Circle())
                    .scaleEffect(isHoldingMic ? 1.15 : 1)
                    .animation(.spring(duration: 0.25), value: isHoldingMic)
                    .opacity(assistant.isThinking ? 0.4 : 1)
                    // Gesture state resets when the touch is cancelled too (onEnded isn't called then),
                    // so listening always stops once the finger is no longer on the button.
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($isPressingMic) { _, isPressing, _ in isPressing = true }
                    )
                    .onChange(of: isPressingMic) { _, isPressing in
                        if isPressing { startListening() } else { stopListening() }
                    }
                    .accessibilityLabel(speech.isRecording ? "Stop and send" : "Hold to talk")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        if speech.isRecording { stopListening() } else { startListening() }
                    }

                if !speech.isRecording {
                    Button("Send", systemImage: "arrow.up.circle.fill") { send(input) }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 36))
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || assistant.isThinking)
                }
            }
            .padding(.horizontal)

            if speech.isRecording {
                Text("Release to send")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .background(.bar)
        .animation(.default, value: speech.isRecording)
        .animation(.default, value: isShowingHoldHint)
    }

    private func startListening() {
        guard !isHoldingMic, !assistant.isThinking else { return }
        isHoldingMic = true
        isShowingHoldHint = false
        inputFocused = false
        synthesizer.stopSpeaking(at: .immediate)
        recordingStart = .now
        Task {
            await speech.start()
            // The finger may lift while permission prompts are up, before recording began.
            if !isHoldingMic { speech.stop() }
        }
    }

    private func stopListening() {
        guard isHoldingMic else { return }
        isHoldingMic = false
        // A quick tap records nothing, so explain how the button works.
        if speech.transcript.isEmpty && Date.now.timeIntervalSince(recordingStart) < 0.6 {
            isShowingHoldHint = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                isShowingHoldHint = false
            }
        }
        speech.stop()
    }

    private func send(_ text: String) {
        input = ""
        Task { await assistant.send(text, in: context) }
    }
}

/// Scrolling bars of recent loudness, newest on the right, like a voice recorder.
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geometry in
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 2
            let count = max(Int((geometry.size.width + spacing) / (barWidth + spacing)), 1)
            let recent = levels.suffix(count)
            let bars = Array(repeating: Float(0), count: count - recent.count) + recent

            HStack(alignment: .center, spacing: spacing) {
                ForEach(bars.indices, id: \.self) { index in
                    Capsule()
                        .fill(bars[index] > 0 ? Color.red : Color.secondary.opacity(0.4))
                        .frame(width: barWidth, height: max(barWidth, CGFloat(bars[index]) * geometry.size.height))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
        }
    }
}

private struct MessageBubble: View {
    let message: Assistant.Message

    var body: some View {
        Text(message.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(message.fromUser ? .white : .primary)
            .background(message.fromUser ? Color.accentColor : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
            .padding(message.fromUser ? .leading : .trailing, 40)
    }
}

private struct SmartAISettings: View {
    @Environment(\.dismiss) private var dismiss
    private let localModel = LocalModel.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Smart AI runs a small language model (Qwen3 1.7B) entirely on your iPhone, so it understands more flexible phrasing than basic mode. What you type never leaves your phone.")
                        .font(.callout)
                }

                Section {
                    if localModel.isDownloaded {
                        LabeledContent("Status", value: localModel.isReady ? "On" : localModel.isLoading ? "Loading…" : "Downloaded")
                        Button("Delete Model", role: .destructive) { localModel.delete() }
                    } else if let progress = localModel.downloadProgress {
                        ProgressView(value: progress) {
                            Text("Downloading…")
                        } currentValueLabel: {
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                        }
                        Button("Cancel Download", role: .destructive) { localModel.cancelDownload() }
                    } else {
                        Button("Download (about 1 GB)", systemImage: "arrow.down.circle") { localModel.download() }
                    }
                } footer: {
                    if !localModel.isDownloaded {
                        Text("Wi-Fi recommended. Internet is only needed for the download. Basic mode keeps working without it.")
                    }
                }

                if let error = localModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Smart AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
