import SwiftUI
import CoreLocation
import Combine
import UIKit

struct MeetingPoint: Codable, Identifiable {
    let id: UUID
    var name: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let savedAt: Date
    var coordinates: String { String(format: "%.6f, %.6f", latitude, longitude) }

    init(id: UUID = UUID(), name: String = "Meeting point", latitude: Double, longitude: Double, accuracy: Double, savedAt: Date) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude; self.accuracy = accuracy; self.savedAt = savedAt
    }
    enum CodingKeys: String, CodingKey { case id, name, latitude, longitude, accuracy, savedAt }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Meeting point"
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        accuracy = try values.decode(Double.self, forKey: .accuracy)
        savedAt = try values.decode(Date.self, forKey: .savedAt)
    }
}

@MainActor
final class LocationStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var fix: CLLocation?
    @Published private(set) var tracking = false
    @Published private(set) var status = "Tap Start location to use your phone’s location sensor."
    @Published private(set) var meeting: MeetingPoint?
    @Published private(set) var places: [MeetingPoint] = []
    @Published private(set) var heading: CLHeading?
    @Published private(set) var backgroundPermission = "Checking location permission…"
    private var compassRequested = false
    private let manager = CLLocationManager()
    private let supportsBackground: Bool
    private var wantsLocation = false
    private let key = "offlineCompanion.meetingPoint.v1"

    override convenience init() { self.init(background: false) }

    init(background: Bool) {
        supportsBackground = background
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.headingFilter = 3
        if background {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.distanceFilter = 10
            manager.activityType = .otherNavigation
        }
        refreshMeetingPoint(); refreshBackgroundPermission()
    }

    func refreshMeetingPoint() {
        if let data = UserDefaults.standard.data(forKey: "offlineCompanion.savedPlaces.v2"),
           let stored = try? JSONDecoder().decode([MeetingPoint].self, from: data) { places = stored }
        if let data = UserDefaults.standard.data(forKey: key), let selected = try? JSONDecoder().decode(MeetingPoint.self, from: data) {
            meeting = places.first(where: { $0.id == selected.id }) ?? selected
            if places.isEmpty { places = [selected]; persistPlaces() }
        } else { meeting = places.first }
    }

    private func persistPlaces() {
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: "offlineCompanion.savedPlaces.v2") }
        if let meeting, let data = try? JSONEncoder().encode(meeting) { UserDefaults.standard.set(data, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    func selectPlace(_ point: MeetingPoint) { meeting = point; persistPlaces() }

    func renamePlace(_ point: MeetingPoint, name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !clean.isEmpty, let index = places.firstIndex(where: { $0.id == point.id }) else { return }
        places[index].name = clean
        if meeting?.id == point.id { meeting = places[index] }
        persistPlaces()
    }

    func deletePlace(_ point: MeetingPoint) {
        places.removeAll { $0.id == point.id }
        if meeting?.id == point.id { meeting = places.first }
        persistPlaces()
    }

    func refreshBackgroundPermission() {
        switch manager.authorizationStatus {
        case .authorizedAlways: backgroundPermission = "Always access enabled. "
        case .authorizedWhenInUse: backgroundPermission = "Currently: While Using the App. Choose Always in Settings for background sharing. "
        case .notDetermined: backgroundPermission = "Location permission has not been granted. "
        case .denied: backgroundPermission = "Location access denied. Enable it in Settings. "
        case .restricted: backgroundPermission = "Location access is restricted by this device. "
        @unknown default: backgroundPermission = "Location permission unavailable. "
        }
        backgroundPermission += manager.accuracyAuthorization == .fullAccuracy ? "Precise Location is on." : "Enable Precise Location in Settings."
    }

    func openLocationSettings() {
        guard let url = URL(string:UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func requestBackgroundAccess() {
        guard supportsBackground else { return }
        refreshBackgroundPermission()
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            if UserDefaults.standard.bool(forKey:"requestedAlwaysLocation.v2") { openLocationSettings() }
            else {
                UserDefaults.standard.set(true,forKey:"requestedAlwaysLocation.v2")
                manager.requestAlwaysAuthorization()
                backgroundPermission = "If iOS does not show a prompt, tap Open Settings below, then Location > Always. Turn Precise Location on."
            }
        case .authorizedAlways: backgroundPermission = "Always location access is already enabled. Background delivery still depends on iOS and Bluetooth."
        default: openLocationSettings()
        }
    }

    func start() {
        wantsLocation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Allow location access to continue."
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            tracking = true
            status = "Finding your location. Outdoors may give a better signal."
            manager.startUpdatingLocation()
            if compassRequested && CLLocationManager.headingAvailable() {
                updateHeadingOrientation()
                manager.startUpdatingHeading()
            }
        case .denied, .restricted:
            status = "Location access is off. Enable it in iPhone Settings for Offline Companion."
        @unknown default:
            status = "Location access is unavailable."
        }
    }

    func stop() {
        wantsLocation = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        heading = nil
        tracking = false
        status = "Location updates stopped. Any coordinates below are the last reading."
    }

    func enableCompass() {
        compassRequested = true
        updateHeadingOrientation()
        if tracking && CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func updateHeadingOrientation() {
        guard compassRequested else { return }
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.interfaceOrientation
        // Interface landscape directions are opposite physical device orientation names.
        let next: CLDeviceOrientation
        switch orientation {
        case .landscapeLeft: next = .landscapeRight
        case .landscapeRight: next = .landscapeLeft
        case .portraitUpsideDown: next = .portraitUpsideDown
        default: next = .portrait
        }
        if manager.headingOrientation != next { heading = nil; manager.headingOrientation = next }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard tracking, compassRequested else { return }
        heading = newHeading
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshBackgroundPermission()
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: if wantsLocation { start() }
        case .denied, .restricted: stop(); status = "Location permission is off. Enable it in iPhone Settings."
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        fix = latest
        status = manager.accuracyAuthorization == .reducedAccuracy
            ? "Approximate location. Enable Precise Location in Settings for better accuracy."
            : "Location reading received. Check accuracy and update time below."
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Location unavailable: \(error.localizedDescription). Try outdoors."
    }

    func refreshCurrentLocation() {
        // Restart continuous GPS updates so a stationary old fix does not look current.
        manager.stopUpdatingLocation()
        start()
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            status = "Refreshing GPS. Keep the app open; try outdoors if it takes time."
        }
    }

    func canSave(at now: Date) -> Bool {
        guard let fix else { return false }
        return tracking && fix.horizontalAccuracy >= 0 && abs(now.timeIntervalSince(fix.timestamp)) < 60
    }

    @discardableResult
    func saveMeetingPoint(name: String = "Meeting point") -> Bool {
        guard canSave(at: Date()), let fix else { status = "Place not saved: refresh GPS and try again."; return false }
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let point = MeetingPoint(name: clean.isEmpty ? "Meeting point" : clean, latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
                                 accuracy: fix.horizontalAccuracy, savedAt: fix.timestamp)
        places.insert(point, at: 0); meeting = point; persistPlaces()
        status = "Saved " + point.name + "."
        return true
    }

    func removeMeetingPoint() { if let meeting { deletePlace(meeting) } }

    func pauseCompass() { manager.stopUpdatingHeading(); heading = nil; compassRequested = false }
}

struct LocationView: View {
    @ObservedObject var location: LocationStore
    var showOnMap: (MeetingPoint, Bool) -> Void = { _, _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var placeName = ""
    @State private var save = false
    @State private var editing: MeetingPoint?
    @State private var rename = false
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Save where I am") {
                    TextField("Name, e.g. Home, Car or Campsite", text: $placeName)
                    if let fix = location.fix {
                        Text("Estimated accuracy ±\(Int(fix.horizontalAccuracy)) m").font(.caption)
                    }
                    TimelineView(.periodic(from:.now,by:1)) { timeline in
                        VStack(alignment:.leading,spacing:8) {
                            Button("Save place") { save = true }
                                .disabled(!location.canSave(at:timeline.date) || placeName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                            if placeName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                                Text("Enter a name for your current position.").font(.caption)
                            } else if let fix = location.fix {
                                let age = max(0,Int(timeline.date.timeIntervalSince(fix.timestamp)))
                                Text("GPS reading: \(age) seconds old.").font(.caption)
                                if !location.canSave(at:timeline.date) {
                                    Text("Save needs a fresh GPS reading. Tap Refresh GPS below.").font(.caption).foregroundStyle(.orange)
                                }
                            } else {
                                Text("Waiting for GPS coordinates. Allow location access and tap Refresh GPS.").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    Text("This saves where you are now with a name; it does not search for a typed address.").font(.caption).foregroundStyle(.secondary)
                    Text(location.status).font(.caption).foregroundStyle(.secondary)
                    Button("Refresh GPS") { location.refreshCurrentLocation() }
                    Button("Open location settings") { location.openLocationSettings() }
                }
                Section("Saved places") {
                    if location.places.isEmpty { Text("Save a place above to return to it later.").foregroundStyle(.secondary) }
                    ForEach(location.places) { point in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(point.name, systemImage: location.meeting?.id == point.id ? "mappin.circle.fill" : "mappin.circle").font(.headline)
                            Text(point.coordinates).font(.caption.monospaced()).textSelection(.enabled)
                            HStack {
                                Button("Show") { location.selectPlace(point); showOnMap(point, false); dismiss() }
                                Button("Directions") { location.selectPlace(point); showOnMap(point, true); dismiss() }
                                Menu {
                                    Button("Rename") { editing = point; renameText = point.name; rename = true }
                                    Button("Use for compass") { location.selectPlace(point) }
                                    Button("Delete", role: .destructive) { location.deletePlace(point) }
                                } label: { Image(systemName: "ellipsis.circle") }
                            }.buttonStyle(.bordered)
                        }.padding(.vertical, 4)
                    }
                }
                if let point = location.meeting {
                    Section("Compass to \(point.name)") {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            MeetingDirectionView(fix: location.fix, heading: location.heading, point: point, tracking: location.tracking, now: timeline.date)
                        }
                    }
                }
            }
            .navigationTitle("Saved places")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Save \(placeName)?", isPresented: $save) {
                Button("Save") { if location.saveMeetingPoint(name: placeName) { placeName = "" } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("The saved point includes the GPS accuracy shown above. A poor reading may be far from the intended place.") }
            .alert("Rename place", isPresented: $rename) {
                TextField("Place name", text: $renameText)
                Button("Save") { if let editing { location.renamePlace(editing, name: renameText) } }
                Button("Cancel", role: .cancel) { }
            }
        }
        .onAppear { location.refreshMeetingPoint(); location.enableCompass(); location.start() }
    }
}

