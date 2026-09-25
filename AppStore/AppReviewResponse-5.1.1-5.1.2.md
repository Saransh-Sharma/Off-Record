# App Review Response - Guideline 5.1.1(iv)

Hello App Review,

Thank you for the clarification. OffRecord has moved transcription to Apple's iOS 26 SpeechAnalyzer stack. Recognition now runs entirely on device and the app no longer requests the separate Speech Recognition permission.

Before transcription, OffRecord presents a neutral in-app disclosure with a “Continue” action. The only system permission requested for live voice capture is Microphone access.

We also updated Settings, privacy copy, and error states to describe the on-device SpeechAnalyzer behavior and possible Apple language-model download.

If transcription is disabled or the selected locale is unsupported, OffRecord preserves the recording locally and lets the user type manually. There is no server-recognition fallback.
