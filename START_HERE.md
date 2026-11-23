# Save-place feedback update

Saved places now always offers Refresh GPS and Open location settings, and shows why Save is disabled. Type a name for the CURRENT position, allow location with Precise Location on, tap Refresh GPS, and wait for a reading less than 60 seconds old. This field labels the current position; it is not address search. If the GPS expires while the save confirmation is open, the app keeps the entered name and reports that it did not save.

To see a paired person: on THEIR phone enable Share my location and allow GPS. On YOUR phone open Map > People, find their last received location and tap Show on map. A map marker is added only after an actual location packet arrives. Connection alone does not provide a position. Check GPS/receipt timestamps; a gray marker represents a disconnected person’s last known location.

Source syntax checked; fresh-fix and on-device save tests remain required.

---

# Welcome/name screen added

Install over the existing app. This update asks for your name once in a welcome screen. Enter a nonblank name (up to 20 characters) and tap Continue. The name is saved locally and used in Bluetooth invitations. After relaunch the welcome screen is skipped. Change the name later in Map > People > Your name. No email, password, account server or internet is required.

Existing custom names are prefilled; the old placeholder “My phone” is left blank. Models, saved places, Auburn map and accepted Bluetooth pairing are retained. If a pairing QR link opens the app before welcome is complete, it waits until you finish naming the phone.

Source syntax and project checks passed. On-device first launch, relaunch and pairing-name display need your test.

---

# Background permission and voice input update

Install on both phones over the existing apps. The accepted QR pairing and Auburn map remain included.

Background location: in People > Background sharing, read the displayed permission status. Tap Allow background location. If iOS does not show a new prompt, use Open Settings → Location → Always, and enable Precise Location. Always permission is not a guarantee of uninterrupted Bluetooth/GPS execution. Confirm background receipt times with both phones locked. The UI refreshes permission status when returning from Settings.

Voice: in Assistant, tap the microphone, grant Microphone and Speech Recognition permissions, speak in English (US), tap Stop, review the recognized text, then tap Send. Recognition requests require on-device processing; no cloud transcription fallback is enabled. English (US) on-device recognition must be supported and its resources available on the phone. If unavailable or recognition fails, the app displays a message and typing remains usable. Dictation replaces the current question when recognized text arrives; it never sends automatically. Recording stops when leaving Assistant, entering background, switching models, starting generation, or using read-aloud.

Test voice online once for permissions, then in airplane mode after relaunch; confirm captured text and local Llama answer. Check read-aloud still works after microphone use. Denied permissions, no speech, and cancellation must recover to typed input. These native-device tests remain unverified here; source syntax, project structure and plist declarations are checked.

Current providers: Meta Llama 3.2 1B Instruct Q4_K_M for text; Hugging Face SmolVLM 500M for photos; Apple Speech for on-device English (US) transcription; Apple speech synthesis for read-aloud; Apple Core Bluetooth/Core Location for pairing and positioning; MapLibre/OpenStreetMap for offline maps. No Meta API calls or video understanding are integrated. Existing People name fields are saved locally; welcome/name onboarding is deferred until the final UI pass.

---

# Invitation delivery update

Install this build on BOTH phones over the existing apps. Open People on both with Bluetooth enabled. On the scanning phone, cancel any waiting invitation, then scan the other phone’s current QR once. Keep both apps open.

The phone whose QR was scanned should show the scanner’s name and Accept invitation. The scanner now retries the request automatically. Both screens display connection progress: looking for the phone, opening the invitation channel, request delivered, or invitation received. If Accept still does not appear, report the progress line from BOTH phones; this distinguishes Bluetooth discovery from invitation delivery failures.

This build isolates Bluetooth state restoration by the pairing secret’s service identifier, checks restored services, retries unconfirmed invitations/acceptance every three seconds while the foreground app runs, and clears abandoned pending invitations when the subscriber leaves. It does not change the location update interval or promise background timer execution. These fixes address identified failure paths; successful two-phone invitation delivery is not yet verified here.

---

# Simple pairing — install this build on BOTH phones

