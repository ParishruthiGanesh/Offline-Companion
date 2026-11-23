import SwiftUI
import CoreLocation
import MapLibre
import UIKit

struct ExplorePin {
    let key: String
    let title: String
    let subtitle: String
    let point: MapPoint
    let color: UIColor
}
struct MapCameraRequest: Identifiable {
    let id = UUID()
    let points: [MapPoint]
    var zoom: Double? = nil
}
final class ExploreAnnotation: MLNPointAnnotation {
    var key = ""
    var color = UIColor.systemBlue
}

// All style sources and Latin glyphs are local. There is no online basemap fallback.
struct NativeOfflineMap: UIViewRepresentable {
    let countries: [CountryOutline]
    let cities: [MapCity]
    let areas: [SavedMapArea]
    let pins: [ExplorePin]
    let route: OfflineWalkingRoute?
    let camera: MapCameraRequest?
    var onSelect: (String) -> Void
    var onDirections: (String) -> Void
    var onCenterChanged: (MapPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero, styleJSON: OfflineMapStyle.make(countries: countries, cities: cities, areas: areas, route: route))
        view.delegate = context.coordinator
        view.minimumZoomLevel = 1
        view.maximumZoomLevel = 19
        view.isPitchEnabled = false
        view.compassViewMargins = CGPoint(x: 20, y: 110)
        view.automaticallyAdjustsContentInset = false
        view.setCenter(CLLocationCoordinate2D(latitude: 32.6, longitude: -85.48), zoomLevel: 12, animated: false)
        context.coordinator.signature = signature
        return view
    }
    private var signature: String { areas.map { $0.id.uuidString }.joined() + (route?.id.uuidString ?? "") }
    func updateUIView(_ view: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if signature != coordinator.signature {
            coordinator.signature = signature
            coordinator.styleReady = false
            view.styleJSON = OfflineMapStyle.make(countries: countries, cities: cities, areas: areas, route: route)
        }
        let wanted = Set(pins.map(\.key))
        for (key, annotation) in coordinator.annotations where !wanted.contains(key) {
            view.removeAnnotation(annotation); coordinator.annotations[key] = nil
        }
        for pin in pins {
            let annotation: ExploreAnnotation
            if let existing = coordinator.annotations[pin.key] { annotation = existing }
            else {
                annotation = ExploreAnnotation(); annotation.key = pin.key
                coordinator.annotations[pin.key] = annotation
                annotation.coordinate = CLLocationCoordinate2D(latitude: pin.point.lat, longitude: pin.point.lon)
                annotation.title = pin.title; annotation.subtitle = pin.subtitle; annotation.color = pin.color
                view.addAnnotation(annotation)
            }
            annotation.coordinate = CLLocationCoordinate2D(latitude: pin.point.lat, longitude: pin.point.lon)
            annotation.title = pin.title; annotation.subtitle = pin.subtitle; annotation.color = pin.color
            view.view(for: annotation)?.backgroundColor = pin.color
        }
        if let camera, camera.id != coordinator.cameraID {
            if coordinator.styleReady { coordinator.apply(camera, to: view) }
            else { coordinator.pendingCamera = camera }
        }
    }
    static func dismantleUIView(_ uiView: MLNMapView, coordinator: Coordinator) { uiView.delegate = nil }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: NativeOfflineMap
        var signature = ""
        var cameraID: UUID?
        var pendingCamera: MapCameraRequest?
        var styleReady = false
        var annotations: [String: ExploreAnnotation] = [:]
        init(parent: NativeOfflineMap) { self.parent = parent }
        func apply(_ request: MapCameraRequest, to view: MLNMapView) {
            cameraID = request.id; pendingCamera = nil
            if let zoom = request.zoom, let first = request.points.first {
                view.setCenter(CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon), zoomLevel: zoom, animated: true)
            } else if request.points.count > 1 {
                var coordinates = request.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                view.setVisibleCoordinates(&coordinates, count: UInt(coordinates.count), edgePadding: UIEdgeInsets(top: 100, left: 40, bottom: 210, right: 40), animated: true)
            }
        }
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleReady = true
            if let pendingCamera { apply(pendingCamera, to: mapView) }
        }
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let pin = annotation as? ExploreAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "location-pin") ?? MLNAnnotationView(reuseIdentifier: "location-pin")
            view.frame = CGRect(x: 0, y: 0, width: pin.key == "previous" ? 13 : 23, height: pin.key == "previous" ? 13 : 23)
            view.layer.cornerRadius = view.frame.width/2
            view.layer.borderWidth = 3; view.layer.borderColor = UIColor.white.cgColor
            view.layer.shadowOpacity = 0.2; view.layer.shadowRadius = 3; view.layer.shadowOffset = CGSize(width: 0, height: 2)
            view.backgroundColor = pin.color
            view.accessibilityLabel = [pin.title,pin.subtitle].compactMap{$0}.joined(separator: ", ")
            return view
        }
        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { true }
        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            if let pin = annotation as? ExploreAnnotation { parent.onSelect(pin.key) }
        }
        func mapView(_ mapView: MLNMapView, rightCalloutAccessoryViewFor annotation: MLNAnnotation) -> UIView? {
            guard let pin = annotation as? ExploreAnnotation, pin.key != "me" && pin.key != "previous" else { return nil }
            let button = UIButton(type: .system); button.setTitle("Directions", for: .normal); button.sizeToFit()
            return button
        }
        func mapView(_ mapView: MLNMapView, annotation: MLNAnnotation, calloutAccessoryControlTapped control: UIControl) {
            if let pin = annotation as? ExploreAnnotation { parent.onDirections(pin.key) }
        }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            let coordinate = mapView.centerCoordinate
            let point = MapPoint(lat: coordinate.latitude, lon: coordinate.longitude)
            DispatchQueue.main.async { [weak self] in self?.parent.onCenterChanged(point) }
        }
    }
}