// Initial great-circle bearing, clockwise from TRUE north. This is not road routing.
enum MeetingBearing {
    static func degrees(from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) -> Double {
        let radians = Double.pi / 180
        let first = origin.latitude * radians
        let second = target.latitude * radians
        let longitudeDifference = (target.longitude - origin.longitude) * radians
        let y = sin(longitudeDifference) * cos(second)
        let x = cos(first) * sin(second) - sin(first) * cos(second) * cos(longitudeDifference)
        return (atan2(y, x) / radians + 360).truncatingRemainder(dividingBy: 360)
    }

    static func relativeAngle(bearing: Double, heading: Double) -> Double {
        (bearing - heading + 540).truncatingRemainder(dividingBy: 360) - 180
    }
}

struct MeetingDirectionView: View {
    let fix: CLLocation?
    let heading: CLHeading?
    let point: MeetingPoint
    let tracking: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Direction to meeting point", systemImage: "location.north.circle")
                .font(.headline)
            if !tracking {
                Text("Tap Start location to use the direction arrow.").foregroundStyle(.secondary)
            } else if !CLLocationManager.headingAvailable() {
                Text("A compass is not available on this device. Coordinates and distance still work.")
            } else if let fix, abs(now.timeIntervalSince(fix.timestamp)) < 60 {
                let target = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                let distance = fix.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                let uncertainty = max(10, fix.horizontalAccuracy + point.accuracy)
                if distance <= uncertainty {
                    Label("Too close for a reliable direction", systemImage: "scope")
                        .foregroundStyle(.orange)
                    Text("You are within the combined location uncertainty of the saved point. Check your surroundings; this does not confirm arrival.")
                        .font(.footnote)
                } else if let heading, heading.trueHeading >= 0,
                          heading.headingAccuracy >= 0, heading.headingAccuracy <= 30,
                          abs(now.timeIntervalSince(heading.timestamp)) < 60 {
                    let bearing = MeetingBearing.degrees(from: fix.coordinate, to: target)
                    let turn = MeetingBearing.relativeAngle(bearing: bearing, heading: heading.trueHeading)
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Color.teal.opacity(0.25), lineWidth: 3)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 66, weight: .bold))
                                .foregroundStyle(.teal)
                                .rotationEffect(.degrees(turn))
                                .accessibilityHidden(true)
                        }.frame(width: 150, height: 150)
                        Text(abs(turn) <= 15 ? "Meeting point is ahead" : turn > 0 ? "Turn right toward the arrow" : "Turn left toward the arrow")
                            .font(.headline)
                        Text(String(format: "Direction %.0f° from true north • compass accuracy ±%.0f°", bearing, heading.headingAccuracy))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                } else {
                    Text("Waiting for an accurate compass reading.").foregroundStyle(.secondary)
                    Text("Hold the phone roughly flat, turn slowly, and move away from magnets or metal. A fresh location is needed for true north.")
                        .font(.footnote)
                }
            } else {
                Text("Waiting for a fresh location. Try outdoors.").foregroundStyle(.secondary)
            }
            Text("Hold the phone roughly flat with the top of the screen pointing forward. The arrow points directly toward your saved spot.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Straight-line direction only—not a safe walking route. It does not account for buildings, rivers, roads or other obstacles.")
                .font(.caption).foregroundStyle(.orange)
        }.padding(.vertical, 8)
    }
}

