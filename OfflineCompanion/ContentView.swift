import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import Speech
import AVFoundation
import Combine
import UIKit

struct ContentView: View {
    @StateObject private var store = ChatStore()
    @StateObject private var voice = OfflineVoiceInput()
    @State private var importing = false
    @State private var showInfo = false
    @State private var confirmDownload = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    Text(store.status).font(.caption)
                    Spacer(minLength: 0)
                    if store.busy { ProgressView() }
                }
                .padding().background(Color.teal.opacity(0.10))

                Picker("Assistant mode", selection: Binding(get: { store.mode }, set: { store.chooseMode($0) })) {
                    ForEach(AssistantMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8).disabled(store.busy)

                if store.ready { chat } else { setup }

                if let speechStatus = store.speechStatus {
                    HStack {
                        Text(speechStatus).font(.caption)
                        Spacer()
                        Button("Stop audio") { store.stopSpeech() }.font(.caption.bold())
                    }.padding().background(Color.teal.opacity(0.10))
                }

                if let error = store.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Error: \(error)")
                }
            }
            .onChange(of:store.mode) { _, _ in voice.stop() }
            .onChange(of:store.busy) { _, value in if value { voice.stop() } }
            .onChange(of:voice.transcript) { _, value in if !value.isEmpty { store.input = value } }
            .onChange(of:store.speechStatus) { _, value in if value != nil { voice.stop() } }
            .onDisappear { voice.stop() }
            .onReceive(NotificationCenter.default.publisher(for:UIApplication.didEnterBackgroundNotification)) { _ in voice.stop() }
            .navigationTitle("Offline Companion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showInfo = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About this build")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.busy {
                        Button("Stop") { store.stop() }
                    } else if store.ready {
                        Button("Clear") { store.clear() }
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { store.importModel(from: url) }
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .onChange(of: photoItem) { _, item in
                if let item { store.choosePhoto(item); photoItem = nil }
            }
            .confirmationDialog(store.mode == .text ? "Download Meta Llama 3.2 1B?" : "Download SmolVLM image model?", isPresented: $confirmDownload, titleVisibility: .visible) {
                Button(store.mode == .text ? "Download 808 MB" : "Download two files — 546 MB") { store.download() }
            } message: {
                Text("Requires internet during setup and about 2 GB free storage for verification. Review the model source and license first. After setup, questions and selected photos are processed on this device.")
            }
            .sheet(isPresented: $showInfo) { about }
        }
        .tint(.teal)
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 44)).foregroundStyle(.teal).accessibilityHidden(true)
                Text("Your assistant, on your phone.").font(.title2.bold())
                Text(store.mode == .text
                     ? "Text questions use Meta Llama 3.2 1B Instruct. Once saved, no internet or API key is needed for answers."
                     : "Photo questions use SmolVLM 500M, a separate model from Hugging Face, not Meta. This small model can miss objects and invent details. Use this mode to test image descriptions.")
                Label(store.mode == .text ? "Meta Llama 3.2 1B • Q4_K_M" : "SmolVLM 500M • Q8_0 + image component", systemImage: "cpu")
                    .font(.subheadline)
                if store.hasModel {
                    if store.busy { ProgressView("Getting ready…") }
                    else { Button("Try again") { store.load() }.buttonStyle(.borderedProminent) }
                    Text("Offline files are already saved. The assistant opens automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button(store.mode == .text ? "Set up offline chat — 808 MB" : "Set up offline photos — 546 MB") { confirmDownload = true }
                        .buttonStyle(.borderedProminent).disabled(store.busy)
                    Text("One-time download while online. After setup, just open the app and chat offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup("Advanced: import existing files") {
                        Button("Import file") { importing = true }.disabled(store.busy)
                        Text(store.mode == .text ? ModelFiles.filename : "\(VisionFiles.model.name)\n\(VisionFiles.projector.name)")
                            .font(.caption).textSelection(.enabled)
                    }
                }
                if store.mode == .text {
                    Link("Review Meta Llama 3.2 license", destination: URL(string: "https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/blob/main/LICENSE.txt")!)
                    Link("Model source and download details", destination: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF")!)
                } else {
                    Link("Review SmolVLM model card and license", destination: URL(string: "https://huggingface.co/HuggingFaceTB/SmolVLM-500M-Instruct")!)
                    Link("Image files and download details", destination: URL(string: "https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF")!)
                    Text("Switching modes unloads the previous model before loading the next one.").font(.footnote)
                }
                Text("Built with Llama. Quantized weights by bartowski. Local inference uses llama.cpp through LlamaSwift.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if store.messages.isEmpty {
                            Text("Try a question, then repeat with Wi-Fi and cellular data switched off.")
                                .foregroundStyle(.secondary)
                            if store.mode == .text {
                                Button("Help me draft a short check-in message.") {
                                    store.input = "Help me draft a short check-in message to my family."
                                }.buttonStyle(.bordered)
                            } else {
                                Text("Choose a photo below. No photo is sent to a server. This test cannot establish a safe route or identify your exact location.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(store.messages) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(message.isUser ? "You" : "\(message.modelName) • local answer")
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                if let data = message.photo, let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .accessibilityLabel("Photo attached to this question")
                                }
                                Text(message.text).textSelection(.enabled)
                                if !message.isUser {
                                    Button { store.speak(message.text) } label: {
                                        Label("Read aloud", systemImage: "speaker.wave.2")
                                    }.font(.caption)
                                }
                            }
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(message.isUser ? Color.teal.opacity(0.12) : Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .id(message.id)
                        }
                        if let elapsed = store.elapsed { Text(elapsed).font(.caption).foregroundStyle(.secondary) }
                        if store.busy { Text("Generating…").foregroundStyle(.secondary) }
                    }.padding()
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let last = store.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if store.mode == .photo {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose photo", systemImage: "photo")
                    }.disabled(store.busy)
                    if let data = store.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 56, height: 56)
                        Button("Remove") { store.photoData = nil }.disabled(store.busy)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal).padding(.vertical, 8)
            }
            Text("AI can make mistakes. Each question is independent. No SOS messages are sent.")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8)
            if let message = voice.message {
                Text(message).font(.caption).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal)
            }
            HStack(alignment: .bottom) {
                Button {
                    if voice.recording || voice.starting { voice.stop() }
                    else { store.stopSpeech(); voice.start() }
                } label: { Image(systemName:voice.recording ? "stop.circle.fill" : "mic.fill").font(.title2) }
                    .accessibilityLabel(voice.recording ? "Stop voice input" : "Speak your question")
                    .disabled(store.busy)
                TextField("Ask a question…", text: $store.input, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.roundedBorder).disabled(store.busy)
                Button { store.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .accessibilityLabel("Send question")
                    .disabled(store.busy || voice.recording || voice.starting || store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (store.mode == .photo && store.photoData == nil))
            }.padding().background(.bar)
        }
    }

    private var about: some View {
        NavigationStack {
            List {
                Section("Working scope of this build") {
                    Text("Local Meta Llama text questions, Apple on-device voice input when available, an experimental SmolVLM photo test, verified model setup, read-aloud using an installed voice, GPS readings, a saved meeting point with a compass direction arrow, consent-based nearby location snapshots and foreground live sharing. New experimental screens add a compact offline map and paired Bluetooth background sharing. Only one model is loaded at a time.")
                    Text("You verified offline text, relaunching and read-aloud on your iPhone 13. Offline photos work in device tests, but object labels and spatial answers can be wrong.")
                }
                Section("Still to build") {
                    Text("Video understanding, full-country street maps, spoken turn-by-turn navigation, verified accounts and production validation of background sharing and offline walking routes.")
                }
                Section("Connection and privacy") {
                    Text("Voice input uses Apple on-device speech recognition only when supported and available for English (US); it does not send audio to an online transcription service. Tap the microphone, speak, stop, review the text, then send. Unsupported or missing speech resources show an error. Internet is used when you explicitly download the model or open a source link. People uses a saved, accepted Bluetooth pairing with separate opt-in location sharing. Background delivery depends on iOS and Bluetooth range. Map downloads send the chosen area to a public Overpass service; country outlines are bundled. Chat inference and selected photos stay on the device. Photos are resized to at most 768 pixels on the longest side. Chats are held in memory and are not uploaded or saved between launches.")
                    Text("No satellite connection, live alerts, or rescue dispatch is provided.")
                }
            }
            .navigationTitle("About this build")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInfo = false } } }
        }
    }
}

