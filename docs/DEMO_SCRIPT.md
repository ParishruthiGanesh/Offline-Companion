# Demo video — outline, narration and shot list

**Status: planning document.** No video has been recorded or rendered yet. This is the edit plan
that the real screen recordings will be cut against.

**Target length:** approximately **2:00**. The Meta Global AI Developer Hackathon portal's actual
duration limit has not been confirmed — check it before final export and trim or extend to fit.
A 2:30–3:00 variant is noted below in case the limit is more generous.

---

## Accuracy rules for this edit

These are binding on the final cut. Every technical claim has to be supported by the actual
implementation and the actual footage.

- **Meta Llama 3.2 1B Instruct powers the offline text assistant — and nothing else.** Do not
  imply Meta powers photo understanding, speech recognition, read-aloud, GPS, maps, or Bluetooth.
- **Photo understanding is SmolVLM** (Hugging Face), not Meta. If photo mode appears at all, the
  caption must say so.
- **Voice input and read-aloud are Apple** on-device features.
- **Maps are MapLibre + OpenStreetMap. GPS is Core Location. Pairing is Core Bluetooth.** All
  separate from the Meta model.
- **Initial model download requires internet.** Say it. The offline claim is about inference.
- **Nearby sharing requires Bluetooth range.** Not worldwide tracking.
- **Background delivery is not guaranteed.**
- **No satellite link, no SOS transmission, no rescue dispatch exists.** Never imply otherwise.
- **Never describe the app as guaranteeing anyone's safety.** It is a prototype.
- **AI-generated illustrations must be visibly labelled** as illustrations, distinct from real app
  footage.
- **Do not fabricate app screens, answers, routes, or location-sharing results.** Only show what
  the recordings actually show.
- **Do not alter footage to make a failed feature look successful.** If a feature did not work on
  camera, cut it or caption it honestly.
- **Blur or replace every real pairing QR code**, pairing secret, and personal coordinate.
  Suggested approach: record pairing with a throwaway pairing (which you then *Forget*), and still
  blur the QR region and the visible latitude/longitude digits in post.

---

## Structure (≈2:00)

| # | Section | Length | Source |
|---|---|---|---|
| 1 | The problem | 0:00–0:18 | AI illustration (labelled) |
| 2 | Offline intelligence — Meta Llama | 0:18–0:52 | **Real app footage** |
| 3 | Accessibility — voice in, speech out | 0:52–1:10 | **Real app footage** |
| 4 | Staying oriented — places and the offline map | 1:10–1:32 | **Real app footage** |
| 5 | Nearby connection — pairing and location | 1:32–1:50 | **Real app footage** (two phones) |
| 6 | Purpose and honest limits | 1:50–2:00 | Title cards |

If the portal allows 3:00, extend §2 with a second Llama answer (a drafted check-in message),
§4 with the walking-route steps sheet, and §5 with the disconnected last-known marker.

---

## Section 1 — The problem (0:00–0:18)

**Visual:** AI-generated illustration sequence — a person walking alone on an unfamiliar street at
dusk; a hiker on a ridge trail; a phone showing no signal. Slow push-in on each, ~5s per image.
Persistent corner label: **"Illustration"**.

**Narration**
> "When connectivity disappears, access to assistance shouldn't disappear with it. Offline
> Companion brings Meta Llama onto your phone — alongside offline maps and nearby trusted-person
> location sharing."

**Captions:** `Illustration` (corner, whole section) · `No signal. No assistance?` (0:10)

---

## Section 2 — Offline intelligence (0:18–0:52)

This is the heart of the video. It must be unambiguous that the phone is offline and that the
answer came from the device.

**Visual:** real screen recording, in this order:
1. Pull down Control Centre / Settings showing **Airplane Mode on, Wi-Fi off, cellular off**. Hold
   2 seconds — this shot is what makes the whole claim credible.
2. Launch the app from cold (proving the model loads from local storage).
3. Type or paste a practical question and send it.
4. The answer streams in, with the `Meta Llama • local answer` header visible.
5. The footer timing line — *"N seconds • generated on this device"* — held long enough to read.
6. A second question: *"Help me draft a short check-in message to my family."* Show the drafted
   message.

**Narration**
> "Airplane mode. No Wi-Fi, no cellular. The app launches cold — and Meta Llama 3.2 1B Instruct
> loads from the phone's own storage. Ask a practical question and the answer is generated here, on
> this device, in seconds. It can reason through a situation and draft a message for you to review
> and send yourself. One download while you have signal; after that, no cloud inference is required
> for text answers."

**Captions**
- `Powered by Meta Llama 3.2` (on the answer header)
- `Text inference runs on the device`
- `No cloud inference required for text answers`
- `Useful assistance when internet is unavailable`
- `Initial model download requires internet` *(small, honest, during the voiceover line)*

---

## Section 3 — Accessibility (0:52–1:10)

**Visual:** real footage — tap the microphone, speak a question, tap Stop, show the recognised text
appearing **in the editable field**, then tap Send. Then tap **Read aloud** on the answer and show
the audio status line.

**Narration**
> "You don't have to type. Apple's on-device speech recognition turns what you say into editable
> text — you review it before anything is sent. And any answer can be read back aloud with a voice
> already installed on the phone. Both work without a connection."

**Captions**
- `Voice input: Apple on-device speech recognition`
- `Read aloud: Apple speech synthesis`
- `Speech becomes editable text — nothing sends automatically`

> Note: if voice input does not work cleanly on camera, cut this section rather than re-staging it.
> It is listed as *needs device testing* in the README.