struct CompanionRootView: View {
    @StateObject private var coordinator = BluetoothCoordinator()
    @State private var selectedTab = "assistant"
    @State private var showPeople = false
    @State private var mapAction: ExploreAction?
    @AppStorage("welcomeCompleted.v1") private var welcomeCompleted = false
    @AppStorage("bluetoothDisplayName") private var displayName = ""
    @State private var pendingPairURL: URL?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if welcomeCompleted {
                mainContent.onAppear {
                    if let url = pendingPairURL {
                        pendingPairURL = nil
                        coordinator.transport.receivePairingLink(url)
                        selectedTab = "map"; showPeople = true
                    }
                }
            } else {
                CompanionWelcomeView(initialName:displayName) { name in
                    displayName = name
                    coordinator.transport.updateDisplayName(name)
                    welcomeCompleted = true
                }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "offlinecompanion", url.host == "pair" else { return }
            if welcomeCompleted {
                coordinator.transport.receivePairingLink(url)
                selectedTab = "map"; showPeople = true
            } else { pendingPairURL = url }
        }
    }

    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            ContentView().tabItem { Label("Assistant", systemImage: "bubble.left.and.text.bubble.right") }.tag("assistant")
            ExploreView(location: coordinator.location, bluetooth: coordinator.transport, action: $mapAction, openPeople: { showPeople = true })
                .tabItem { Label("Map", systemImage: "map.fill") }.tag("map")
        }.tint(.teal)
        .safeAreaInset(edge: .top) { BluetoothSharingBanner(bluetooth: coordinator.transport) }
        .sheet(isPresented: $showPeople) {
            BluetoothView(bluetooth: coordinator.transport, location: coordinator.location, showOnMap: { directions in
                selectedTab = "map"; mapAction = ExploreAction(key: "person", directions: directions); showPeople = false
            })
        }
        .onReceive(coordinator.transport.$incomingName) { name in
            if name != nil { selectedTab = "map"; showPeople = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                coordinator.location.pauseCompass()
                if !coordinator.transport.sharing { coordinator.location.stop() }
            } else if phase == .active && selectedTab == "map" {
                coordinator.location.start(); coordinator.location.enableCompass()
            }
        }
    }
}

