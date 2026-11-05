# Offline Companion

**An iPhone prototype that keeps basic assistance available when the internet is not.**
Meta Llama 3.2 1B Instruct runs directly on the phone for text answers — no cloud inference,
no API key, no account — alongside a bundled offline OpenStreetMap area, named saved places,
a compass, and encrypted nearby location sharing with one trusted person over Bluetooth.

> **Prototype, not an emergency service.** Offline Companion has no satellite link, no SOS
> transmission, and no connection to rescue or dispatch services. It cannot guarantee anyone's
> safety. See [Limitations](#limitations-and-what-is-not-implemented).

---

## Table of contents

- [Purpose and intended users](#purpose-and-intended-users)
- [What the app does](#what-the-app-does)
- [Working on device](#working-on-device)
- [Limitations and what is not implemented](#limitations-and-what-is-not-implemented)
- [Meta Llama integration — exact details](#meta-llama-integration--exact-details)
- [Which component powers which feature](#which-component-powers-which-feature)
- [Why these models](#why-these-models)
- [Setup: build and run on a physical iPhone](#setup-build-and-run-on-a-physical-iphone)
- [Downloading the models](#downloading-the-models)
- [Pairing two phones and sharing location](#pairing-two-phones-and-sharing-location)
- [Testing offline operation](#testing-offline-operation)
- [Architecture](#architecture)
- [Data handling and privacy](#data-handling-and-privacy)
- [Troubleshooting](#troubleshooting)
- [Demo video](#demo-video)
- [Licensing and attribution](#licensing-and-attribution)
- [Repository layout](#repository-layout)

---

## Purpose and intended users

Connectivity is not evenly distributed, and the moments people most want a second opinion are
often the moments they have no bars. Offline Companion is built for:

- **People travelling alone**, including women who want a way to think through a situation and
  draft a check-in message without needing a signal.
- **People in unfamiliar places**, who need to orient themselves and ask practical questions.
- **Hikers and travellers moving through areas without coverage**, who want a known saved point,
  a direction, and a nearby companion's last known position.

The design goal is narrow and honest: make a small amount of genuinely useful help work with the
radios switched off, and be explicit about everything it cannot do.

## What the app does

The app has two tabs: **Assistant** and **Map**.

**Assistant**
- **Offline text questions** answered by Meta Llama 3.2 1B Instruct running on the phone.
- **Read aloud** for any answer, using an English voice already installed on the phone.
- **Voice input** that turns speech into *editable* text with Apple's on-device recogniser; nothing
  is sent automatically, and there is no cloud transcription fallback.
- **Experimental photo questions** answered locally by SmolVLM-500M-Instruct (a Hugging Face
  model — **not** a Meta model).

**Map**
- **GPS coordinates** with the accuracy estimate and the timestamp of the reading.
- **Named saved places** ("Home", "Car", "Campsite") that store the current GPS position.
- **A compass arrow and straight-line distance** toward a selected saved place.
- **A bundled offline street map** of central Auburn, Alabama and the university area, rendered
  with MapLibre Native from OpenStreetMap data — available with no download and no network.
- **Experimental offline walking routes** computed from the bundled/downloaded road and path graph.
- **People**: QR-based pairing with one nearby trusted phone, and encrypted Bluetooth exchange of
  GPS readings once each side separately opts in.

A welcome screen asks for a display name once and stores it on the phone. There is no email,
password, account server, or online login anywhere in the app.

**Each question is independent.** The model context is cleared before every question
(`llama_memory_clear`), and only the current question is placed in the prompt. The app does not
have conversational memory, and chat history is held in memory only — it is not written to disk
and does not survive a relaunch.

## Working on device

Every capability below has been run on real hardware — an iPhone 13 with 128 GB, plus a second
iPhone for pairing. Most of it is captured in the demo video, recorded in airplane mode.

| Capability | Confirmed on device |
|---|---|
| Offline Meta Llama text answers | Answers generated on the phone in airplane mode, in about 4.6 seconds, including after a cold relaunch |
| Read aloud | Any answer spoken back with an installed Apple voice, offline |
| Voice input | Speech turned into editable text by Apple's on-device English (US) recogniser, with no network |
| Offline photo questions | SmolVLM describes a chosen photo entirely on the phone — an experimental mode; at 500M parameters it misses and misidentifies things |
| GPS readings | Live coordinates with accuracy and reading timestamps |
| Named saved places | Current position saved under a name, with GPS-freshness feedback before saving |
| Compass direction | Bearing and straight-line distance to a saved place |
| Offline map rendering | Central Auburn street data rendered by MapLibre with no network and no tiles to fetch |
| Offline walking routes | A 225 m route computed on the phone over real mapped OpenStreetMap paths, offline |
| Trusted-person pairing | QR → invitation → Accept handshake completed between two phones |
| Encrypted nearby sharing | GPS readings exchanged over Bluetooth, with each position's timestamp and accuracy shown |

All of this runs with Wi-Fi and cellular switched off. The only step that needs internet is the
one-time model download during setup.

**Still being tested.** Sustained background delivery while the phone is locked depends on how iOS
schedules execution, so it is not yet characterised. Downloading map areas beyond the bundled
Auburn dataset relies on public Overpass servers, which have been unavailable during testing — the
built-in Auburn map works without them. See
[Limitations](#limitations-and-what-is-not-implemented) for the full picture, and
[`DeveloperNotes/VALIDATION.md`](DeveloperNotes/VALIDATION.md) for what was checked where.

## Limitations and what is not implemented

**Not implemented at all:**

- Satellite communication or satellite alerts.
- SOS transmission, emergency broadcast, or rescue dispatch of any kind.
- Video understanding.
- Guaranteed continuous background tracking.
- Full-country or nationwide street maps.
- Manual address search or manual coordinate entry.
- Verified online user accounts.

**Real constraints you should understand before trusting any part of this:**

- **Initial model downloads require internet.** Text and photo inference run on the phone *after*
  the weights are installed.
- **Bluetooth range is limited.** Nearby sharing works over Bluetooth Low Energy between two
  phones in range. This is not worldwide tracking.
- **A "Connected" state does not prove a location is fresh.** The UI shows the GPS timestamp,
  the accuracy, and the receipt age for exactly this reason. Read them.
- **Background delivery depends on iOS.** Background modes and restoration identifiers are
  configured, but iOS controls scheduling. The 10-second minimum send interval is a floor, not a
  promise. Force-quitting the app (swiping it away) stops all background work.
- **Names are local display names, not verified identities.** Anyone can type any name.
- **The bundled map covers roughly 32.53–32.67° N, 85.56–85.42° W** — central Auburn and the
  university area. Not the whole Auburn municipality, not Alabama, not the country.
- **Map data is a snapshot**, not live hazard, closure, flooding or access information.
- **The walking router is a preview, not a navigation engine.** It does not evaluate closures,
  flooding, every barrier or crossing restriction, accessibility, stairs suitability, or safety.
- **The models make mistakes.** A 1B text model and a 500M vision model are small. Treat answers
  as a starting point, never as authoritative guidance about a real situation.

## Meta Llama integration — exact details

This is the precise integration, read off the code in
[`OfflineCompanion/ModelFiles.swift`](OfflineCompanion/ModelFiles.swift) and
[`OfflineCompanion/LocalLlama.swift`](OfflineCompanion/LocalLlama.swift).

| Property | Value |
|---|---|
| Model | **Meta Llama 3.2 1B Instruct** |
| Format / quantisation | GGUF, **Q4_K_M** |
| File | `Llama-3.2-1B-Instruct-Q4_K_M.gguf` |
| Exact size | `807,694,464` bytes (~808 MB) |
| Pinned SHA-256 | `6f85a640a97cf2bf5b8e764087b1e83da0fdb51d7c9fab7d0fece9385611df83` |
| Download source | [`bartowski/Llama-3.2-1B-Instruct-GGUF`](https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF) (community GGUF conversion of Meta's weights) |
| Inference runtime | `llama.cpp`, reached from Swift via [LlamaSwift](https://github.com/mattt/llama.swift) `2.10549.0` (exact version pin) |
| Where weights live | `Application Support/Models/`, excluded from iCloud/iTunes backup |
| Context window | 2048 tokens (`n_ctx`) |
| Batch / micro-batch | 128 / 128 |
| Threads | `max(1, min(4, activeProcessorCount - 1))` |
| GPU offload | `n_gpu_layers = -1` on device (all layers); `0` in the simulator |
| Sampling | Greedy (`llama_sampler_init_greedy`) — deterministic, no temperature |
| Answer cap | 192 tokens for text |
| Conversation state | **Cleared before every question.** No multi-turn memory. |

**The app uses downloaded Meta model weights locally. It makes no Meta Model API calls** — there
is no inference endpoint, no API key, and no account. The only network traffic the app ever
initiates is: (1) the one-time model download you explicitly confirm, (2) an optional Overpass map
download you explicitly request, and (3) opening a license or model-card link you tap.

Weights are verified before installation: the downloaded file must match both the expected byte
size **and** the pinned SHA-256, streamed in 4 MB chunks, before it is moved into place. A
mismatched or truncated file is rejected rather than loaded.

The system prompt (`PromptBuilder` in `LocalLlama.swift`) constrains the assistant deliberately:
it is told it has no internet, no current news, no location-reading tool, and no messaging tools;
that it cannot operate the Map screens; that it must say when it does not know; and that it must
never invent observations, alerts or rescue activity. It can draft a message for you to review,
but the chat cannot send anything.

**Meta's licenses apply to the weights.** Review and comply with the
[Llama 3.2 Community License](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/blob/main/LICENSE.txt)
and the [Acceptable Use Policy](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/blob/main/USE_POLICY.md)
before downloading, using or redistributing them. No weights are included in this repository.

Built with Llama.

## Which component powers which feature

Attribution matters, so this is explicit. **Meta Llama powers the offline text assistant and
nothing else.** It does not power photo understanding, speech, maps, GPS, or Bluetooth.

| Feature | Powered by |
|---|---|
| Offline text answers, message drafting, supportive responses | **Meta Llama 3.2 1B Instruct** (GGUF Q4_K_M, via llama.cpp / LlamaSwift) |
| Experimental offline photo questions | **SmolVLM-500M-Instruct** by HuggingFaceTB + its `mmproj` vision projector (GGUF Q8_0, via llama.cpp `mtmd`) — **not a Meta model** |
| Voice input (speech → editable text) | **Apple** `SFSpeechRecognizer`, on-device English (US) only |
| Read aloud | **Apple** `AVSpeechSynthesizer` with an installed English voice |
| GPS, accuracy, timestamps, compass heading | **Apple** Core Location |
| Nearby pairing and location exchange | **Apple** Core Bluetooth, CryptoKit (AES-GCM), Keychain |
| Photo resizing before inference | **Apple** ImageIO / Core Graphics |
| Map rendering | **MapLibre Native iOS 7.0.0** |
| Street, path and waterway data | **OpenStreetMap** contributors (ODbL) |
| Country outlines and major-city points | **Natural Earth** 1:110m (public domain) |
| Map label glyphs | **Noto Sans** Regular, Latin range (SIL OFL) |

### SmolVLM — the experimental photo path

| Property | Value |
|---|---|
| Model | `SmolVLM-500M-Instruct-Q8_0.gguf` — `436,806,912` bytes, SHA-256 `9d4612de6a42214499e301494a3ecc2be0abdd9de44e663bda63f1152fad1bf4` |
| Vision projector | `mmproj-SmolVLM-500M-Instruct-Q8_0.gguf` — `108,783,360` bytes, SHA-256 `d1eb8b6b23979205fdf63703ed10f788131a3f812c7b1f72e0119d5d81295150` |
| Combined download | ~546 MB (both files are required) |
| Source | [`ggml-org/SmolVLM-500M-Instruct-GGUF`](https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF) · [model card](https://huggingface.co/HuggingFaceTB/SmolVLM-500M-Instruct) |
| Photo preprocessing | Resized on device to at most **768 px** on the longest side, EXIF orientation normalised, re-encoded as JPEG at quality 0.85 |
| Answer cap | 96 tokens |

Only one model is loaded at a time. Switching between Text and Photo unloads the previous model
first. **Photo recognition is genuinely unreliable at this size** — in device testing it missed
objects and misidentified others. It is included as an experiment, not as a feature to rely on.

## Why these models

Model selection was driven by what fits and runs on the test hardware, not by a benchmark sweep.

- **Development machine:** Apple M4 Max MacBook, 128 GB memory.
- **Primary test device:** iPhone 13, 128 GB storage. A second iPhone was used for pairing tests.

The constraint that mattered was the phone, not the Mac. A 1B-parameter instruct model at 4-bit
quantisation leaves roughly 800 MB on disk and fits in an iPhone 13's memory budget alongside a
SwiftUI app, Core Bluetooth, Core Location and a MapLibre map. **Meta Llama 3.2 1B Instruct
Q4_K_M** was selected because it is an instruction-tuned model at that size with a clearly
documented license, a well-supported GGUF conversion, and good llama.cpp support — which is what
makes on-device text answers, basic reasoning, message drafting and supportive responses possible
with the radios off.

**SmolVLM-500M-Instruct Q8_0** was added for experimental photo understanding because a
500M-parameter VLM plus its projector is one of the few image-capable options that fits the same
budget. It is a Hugging Face model, not a Meta model.

**Meta V-JEPA 2** was investigated for video understanding and **not integrated**: it is not a
ready-to-use video chat model, and there is no established iPhone deployment path for this use
case.

This was practical selection under device constraints. **It was not an exhaustive benchmark**, and
no performance comparison between candidate models is claimed. Small local models tested here
produced noticeably imperfect photo recognition.

## Setup: build and run on a physical iPhone

### Requirements

- A Mac with **Xcode 16** or newer (project `objectVersion = 56`, `LastUpgradeCheck = 1600`).
- **iOS 17.0 or newer** on the device (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`).
- An Apple Developer account for signing (a free account works for development installs).
- **Internet on the Mac for the first build**, so Swift Package Manager can resolve MapLibre and
  LlamaSwift. No map API key is required, at any point.
- **~2 GB free on the phone** for the Llama download and its verification copy; ~1.4 GB more if
  you also install the SmolVLM files.

### Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/ParishruthiGanesh/Offline-Companion.git
   ```
2. Open `OfflineCompanion.xcodeproj` in Xcode.
3. **Let Swift Package Manager finish resolving** before building. The project pins exact versions:
   - [`maplibre/maplibre-gl-native-distribution`](https://github.com/maplibre/maplibre-gl-native-distribution) `7.0.0`
   - [`mattt/llama.swift`](https://github.com/mattt/llama.swift) `2.10549.0` (product `LlamaSwift`)
4. **Set your own signing team.** Select the `OfflineCompanion` target → *Signing & Capabilities* →
   choose your team. Code signing is `Automatic`. The committed project still carries the original
   author's `DEVELOPMENT_TEAM`; replace it with yours, and change
   `PRODUCT_BUNDLE_IDENTIFIER` (`com.parishruthi.OfflineCompanion`) to an identifier you own.
5. Select your connected iPhone as the run destination and press **Run**. The simulator will build,
   but GPS, the compass, Bluetooth pairing and Metal GPU offload need real hardware.
6. On first launch, enter a display name (up to 20 characters) and tap **Continue**. It is stored
   locally and shown to a paired phone.

> **Installing over an existing build:** keep the same signing team and bundle identifier and
> install over the old app rather than deleting it. Downloaded models, saved places, saved map
> areas and an accepted pairing are all preserved.

The app targets iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), but it is designed and tested
as an iPhone app.

## Downloading the models

No weights ship with this repository. Both models are fetched on device, once, with your explicit
confirmation.

**In-app download (recommended)**

1. Connect the phone to Wi-Fi.
2. Open **Assistant**. With the **Text** mode selected, tap **Set up offline chat — 808 MB** and
   confirm. Keep the app open; the download is verified against its pinned SHA-256 before install.
3. For the experimental photo mode, switch the picker to **Photo** and tap
   **Set up offline photos — 546 MB**. Both SmolVLM files are fetched in sequence.
4. After setup the assistant prepares its saved model automatically on launch and when you switch
   modes. There is no "Load model" step.

**Manual import (Advanced)**

If you already have the exact files, use *Advanced: import existing files* on the setup screen.
The filenames, byte sizes and SHA-256 hashes must match exactly — see the tables above. For photo
mode you must import **both** the model and the `mmproj-` projector.

Files land in `Application Support/Models/` and are excluded from backup. Deleting the app deletes
them.

## Pairing two phones and sharing location

Pairing is a deliberate, in-person, consent-based handshake. Install the same build on **both**
phones, turn Bluetooth on, and keep both apps open for the first pairing.

1. On both phones, open **Map → People**. Each phone displays its own private QR automatically.
2. On **either** phone, tap **Scan their QR** and scan the other phone's QR. Allow Camera access
   if asked. **Only one phone needs to scan.**
3. On the phone **whose QR was scanned**, the scanner's name appears with **Accept invitation** /
   **Decline**. Tap **Accept**.
4. Wait for **Connected to [name]** on both phones. That completes pairing.
5. **Each phone separately turns on "Share my location."** Pairing alone shares nothing. The opt-in
   is remembered until switched off.

Once sharing is on, new GPS readings are sent automatically — **no more often than every 10
seconds** — whenever a Bluetooth link is available. There is no Send button.

**For background sharing:** in **People → Background sharing**, read the permission status, tap
**Allow background location**, and if iOS shows no new prompt use **Open Settings → Location →
Always** with **Precise Location** enabled. "Always" permission still does not guarantee
uninterrupted execution.

**Map marker colours**

| Colour | Meaning |
|---|---|
| 🔵 Blue | your last GPS reading |
| 🟠 Orange | your saved named places |
| 🩷 Pink | the paired phone's latest received position, while connected |
| ⚪ Grey | its last-known position while disconnected, plus a small previous-update marker |

**Important:** a marker appears only after an actual location packet arrives. Connection alone
does not provide a position. Tap a marker or the person's card to see the GPS time, accuracy and
receipt age. Two snapshots are retained (latest and previous) — this is not a movement history.
Turning sharing off cannot remove data the other phone already received.

**Protocol summary** (full detail in [`DeveloperNotes/PAIRING_FLOW.md`](DeveloperNotes/PAIRING_FLOW.md)):
each unpaired phone generates an independent 256-bit random secret, encoded in its QR and used to
derive its own BLE service UUID (`SHA-256` of the key, first 16 bytes). Control and location
messages are AES-GCM authenticated under that key. Accept binds the pairing to a specific request
UUID; the host shows *Connected* only after a matching acknowledgement. No location message can
itself create a pairing. Declining returns the scanner to its own QR without sharing anything.
Pairings and pending requests persist in the Keychain with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and **Forget pairing** removes them along with
the stored snapshots. Old-protocol QR codes are not accepted.

> **Never share your pairing QR publicly.** It carries the secret that authenticates your link.
> Keep real QR codes, pairing secrets and personal coordinates out of screenshots, recordings,
> issues and commits.

## Testing offline operation

The point of the project is that this works. Test it properly.

**Offline text (the core claim)**

1. While online, complete the Llama download and ask one question to confirm the model loads.
2. Turn on **Airplane Mode**, and switch **Wi-Fi and cellular data off** (keep Bluetooth on only
   if you are also testing sharing).
3. **Force-quit and relaunch the app.** This proves the model is loaded from local storage, not
   held from a previous session.
4. Ask a question. The answer header shows `Meta Llama • local answer` and the footer reports the
   generation time and that it was *generated on this device*.
5. Tap **Read aloud** on the answer.
6. Ask a second, unrelated question to confirm answers are independent.

**Offline voice input**

Test once while online to grant Microphone and Speech Recognition permissions, then repeat in
Airplane Mode after a relaunch. Tap the microphone, speak English (US), tap Stop, review the
recognised text, then tap **Send**. It never sends automatically. If on-device English (US)
recognition is unavailable on the phone, the app says so and typing still works.

**Offline map and places**

1. Open **Map**. Central Auburn and university-area streets are built in — no download needed.
2. **Offline maps → "Auburn centre & university · built in"** centres the map there.
3. With Wi-Fi and cellular off, confirm streets and labels still render.
4. Outdoors with **Precise Location** on, tap **Refresh GPS**, wait for a reading less than 60
   seconds old, type a name, and **Save place**. The Save button explains itself when disabled.
5. Select the saved place and check the compass arrow and distance.
6. Try **Walking directions** to a saved place inside the Auburn coverage. All 11,888 bundled
   features carry OSM node IDs and walking-access flags, so routing works on the bundled area
   with no download. A GPS fix within about ±100 m is required.

**Offline nearby sharing**

Pair both phones (above), enable sharing on each, then switch Wi-Fi and cellular off on both and
confirm new GPS timestamps still arrive over Bluetooth. For the background test, start sharing in
the foreground, lock only the sender, move outdoors within range, and verify that **new** GPS
timestamps arrive without unlocking the sender. Then reverse roles.

**Core logic tests on a Mac**

[`DeveloperNotes/run-core-tests.py`](DeveloperNotes/run-core-tests.py) compiles the actual
production router and model types with `swiftc` and runs
[`DeveloperNotes/CoreTests.swift`](DeveloperNotes/CoreTests.swift), covering blocked shortcuts,
disconnected geometric crossings, foot one-way restrictions, missing coverage, old-place migration
and named-place persistence:

```bash
python3 DeveloperNotes/run-core-tests.py
```

It requires `swiftc` on `PATH` and exits with status 2 if Swift is unavailable. **These tests have
not been executed in this repository's environment** — no Swift compiler was available there.

## Architecture

SwiftUI app, two tabs, no backend. `OfflineCompanionApp` → `CompanionRootView`, which shows the
welcome screen until a name is stored, then the `TabView`.

```
OfflineCompanion/
├── OfflineCompanionApp.swift     @main entry point
├── LocationView.swift            CompanionRootView (root + welcome), LocationStore (Core Location),
│                                 MeetingPoint model, saved places, compass bearing maths
├── ContentView.swift             Assistant tab UI, setup/download flow, OfflineVoiceInput
│                                 (SFSpeechRecognizer, on-device only)
├── ChatStore.swift               Assistant state machine, mode switching, photo preparation,
│                                 read-aloud (AVSpeechSynthesizer)
├── LocalLlama.swift              Swift actor owning all llama.cpp state; PromptBuilder (Llama 3.2
│                                 chat template) and VisionPrompt (SmolVLM template)
├── ModelFiles.swift              Llama + SmolVLM download, size/SHA-256 verification, install
├── ExploreView.swift             Map tab, route steps sheet, MapDownloadsView
├── NativeOfflineMap.swift        MapLibre UIViewRepresentable; OfflineMapStyle builds the style
│                                 JSON with local GeoJSON sources and bundled glyphs
├── OfflineMapView.swift          OfflineMapStore (bundled + downloaded areas, LZFSE storage),
│                                 MapAreaDownloader (Overpass), data models
├── OfflineWalkingRouter.swift    Dijkstra/A* over OSM node IDs with walking-access and foot
│                                 one-way handling; refuses disconnected coverage
├── BluetoothStore.swift          Core Bluetooth central + peripheral, pairing protocol v2,
│                                 AES-GCM messaging, Keychain persistence, BluetoothCoordinator
├── BluetoothView.swift           People sheet, QR display, camera QR scanner, sharing banner
├── SharedLocationPacket.swift    Wire format for a shared GPS reading, with validation
├── AuburnMap.json                Bundled Auburn OSM extract (ODbL) — 11,888 features
├── Countries.geojson             Natural Earth country outlines (public domain)
├── Cities.json                   Natural Earth major-city points (public domain)
├── MapStyle.json                 MapLibre style template, 12 layers, local glyph reference
├── MapGlyphs/                    Noto Sans Regular, Latin range 0–255 (SIL OFL)
└── Info.plist                    Permission strings, background modes, pairing URL scheme
```

**Concurrency.** All llama.cpp state lives inside the `LocalLlama` actor, off the UI actor.
`ChatStore`, `LocationStore` and the coordinator are `@MainActor`. Core Bluetooth managers and all
observable mutations run on the main queue. Background Bluetooth work is event-driven (location
callbacks and BLE delegate events), not timer-driven; only the 3-second foreground invitation retry
uses a timer.

**Storage.**

| What | Where |
|---|---|
| Model weights | `Application Support/Models/`, excluded from backup |
| Downloaded map areas | `Application Support/OfflineRoadMaps/*.mapdata`, LZFSE-compressed, excluded from backup |
| Saved places, display name, map budget, onboarding flag | `UserDefaults` |
| Pairing key, peer name, opt-in state, last two received snapshots | **Keychain**, this-device-only, after-first-unlock |
| Chat history | **In memory only** — never written to disk |
| Bundled Auburn map | read directly from the app bundle on every reload; no first-run copy |

## Data handling and privacy

- **Inference is local.** Text questions and selected photos are processed on the phone. Neither
  is uploaded anywhere.
- **No account, no login, no analytics, no telemetry, no crash reporting SDK, no ad SDK.** The app
  has no backend.
- **Chats are ephemeral.** Held in memory, cleared when you switch modes or tap Clear, gone on
  relaunch.
- **Photos** are resized to at most 768 px on the longest side before inference and are not
  retained after the session.
- **Network use is explicit and limited to three things:** a model download you confirm, an
  Overpass map download you request, and license/model-card links you tap. An Overpass request
  sends only the selected map rectangle — never pairing secrets, names, or contact identities.
- **Location data** stays on your phone unless you pair a person *and* enable sharing. Then GPS
  readings go to that one paired phone over AES-GCM-encrypted Bluetooth. The other phone keeps the
  latest and previous snapshot only.
- **You cannot un-send a location.** Turning sharing off stops future updates; it cannot remove
  what the other phone already received.
- **Pairing secrets live in the Keychain**, this-device-only, and are deleted by *Forget pairing*.
- **Display names are unverified.** They identify a requested person in the UI, nothing more.
- The app enables `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` to support model
  file import. This exposes the app's *Documents* directory in the Files app. Models, maps and
  pairing data are stored outside Documents (Application Support and Keychain), so none of it is
  exposed there.

## Troubleshooting

**Package resolution fails on first build.** Keep the Mac online and let SPM finish. The versions
are exact pins; *File → Packages → Reset Package Caches* then rebuild if resolution is stuck.

**"Signing for OfflineCompanion requires a development team."** Select the target →
*Signing & Capabilities* → choose your team, and change the bundle identifier to one you own.

**Model download fails.** The error distinguishes no-internet, HTTP failures and timeouts. The app
rejects any file that does not match both the expected byte size and the pinned SHA-256 — a partial
or proxy-modified download is discarded rather than loaded. Retry on stable Wi-Fi, or import the
exact file manually.

**"Could not load the model."** Close other apps and retry; the 1B model needs real memory
headroom. Restart the app if the context cannot be created.

**Assistant stuck on "Getting your offline assistant ready…"** Tap **Try again** on the setup
screen. Switching modes unloads the previous model first, which takes a moment.

**Voice input says offline recognition is unavailable.** Apple's on-device English (US) assets must
be present and supported on the phone; they are provided by iOS and are not bundled here. Typing
remains available. Also check that Microphone and Speech Recognition are allowed in
*Settings → Apps → Offline Companion*.

**Read aloud is silent.** Raise the media volume and check the audio route (headphones/Bluetooth).
If no English voice is found, download one while online under
*Settings → Accessibility → Spoken Content → Voices*, then retry offline.

**Save place is disabled.** The app requires a GPS reading less than 60 seconds old with a valid
accuracy. Allow location with **Precise Location** on, tap **Refresh GPS**, and try outdoors. The
button states its own reason.

**Compass says "Waiting for an accurate compass reading."** Hold the phone roughly flat, turn
slowly, and move away from magnets and metal. True north needs a fresh location fix. If you are
within the combined uncertainty of your position and the saved point, the app says it is too close
for a reliable direction rather than pointing anywhere.

**Walking directions refuse to calculate.** The router refuses rather than drawing a straight line
and calling it a route. Causes: GPS accuracy worse than about ±100 m; start or destination more
than 150 m from a mapped node; coverage missing or disconnected between the two points; both
points snapping to the same node (it suggests distance and compass instead). Older downloaded
areas labelled **Display only** lack OSM node IDs and must be downloaded again.

**Additional map download fails.** Expected. Public Overpass endpoints are frequently unavailable,
and this has failed in testing. A smaller radius only helps when the response was too large; it
does not fix an unavailable server. The bundled Auburn area works regardless.

**Accept invitation never appears.** Both phones need Bluetooth on, both apps open and in the
foreground, and the scanner must scan the *other* phone's current QR. The scanning phone retries
the request every 3 seconds. Both screens show a progress line — *looking for the phone*, *opening
the invitation channel*, *request delivered*, *invitation received* — which distinguishes a
discovery failure from a delivery failure. Cancel any waiting invitation on the scanner before
rescanning. QR codes from older builds are rejected.

**Paired but no marker for the other person.** Connection is not a position. On *their* phone,
**Share my location** must be on and GPS allowed. A marker appears only after a packet arrives.
Check the receipt timestamps on the person's card.

**Background updates stop.** Expected under several conditions: the app was force-quit by swiping
it away, the phones went out of Bluetooth range, Bluetooth was turned off, permissions were
revoked, or iOS suspended execution. Background delivery is not guaranteed.

## Demo video

A 2:25 walkthrough has been cut from real device recordings for the Meta Global AI Developer
Hackathon submission.

### 🎬 Hosted link coming soon

> The video file is not committed to this repository (see `.gitignore`). **The public link will
> replace this line once the video is uploaded.** Nothing here stands in for a result that has not
> happened.

Everything else about the video is in [`docs/demo/`](docs/demo):

- [`docs/demo/README.md`](docs/demo/README.md) — how the edit was built, how to rebuild or re-cut
  it, what was staged, and every claim checked against the code
- [`docs/demo/VOICEOVER-SCRIPT.md`](docs/demo/VOICEOVER-SCRIPT.md) — narration, on-screen captions
  and the source timecode of every shot
- [`docs/demo/OfflineCompanion-demo.srt`](docs/demo/OfflineCompanion-demo.srt) — subtitle track
- [`docs/demo/thumbnail.png`](docs/demo/thumbnail.png) — title card
- [`docs/demo/build/`](docs/demo/build) — the scripts that generate the whole edit

**What the video shows, and what it does not.** Every phone screen in it is unaltered footage
recorded in airplane mode — the Meta Llama answer (4.6 s, generated on device), voice input,
read-aloud, the experimental SmolVLM photo answer, the bundled Auburn map, a saved place, the
compass, and a 225 m offline walking route. The opening scenes and the explainer cards are
original vector graphics, badged on screen as illustrations. The pairing handshake is shown as a
labelled **diagram**, because no recording captures that flow. The saved place's real coordinates
are cropped out of every frame.

The earlier planning outline is kept at [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md) for
reference; `docs/demo/` describes the video as it was actually cut.

## Licensing and attribution

**Application source code** in this repository is released under the MIT License in
[`LICENSE`](LICENSE).

**That license does not and cannot cover the bundled third-party data and fonts**, which keep their
own terms. In particular:

| Component | License | Notes |
|---|---|---|
| Meta Llama 3.2 1B Instruct **weights** | [Llama 3.2 Community License](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/blob/main/LICENSE.txt) + [AUP](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/blob/main/USE_POLICY.md) | **Not included here**; downloaded by the user. "Built with Llama." |
| GGUF conversion / quantisation | per publisher | [bartowski/Llama-3.2-1B-Instruct-GGUF](https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF) |
| SmolVLM-500M-Instruct + `mmproj` | per model card | [HuggingFaceTB](https://huggingface.co/HuggingFaceTB/SmolVLM-500M-Instruct) · GGUF by [ggml-org](https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF). **Not a Meta model.** Not included here. |
| llama.cpp | MIT | [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) |
| LlamaSwift | MIT | [mattt/llama.swift](https://github.com/mattt/llama.swift), pinned `2.10549.0` |
| MapLibre Native iOS 7.0.0 | BSD 2-Clause | [`DeveloperNotes/MapLibre-LICENSE.md`](DeveloperNotes/MapLibre-LICENSE.md) |
| `AuburnMap.json` | **ODbL 1.0** | Adapted database © OpenStreetMap contributors, from the [Geofabrik Alabama extract](https://download.geofabrik.de/north-america/us/alabama.html), retrieved 2026-11-04. Reusable under [ODbL](https://opendatacommons.org/licenses/odbl/1-0/); no additional restrictions are imposed. |
| Roads/paths downloaded in-app | **ODbL 1.0** | © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), via public Overpass endpoints |
| `Countries.geojson`, `Cities.json` | Public domain | [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/) 1:110m |
| Noto Sans Regular glyphs | SIL Open Font License | [`OfflineCompanion/MapGlyphs/OFL.txt`](OfflineCompanion/MapGlyphs/OFL.txt), [`DeveloperNotes/NotoSans-OFL.txt`](DeveloperNotes/NotoSans-OFL.txt) |

**© OpenStreetMap contributors · Natural Earth** — credited in the map UI as well as here.

Full notices, including the exact derivation of the Auburn database, are in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and
[`DeveloperNotes/AUBURN_DATA.md`](DeveloperNotes/AUBURN_DATA.md).

No Google Maps, Mapbox service, or OpenFreeMap data is used. No map API key is required anywhere.

## Repository layout

```
.
├── OfflineCompanion.xcodeproj/   Xcode project (SPM pins for MapLibre + LlamaSwift)
├── OfflineCompanion/             App sources and bundled resources
├── DeveloperNotes/               Design, data-provenance and validation notes; core test harness
│   ├── AUBURN_DATA.md            How the bundled OSM extract was produced and validated
│   ├── PAIRING_FLOW.md           Pairing protocol v2 in detail
│   ├── VOICE_AND_LOCATION.md     Speech and background-permission implementation notes
│   ├── VALIDATION.md             What has and has not been verified
│   ├── CoreTests.swift           Router/model tests (run via run-core-tests.py on a Mac)
│   ├── MapLibre-LICENSE.md       BSD 2-Clause notice
│   └── NotoSans-OFL.txt          SIL OFL notice
├── docs/
│   ├── DEMO_SCRIPT.md            Original demo-video planning outline
│   └── demo/                     The video as actually cut
│       ├── README.md             Build/re-cut instructions, staged graphics, claim checks
│       ├── VOICEOVER-SCRIPT.md   Narration, captions and per-shot source timecodes
│       ├── OfflineCompanion-demo.srt
│       ├── thumbnail.png
│       └── build/                Scripts that generate the edit end to end
├── START_HERE.md                 Build-by-build release notes, newest first
├── THIRD_PARTY_NOTICES.md        Full attribution and data provenance
├── LICENSE                       MIT, for the application source code
└── README.md                     This file
```