enum OfflineMapStyle {
    static func make(countries: [CountryOutline], cities: [MapCity], areas: [SavedMapArea], route: OfflineWalkingRoute?) -> String {
        func collection(_ features: [[String: Any]]) -> [String: Any] { ["type":"FeatureCollection","features":features] }
        func feature(_ geometry: [String: Any], _ properties: [String: Any] = [:]) -> [String: Any] { ["type":"Feature","geometry":geometry,"properties":properties] }
        let land = countries.map { country in
            feature(["type":"MultiPolygon","coordinates":country.rings.map { ring in [ring.map{[$0.lon,$0.lat]}] }], ["name":country.id])
        }
        let roads = areas.flatMap(\.features).map { item in
            feature(["type":"LineString","coordinates":item.points.map{[$0.lon,$0.lat]}], ["name":item.name,"kind":item.kind])
        }
        let cityFeatures = cities.map { feature(["type":"Point","coordinates":[$0.lon,$0.lat]],["name":$0.name]) }
        let countryLabels = countries.map { feature(["type":"Point","coordinates":[$0.center.lon,$0.center.lat]],["name":$0.id]) }
        let routeFeatures = route.map { [feature(["type":"LineString","coordinates":$0.points.map{[$0.lon,$0.lat]}])] } ?? []
        let glyphBase = Bundle.main.resourceURL!.appendingPathComponent("MapGlyphs").absoluteString
        guard let template = Bundle.main.url(forResource: "MapStyle", withExtension: "json"),
              let templateData = try? Data(contentsOf: template),
              var style = try? JSONSerialization.jsonObject(with: templateData) as? [String: Any] else {
            return "{\"version\":8,\"sources\":{},\"layers\":[]}"
        }
        style["glyphs"] = glyphBase+"/{fontstack}/{range}.pbf"
        style["sources"] = ["land":["type":"geojson","data":collection(land)],"roads":["type":"geojson","data":collection(roads)],
                            "cities":["type":"geojson","data":collection(cityFeatures)],"country-labels":["type":"geojson","data":collection(countryLabels)],
                            "route":["type":"geojson","data":collection(routeFeatures)]]
        guard let data = try? JSONSerialization.data(withJSONObject:style), let json = String(data:data,encoding:.utf8) else { return "{\"version\":8,\"sources\":{},\"layers\":[]}" }
        return json
    }
}
