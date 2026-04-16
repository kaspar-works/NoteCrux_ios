import AVFoundation
import Foundation
import Speech

@MainActor
final class RecordingTranscriptionController: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var authorizationMessage: String?
    @Published var audioLevel: CGFloat = 0
    @Published var timestampedLines: [String] = []

    private let audioEngine = AVAudioEngine()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var startDate: Date?
    private var committedTranscript = ""
    private var activeSegmentStart: TimeInterval = 0
    private var currentSegmentText = ""
    private var audioFile: AVAudioFile?
    private(set) var audioFileURL: URL?

    var elapsedTime: TimeInterval {
        guard let startDate else { return 0 }
        return Date().timeIntervalSince(startDate)
    }

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let microphoneGranted = await AVAudioApplication.requestRecordPermission()

        guard speechStatus == .authorized, microphoneGranted else {
            authorizationMessage = "Microphone and Speech Recognition permissions are required for local transcription."
            return false
        }

        authorizationMessage = nil
        return true
    }

    func start(localeIdentifier: String = "en-US") async {
        guard !isRecording else { return }
        guard await requestPermissions() else { return }

        do {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
            try configureAudioSession()
            try prepareAudioFile()
            committedTranscript = transcript
            activeSegmentStart = 0
            try startSpeechRecognition()
            startDate = .now
            isRecording = true
            isPaused = false
        } catch {
            authorizationMessage = error.localizedDescription
            stop()
        }
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        commitCurrentSegment()
        stopSpeechRecognition()
        isPaused = true
        audioLevel = 0
    }

    func resume() {
        guard isRecording, isPaused else { return }

        do {
            try configureAudioSession()
            committedTranscript = transcript
            activeSegmentStart = elapsedTime
            try startSpeechRecognition()
            isPaused = false
        } catch {
            authorizationMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning || isPaused else { return }

        commitCurrentSegment()
        stopSpeechRecognition()
        isRecording = false
        isPaused = false
        audioLevel = 0
        audioFile = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func prepareAudioFile() throws {
        let folderURL = try recordingsFolderURL()
        let fileURL = folderURL.appendingPathComponent("meeting-\(UUID().uuidString).caf")
        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        audioFileURL = fileURL
        DataProtectionService.protectFile(at: fileURL)
    }

    private func recordingsFolderURL() throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderURL = documentsURL.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        DataProtectionService.protectFolder(at: folderURL)
        return folderURL
    }

    private func startSpeechRecognition() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        currentSegmentText = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            try? self?.audioFile?.write(from: buffer)
            Task { @MainActor in
                self?.audioLevel = Self.normalizedLevel(from: buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.updateTranscript(with: result.bestTranscription.formattedString)
                    if result.isFinal {
                        self?.commitCurrentSegment()
                    }
                }

                if let error {
                    self?.authorizationMessage = error.localizedDescription
                    self?.stop()
                }
            }
        }
    }

    private func stopSpeechRecognition() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func updateTranscript(with partial: String) {
        currentSegmentText = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [committedTranscript, currentSegmentText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        transcript = combined
    }

    private func commitCurrentSegment() {
        let cleanedSegment = currentSegmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSegment.isEmpty else { return }

        timestampedLines.append("[\(Self.formatTimestamp(activeSegmentStart))] \(cleanedSegment)")
        committedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        currentSegmentText = ""
        activeSegmentStart = elapsedTime
    }

    private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for frame in 0..<frameLength {
            sum += abs(channelData[frame])
        }

        let average = sum / Float(frameLength)
        return CGFloat(min(max(average * 18, 0), 1))
    }

    private static func formatTimestamp(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
