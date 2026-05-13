import AVFoundation
import Foundation
import Speech
import UIKit

@MainActor
final class RecordingTranscriptionController: ObservableObject {
    @Published private(set) var committedTranscript = ""
    @Published private(set) var currentSegmentText = ""
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var authorizationMessage: String?
    @Published var audioLevel: CGFloat = 0
    @Published var timestampedLines: [String] = []

    var transcript: String {
        [committedTranscript, currentSegmentText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private let audioEngine = AVAudioEngine()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var startDate: Date?
    private var activeSegmentStart: TimeInterval = 0
    private var isStopping = false
    private var audioFile: AVAudioFile?
    private(set) var audioFileURL: URL?
    private var pendingFileURL: URL?
    private var lastRecognitionStart: Date?
    private var recognitionMonitorTask: Task<Void, Never>?
    private let recognitionRefreshInterval: TimeInterval = 45 * 60

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
            try reserveRecordingURL()
            committedTranscript = transcript
            activeSegmentStart = 0
            try startSpeechRecognition()
            startDate = .now
            isRecording = true
            isPaused = false
            UIApplication.shared.isIdleTimerDisabled = true
            lastRecognitionStart = .now
            startRecognitionMonitor()
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
            lastRecognitionStart = .now
        } catch {
            authorizationMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning || isPaused else { return }

        isStopping = true
        recognitionMonitorTask?.cancel()
        recognitionMonitorTask = nil
        commitCurrentSegment()
        stopSpeechRecognition()
        isRecording = false
        isPaused = false
        audioLevel = 0
        audioFile = nil
        isStopping = false
        lastRecognitionStart = nil
        UIApplication.shared.isIdleTimerDisabled = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func reserveRecordingURL() throws {
        let folderURL = try recordingsFolderURL()
        pendingFileURL = folderURL.appendingPathComponent("meeting-\(UUID().uuidString).caf")
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
        inputNode.removeTap(onBus: 0)

        // Prepare the engine so the input node reports the actual hardware
        // format the tap will deliver. Reading the format before prepare()
        // (e.g. while the session is still settling on iPad/voiceChat) yields
        // a stale format; writes to AVAudioFile then silently fail and the
        // saved .caf ends up header-only (plays back as 0:00).
        audioEngine.prepare()
        let format = inputNode.outputFormat(forBus: 0)

        // Create the AVAudioFile on initial start using the exact format the
        // tap will deliver. Skip on resume after pause (audioFile already open).
        if audioFile == nil, let url = pendingFileURL {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            audioFileURL = url
            DataProtectionService.protectFile(at: url)
            pendingFileURL = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            try? self?.audioFile?.write(from: buffer)
            Task { @MainActor in
                self?.audioLevel = Self.normalizedLevel(from: buffer)
            }
        }

        try audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.updateTranscript(with: result.bestTranscription.formattedString)
                    if result.isFinal {
                        self?.commitCurrentSegment()
                    }
                }

                if let error, self?.isStopping != true {
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
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func updateTranscript(with partial: String) {
        currentSegmentText = partial.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func startRecognitionMonitor() {
        recognitionMonitorTask?.cancel()
        recognitionMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, self.isRecording, !self.isPaused else { continue }
                guard let last = self.lastRecognitionStart else { continue }
                if Date().timeIntervalSince(last) >= self.recognitionRefreshInterval {
                    self.refreshRecognition()
                }
            }
        }
    }

    private func refreshRecognition() {
        commitCurrentSegment()

        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        currentSegmentText = ""
        activeSegmentStart = elapsedTime
        committedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.updateTranscript(with: result.bestTranscription.formattedString)
                    if result.isFinal {
                        self?.commitCurrentSegment()
                    }
                }
                if error != nil, self?.isStopping != true {
                    // Silent failure on background refresh — audio keeps recording
                }
            }
        }

        lastRecognitionStart = .now
    }
}
