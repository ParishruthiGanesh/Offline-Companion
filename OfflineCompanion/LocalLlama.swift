import Foundation
import LlamaSwift

/// All llama.cpp state lives on this actor, away from the UI actor.
actor LocalLlama {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vision: OpaquePointer?
    private static let backend: Void = { llama_backend_init() }()
    private let contextSize = 2048
    private let answerLimit = 192

    enum Failure: LocalizedError {
        case load, context, tokenize, tooLong, decode, empty, image
        var errorDescription: String? {
            switch self {
            case .load: return "Could not load the model. Close other apps and try again."
            case .context: return "Not enough resources to create the model context. Restart the app and try again."
            case .tokenize: return "The model could not read this question."
            case .tooLong: return "This question is too long. Please shorten it."
            case .decode: return "Local generation failed. Try a shorter question or restart the app."
            case .image: return "Could not process the photo or image component. Try one clear, smaller photo."
            case .empty: return "The model returned no answer. Try rephrasing your question."
            }
        }
    }

    func load(from url: URL, projectionURL: URL? = nil) throws {
        if model != nil { return }
        _ = Self.backend
        try Task.checkCancellation()
        var params = llama_model_default_params()
        #if targetEnvironment(simulator)
        params.n_gpu_layers = 0
        #else
        params.n_gpu_layers = -1
        #endif
        guard let loaded = url.path.withCString({ llama_model_load_from_file($0, params) }) else {
            throw Failure.load
        }
        var ctx = llama_context_default_params()
        ctx.n_ctx = UInt32(contextSize)
        ctx.n_batch = 128
        ctx.n_ubatch = 128
        ctx.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1)))
        ctx.n_threads_batch = ctx.n_threads
        guard let created = llama_init_from_model(loaded, ctx) else {
            llama_model_free(loaded)
            throw Failure.context
        }
        if let projectionURL {
            var visionParams = mtmd_context_params_default()
            visionParams.n_threads = ctx.n_threads
            visionParams.print_timings = false
            visionParams.warmup = false
            #if targetEnvironment(simulator)
            visionParams.use_gpu = false
            #endif
            guard let createdVision = projectionURL.path.withCString({ mtmd_init_from_file($0, loaded, visionParams) }) else {
                llama_free(created)
                llama_model_free(loaded)
                throw Failure.image
            }
            guard mtmd_support_vision(createdVision) else {
                mtmd_free(createdVision)
                llama_free(created)
                llama_model_free(loaded)
                throw Failure.image
            }
            vision = createdVision
        }
        model = loaded
        context = created
    }

    func unload() {
        if let vision { mtmd_free(vision) }
        vision = nil
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
    }

    func answer(_ question: String) throws -> String {
        guard let model, let context, let vocab = llama_model_get_vocab(model) else { throw Failure.load }
        try Task.checkCancellation()
        // Each question starts from a clean context: no hidden previous-turn state.
        llama_memory_clear(llama_get_memory(context), true)
        let prompt = PromptBuilder.make(question)
        let bytes = prompt.utf8.count
        let needed = prompt.withCString { llama_tokenize(vocab, $0, Int32(bytes), nil, 0, false, true) }
        guard needed < 0, needed != Int32.min else { throw Failure.tokenize }
        let count = Int(-needed)
        guard count + answerLimit < contextSize else { throw Failure.tooLong }
        var tokens = [llama_token](repeating: 0, count: count)
        let actual = prompt.withCString { llama_tokenize(vocab, $0, Int32(bytes), &tokens, Int32(count), false, true) }
        guard actual > 0 else { throw Failure.tokenize }
        tokens = Array(tokens.prefix(Int(actual)))

        var batch = llama_batch_init(128, 0, 1)
        defer { llama_batch_free(batch) }
        var position = 0
        for start in stride(from: 0, to: tokens.count, by: 128) {
            try Task.checkCancellation()
            let part = Array(tokens[start..<min(start + 128, tokens.count)])
            fill(&batch, tokens: part, position: position)
            guard llama_decode(context, batch) == 0 else { throw Failure.decode }
            position += part.count
        }
        return try generate(context: context, vocab: vocab, position: position, limit: answerLimit)
    }

    func answerImage(_ data: Data, question: String) throws -> String {
        guard let model, let context, let vision,
              let vocab = llama_model_get_vocab(model) else { throw Failure.load }
        try Task.checkCancellation()
        llama_memory_clear(llama_get_memory(context), true)
        let wrapper = data.withUnsafeBytes { buffer in
            mtmd_helper_bitmap_init_from_buf(vision, buffer.bindMemory(to: UInt8.self).baseAddress, data.count, false)
        }
        guard let bitmap = wrapper.bitmap else { throw Failure.image }
        defer { mtmd_bitmap_free(bitmap) }
        guard let chunks = mtmd_input_chunks_init() else { throw Failure.image }
        defer { mtmd_input_chunks_free(chunks) }
        let marker = String(cString: mtmd_default_marker())
        let prompt = VisionPrompt.make(question, marker: marker)
        var bitmaps: [OpaquePointer?] = [bitmap]
        let result = prompt.withCString { text in
            var input = mtmd_input_text(text: text, text_len: prompt.utf8.count, add_special: false, parse_special: true)
            return bitmaps.withUnsafeMutableBufferPointer { buffer in
                mtmd_tokenize(vision, chunks, &input, buffer.baseAddress, buffer.count)
            }
        }
        guard result == 0 else { throw Failure.image }
        guard mtmd_helper_get_n_tokens(chunks) + 96 < contextSize else { throw Failure.tooLong }
        try Task.checkCancellation()
        var position: llama_pos = 0
        guard mtmd_helper_eval_chunks(vision, context, chunks, 0, 0, 128, true, &position) == 0 else { throw Failure.image }
        try Task.checkCancellation()
        return try generate(context: context, vocab: vocab, position: Int(position), limit: 96)
    }

    private func generate(context: OpaquePointer, vocab: OpaquePointer, position start: Int, limit: Int) throws -> String {
        var position = start
        var batch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(batch) }
        guard let sampler = llama_sampler_init_greedy() else { throw Failure.context }
        defer { llama_sampler_free(sampler) }
        var output = [UInt8]()
        for _ in 0..<limit {
            try Task.checkCancellation()
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            var piece = [CChar](repeating: 0, count: 256)
            var length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if length < 0 {
                piece = [CChar](repeating: 0, count: Int(-length))
                length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            }
            guard length >= 0 else { throw Failure.decode }
            output.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            fill(&batch, tokens: [token], position: position)
            guard llama_decode(context, batch) == 0 else { throw Failure.decode }
            position += 1
        }
        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }

    private func fill(_ batch: inout llama_batch, tokens: [llama_token], position: Int) {
        batch.n_tokens = Int32(tokens.count)
        for (i, token) in tokens.enumerated() {
            batch.token[i] = token
            batch.pos[i] = Int32(position + i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = i == tokens.count - 1 ? 1 : 0
        }
    }
}