1. Open Map > People on both phones and enter your names. Each phone shows a QR automatically.
2. On EITHER phone, tap Scan their QR and scan the other phone’s QR. Allow Camera access if asked. Only one phone needs to scan.
3. On the phone whose QR was scanned, tap Accept invitation when the scanner’s name appears.
4. Wait for Connected to [name] on both. That completes pairing. Turn on Share my location separately on each phone that wants to send it.

No copy/paste links or manual confirmation on the scanning phone. Decline rejects the request without sharing a location. Both phones must be nearby with Bluetooth on and the apps open for this initial test. Pairing uses encrypted Bluetooth messages and works without internet. The built-in Auburn map is included.

This version adds an explicit request/accept/acknowledgement handshake and a camera QR scanner. Install over the existing app to retain models/maps/places, then pair again once using this new flow. Old invitation QR codes are not compatible. Names identify the requested person in the UI; they are not verified account identities. Location sharing stays off until enabled. Background timing and range limits still apply.

Source syntax, resource registration and archive checks completed. Native compilation and the two-phone handshake have not been run in this environment.

---

# Built-in Auburn map — start here

1. Extract this ZIP and open its OfflineCompanion.xcodeproj in Xcode.
2. Run on your phone over the existing installation. Do not delete the installed app.
3. Open Map. Central Auburn and university-area roads are included with this build: no map download is needed.
4. To centre the map, open Offline maps, then tap “Auburn centre & university · built in”.
5. Turn off Wi-Fi and cellular data and check that streets remain visible. Keep Bluetooth on only when testing nearby sharing.
6. With a fresh precise GPS fix, select a saved place in this coverage and test Directions. Route calculation is experimental and has not been tested on an iPhone here.

Coverage: approximately 32.54–32.67° N and 85.56–85.42° W (central Auburn and surrounding university area), not the entire Auburn municipal boundary or Alabama. The built-in dataset occupies about 5.6 MB before app compression. Street data is a snapshot, not live hazard/access information. Pairing, AI models and downloaded maps already stored on the phone should be retained when installing over the existing app.

Additional-area downloads still depend on public map services and may fail. The bundled Auburn area works independently of those services. Existing model downloads are separate from this map.

---

# Map download update

This build uses the current Private.coffee endpoint and tries a second provider when the first returns invalid data, including an HTTP 200 response containing a server error. Errors now distinguish no internet, oversized responses, HTTP failures and timeouts. Public servers can still be unavailable. On-device download success remains unverified. Install this build over the existing app and test one 1 km download while online. If it fails, retain the exact error message.

# Offline Companion — unified app build

## Install
1. Close the old Xcode project, extract this ZIP into a new folder and open OfflineCompanion.xcodeproj.
2. Keep the Mac ONLINE for Xcode's new MapLibre 7.0.0 package download. No map API key is required. Let package resolution finish, then run on both phones in turn.
3. Keep the same signing team and bundle identifier. Install OVER the existing apps; do not delete them. AI models, saved places and map data remain available. The old pairing setup is replaced by the new invitation flow; pair the two phones once again.
4. Assistant now prepares its saved model automatically on launch and when switching Text/Photo. A device without models still needs one initial download consent, but there is no Load model step. Map and People can be used without downloading AI models onto the second phone.

## Two main tabs
- Assistant: offline Meta Llama chat and the existing experimental SmolVLM photo descriptions. Automatic preparation may take a moment; failures show Try again.
- Map: one full-screen MapLibre map with People, Saved places and Offline maps. The old separate Location, Nearby and Bluetooth tabs are removed. Sharing uses ONE saved Bluetooth pairing, not two competing transports.

## Named places
Open Map > Saved places. Enter Home, Car, Campsite, or another name, then Save place. Check GPS accuracy before confirming. Multiple named places stay saved after app restart. The existing meeting point migrates as Meeting point; use its ellipsis menu > Rename. Show centres the map on it; Directions calculates an offline walking-route preview. Use for compass selects the point for the existing compass arrow in this sheet.

## People, latest and last-known locations
Open Map > People on both updated phones. Each shows its own QR automatically. One phone scans the other; the phone displaying that QR taps Accept invitation. No paste-link or scanner-side confirmation is needed. The new flow replaces earlier pairing setups. Keep the QR private.

