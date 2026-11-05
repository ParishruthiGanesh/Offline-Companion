import Foundation

struct OfflineWalkingRoute: Identifiable, Sendable {
    let id = UUID()
    let points: [MapPoint]
    let distance: Double
    let startGap: Double
    let endGap: Double
    let instructions: [String]
}

enum WalkingRouteError: LocalizedError, Equatable {
    case noData, tooFar, disconnected, tooLarge, samePoint
    var errorDescription: String? {
        switch self {
        case .noData: return "Download this area again to enable walking directions. Older downloads do not include road connections."
        case .tooFar: return "A start or destination is too far from downloaded walking paths. Download coverage around both points and the area between them."
        case .disconnected: return "No connected walking path was found in the saved area. Download more coverage; a straight line would not be a walking route."
        case .tooLarge: return "This walking network is too large for this prototype. Try a smaller saved area."
        case .samePoint: return "Both positions are near the same mapped path point. Use the distance and compass; no walking route is needed."
        }
    }
}

// A* over actual shared OSM node IDs. A geometric crossing is NOT treated as an intersection.
// Road access tags and explicit one-way foot restrictions are respected when downloaded.
// This prototype does not evaluate crossings, stairs accessibility, closures, flooding or terrain.
enum OfflineWalkingRouter {
    private struct Edge { let to: Int64; let metres: Double; let name: String }
    private struct Snap { let from: Int64; let to: Int64; let point: MapPoint; let gap: Double; let name: String }
    private struct QueueItem { let id: Int64; let score: Double; let cost: Double }
    private struct Heap {
        var values: [QueueItem] = []
        mutating func push(_ value: QueueItem) {
            values.append(value)
            var child = values.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                if values[parent].score <= values[child].score { break }
                values.swapAt(parent,child); child = parent
            }
        }
        mutating func pop() -> QueueItem? {
            guard !values.isEmpty else { return nil }
            if values.count == 1 { return values.removeLast() }
            values.swapAt(0, values.count - 1)
            let first = values.removeLast()
            var parent = 0
            while parent * 2 + 1 < values.count {
                let left = parent * 2 + 1, right = left + 1
                let child = right < values.count && values[right].score < values[left].score ? right : left
                if values[parent].score <= values[child].score { break }
                values.swapAt(parent,child); parent = child
            }
            return first
        }
    }

    static func metres(_ a: MapPoint, _ b: MapPoint) -> Double {
        let radians = Double.pi / 180
        let first = a.lat * radians, second = b.lat * radians
        let dLat = second - first, dLon = (b.lon-a.lon) * radians
        let v = pow(sin(dLat/2),2) + cos(first)*cos(second)*pow(sin(dLon/2),2)
        return 6_371_000 * 2 * atan2(sqrt(max(0,v)),sqrt(max(0,1-v)))
    }

    static func calculate(areas: [SavedMapArea], from start: MapPoint, to end: MapPoint) throws -> OfflineWalkingRoute {
        var nodes: [Int64:MapPoint] = [:]
        var edges: [Int64:[Edge]] = [:]
        var visitedWays = Set<Int64>()
        var connections = 0
        for area in areas {
            for feature in area.features {
                try Task.checkCancellation()
                guard feature.walkingAllowed == true, let ids = feature.osmNodes,
                      ids.count == feature.points.count, ids.count > 1 else { continue }
                if let id = feature.osmWayID, !visitedWays.insert(id).inserted { continue }
                for (id,point) in zip(ids,feature.points) { nodes[id] = point }
                for index in 1..<ids.count {
                    let distance = metres(feature.points[index-1],feature.points[index])
                    guard distance > 0 else { continue }
                    let name = feature.name.isEmpty ? (feature.kind == "steps" ? "the steps" : "the mapped path") : feature.name
                    if feature.footReverse == true {
                        edges[ids[index],default:[]].append(Edge(to:ids[index-1],metres:distance,name:name))
                    } else {
                        edges[ids[index-1],default:[]].append(Edge(to:ids[index],metres:distance,name:name))
                        if feature.footOneWay != true { edges[ids[index],default:[]].append(Edge(to:ids[index-1],metres:distance,name:name)) }
                    }
                    connections += 1
                }
                if nodes.count > 250_000 || connections > 500_000 { throw WalkingRouteError.tooLarge }
            }
        }
        guard !edges.isEmpty else { throw WalkingRouteError.noData }
        func nearest(_ point: MapPoint) -> Snap? {
            var answer: Snap?
            let longitudeScale = max(0.01,cos(point.lat * .pi / 180))
            for (from,list) in edges {
                guard let first = nodes[from] else { continue }
                for edge in list {
                    guard let second = nodes[edge.to] else { continue }
                    let ax = (first.lon-point.lon)*longitudeScale, ay = first.lat-point.lat
                    let dx = (second.lon-first.lon)*longitudeScale, dy = second.lat-first.lat
                    let squared = dx*dx+dy*dy
                    guard squared > 0 else { continue }
                    let fraction = min(1,max(0,-(ax*dx+ay*dy)/squared))
                    let projected = MapPoint(lat:first.lat+(second.lat-first.lat)*fraction,lon:first.lon+(second.lon-first.lon)*fraction)
                    let gap = metres(point,projected)
                    if gap < (answer?.gap ?? .infinity) { answer = Snap(from:from,to:edge.to,point:projected,gap:gap,name:edge.name) }
                }
            }
            return answer
        }
        guard let sourceSnap = nearest(start), let endSnap = nearest(end), sourceSnap.gap <= 150, endSnap.gap <= 150 else { throw WalkingRouteError.tooFar }
        guard metres(sourceSnap.point,endSnap.point) > 1 else { throw WalkingRouteError.samePoint }
        let sourceID = Int64.min + 1, destinationID = Int64.min + 2
        let source = (sourceID,sourceSnap.gap), destination = (destinationID,endSnap.gap)
        let sourceReverse = (edges[sourceSnap.to] ?? []).contains { $0.to == sourceSnap.from }
        let endReverse = (edges[endSnap.to] ?? []).contains { $0.to == endSnap.from }
        nodes[sourceID] = sourceSnap.point; nodes[destinationID] = endSnap.point
        edges[sourceID,default:[]].append(Edge(to:sourceSnap.to,metres:metres(sourceSnap.point,nodes[sourceSnap.to]!),name:sourceSnap.name))
        if sourceReverse { edges[sourceID,default:[]].append(Edge(to:sourceSnap.from,metres:metres(sourceSnap.point,nodes[sourceSnap.from]!),name:sourceSnap.name)) }
        edges[endSnap.from,default:[]].append(Edge(to:destinationID,metres:metres(nodes[endSnap.from]!,endSnap.point),name:endSnap.name))
        if endReverse { edges[endSnap.to,default:[]].append(Edge(to:destinationID,metres:metres(nodes[endSnap.to]!,endSnap.point),name:endSnap.name)) }
        // If both endpoints project onto the same segment, route along that segment without
        // detouring to a junction. Test orientation against the actual permitted directed edge.
        if (sourceSnap.from == endSnap.from && sourceSnap.to == endSnap.to) || (sourceSnap.from == endSnap.to && sourceSnap.to == endSnap.from) {
            let first = nodes[sourceSnap.from]!
            let sourceDistance = metres(first,sourceSnap.point), endDistance = metres(first,endSnap.point)
            if endDistance >= sourceDistance || sourceReverse {
                edges[sourceID,default:[]].append(Edge(to:destinationID,metres:metres(sourceSnap.point,endSnap.point),name:sourceSnap.name))
            }
        }
        var heap = Heap(); heap.push(QueueItem(id:source.0,score:metres(nodes[source.0]!,nodes[destination.0]!),cost:0))
        var costs: [Int64:Double] = [source.0:0]
        var previous: [Int64:(Int64,Edge)] = [:]
        var expanded = 0
        while let item = heap.pop() {
            if item.cost > (costs[item.id] ?? .infinity) { continue }
            if item.id == destination.0 { break }
            expanded += 1
            if expanded % 256 == 0 { try Task.checkCancellation() }
            if expanded > 500_000 { throw WalkingRouteError.tooLarge }
            for edge in edges[item.id] ?? [] {
                let cost = item.cost + edge.metres
                if cost < (costs[edge.to] ?? .infinity), let point = nodes[edge.to] {
                    costs[edge.to] = cost; previous[edge.to] = (item.id,edge)
                    heap.push(QueueItem(id:edge.to,score:cost+metres(point,nodes[destination.0]!),cost:cost))
                }
            }
        }
        guard let distance = costs[destination.0], previous[destination.0] != nil else { throw WalkingRouteError.disconnected }
        var ids = [destination.0], ordered: [Edge] = [], current = destination.0
        while current != source.0 {
            guard let step = previous[current] else { throw WalkingRouteError.disconnected }
            ordered.append(step.1); current = step.0; ids.append(current)
        }
        ordered.reverse(); ids.reverse()
        var groups: [(String,Double)] = []
        for edge in ordered {
            if groups.last?.0 == edge.name { groups[groups.count-1].1 += edge.metres }
            else { groups.append((edge.name,edge.metres)) }
        }
        let instructions = groups.map { String(format:"Follow %@ for about %.0f m",$0.0,$0.1) }
        var points: [MapPoint] = []
        for id in ids {
            if let point = nodes[id], points.last.map({ metres($0,point) > 0.1 }) ?? true { points.append(point) }
        }
        return OfflineWalkingRoute(points:points,distance:distance,startGap:source.1,endGap:destination.1,instructions:instructions)
    }
}
