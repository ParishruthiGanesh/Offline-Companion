import Foundation
import SwiftUI
import Combine
import AVFoundation
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

enum AssistantMode: String, CaseIterable, Identifiable, Sendable {
    case text = "Text", photo = "Photo"
    var id: String { rawValue }
    var modelName: String { self == .text ? "Meta Llama" : "SmolVLM (not Meta)" }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    var modelName: String = "Meta Llama"
    var photo: Data? = nil
}

@MainActor
final class ChatStore: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var status = "Set up the model to begin."
    @Published var error: String?
    @Published var busy = false
    @Published var ready = false
    @Published var hasModel = ModelFiles.exists
    @Published var elapsed: String?
    @Published var speechStatus: String?
    @Published private(set) var mode: AssistantMode = .text
    @Published var photoData: Data?
    private var selectedModelExists: Bool { mode == .text ? ModelFiles.exists : VisionFiles.exists }
    var readyStatus: String { "\(mode.modelName) ready • on-device \(mode == .text ? "text" : "photo test")" }
    private let engine = LocalLlama()
    private let speaker = AVSpeechSynthesizer()
    private var operation: Task<Void, Never>?

    override init() {
        super.init()
        speaker.delegate = self
        speaker.usesApplicationAudioSession = true
        if hasModel { load() }
    }

    func chooseMode(_ newMode: AssistantMode) {
        guard newMode != mode, !busy else { return }
        stopSpeech()
        busy = true
        ready = false
        messages.removeAll()
        photoData = nil
        input = ""
        error = nil
        elapsed = nil
        status = "Switching assistant mode…"
        operation = Task {
            await engine.unload()
            mode = newMode
            hasModel = selectedModelExists
            do {
                if hasModel { try await activateSelectedModel() }
                else { status = "Set up offline \(mode == .text ? "chat" : "photos") once to begin." }
            } catch { ready = false; self.error = error.localizedDescription; status = "Could not prepare the assistant. Try again." }
            busy = false
            operation = nil
        }
    }

    func choosePhoto(_ item: PhotosPickerItem) {
        guard mode == .photo, ready, !busy else { return }
        busy = true
        error = nil
        photoData = nil
        status = "Preparing a small photo on this device…"
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                guard let raw = try await item.loadTransferable(type: Data.self) else { throw VisionFiles.VisionFailure.image }
                try Task.checkCancellation()
                let task = Task.detached(priority: .userInitiated) { try PhotoPreparation.jpeg(raw) }
                let prepared = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                try Task.checkCancellation()
                photoData = prepared
                if input.isEmpty { input = "List the clearly visible objects. Say when you are unsure." }
                status = readyStatus
            } catch is CancellationError {
                status = readyStatus
            } catch {
                self.error = "Could not prepare the photo. It may need downloading from iCloud first. \(error.localizedDescription)"
                status = readyStatus
            }
        }
    }

    private func activateSelectedModel() async throws {
        hasModel = selectedModelExists
        guard hasModel else { return }
        status = "Getting your offline assistant ready…"
        if mode == .text { try await engine.load(from: ModelFiles.modelURL) }
        else { try await engine.load(from: VisionFiles.model.url, projectionURL: VisionFiles.projector.url) }
        try Task.checkCancellation()
        ready = true
        status = readyStatus
    }

    func load() {
        guard !busy, hasModel else { return }
        busy = true
        error = nil
        status = "Getting your offline assistant ready…"
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                try await activateSelectedModel()
            } catch is CancellationError {
                await engine.unload()
                ready = false
                status = "Loading cancelled."
            } catch {
                ready = false
                self.error = error.localizedDescription
                status = "Model could not load."
            }
        }
    }

    func download() {
        guard !busy, !ready else { return }
        busy = true
        error = nil
        status = mode == .text
            ? "Downloading and verifying 808 MB. Keep the app open."
            : "Downloading two image-model files (546 MB total). Keep the app open."
        operation = Task {
            defer { busy = false; operation = nil; hasModel = selectedModelExists }
            do {
                let selectedMode = mode
                let task = Task.detached(priority: .userInitiated) {
                    if selectedMode == .text { try await ModelFiles.download() }
                    else { try await VisionFiles.download() }
                }
                try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                try await activateSelectedModel()
            } catch is CancellationError {
                status = "Download cancelled."
            } catch {
                self.error = error.localizedDescription
                status = "Setup did not finish."
            }
        }
    }

    func importModel(from url: URL) {
        guard !busy, !ready else { return }
        busy = true
        error = nil
        status = "Copying and verifying the model…"
        operation = Task {
            defer { busy = false; operation = nil; hasModel = selectedModelExists }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let selectedMode = mode
                let task = Task.detached(priority: .userInitiated) {
                    if selectedMode == .text { try ModelFiles.install(from: url) }
                    else { try VisionFiles.install(from: url) }
                }
                try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                if selectedModelExists { try await activateSelectedModel() }
                else { status = "One file saved. Import the other image-model file too." }
            } catch is CancellationError {
                status = "Import cancelled."
            } catch {
                self.error = error.localizedDescription
                status = "Import did not finish."
            }
        }
    }

    func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ready, !busy, !question.isEmpty else { return }
        if mode == .photo && photoData == nil {
            error = "Choose a photo before asking an image question."
            return
        }
        stopSpeech()
        let photo = mode == .photo ? photoData : nil
        let answeringMode = mode
        messages.append(ChatMessage(isUser: true, text: question, photo: photo))
        input = ""
        busy = true
        error = nil
        elapsed = nil
        status = "Answering on this iPhone…"
        operation = Task {
            let start = Date()
            defer { busy = false; operation = nil }
            do {
                let answer: String
                if let photo { answer = try await engine.answerImage(photo, question: question) }
                else { answer = try await engine.answer(question) }
                try Task.checkCancellation()
                messages.append(ChatMessage(isUser: false, text: answer, modelName: answeringMode.modelName))
                elapsed = String(format: "%.1f seconds • generated on this device", Date().timeIntervalSince(start))
                status = readyStatus
            } catch is CancellationError {
                status = "Answer stopped."
            } catch {
                self.error = error.localizedDescription
                status = "Could not finish this answer."
            }
        }
    }

    func stop() { operation?.cancel(); stopSpeech() }
    func clear() {
        guard !busy else { return }
        messages.removeAll()
        photoData = nil
        elapsed = nil
        error = nil
        stopSpeech()
    }

    func stopSpeech() {
        speaker.stopSpeaking(at: .immediate)
        speechStatus = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stopSpeech()
        error = nil
        // Prefer a basic installed voice; accept other English locales as a fallback.
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let voice = voices.first { $0.language == "en-US" && $0.quality == .default }
            ?? voices.first { $0.language.hasPrefix("en") && $0.quality == .default }
            ?? voices.first { $0.language.hasPrefix("en") }
        guard let voice else {
            error = "No English voice was found. While online, download an English voice in iPhone Settings under Accessibility (search for Voices), then retry offline."
            return
        }
        do {
            // Playback makes explicit read-aloud audible even with the Silent switch on.
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audio.setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.volume = 1
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            speechStatus = "Starting voice. Check media volume and the selected audio output."
            speaker.speak(utterance)
        } catch {
            self.error = "Could not start audio: \(error.localizedDescription)"
            speechStatus = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.speaker.isSpeaking else { return }
            self.speechStatus = "Reading aloud. If silent, raise media volume and check headphones/Bluetooth output."
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finishSpeechIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finishSpeechIfIdle() }
    }

    private func finishSpeechIfIdle() {
        guard !speaker.isSpeaking else { return }
        speechStatus = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}


// Resize before model input; normalize EXIF orientation without keeping a full-resolution bitmap.
enum PhotoPreparation {
    static func jpeg(_ data: Data) throws -> Data {
        try Task.checkCancellation()
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw VisionFiles.VisionFailure.image }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 768,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw VisionFiles.VisionFailure.image
        }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw VisionFiles.VisionFailure.image
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw VisionFiles.VisionFailure.image }
        return output as Data
    }
}
