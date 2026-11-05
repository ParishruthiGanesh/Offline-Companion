# Demo video — assets and how it was built

**Final cut:** 2:25.20, 1920×1080, 30 fps, H.264 High @ 4.1, AAC 192 kbps 48 kHz, ~31 MB,
`+faststart`, loudness-normalised to −16 LUFS.

The MP4 itself is not committed (see the repository `.gitignore`) — host it and link it from the
main [README](../../README.md). Everything needed to reproduce or re-cut it is here.

| File | What it is |
|---|---|
| [`VOICEOVER-SCRIPT.md`](VOICEOVER-SCRIPT.md) | Narration, burned-in captions, and the exact source timecode of every shot |
| [`OfflineCompanion-demo.srt`](OfflineCompanion-demo.srt) | Subtitle track (the spoken narration) |
| [`thumbnail.png`](thumbnail.png) | 1920×1080 title card |
| [`build/`](build) | The scripts that generate the whole edit |

There is no Premiere or Resolve project. The edit is **reproducible from scripts** — every cut,
caption, crop and audio level is data in a few files, which is easier to adjust and re-run than a
binary timeline.

---

## Rebuilding

Needs `ffmpeg` 6.x, Python 3 with `numpy` and `pillow`, and `piper-tts` with the
`en_US-amy-medium` voice. Build time ≈ 6 minutes.

```bash
pip install piper-tts numpy pillow
python3 -m piper.download_voices en_US-amy-medium
```

Point `SRC` in `build/build_video.py` at your copies of the four recordings, set `SP` to a scratch
directory, then:

```bash
python3 -I build/tts.py         "$SP"   # narration WAVs (Piper, entirely local)
python3 -I build/build_audio.py "$SP"   # narration.wav + timeline.json + the SRT
python3 -I build/build_mix.py   "$SP"   # ambient score + ducking -> final_audio.wav
python3 -I build/illus.py       "$SP/ill"   # the four opening illustrations
python3 -I build/build_cards.py "$SP"   # title/spec cards, caption overlays, thumbnail
python3 -I build/build_video.py "$SP"   # 30 beats -> concat -> final MP4
```

## What to edit, and where

| Want to change | Edit |
|---|---|
| Narration wording | `build/script.json` → `say` (spoken) and `srt` (subtitle) |
| Burned-in captions | `build/script.json` → `cap` (`\n` splits lines) |
| Which footage plays under which line | `build/beats.json` — `[source, in, out, crop]` per beat |
| Full-bleed vs. phone-on-left, and the badge | `build/layout.json` |
| Pacing and pauses | `build/build_audio.py` → `LEAD`, `TAIL`, `GAP_LINE`, `GAP_SECTION` |
| Music level, ducking depth | `build/build_mix.py` → `MUSIC_DB`, the `duck[s:e] = 0.30` line |
| Phone size and position in frame | `build/build_video.py` → `FG_CX, FG_W, FG_H` |
| Opening illustrations | `build/illus.py` |
| Cards and thumbnail | `build/build_cards.py` |

## Source recordings

Four device recordings, used read-only and never altered beyond retiming and cropping:

| Key | File | Used for |
|---|---|---|
| `A` | `IMG_1827.MOV` (8.5 s, handheld 1080p) | real-device map and received-location shots |
| `B` | `ScreenRecording_18-42-08` (39.5 s) | SmolVLM photo mode, voice input, read-aloud |
| `C` | `ScreenRecording_18-38-22` (37.0 s) | offline map, saved place, compass, walking route |
| `D` | `ScreenRecording_18-53-17` (37.9 s) | airplane mode + the Meta Llama text answer |

**Timing model.** Every beat's duration is derived from the narration timeline, including the
silence after each line, so picture and voice cannot drift. Changing a beat's in/out points
retimes that clip (`setpts`) to fill its slot instead of shifting everything after it.

## Music

Synthesised from scratch in `build_mix.py`: a slow D-minor pad with detuned voices, a shimmer
layer that arrives with section 2, a swell at each of the four section boundaries, and an
exponential-FIR low-pass that opens as the piece goes on. **Royalty-free by construction** — no
sampled or licensed track is used. Narration ducking is computed directly from the line timings
(−10.5 dB under speech, 0.3 s smoothing) rather than from a sidechain detector.

