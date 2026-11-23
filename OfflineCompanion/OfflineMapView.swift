import SwiftUI
import CoreLocation
import Combine

struct MapPoint: Codable, Sendable {
    let lat: Double
    let lon: Double
}
struct MapCity: Codable {
    let name: String
    let lat: Double
    let lon: Double
}
struct MapFeature: Codable, Sendable {
    let kind: String
    let name: String
    let points: [MapPoint]
    var osmNodes: [Int64]? = nil
    var walkingAllowed: Bool? = nil
    var footOneWay: Bool? = nil
    var footReverse: Bool? = nil
    var osmWayID: Int64? = nil
}
struct SavedMapArea: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let created: Date
    let center: MapPoint
    let radiusKM: Double
    let features: [MapFeature]
}
struct CountryOutline: Identifiable {
    let id: String
    let rings: [[MapPoint]]
    var mainRing: [MapPoint] { rings.max(by: { $0.count < $1.count }) ?? [] }
    func contains(_ point: MapPoint) -> Bool {
        for ring in rings where ring.count > 2 {
            var inside = false
            var previous = ring.count - 1
            for current in ring.indices {
                let a = ring[current], b = ring[previous]
                if (a.lat > point.lat) != (b.lat > point.lat) && point.lon < (b.lon-a.lon) * (point.lat-a.lat) / (b.lat-a.lat) + a.lon { inside.toggle() }
                previous = current
            }
            if inside { return true }
        }
        return false
    }
    var center: MapPoint {
        let ring = mainRing
        return MapPoint(lat: ((ring.map(\.lat).min() ?? 0) + (ring.map(\.lat).max() ?? 0)) / 2,
                        lon: ((ring.map(\.lon).min() ?? 0) + (ring.map(\.lon).max() ?? 0)) / 2)
    }
}

@MainActor
final class OfflineMapStore: ObservableObject {
    @Published private(set) var areas: [SavedMapArea] = []
    @Published private(set) var bytesUsed = 0
    @Published private(set) var busy = false
    @Published private(set) var message = "Auburn streets and paths are built in and available offline. Other areas require an online download."
    @Published var budgetMB = 100 { didSet { UserDefaults.standard.set(budgetMB, forKey: "offlineMapBudgetMB") } }
    let countries: [CountryOutline]
    let cities: [MapCity]
    static let bundledAreaID = UUID(uuidString: "A0B00000-0000-4000-8000-000000000001")!
    func isBundled(_ area: SavedMapArea) -> Bool { area.id == Self.bundledAreaID }
    private var job: Task<Void, Never>?
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineRoadMaps", isDirectory: true)
    }

    init() {
        if let url = Bundle.main.url(forResource: "Cities", withExtension: "json"),
           let data = try? Data(contentsOf: url) { cities = (try? JSONDecoder().decode([MapCity].self, from: data)) ?? [] }
        else { cities = [] }
        var outlines: [CountryOutline] = []
        if let url = Bundle.main.url(forResource: "Countries", withExtension: "geojson"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let features = json["features"] as? [[String: Any]] {
            for feature in features {
                guard let properties = feature["properties"] as? [String: Any],
                      let name = properties["name"] as? String,
                      let geometry = feature["geometry"] as? [String: Any] else { continue }
                let polygons: [[[[Double]]]]
                if geometry["type"] as? String == "MultiPolygon" { polygons = geometry["coordinates"] as? [[[[Double]]]] ?? [] }
                else { polygons = [geometry["coordinates"] as? [[[Double]]] ?? []] }
                // Exterior rings form a compact country overview; local roads are separate downloads.
                let rings = polygons.compactMap { $0.first }.map { ring in
                    ring.compactMap { pair -> MapPoint? in
                        guard pair.count >= 2 else { return nil }
                        return MapPoint(lat: pair[1], lon: pair[0])
                    }
                }
                outlines.append(CountryOutline(id: name, rings: rings))
            }
        }
        countries = outlines.sorted { $0.id < $1.id }
        let savedBudget = UserDefaults.standard.integer(forKey: "offlineMapBudgetMB")
        if [50,100,250].contains(savedBudget) { budgetMB = savedBudget }
        reload()
    }

    func reload() {
        areas = []
        bytesUsed = 0
        if let url = Bundle.main.url(forResource: "AuburnMap", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let area = try? JSONDecoder().decode(SavedMapArea.self, from: data) {
            areas.append(area)
            bytesUsed += data.count
        } else {
            message = "The built-in Auburn map could not be opened. Reinstall the updated build; saved downloaded areas remain available."
        }
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            guard file.pathExtension == "mapdata", let compressed = try? Data(contentsOf: file),
                  let expanded = try? (compressed as NSData).decompressed(using: .lzfse),
                  let area = try? JSONDecoder().decode(SavedMapArea.self, from: expanded as Data) else { continue }
            bytesUsed += compressed.count
            areas.append(area)
        }
        areas.sort { $0.created > $1.created }
    }

    func remove(_ area: SavedMapArea) {
        guard !isBundled(area) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(area.id.uuidString + ".mapdata"))
        reload()
    }

    func cancel() { job?.cancel() }

    func download(center: CLLocationCoordinate2D, radiusKM: Double) {
        guard !busy else { return }
        busy = true
        message = "Downloading roads, paths and waterways. Keep the app open; this may take a minute."
        let available = max(0, budgetMB * 1_000_000 - bytesUsed)
        job = Task {
            defer { busy = false; job = nil }
            do {
                guard available > 1_000_000 else { throw MapDownloadError.limit }
                let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
                if let free = attributes[.systemFreeSize] as? NSNumber, free.int64Value < 20_000_000 { throw MapDownloadError.disk }
                let area = try await MapAreaDownloader.fetch(center: center, radiusKM: radiusKM)
                try Task.checkCancellation()
                let raw = try JSONEncoder().encode(area)
                let data = try (raw as NSData).compressed(using: .lzfse) as Data
                guard data.count <= available else { throw MapDownloadError.limit }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent(area.id.uuidString + ".mapdata"), options: .atomic)
                var folder = directory
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try? folder.setResourceValues(values)
                reload()
                message = "Saved \(area.features.count) features. Offline map and walking connections are ready within this area."
            } catch is CancellationError { message = "Download cancelled. Previously saved maps are unchanged." }
            catch { message = error.localizedDescription }
        }
    }
}

