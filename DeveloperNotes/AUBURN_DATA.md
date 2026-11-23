# Auburn bundled database

Source: https://download.geofabrik.de/north-america/us/alabama-latest.osm.pbf
Retrieved: 2026-11-04
Original extract: 151,535,477 bytes
Derived dataset: AuburnMap.json
SHA-256: 83aca4e08dfd402a25ee96ee31ac5fbc66cbdd56467c1b792bbe6a13ea31dc12
Database license: ODbL 1.0; see THIRD_PARTY_NOTICES.md.

Processing uses pyosmium to read OSM ways with resolved node locations. Highway and waterway segments touching the rectangle south 32.54, west -85.56, north 32.67, east -85.42 are retained, including boundary-crossing segment endpoints. Original node IDs and way IDs are preserved for connectivity. Access and foot one-way handling match MapAreaDownloader. No synthetic roads or inferred junctions are introduced. Administrative city boundaries are not used.

Validation: 11888 features, 83,161 points; coordinates finite and in valid ranges; all feature node lists match geometry lengths. Walking-eligible undirected connectivity contains 60,516 nodes with 57,407 in the largest component. College Street and Thach Avenue names are present. This connectivity check does not establish turn-by-turn correctness or route safety. Swift syntax and Xcode project structure checked; no native compiler is available in this environment. Phone rendering, GPS routing and airplane-mode tests remain required.

AuburnMap.json is listed in the Xcode resource phase. OfflineMapStore reads it directly from Bundle on reload, so no network request, manual import or first-run write is required. The built-in area is displayed in Saved areas and cannot be deleted. Additional saved areas remain removable.
