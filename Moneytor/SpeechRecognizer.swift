import Accelerate
import AVFoundation
@preconcurrency import Speech

/// Live English speech-to-text using Apple's built-in recognizer, on-device when supported.
@Observable @MainActor
final class SpeechRecognizer {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var errorMessage: String?
    /// Recent input loudness from 0 (silence) to 1 (loud), oldest first, sampled 20 times a second.
    private(set) var levels: [Float] = []

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Loudest level heard since the waveform last sampled it.
    private var pendingLevel: Float?
    private var levelTask: Task<Void, Never>?

    func start() async {
        guard !isRecording else { return }
        transcript = ""
        errorMessage = nil
        levels = []

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized, await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Allow microphone and speech recognition access in Settings to talk to the assistant."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request

            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { @Sendable [weak self] buffer, _ in
                request.append(buffer)
                guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                var rms: Float = 0
                vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
                // A quiet room sits around -50 dB and close, loud speech near -10 dB.
                let decibels = 20 * log10(max(rms, 0.000_001))
                let level = min(max((decibels + 50) / 40, 0), 1)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    pendingLevel = max(pendingLevel ?? 0, level)
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            // Sample on a fixed clock so the waveform scrolls evenly whatever buffer size the hardware uses.
            levelTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard let self else { return }
                    levels.append(pendingLevel ?? levels.last ?? 0)
                    if levels.count > 120 { levels.removeFirst(levels.count - 120) }
                    pendingLevel = nil
                }
            }

            task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isDone = error != nil || result?.isFinal == true
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    if let text { self.transcript = text }
                    if isDone { self.stop() }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning || request != nil else { return }
        // Tear down fully even if the engine already stopped on its own (e.g. an audio interruption),
        // then release the mic so it only listens while the button is held. Spoken replies use playback.
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .spokenAudio)
        request?.endAudio()
        task?.cancel()
        levelTask?.cancel()
        request = nil
        task = nil
        levelTask = nil
        pendingLevel = nil
        isRecording = false
    }
}
