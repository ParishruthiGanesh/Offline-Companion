import SwiftUI
import CoreLocation

struct ExploreAction: Identifiable {
    let id = UUID()
    let key: String
    let directions: Bool
}

struct ExploreView: View {
    @ObservedObject var location: LocationStore
    @ObservedObject var bluetooth: BluetoothStore
    @StateObject private var maps = OfflineMapStore()
    @Binding var action: ExploreAction?
    var openPeople: () -> Void
    @State private var showPlaces = false
    @State private var showDownloads = false
    @State private var showSteps = false
    @State private var center = MapPoint(lat: 32.6, lon: -85.48)
    @State private var camera: MapCameraRequest?
    @State private var selectedKey: String?
    @State private var route: OfflineWalkingRoute?
    @State private var routeName = ""
    @State private var routeMessage: String?
    @State private var calculating = false
    @State private var routeTask: Task<Void,Never>?
    @State private var routeGeneration = UUID()
    @State private var autoCentered = false
    @Environment(\.scenePhase) private var scenePhase

    private var pins: [ExplorePin] {
        var pins: [ExplorePin] = []
        if let fix = location.fix {
            pins.append(ExplorePin(key:"me",title:"You",subtitle:"GPS accuracy ±\(Int(fix.horizontalAccuracy)) m",point:MapPoint(lat:fix.coordinate.latitude,lon:fix.coordinate.longitude),color:.systemBlue))
        }
        for point in location.places {
            pins.append(ExplorePin(key:"place:"+point.id.uuidString,title:point.name,subtitle:"Saved place",point:MapPoint(lat:point.latitude,lon:point.longitude),color:.systemOrange))
        }
        if let packet = bluetooth.received {
            let time = packet.recordedAt.formatted(date:.omitted,time:.standard)
            pins.append(ExplorePin(key:"person",title:bluetooth.peerName,subtitle:"Last GPS \(time) • ±\(Int(packet.accuracy)) m",point:MapPoint(lat:packet.latitude,lon:packet.longitude),color:bluetooth.connected ? .systemPink : .systemGray))
        }
        if let packet = bluetooth.previousReceived {
            pins.append(ExplorePin(key:"previous",title:"Previous update",subtitle:packet.recordedAt.formatted(date:.omitted,time:.standard),point:MapPoint(lat:packet.latitude,lon:packet.longitude),color:.systemGray3))
        }
        return pins
    }
    private var selectedPin: ExplorePin? { pins.first { $0.key == selectedKey } }