enum MapDownloadError: LocalizedError {
    case server, limit, empty, disk, tooLarge, offline
    case services([String])
    var errorDescription: String? {
        switch self {
        case .server: return "The map server returned incomplete or invalid data. No map was saved."
        case .offline: return "No internet connection. Connect to working Wi-Fi or cellular data for this download. Saved maps still work offline."
        case .tooLarge: return "This area returned too much map data. Choose a smaller radius. No map was saved."
        case .services(let reasons): return "Could not reach a working map service. No map was saved. " + reasons.joined(separator: " • ")
        case .limit: return "This map would exceed the saved-map budget. Delete an area or increase the budget."
        case .disk: return "Less than 20 MB of free device storage remains. Free up space before downloading."
        case .empty: return "No supported roads or paths were returned. Try another area."
        }
    }
}

enum MapAreaDownloader {
    static func fetch(center: CLLocationCoordinate2D, radiusKM: Double) async throws -> SavedMapArea {
        let km = min(5, max(1, radiusKM))
        let dy = km / 111
        let dx = min(10, km / (111 * max(0.1, cos(center.latitude * .pi / 180))))
        let south = max(-85, center.latitude - dy), north = min(85, center.latitude + dy)
        let west = max(-180, center.longitude - dx), east = min(180, center.longitude + dx)
        let bbox = "\(south),\(west),\(north),\(east)"
        let query = "[out:json][timeout:25][maxsize:33554432];(way[highway](\(bbox));way[waterway](\(bbox)););out geom;"
        let point = MapPoint(lat: center.latitude, lon: center.longitude)
        var failures: [String] = []
        // Use direct current endpoints and GET so a redirect cannot discard a POST body.
        // Providers are tried sequentially, including after HTTP-200 server error responses.
        for endpoint in ["https://overpass.private.coffee/api/interpreter", "https://overpass-api.de/api/interpreter"] {
            try Task.checkCancellation()
            var components = URLComponents(string: endpoint)!
            components.queryItems = [URLQueryItem(name: "data", value: query)]
            var request = URLRequest(url: components.url!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 40
            request.setValue("OfflineCompanion/1.0 (offline regional map prototype)", forHTTPHeaderField: "User-Agent")
            let host = components.host ?? "Map server"
            do {
                let (stream, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { failures.append(host + ": invalid response"); continue }
                guard http.statusCode == 200 else {
                    failures.append(host + ": HTTP " + String(http.statusCode)); continue
                }
                var data = Data()
                for try await byte in stream {
                    if data.count >= 12_000_000 { throw MapDownloadError.tooLarge }
                    data.append(byte)
                    if data.count % 65536 == 0 { try Task.checkCancellation() }
                }
                let downloaded = data
                let worker = Task.detached(priority: .userInitiated) { try parseResponse(downloaded, center: point, radiusKM: km) }
                return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            } catch is CancellationError { throw CancellationError() }
            catch MapDownloadError.tooLarge { throw MapDownloadError.tooLarge }
            catch MapDownloadError.empty { throw MapDownloadError.empty }
            catch let error as URLError {
                if Task.isCancelled { throw CancellationError() }
                if error.code == .notConnectedToInternet { throw MapDownloadError.offline }
                let reason: String
                switch error.code {
                case .timedOut: reason = "timed out"
                case .cannotFindHost, .dnsLookupFailed: reason = "address could not be resolved"
                case .cannotConnectToHost: reason = "connection failed"
                case .networkConnectionLost: reason = "connection interrupted"
                default: reason = "network error " + String(error.code.rawValue)
                }
                failures.append(host + ": " + reason)
            } catch {
                failures.append(host + ": invalid data or server could not finish the query")
            }
        }
        try Task.checkCancellation()
        throw MapDownloadError.services(failures)
    }

    static func parseResponse(_ data: Data, center: MapPoint, radiusKM km: Double) throws -> SavedMapArea {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["remark"] == nil, let elements = json["elements"] as? [[String: Any]] else { throw MapDownloadError.server }
        var features: [MapFeature] = []
        guard elements.count <= 25_000 else { throw MapDownloadError.tooLarge }
        for element in elements {
            try Task.checkCancellation()
            guard let geometry = element["geometry"] as? [[String: Any]],
                  let tags = element["tags"] as? [String: String] else { continue }
            let points = geometry.compactMap { coordinate -> MapPoint? in
                guard let lat = coordinate["lat"] as? Double, let lon = coordinate["lon"] as? Double else { return nil }
                return MapPoint(lat: lat, lon: lon)
            }
            if points.count > 1 {
                let kind = tags["highway"] ?? "waterway"
                let blockedKinds = ["waterway", "motorway", "motorway_link", "trunk", "trunk_link", "construction", "proposed", "raceway"]
                let blockedAccess = ["no", "private", "customers", "delivery", "agricultural", "forestry", "permit"]
                let explicitFoot = ["yes", "designated", "permissive"].contains(tags["foot"] ?? "")
                let walking = !blockedKinds.contains(kind) && !["no", "private", "use_sidepath"].contains(tags["foot"] ?? "")
                    && (!blockedAccess.contains(tags["access"] ?? "") || explicitFoot)
                    && (kind != "cycleway" || explicitFoot)
                let nodes = (element["nodes"] as? [NSNumber])?.map { $0.int64Value }
                features.append(MapFeature(kind: kind, name: tags["name"] ?? "", points: points,
                                           osmNodes: nodes, walkingAllowed: walking,
                                           footOneWay: ["yes", "1", "true", "-1"].contains(tags["oneway:foot"] ?? ""),
                                           footReverse: tags["oneway:foot"] == "-1", osmWayID: (element["id"] as? NSNumber)?.int64Value))
            }
        }
        guard !features.isEmpty else { throw MapDownloadError.empty }
        let label = String(format: "%.3f, %.3f • %.0f km", center.lat, center.lon, km)
        return SavedMapArea(id: UUID(), name: label, created: Date(), center: MapPoint(lat: center.lat, lon: center.lon), radiusKM: km, features: features)
    }
}