// These are instructions, not a guarantee of model reliability.
enum PromptBuilder {
    static func make(_ question: String) -> String {
        let clean = question.replacingOccurrences(of: "<|", with: "‹|")
        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>

        You are Offline Companion, a small on-device text assistant powered by Meta Llama. Answer briefly and plainly. This chat has no internet, current news, image input, location-reading tool, or messaging tools. The app has a separate Map screen: People pairs a nearby phone and shares locations with consent; Saved places stores named points and offers directions within downloaded map coverage. You cannot operate those controls or see their current state from chat. If asked to share or navigate, explain which screen to open; never claim you already did it. Say when you do not know. Never invent observations, locations, alerts, or rescue activity. A message acknowledgement does not prove rescue dispatch. Unconfirmed help is unknown, not proof that nobody is coming. This app cannot dispatch rescue or send an SOS. You can draft a message for review, but this chat cannot send it.
        <|eot_id|><|start_header_id|>user<|end_header_id|>

        \(clean)
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>

        """
    }
}

// SmolVLM's published template uses capitalized roles and <end_of_utterance>.
enum VisionPrompt {
    static func make(_ question: String, marker: String) -> String {
        let clean = question.replacingOccurrences(of: "<|", with: "‹|")
            .replacingOccurrences(of: "<end_of_utterance>", with: "[end]")
            .replacingOccurrences(of: marker, with: "[image]")
        return "<|im_start|>User:" + marker + "\n" + clean
            + "<end_of_utterance>\nAssistant:"
    }
}
