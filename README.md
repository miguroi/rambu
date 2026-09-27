# Rambu Speakerphone Transcription Prototype

This prototype tests one question: can an Android phone transcribe both sides of a consented call by recording the call through its microphone while speakerphone is enabled?

It does not capture Android's internal call audio. The Android app records a mono 16 kHz WAV file, sends it to a server on your Mac, and displays the Indonesian transcript returned by `faster-whisper`.

## Requirements

- A physical Android phone running Android 10 or newer
- The phone and Mac on the same Wi-Fi network
- A second phone for the test call
- The other caller's explicit consent to recording
- `uv`, JDK 17, Android SDK 36, and `adb`

## Project structure

- `android/` — recording app and Android unit tests
- `backend/` — local FastAPI and faster-whisper server

## 1. Start the local transcription server

```bash
cd backend
uv run uvicorn rambu_transcriber.app:app --host 0.0.0.0 --port 8000
```

Check it from the Mac:

```bash
curl http://127.0.0.1:8000/health
```

The first transcription downloads the `small` Whisper model and is slower than later requests. Audio is written to a temporary server file and deleted after the request finishes.

Find the Mac's Wi-Fi address:

```bash
ipconfig getifaddr en0
```

If that returns nothing, find the active local IP in macOS System Settings → Wi-Fi → Details. The phone will use `http://MAC_IP:8000`.

## 2. Build and install the Android app

Enable Developer Options and USB debugging on the phone, connect it by USB, then run:

```bash
cd android
./gradlew installDebug
```

This assumes `JAVA_HOME` points to JDK 17 and `ANDROID_HOME` points to your Android SDK. The built APK is available at `android/app/build/outputs/apk/debug/app-debug.apk`.

## 3. Run the feasibility test

1. Open **Rambu Prototype** and replace the server address with `http://MAC_IP:8000`.
2. Receive a call from the second phone, answer it, enable speakerphone, and set the volume high.
3. Tell the caller the call will be recorded and obtain consent.
4. Return to Rambu, check the consent box, and tap **Mulai Rekam**.
5. Have each person read a known Indonesian script for 20–30 seconds in a quiet room.
6. Tap **Hentikan Rekaman**, then **Transkripsikan**.
7. Compare the displayed transcript with the known script.
8. Tap **Hapus Rekaman Lokal** when finished.

For a simple accuracy score, count recognizable words in the correct order and calculate:

```text
recognizable words / total spoken words × 100%
```

Run at least three calls. The initial target is an average of 60–70% recognizable words for both speakers on one documented phone in a quiet room.

## Important limitations

- Some Android devices suppress microphone input or heavily process it during calls. That device behavior is exactly what this prototype tests.
- Keep Rambu visible while recording; this prototype does not use a background foreground-service yet.
- Speaker volume, phone placement, echo cancellation, room noise, and the device model materially affect accuracy.
- HTTP is allowed only to simplify local-network testing. It is not suitable for production or untrusted networks.
- This prototype does not yet perform scam detection, live warnings, call screening, Langflow analysis, or cloud deployment.
- `10.0.2.2` works only from an Android emulator. A physical phone must use the Mac's local IP address.

## Tests

Backend:

```bash
cd backend
uv run pytest -q
```

Android:

```bash
cd android
./gradlew testDebugUnitTest assembleDebug
```
