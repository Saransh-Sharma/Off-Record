# App Review Response - Guidelines 5.1.1(i) and 5.1.2(i)

Hello App Review,

Thank you for the clarification. We found that OffRecord uses Apple's Speech framework for transcription. The app does not integrate OpenAI, Anthropic, Gemini, analytics SDKs, advertising SDKs, or any non-Apple third-party AI service.

We have submitted an updated build that now clearly explains before transcription that voice audio may be processed by Apple Speech when online, identifies Apple as the service provider, and asks the user for permission before transcription begins. If the user does not consent, the recording is saved locally and they can type the entry manually.

We also updated the in-app privacy disclosures, added an easily accessible Privacy Policy link in Settings, updated the Privacy Policy to describe Apple Speech and optional iCloud Sync, and corrected App Store metadata/review notes so they match the app's actual behavior.

Friday insights, mood analysis, Semantic Memory, and journal analysis remain on-device. OffRecord does not send journal data to developer servers or non-Apple AI services.