## Cutting it to 2:00

Check the submission portal's actual limit before publishing. This edit is 2:25. To reach roughly
2:00, delete these from `script.json` and re-run — nothing else needs touching, because all
timing is derived:

- `L03` (5.3 s) — restates the problem `L01`/`L02` already make.
- `L05` (3.9 s) — the model section opens cleanly on `L06` without it.
- Shorten `L10` (11.5 s) to a single sentence about SmolVLM.
- Shorten `L18` (11.1 s) to "No satellite. No SOS. No rescue dispatch." and let the card carry the rest.

That removes about 24 s. Do **not** drop `L18` entirely — it is the honest-limits beat.

---

## Staged graphics

No app screen in this video is fabricated. Six passages are original graphics, each badged on
screen while visible:

| Shown | What it is | Badge |
|---|---|---|
| 0:00–0:19 | Three flat-vector scenes: a woman walking alone past a streetlamp; a lone figure on a forest trail; a phone with the signal gone | `ILLUSTRATION` |
| 0:19–0:22 | Teal beacon title frame | `ILLUSTRATION` |
| 0:23–0:36 | "Intelligence that lives on the phone itself" and the Meta Llama spec card | `ILLUSTRATION · NOT APP FOOTAGE` |
| 1:47–1:56 | Pairing diagram — two phone outlines, a QR glyph, the handshake steps | `DIAGRAM · NOT APP FOOTAGE` |
| 2:05–2:25 | "What this is not" and the closing card | — (plainly a title card) |

These are drawn programmatically with Pillow (`illus.py`, `build_cards.py`). **They are not
AI-generated photographs** — flat vector art was chosen deliberately so nothing can be mistaken
for a real photograph or a real app screen. The QR glyph on the pairing card is random noise, not
a scannable code.

Everything else on screen is unaltered footage, retimed and cropped only.

## Privacy edits

- **The saved place's real coordinates never appear.** They are visible in the source recording
  whenever the Saved places sheet is open, so two shots were cropped to exclude them
  (`crop=1170:980:0:0` for the save-a-place beat, `crop=1170:1382:0:1150` for the compass beat),
  and one map beat was moved from 21.9 s to 23.0 s because the sheet was still sliding away.
  Every frame of the finished cut was checked.
- **No pairing QR code appears** in any recording, and none was added.
- Two first names appear as local display names with GPS times and accuracy, exactly as the app
  renders them. No account identity and no coordinates.

## Claims checked against the implementation

| Claim in the video | Basis |
|---|---|
| "Meta Llama 3.2 1B Instruct" | `ModelFiles.swift` — pinned filename, 807,694,464 bytes, SHA-256 |
| "4.6 seconds, generated on this device" | read off the app's own footer in the recording |
| "No cloud, no API key, no account" | no inference endpoint exists anywhere in the source |
| "SmolVLM … not Meta" | `VisionFiles` in `ModelFiles.swift`; the app's own UI says "not Meta" |
| "Voice input and read-aloud are Apple's" | `SFSpeechRecognizer` (`requiresOnDeviceRecognition = true`), `AVSpeechSynthesizer` |
| "MapLibre + OpenStreetMap, central Auburn" | `AuburnMap.json` — 11,888 features, ODbL, bbox verified |
| "225 metres on mapped paths" | the app's own route card in the recording |
| "encrypted Bluetooth" | `AES.GCM` in `BluetoothStore.swift` |
| "Airplane mode" | the status bar is visible throughout clips B, C and D |

## Deliberately left out

- **Any claim that the pairing handshake was demonstrated.** No recording shows the
  QR → invite → Accept flow, so the video shows a labelled diagram and says so on screen.
- **Any suggestion of safety, rescue or emergency use.** The closing section states the opposite.
- **Benchmarks or model comparisons.** The card reads "practical selection under device limits —
  not an exhaustive benchmark".
- **Background delivery working.** Captioned as not guaranteed.
- **The Overpass map download**, which has failed in testing.
- **Endorsement of the SmolVLM answer.** The model replies "No." to a question about whether a dog
  is dangerous; the caption calls the mode experimental and error-prone, and the narration does
  not treat the answer as correct.