@MainActor
private final class OfflineVoiceInput: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var starting = false
    @Published private(set) var transcript = ""
    @Published private(set) var message: String?
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false
    private var generation = UUID()

    func start() {
        guard !recording, !starting else { return }
        starting = true; message = "Checking offline voice input…"
        let token = UUID(); generation = token
        Task {
            let permission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning:$0) }
            }
            guard generation == token else { return }
            guard permission == .authorized else {
                starting = false; message = "Allow Speech Recognition in iPhone Settings > Apps > Offline Companion."; return
            }
            let microphone = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning:$0) }
            }
            guard generation == token else { return }
            guard microphone else {
                starting = false; message = "Allow Microphone access in iPhone Settings > Apps > Offline Companion."; return
            }
            guard let recognizer = SFSpeechRecognizer(locale:Locale(identifier:"en-US")), recognizer.supportsOnDeviceRecognition else {
                starting = false; message = "Offline English (US) speech recognition is unavailable on this phone. Type your question instead."; return
            }
            self.recognizer = recognizer
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            do {
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.record,mode:.measurement,options:[.duckOthers])
                try audio.setActive(true,options:.notifyOthersOnDeactivation)
                let input = engine.inputNode
                let format = input.outputFormat(forBus:0)
                guard format.sampleRate > 0, format.channelCount > 0 else {
                    stop(); message = "No microphone input is available."; return
                }
                input.installTap(onBus:0,bufferSize:1024,format:format) { buffer, _ in request.append(buffer) }
                tapped = true; transcript = ""
                task = recognizer.recognitionTask(with:request) { [weak self] result, error in
                    let text = result?.bestTranscription.formattedString
                    let final = result?.isFinal ?? false
                    let failed = error != nil
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        if let text { self.transcript = text }
                        if final || failed {
                            self.stop()
                            self.message = failed ? "Offline recognition stopped. Speech resources may be unavailable. Review any captured text or type your question." : "Review your question, then tap Send."
                        }
                    }
                }
                engine.prepare(); try engine.start()
                starting = false; recording = true
                message = "Listening offline in English (US). Tap Stop, review the text, then Send."
            } catch {
                stop(); message = "Could not start offline voice input. Check microphone access and try again."
            }
        }
    }

    func stop() {
        let wasActive = starting || recording || tapped
        generation = UUID(); starting = false; recording = false
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus:0); tapped = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; recognizer = nil
        if wasActive {
            try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
            message = transcript.isEmpty ? "Voice input stopped. Tap the microphone to try again." : "Review your question, then tap Send."
        }
    }
}
