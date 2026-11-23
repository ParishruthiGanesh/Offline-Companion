# Unified build validation

- Swift source syntax parsing: completed for all production files.
- MapLibre style JSON: validated against the official @maplibre/maplibre-gl-style-spec package, all 12 layers accepted.
- MapLibre iOS 7.0.0 package manifest and key Objective-C API headers inspected from the matching official release. Swift-import names still require native compilation.
- Project file/source/resource references, bundled Latin glyphs and licence/data files: checked.
- Foundation-only core Swift test harness included. Execution is blocked here by absence of swiftc; it must not be reported as passing.
- Native build/runtime, actual map label appearance, saved-place migration, assistant auto-preparation, persistent pairing/last snapshots and offline route behavior need device regression tests.
- Existing user evidence covered earlier offline text/voice/GPS, the old compass display and old Nearby foreground sharing/reconnection. That does not establish that the new MapLibre map/router or Bluetooth background sharing passes.
