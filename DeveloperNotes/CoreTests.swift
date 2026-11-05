import Foundation

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fatalError("FAIL: " + label) }
    print("PASS: " + label)
}
func expect(_ error: WalkingRouteError, _ label: String, _ operation: () throws -> OfflineWalkingRoute) {
    do { _ = try operation(); fatalError("FAIL: expected " + label) }
    catch let actual as WalkingRouteError { check(actual == error, label) }
    catch { fatalError("FAIL: unexpected error \(error)") }
}
func feature(_ ids: [Int64], _ points: [MapPoint], way: Int64, allowed: Bool = true, oneWay: Bool = false, reverse: Bool = false) -> MapFeature {
    MapFeature(kind: "residential", name: "Test path", points: points, osmNodes: ids,
               walkingAllowed: allowed, footOneWay: oneWay, footReverse: reverse, osmWayID: way)
}
func area(_ features: [MapFeature]) -> SavedMapArea {
    SavedMapArea(id:UUID(),name:"Test",created:Date(),center:MapPoint(lat:0,lon:0),radiusKM:1,features:features)
}
let a = MapPoint(lat:0,lon:0), b = MapPoint(lat:0.001,lon:0.001), c = MapPoint(lat:0,lon:0.002)
let detour = area([feature([1,2,3],[a,b,c],way:1),feature([1,3],[a,c],way:2,allowed:false)])
let result = try OfflineWalkingRouter.calculate(areas:[detour],from:a,to:c)
check(result.distance > 300 && result.distance < 320 && result.points.count == 3,"blocked shortcut is excluded")
check(abs(OfflineWalkingRouter.metres(a,MapPoint(lat:0,lon:0.001))-111.195) < 0.1,"distance uses geographic metres")
let longSegment = area([feature([100,101],[MapPoint(lat:0,lon:0),MapPoint(lat:0,lon:0.01)],way:100)])
let nearbyRoute = try OfflineWalkingRouter.calculate(areas:[longSegment],from:MapPoint(lat:0,lon:0.004),to:MapPoint(lat:0,lon:0.0045))
check(nearbyRoute.distance > 55 && nearbyRoute.distance < 56,"nearby endpoints on one road segment route without junction detours")
let crossing = area([
    feature([10,11,12],[MapPoint(lat:0,lon:0),b,MapPoint(lat:0.002,lon:0.002)],way:10),
    feature([20,21,22],[MapPoint(lat:0,lon:0.002),b,MapPoint(lat:0.002,lon:0)],way:20)
])
expect(.disconnected,"geometric crossing without shared OSM node is not a junction") {
    try OfflineWalkingRouter.calculate(areas:[crossing],from:a,to:c)
}
let oneWay = area([feature([1,2],[a,b],way:30,oneWay:true)])
expect(.disconnected,"one-way foot restriction blocks reverse travel") { try OfflineWalkingRouter.calculate(areas:[oneWay],from:b,to:a) }
let reverseWay = area([feature([1,2],[a,b],way:31,oneWay:true,reverse:true)])
let reverseResult = try OfflineWalkingRouter.calculate(areas:[reverseWay],from:b,to:a)
check(reverseResult.points.count == 2,"reverse one-way foot restriction is supported")
expect(.disconnected,"reverse one-way does not allow forward travel") { try OfflineWalkingRouter.calculate(areas:[reverseWay],from:a,to:b) }
expect(.tooFar,"unmapped origin is rejected") { try OfflineWalkingRouter.calculate(areas:[detour],from:MapPoint(lat:1,lon:1),to:c) }
let oldArea = area([MapFeature(kind:"residential",name:"Old",points:[a,b])])
expect(.noData,"legacy display-only maps require a new download for routing") { try OfflineWalkingRouter.calculate(areas:[oldArea],from:a,to:b) }
let oldJSON = try JSONSerialization.data(withJSONObject:["latitude":32.6,"longitude": -85.48,"accuracy":5.0,"savedAt":0.0])
let migrated = try JSONDecoder().decode(MeetingPoint.self,from:oldJSON)
check(migrated.name == "Meeting point","old meeting point migrates without losing coordinates")
var named = migrated; named.name = "Home"
let restored = try JSONDecoder().decode(MeetingPoint.self,from:JSONEncoder().encode(named))
check(restored.id == named.id && restored.name == "Home" && restored.latitude == 32.6,"named place round trip preserves identity and coordinates")
let invalid = SharedLocationPacket(version:1,id:UUID(),latitude:91,longitude:0,accuracy:5,recordedAt:Date(),sentAt:Date())
check(!invalid.valid,"invalid received coordinates are rejected")
print("All offline core tests passed.")
