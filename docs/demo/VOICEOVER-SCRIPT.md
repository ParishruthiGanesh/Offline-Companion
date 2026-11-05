# Voiceover script & shot list — Offline Companion demo

Final cut: **2:25.20**, 1920×1080, 30 fps, H.264 / AAC.

Narration is synthesised speech (Piper `en_US-amy-medium`, generated locally — no cloud TTS).
To swap in a human read, record each line to roughly the same length, drop the WAVs into `vo/`
and re-run the build; see `EDITING-NOTES.md`.

For each line below: **Spoken** is the narration and the subtitle track; **On screen** is the
burned-in caption; **Footage** names the source recording and exact in/out timecodes.


## Section 1 — The problem (illustrated)

### `L01` · 0:00.60 → 0:07.00 (6.40s)

> She told someone where she was going. She just didn't expect the signal to disappear.

- **On screen:** She told someone where she was going. / She just didn't expect the signal to disappear.
- **Footage:** `ILL1` — generated graphic, badged on screen as not app footage

### `L02` · 0:07.28 → 0:13.61 (6.32s)

> It happens on a road you don't know. On a trail that stopped looking familiar an hour ago.

- **On screen:** On a road you don't know. On a trail that / stopped looking familiar an hour ago.
- **Footage:** `ILL2` — generated graphic, badged on screen as not app footage

### `L03` · 0:13.89 → 0:19.16 (5.27s)

> The moment you most need a second opinion is often the moment you have no connection.

- **On screen:** The moment you most need a second opinion / is often the moment you have no connection.
- **Footage:** `ILL3` — generated graphic, badged on screen as not app footage

### `L04` · 0:19.44 → 0:22.51 (3.08s)

> Offline Companion was built for that moment.

- **On screen:** Offline Companion was built for that moment.
- **Footage:** `ILL4` — generated graphic, badged on screen as not app footage


## Section 2 — The models, and Meta Llama on the phone

### `L05` · 0:23.26 → 0:27.12 (3.85s)

> We needed intelligence that lives on the phone itself.

- **On screen:** _(the card carries its own text)_
- **Footage:** `CARD_model_a` — generated graphic, badged on screen as not app footage

### `L06` · 0:27.40 → 0:36.45 (9.05s)

> So we looked at what could actually run inside an iPhone's memory. We chose Meta Llama 3.2 1B Instruct.

- **On screen:** _(the card carries its own text)_
- **Footage:** `CARD_model_b` — generated graphic, badged on screen as not app footage

### `L07` · 0:36.73 → 0:43.67 (6.94s)

> Watch the status bar. Airplane mode. No Wi-Fi. No cellular.

- **On screen:** Airplane mode · No Wi-Fi · No cellular
- **Footage:** ScreenRecording_18-53-17 (Meta Llama text) `0.00–2.30s`; ScreenRecording_18-53-17 (Meta Llama text) `2.90–7.60s`

### `L08` · 0:43.95 → 0:48.81 (4.86s)

> A real question. The kind you would actually ask out there.

- **On screen:** A real question, asked offline
- **Footage:** ScreenRecording_18-53-17 (Meta Llama text) `7.60–10.60s`; ScreenRecording_18-53-17 (Meta Llama text) `11.30–13.20s`

### `L09` · 0:49.09 → 0:57.24 (8.15s)

> 4.6 seconds. Generated on this device. No cloud, no API key, no account.

- **On screen:** Powered by Meta Llama 3.2 — text inference runs on the device / No cloud inference required for text answers
- **Footage:** ScreenRecording_18-53-17 (Meta Llama text) `17.40–21.40s`; ScreenRecording_18-53-17 (Meta Llama text) `24.60–28.75s`

### `L10` · 0:57.52 → 1:09.00 (11.48s)

> Meta Llama powers the text. Photos use SmolVLM, a Hugging Face model, not Meta. It is experimental, and at this size it makes mistakes.