private struct CompanionWelcomeView: View {
    @State private var name: String
    let onContinue: (String) -> Void
    init(initialName: String, onContinue: @escaping (String) -> Void) {
        _name = State(initialValue:initialName == "My phone" ? "" : initialName)
        self.onContinue = onContinue
    }
    private var cleanName: String { String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(20)) }
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            Spacer()
            Image(systemName:"person.2.circle.fill").font(.system(size:64)).foregroundStyle(.teal).accessibilityHidden(true)
            Text("Welcome to\nOffline Companion").font(.largeTitle.bold())
            Text("What’s your name?").font(.title2.bold())
            Text("Your person will see this name when you connect your phones.").foregroundStyle(.secondary)
            TextField("Your name",text:$name)
                .textContentType(.givenName).textInputAutocapitalization(.words).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).font(.title3)
                .onChange(of:name) { _, value in if value.count > 20 { name = String(value.prefix(20)) } }
                .submitLabel(.continue)
                .onSubmit { if !cleanName.isEmpty { onContinue(cleanName) } }
            Button { onContinue(cleanName) } label: {
                Text("Continue").font(.headline).frame(maxWidth:.infinity).padding(.vertical,10)
            }.buttonStyle(.borderedProminent).tint(.teal).disabled(cleanName.isEmpty)
            Text("Saved only on this phone. No account, password or internet needed. You can change your name in People.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding(28).frame(maxWidth:520).frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(Color(uiColor:.systemBackground)).ignoresSafeArea(.keyboard,edges:.bottom)
    }
}