---

## Section 4 — Staying oriented (1:10–1:32)

**Visual:** real footage, still offline — the Map tab with Auburn streets rendered; **Saved
places** with a named point being saved after a GPS refresh; the compass arrow and distance;
optionally the walking-route steps sheet. Blur visible coordinate digits.

**Narration**
> "The map is already on the phone. Central Auburn and the university area are bundled as
> OpenStreetMap data and rendered with MapLibre — no tiles to fetch, no API key. Save a place by
> name, and you get a compass bearing and a straight-line distance back to it. Walking directions
> are computed from the stored road and path graph."

**Captions**
- `Map: MapLibre + OpenStreetMap — © OpenStreetMap contributors`
- `GPS: Apple Core Location`
- `Bundled area: central Auburn, Alabama — not nationwide`
- `Offline walking routes are experimental`

> Only show directions and the route line if the recording shows them actually working.

---

## Section 5 — Nearby connection (1:32–1:50)

**Visual:** real footage from **both phones**, side by side or cut between:
1. Phone A and Phone B both in **People**, each showing its own QR — **QRs blurred**.
2. Phone A scans Phone B's QR.
3. Phone B shows the invitation with A's name → **Accept**.
4. Both show **Connected**.
5. Each phone turns on **Share my location**.
6. A received position appears on the map with its **timestamp and accuracy visible** (coordinates
   blurred).

**Narration**
> "To connect with someone nearby, one phone scans the other's private code. The other phone sees
> who is asking, and accepts. Each side then chooses, separately, whether to share its location —
> and GPS readings move between the phones over encrypted Bluetooth, with no internet at all. Every
> position shows its own timestamp and accuracy, because being connected is not the same as knowing
> where someone is right now."

**Captions**
- `QR pairing + explicit Accept — consent on both sides`
- `Encrypted over Bluetooth (AES-GCM) — no internet`
- `Bluetooth range only — not worldwide tracking`
- `Connection does not prove a location is fresh`
- `Background delivery is not guaranteed`

---

## Section 6 — Purpose and honest limits (1:50–2:00)

**Visual:** clean title cards over a dark background, or a slow hold on the app's About screen.

**Narration**
> "Offline Companion is a prototype. It has no satellite link, no SOS, and no connection to rescue
> services — and it doesn't pretend to. What it does is put a capable Meta Llama model on a phone
> that has no signal, and make a small amount of real help available anyway."

**Captions**
- `Prototype — not an emergency or rescue service`
- `No satellite link · No SOS · No rescue dispatch`
- `Photo understanding uses SmolVLM (Hugging Face), not Meta`
- `Built with Llama`
- Final card: `Offline Companion` + the repository URL

---

## Optional insert — experimental photo mode (≈10s)

Only include if time allows and the footage is honest about errors.

**Narration**
> "There's also an experimental photo mode, running SmolVLM — a Hugging Face model, not Meta.
> At this size it misses and misidentifies things, so it's shown here as an experiment, not a
> feature."

**Caption:** `Photo: SmolVLM-500M (Hugging Face) — NOT a Meta model · experimental, makes errors`

---

## AI-generated illustration brief

Four images, 16:9, cinematic, muted and slightly desaturated so they read as clearly distinct from
the bright app UI. Each gets a persistent `Illustration` label on screen.

1. A lone traveller with a backpack on an unfamiliar street at dusk, warm shop lights, no faces
   identifiable.
2. A hiker on an exposed ridge trail, wide landscape, late afternoon light, figure small in frame.
3. A hand holding a phone with an empty signal indicator, bokeh background suggesting somewhere
   unfamiliar.
4. Abstract closing frame: a phone silhouette with a quiet glow, no network arcs, no map UI.

Do **not** generate anything that imitates the app's screens, a messaging interface, a rescue
scene, or a successful alert.

---

## Audio

- **Voiceover:** calm, warm, unhurried. Confident about what the app does; plain about what it
  does not. No urgency-selling, no implied danger-rescue arc.
- **Music:** soft ambient bed, low. Duck to roughly −18 dB under narration. Consider dropping the
  music out entirely for the first two seconds of the airplane-mode shot in §2 — the silence sells
  "offline" better than the music does.
- **Keep the app's own read-aloud audio audible** in §3; that is a real feature demonstration, not
  a sound effect.

---

## Caption and title style

- Burned-in captions for the Meta-emphasis lines (so they survive any re-upload), **plus** a
  separate sidecar `.srt`/`.vtt` for the full narration.
- Sans-serif, high contrast, lower third, safe-area margins, readable on a phone screen.
- Component-attribution captions appear the moment that component first appears on screen.

---

## What is still needed from the project owner

1. **The screen recordings.** Ideally per section: airplane-mode proof + cold launch + Llama
   answer; voice input + read-aloud; map + saved place + compass (+ route if it worked); two-phone
   pairing and a received location. Phone-native resolution, no pre-applied captions.
2. **The portal's actual video duration limit.**
3. **Whether to include the experimental photo mode** at all.
4. **Voiceover preference:** your own recorded voice, or synthesised narration.
5. **Confirmation of what each recording actually shows**, so no claim in the edit outruns the
   footage.

### Deliverables once the recordings arrive

- One final MP4 with voiceover and readable captions.
- A separate caption file (`.srt` or `.vtt`) and the final voiceover script.
- An editable project or reproducible step-by-step editing instructions.
- A thumbnail.
- A written list of any staged illustrations used and any claim removed for lack of evidence.
