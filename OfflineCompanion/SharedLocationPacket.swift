import Foundation

struct SharedLocationPacket: Codable, Sendable {
    let version: Int
    let id: UUID?
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let recordedAt: Date
    let sentAt: Date
    var coordinates: String { String(format: "%.6f, %.6f", latitude, longitude) }
    var valid: Bool {
        version == 1 && latitude.isFinite && longitude.isFinite && accuracy.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && accuracy >= 0 && accuracy < 100_000
            && recordedAt.timeIntervalSince1970.isFinite && sentAt.timeIntervalSince1970.isFinite
    }
}