- **On screen:** Photos: SmolVLM-500M (Hugging Face) — NOT a Meta model / Experimental: small models miss and misidentify things
- **Footage:** ScreenRecording_18-42-08 (photo / voice) `17.60–22.20s`; ScreenRecording_18-42-08 (photo / voice) `30.60–36.20s`; ScreenRecording_18-42-08 (photo / voice) `36.20–37.50s`

### `L11` · 1:09.28 → 1:17.11 (7.83s)

> Voice input and reading aloud are Apple's, also on device. Speak, review the text, then send.

- **On screen:** Voice input & read-aloud: Apple on-device speech / Speech becomes editable text — nothing sends automatically
- **Footage:** ScreenRecording_18-42-08 (photo / voice) `23.20–28.40s`; ScreenRecording_18-53-17 (Meta Llama text) `28.50–31.13s`


## Section 3 — Location, maps and the nearby person

### `L12` · 1:17.86 → 1:20.02 (2.16s)

> Then there is knowing where you are.

- **On screen:** Then there is knowing where you are.
- **Footage:** ScreenRecording_18-38-22 (map / compass / route) `2.30–3.80s`

### `L13` · 1:20.30 → 1:29.56 (9.26s)

> Central Auburn is built in as OpenStreetMap data, rendered with MapLibre. Nothing to fetch. Still airplane mode.

- **On screen:** Bundled offline map: MapLibre + © OpenStreetMap contributors / Central Auburn, Alabama — not nationwide
- **Footage:** ScreenRecording_18-38-22 (map / compass / route) `3.80–5.20s`; ScreenRecording_18-38-22 (map / compass / route) `23.00–25.30s`; IMG_1827.MOV (handheld) `0.60–4.60s`

### `L14` · 1:29.84 → 1:37.28 (7.44s)

> Save where you're standing. Your car, your camp, the trailhead. And the compass points you back to it.

- **On screen:** Named saved places + compass bearing / GPS: Apple Core Location — straight-line direction, not a safe route
- **Footage:** ScreenRecording_18-38-22 (map / compass / route) `6.70–8.20s`, cropped `crop=1170:980:0:0`; ScreenRecording_18-38-22 (map / compass / route) `12.70–18.14s`, cropped `crop=1170:1382:0:1150`

### `L15` · 1:37.56 → 1:46.71 (9.14s)

> And it will route you. 225 metres on real mapped paths, calculated on the phone, with no connection at all.

- **On screen:** Offline walking route on stored OpenStreetMap paths / Experimental — no closures, hazards or safety data
- **Footage:** ScreenRecording_18-38-22 (map / compass / route) `25.30–34.50s`

### `L16` · 1:46.99 → 1:56.08 (9.10s)

> You can also pair one trusted person nearby. GPS readings then move between the two phones over encrypted Bluetooth.

- **On screen:** _(the card carries its own text)_
- **Footage:** `CARD_pairing` — generated graphic, badged on screen as not app footage

### `L17` · 1:56.36 → 2:04.74 (8.38s)

> Every position carries its own timestamp. When the link drops, the app says so, and shows the last known location.

- **On screen:** Connection does not prove a location is fresh / Background delivery is not guaranteed
- **Footage:** ScreenRecording_18-38-22 (map / compass / route) `35.00–36.90s`; ScreenRecording_18-38-22 (map / compass / route) `2.60–5.20s`, cropped `crop=1170:520:0:1800`; IMG_1827.MOV (handheld) `4.60–8.40s`


## Section 4 — Purpose and honest limits

### `L18` · 2:05.49 → 2:16.57 (11.08s)

> This is a prototype. No satellite. No SOS. No rescue dispatch. It does not promise to keep anyone safe.

- **On screen:** _(the card carries its own text)_
- **Footage:** `CARD_limits` — generated graphic, badged on screen as not app footage

### `L19` · 2:16.85 → 2:23.40 (6.55s)

> What it does is put a capable Meta Llama model in your pocket, and keep it working when nothing else does.

- **On screen:** _(the card carries its own text)_
- **Footage:** `CARD_outro` — generated graphic, badged on screen as not app footage