Enable Share my location once on each phone that wants to send its own position. Opt-in remains saved until switched off. New GPS readings send automatically, no more often than every 10 seconds, when a nearby Bluetooth link is available. There is no Send button or repeated invitation step. Pairing is retained across launches and pending Bluetooth reconnect requests are used when a link drops. The existing iOS background limitations remain; verify on both phones.

The map shows:
- Blue: your last GPS reading.
- Orange: saved named places.
- Pink: the paired phone's latest received position while connected.
- Grey: its last-known position when disconnected, plus a small previous-update marker.

Connection is NOT proof of a current position. Tap a marker or the person's card to see the recorded GPS time, accuracy and/or receipt age. The latest and previous received positions are now retained with the pairing in this-device-only Keychain. They survive app restart and are removed on Forget pairing. This is two snapshots, not a movement history. Turning off sharing cannot remove data already received by another phone.

## Clearer offline map
The former Canvas renderer is replaced by MapLibre Native. Roads have casing, names follow roads, and labels use collision avoidance instead of drawing over each other. Pan, pinch and tap pins normally. Fonts for Latin labels are bundled; no network basemap fallback is used. Areas outside saved local street coverage still show only coarse country/major-city overview data. This is NOT every street nationwide, satellite imagery, or Google's map dataset.

## Walking directions without internet
1. While online, open Map > Offline maps and download coverage around the entire intended walk (1/3/5 km radius around the current map centre). If downloading fails, read the service-specific error. A smaller radius only helps when the response is too large; it does not fix unavailable servers.
2. Older downloads still display, but must be downloaded AGAIN for walking connections. They previously discarded OSM node IDs/access tags. The download list labels old areas Display only.
3. Obtain a recent GPS fix with estimated accuracy within ±100 m. The supplied screenshot showed about ±4.8 km, which is insufficient for a walking origin. Enable Precise Location and try outdoors. A saved place or person's location also needs acceptable accuracy.
4. Turn internet off. Tap a named place or the paired person's latest/last-known marker and choose Walking directions. A blue line follows connected downloaded paths. Steps lists named paths/roads and segment lengths.
5. Routes use actual shared OSM node IDs (geometric crossings are not assumed to connect), walking access tags, and explicit one-way foot restrictions. The calculator refuses missing/disconnected coverage rather than drawing a straight line as a route.
6. Start and destination can be up to 150 m from a mapped node; those off-path gaps are NOT routed and are shown separately. If both snap to the same node the app suggests distance/compass rather than claiming a walking route.
7. Directions to a person target their last received snapshot. They may have moved. When another update arrives while their route is displayed, a new calculation is attempted. This is a route preview with basic road-following steps, not a complete spoken turn-by-turn navigation system.

The experimental router does NOT evaluate current closures, flooding, all crossing/barrier restrictions, accessibility, stairs suitability or route safety. It is not a production routing engine. Follow local restrictions and surroundings. Route behavior and iOS rendering remain to be field-tested.

## Background test
Use People on both phones; Bluetooth on, Wi-Fi/cellular may be off after setup. Allow background location access and Precise Location, start sharing in the foreground, then lock only the sender while leaving the receiver open. Move outdoors within nearby range and verify NEW GPS timestamps arrive without unlocking the sender. Reverse roles. For both locked, inspect the receipt-time test log to distinguish delivery during the lock interval from delivery after reopening.

Background modes and restoration identifiers are configured. iOS controls scheduling; a fixed 10-second background interval is not guaranteed. Force-quitting by swiping the app away stops execution. Out of range, Bluetooth off, revoked permissions or battery loss prevent updates. Pairing being remembered does not guarantee an always-live connection. No SOS or rescue dispatch is implemented.

## Validation
Completed here: Swift syntax parsing, Xcode project/resource checks, MapLibre style-spec validation, bundled font/data presence and ZIP integrity. Public regional-map server tests previously returned errors/timeouts here, though your screenshot shows your phone displayed a downloaded road area.

This environment has no Swift compiler/Xcode. Native iOS compilation, visual rendering, model auto-start, migration/persistence, background BLE delivery and walking-route field tests remain for your Mac/phones. DeveloperNotes/run-core-tests.py compiles the ACTUAL production router/models on a Mac and tests blocked shortcuts, disconnected geometric crossings, foot one-way restrictions, missing coverage, old-place migration and named-place persistence. Those Swift tests are included but could not be executed here.
