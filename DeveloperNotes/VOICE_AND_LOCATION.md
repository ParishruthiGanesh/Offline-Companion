# Speech and background permissions

Voice input is implemented in ContentView.swift using SFSpeechRecognizer and AVAudioEngine. Both microphone and Speech authorization are requested. supportsOnDeviceRecognition must be true before any audio capture; requiresOnDeviceRecognition is always true. No network fallback is requested. Permission/task generations prevent a delayed permission callback or recognition completion from restarting cancelled input. Audio taps, recognition tasks and AVAudioSession activation are torn down on stop. Transcripts remain in the existing in-memory question field and are not sent automatically. English (US) is the explicit initial locale. Speech assets are provided by iOS, not bundled here. Native testing is required to establish actual offline availability and compatibility on the target iPhone.

LocationStore now publishes readable authorization/accuracy state. The first Always upgrade uses Core Location; repeat actions or denied permission open app Settings. A separate Settings button is always visible inside the background-sharing section. Apple may ignore a repeated upgrade request or an upgrade after Allow Once; the UI explains the Settings path rather than implying another prompt is guaranteed. Authorization changes and return-to-foreground refresh the state.

References:
https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition
https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization()

Source syntax and project checks passed; no native compiler/device is available in this environment. Native voice capture, transcription, denial/cancellation recovery, read-aloud interoperation and locked-phone delivery remain to be tested.
