import Foundation
import CryptoKit

/// Network access is confined to an explicit, user-requested setup download.
enum ModelFiles {
    static let filename = "Llama-3.2-1B-Instruct-Q4_K_M.gguf"
    static let expectedSize: Int64 = 807_694_464
    static let expectedSHA256 = "6f85a640a97cf2bf5b8e764087b1e83da0fdb51d7c9fab7d0fece9385611df83"
    static let source = URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
    }
    static var modelURL: URL { directory.appendingPathComponent(filename) }
    static var exists: Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.int64Value == expectedSize
    }

    enum Failure: LocalizedError {
        case invalid, http(Int)
        var errorDescription: String? {
            switch self {
            case .invalid: return "This is not the expected complete Llama 3.2 1B Instruct Q4_K_M file. Use Download model, or import the exact file listed in Setup."
            case .http(let code): return "Download failed (HTTP \(code)). Check your connection and retry, or import the GGUF file."
            }
        }
    }

    static func download() async throws {
        var request = URLRequest(url: source)
        request.timeoutInterval = 3600
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse else { throw Failure.invalid }
        guard response.statusCode == 200 else { throw Failure.http(response.statusCode) }
        try Task.checkCancellation()
        try install(from: temporary)
    }

    static func install(from source: URL) throws {
        try installVerified(from: source, destination: modelURL, size: expectedSize, sha256: expectedSHA256)
    }

    static func installVerified(from source: URL, destination: URL, size: Int64, sha256: String) throws {
        try Task.checkCancellation()
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? manager.removeItem(at: staged) }
        try manager.copyItem(at: source, to: staged)
        let attributes = try manager.attributesOfItem(atPath: staged.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == size else { throw Failure.invalid }
        let handle = try FileHandle(forReadingFrom: staged)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw Failure.invalid }
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staged)
        } else {
            try manager.moveItem(at: staged, to: destination)
        }
        var storedURL = destination
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try storedURL.setResourceValues(values)
    }
}


enum VisionFiles {
    struct Asset: Sendable {
        let name: String
        let size: Int64
        let sha256: String
        var url: URL { ModelFiles.directory.appendingPathComponent(name) }
        var source: URL {
            URL(string: "https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/" + name)!
        }
        var exists: Bool {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let bytes = attrs[.size] as? NSNumber else { return false }
            return bytes.int64Value == size
        }
    }
    static let model = Asset(name: "SmolVLM-500M-Instruct-Q8_0.gguf", size: 436_806_912,
        sha256: "9d4612de6a42214499e301494a3ecc2be0abdd9de44e663bda63f1152fad1bf4")
    static let projector = Asset(name: "mmproj-SmolVLM-500M-Instruct-Q8_0.gguf", size: 108_783_360,
        sha256: "d1eb8b6b23979205fdf63703ed10f788131a3f812c7b1f72e0119d5d81295150")
    static var exists: Bool { model.exists && projector.exists }
    static func download() async throws {
        for asset in [model, projector] where !asset.exists {
            var request = URLRequest(url: asset.source)
            request.timeoutInterval = 3600
            let (temporary, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let response = response as? HTTPURLResponse else { throw ModelFiles.Failure.invalid }
            guard response.statusCode == 200 else { throw ModelFiles.Failure.http(response.statusCode) }
            try Task.checkCancellation()
            try ModelFiles.installVerified(from: temporary, destination: asset.url, size: asset.size, sha256: asset.sha256)
        }
    }
    static func install(from url: URL) throws {
        let asset = url.lastPathComponent.lowercased().hasPrefix("mmproj") ? projector : model
        do {
            try ModelFiles.installVerified(from: url, destination: asset.url, size: asset.size, sha256: asset.sha256)
        } catch ModelFiles.Failure.invalid {
            throw VisionFailure.wrongFile
        }
    }
    enum VisionFailure: LocalizedError {
        case wrongFile, image
        var errorDescription: String? {
            switch self {
            case .wrongFile: return "Use the exact SmolVLM-500M-Instruct-Q8_0.gguf and mmproj-SmolVLM-500M-Instruct-Q8_0.gguf files from ggml-org. Both are needed."
            case .image: return "Could not open this photo. Choose a smaller JPEG or PNG stored on your phone."
            }
        }
    }
}