    var body: some View {
        ZStack(alignment:.top) {
            NativeOfflineMap(countries:maps.countries,cities:maps.cities,areas:maps.areas,pins:pins,route:route,camera:camera,
                onSelect:{ select($0,directions:false) },onDirections:{ select($0,directions:true) },onCenterChanged:{ center = $0 })
                .ignoresSafeArea(edges:.top)
            VStack(spacing:12) {
                topBar
                if location.fix == nil {
                    HStack { ProgressView(); Text(location.status).font(.caption) }
                        .padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).padding(.horizontal)
                }
                if let fix = location.fix, fix.horizontalAccuracy > 100 {
                    Text("GPS is approximate (±\(Int(fix.horizontalAccuracy)) m). Enable Precise Location and try outdoors.")
                        .font(.caption).padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).padding(.horizontal)
                }
                Spacer()
                HStack {
                    Spacer()
                    Button { centreOnMe() } label: { Image(systemName:"location.fill").font(.title3).padding(14) }
                        .background(.regularMaterial,in:Circle()).shadow(radius:3)
                }.padding(.horizontal)
                bottomCard
            }.padding(.top,8).padding(.bottom,12)
        }
        .sheet(isPresented:$showPlaces) {
            LocationView(location:location,showOnMap:{ point,directions in select("place:"+point.id.uuidString,directions:directions) })
        }
        .sheet(isPresented:$showDownloads) {
            MapDownloadsView(maps:maps,location:location,center:center,showArea:{ point in camera = MapCameraRequest(points:[point],zoom:14) })
        }
        .sheet(isPresented:$showSteps) { steps }
        .onAppear {
            location.refreshMeetingPoint(); location.start(); location.enableCompass()
            if let action { select(action.key,directions:action.directions) }
        }
        .onReceive(location.$fix) { fix in
            if let fix, !autoCentered {
                let point = MapPoint(lat:fix.coordinate.latitude,lon:fix.coordinate.longitude)
                let detailed = maps.areas.contains { OfflineWalkingRouter.metres($0.center,point) < $0.radiusKM*1000 }
                camera = MapCameraRequest(points:[point],zoom:detailed ? 15 : 5)
                autoCentered = true
            }
        }
        .onChange(of:action?.id) { _,_ in if let action { select(action.key,directions:action.directions) } }
        .onChange(of:bluetooth.paired) { _,paired in
            if !paired && selectedKey == "person" {
                routeTask?.cancel(); routeGeneration = UUID(); calculating = false
                route = nil; selectedKey = nil; routeMessage = nil
            }
        }
        .onChange(of:location.places.map(\.id)) { _,_ in
            if selectedKey?.hasPrefix("place:") == true && selectedPin == nil {
                routeTask?.cancel(); routeGeneration = UUID(); calculating = false
                route = nil; selectedKey = nil; routeMessage = nil
            }
        }
        .onChange(of:maps.areas.map(\.id)) { _,_ in if route != nil { calculateRoute() } }
        .onChange(of:bluetooth.receivedAt) { _,_ in if selectedKey == "person", route != nil { calculateRoute() } }
        .onChange(of:scenePhase) { _,phase in if phase == .background { routeTask?.cancel(); maps.cancel() } }
        .onDisappear { routeTask?.cancel() }
    }

    private var topBar: some View {
        HStack(spacing:10) {
            VStack(alignment:.leading,spacing:3) {
                Text("Offline Companion").font(.headline)
                Text(maps.areas.isEmpty ? "Download an area for street detail" : "\(maps.areas.count) saved map area\(maps.areas.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action:openPeople) { Label("People",systemImage:"person.2.fill").font(.subheadline.bold()) }
        }.padding(14).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18)).padding(.horizontal)
    }

    private var bottomCard: some View {
        VStack(alignment:.leading,spacing:12) {
            if let pin = selectedPin, pin.key != "me" && pin.key != "previous" {
                HStack {
                    VStack(alignment:.leading,spacing:3) { Text(pin.title).font(.headline); Text(pin.subtitle).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button { selectedKey = nil; route = nil; routeMessage = nil; routeTask?.cancel() } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }
                }
                HStack {
                    Button("Walking directions") { calculateRoute() }.buttonStyle(.borderedProminent)
                    if selectedKey == "person" { Text("To the last received position; they may have moved.").font(.caption).foregroundStyle(.secondary) }
                }
            } else if let at = bluetooth.receivedAt {
                TimelineView(.periodic(from:.now,by:1)) { timeline in
                    Button { select("person",directions:false) } label: {
                        HStack {
                            Circle().fill(bluetooth.connected ? Color.pink : Color.gray).frame(width:10,height:10)
                            Text(bluetooth.peerName).font(.headline)
                            Spacer()
                            Text("Updated \(max(0,Int(timeline.date.timeIntervalSince(at))))s ago").font(.caption)
                        }
                    }
                    Text(bluetooth.connected ? "Connected • last received location shown" : "Connection lost • showing last known location")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Your places and people, offline.").font(.headline)
                Text(bluetooth.paired ? "Waiting for the paired person’s first update." : "Pair once in People to share locations nearby.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if calculating { ProgressView("Finding a saved walking path…") }
            if let message = routeMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let route {
                HStack {
                    Text(String(format:"%.0f m on mapped paths",route.distance)).font(.subheadline.bold())
                    Spacer()
                    Button("Steps") { showSteps = true }
                }
                Text(String(format:"Unrouted gaps: %.0f m at start, %.0f m at destination. No live closure or safety information.",route.startGap,route.endGap))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button { showPlaces = true } label: { Label("Saved places",systemImage:"mappin.and.ellipse") }
                Spacer()
                Button { showDownloads = true } label: { Label("Offline maps",systemImage:"arrow.down.circle") }
            }.font(.subheadline).buttonStyle(.bordered)
            HStack {
                Text("© OpenStreetMap contributors · Natural Earth").font(.system(size:9)).foregroundStyle(.secondary)
                Spacer()
                Link("Map data",destination:URL(string:"https://www.openstreetmap.org/copyright")!).font(.system(size:9))
            }
        }.padding(16).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20)).padding(.horizontal)
    }

    private var steps: some View {
        NavigationStack {
            List {
                Section(routeName) {
                    if let route {
                        ForEach(Array(route.instructions.enumerated()),id:\.offset) { index,text in Text("\(index+1). \(text)") }
                        Text(String(format:"The mapped route starts %.0f m from your GPS point and ends %.0f m from the destination. Those gaps are not routed.",route.startGap,route.endGap)).font(.footnote)
                    }
                }
                Text("Experimental offline walking route on downloaded OpenStreetMap connections. Follow local signs and restrictions. Stairs, crossings, accessibility, flooding and temporary closures are not evaluated.").font(.footnote)
            }.navigationTitle("Walking steps")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { showSteps = false } } }
        }
    }

    private func centreOnMe() {
        location.start()
        if let fix = location.fix { camera = MapCameraRequest(points:[MapPoint(lat:fix.coordinate.latitude,lon:fix.coordinate.longitude)],zoom:16) }
    }
    private func select(_ key: String, directions: Bool) {
        if selectedKey != key {
            routeTask?.cancel(); routeGeneration = UUID(); route = nil; routeMessage = nil; calculating = false
        }
        selectedKey = key
        if let pin = pins.first(where:{$0.key == key}) { camera = MapCameraRequest(points:[pin.point],zoom:16) }
        if directions { calculateRoute() }
    }
    private func calculateRoute() {
        routeTask?.cancel(); routeGeneration = UUID(); calculating = false; route = nil; routeMessage = nil
        guard let pin = selectedPin else { return }
        guard let fix = location.fix, abs(Date().timeIntervalSince(fix.timestamp)) < 60, fix.horizontalAccuracy <= 100 else {
            routeMessage = "Wait for a recent precise GPS reading (within ±100 m) before calculating directions."; return
        }
        if selectedKey == "person", (bluetooth.received?.accuracy ?? .infinity) > 100 {
            routeMessage = "The other person’s location is too approximate for a walking destination."; return
        }
        if let point = location.places.first(where:{"place:"+$0.id.uuidString == selectedKey}), point.accuracy > 100 {
            routeMessage = "This place was saved with poor GPS accuracy. Save it again with a precise reading before routing."; return
        }
        calculating = true; routeName = pin.title
        let generation = UUID(); routeGeneration = generation
        let areas = maps.areas, origin = MapPoint(lat:fix.coordinate.latitude,lon:fix.coordinate.longitude), destination = pin.point
        let worker = Task.detached(priority:.userInitiated) { try OfflineWalkingRouter.calculate(areas:areas,from:origin,to:destination) }
        routeTask = Task { @MainActor in
            defer { if routeGeneration == generation { calculating = false } }
            do {
                let result = try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                try Task.checkCancellation()
                guard routeGeneration == generation else { return }
                route = result; camera = MapCameraRequest(points:result.points)
            } catch is CancellationError { }
            catch { if routeGeneration == generation { routeMessage = error.localizedDescription } }
        }
    }
}

