# App Review Response - Guideline 5.1.1(iv)

Hello App Review,

Thank you for the clarification. We updated the Speech Recognition permission flow so the custom explanatory message now uses neutral wording before the system permission request.

The primary action is now "Continue" instead of "Agree and Transcribe," and the custom message no longer includes a secondary permission-style choice. The user's permission decision is handled by the iOS Speech Recognition permission prompt.

We also reviewed related Speech Recognition wording in Settings and error states to avoid directive permission language.

If Speech Recognition is denied, OffRecord saves the recording locally and lets the user type manually.