struct MapDownloadsView: View {
    @ObservedObject var maps: OfflineMapStore
    @ObservedObject var location: LocationStore
    let center: MapPoint
    var showArea: (MapPoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var radius = 3.0
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Save streets around the map centre") {
                    Text("Auburn centre and university streets are already included. Download additional areas while online for use offline.").font(.footnote)
                    Picker("Radius",selection:$radius) { Text("1 km").tag(1.0); Text("3 km").tag(3.0); Text("5 km").tag(5.0) }.pickerStyle(.segmented)
                    Picker("Storage budget",selection:$maps.budgetMB) { Text("50 MB").tag(50);Text("100 MB").tag(100);Text("250 MB").tag(250) }
                    Text("Used: \(ByteCountFormatter.string(fromByteCount:Int64(maps.bytesUsed),countStyle:.file))").font(.caption)
                    if maps.busy { ProgressView(); Button("Cancel download") { maps.cancel() } }
                    else { Button("Download this area") { confirm = true } }
                    Text(maps.message).font(.footnote)
                }
                Section("Saved areas") {
                    ForEach(maps.areas) { area in
                        VStack(alignment:.leading,spacing:6) {
                            Button(area.name) { showArea(area.center); dismiss() }
                            Text("Saved \(area.created.formatted(date:.abbreviated,time:.shortened))").font(.caption)
                            if !area.features.contains(where:{$0.osmNodes != nil}) { Text("Display only. Download again for walking connections.").font(.caption).foregroundStyle(.orange) }
                            if maps.isBundled(area) {
                                Text("Included with the app · available without downloading").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("Delete",role:.destructive) { maps.remove(area) }.font(.caption)
                            }
                        }
                    }
                }
                Text("Only saved local areas contain streets and paths. Country outlines are an overview, not a complete country street map. Download coverage along the whole intended trip. A route is not a safety guarantee.").font(.footnote)
            }.navigationTitle("Offline maps")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Download this area?",isPresented:$confirm,titleVisibility:.visible) {
                    Button("Download") { maps.download(center:CLLocationCoordinate2D(latitude:center.lat,longitude:center.lon),radiusKM:radius) }
                } message: { Text("Uses internet and sends only the selected map area to a public Overpass service. Pairing secrets and contact identities are not sent.") }
        }
    }
}
