# Rambu

Rambu is a working prototype of an external call-safety system. The iPhone observes call state through CallKit, a separately authenticated Mac acts as the temporary Rambu Puck and hears the loudspeaker acoustically, and the backend transcribes ordered audio chunks, masks sensitive numbers, and sends only masked cumulative text to Langflow for risk analysis.

The prototype deliberately has no runtime analysis fallback. If configuration, transcription, Langflow, the model provider, transport, or response validation fails, the browser and iOS app show a failure instead of manufacturing a risk result.

The iPhone app does **not** capture cellular or WhatsApp audio. CallKit only reports call state. The Mac/physical puck must be close enough to hear the conversation from the phone loudspeaker, and the app must already be running because public iOS APIs do not guarantee launching a terminated third-party app for a cellular call.

## Production prototype flow

```text
iPhone CallKit -> protection session -> Mac/puck microphone -> faster-whisper -> masked transcript -> Langflow + OpenRouter -> warning
```

- Real CallKit state detection while the iOS app is running.
- Ordered external-microphone WAV chunks from the temporary Mac puck.
- Incremental Indonesian transcription and cumulative analysis.
- Strict `low`, `needs_review`, or `high_risk` assessments.
- Validated signals, transcript-backed evidence, explanation, and recommended action.
- A SwiftUI app that creates and polls authoritative protection sessions.
- Optional two-iPhone family-alert synchronization.
- Raw audio is processed in memory and is not persisted by the backend.

Synthetic scenarios and `/api/demo/*` remain available only to automated browser and screenshot fixtures; normal iOS runtime cannot call them.

## Requirements

- Python 3.12
- [uv](https://docs.astral.sh/uv/)
- Langflow 1.12.x
- An OpenRouter API key configured in Langflow
- Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the iOS app

## Required configuration

Import [`langflow/flows/Rambu.json`](langflow/flows/Rambu.json), configure its OpenRouter model, and run it once in the Langflow Playground. Then copy the backend environment template:

```bash
cp backend/.env.example backend/.env
```

Set all three Langflow values in `backend/.env`:

```dotenv
LANGFLOW_URL=http://127.0.0.1:7861
LANGFLOW_FLOW_ID=<imported-flow-id>
LANGFLOW_API_KEY=<langflow-api-key>
```

Do not commit `backend/.env`. The backend refuses to start if any value is absent or blank. During startup it also sends a safe probe through the real flow; an unreachable service, rejected key, invalid JSON, invalid schema, or non-low probe result aborts startup.

## Run the browser prototype

Install and start the repository-compatible Langflow version on port `7861`:

```bash
uv tool install 'langflow>=1.12,<1.13'
langflow run --host 127.0.0.1 --port 7861
```

Then run the backend:

```bash
uv sync --project backend
uv run --project backend uvicorn rambu_api.app:app \
  --host 0.0.0.0 --port 8000 --env-file backend/.env
```

Open <http://127.0.0.1:8000>. The first transcription may download the Whisper `small` model. This browser surface is a fixture; use the flow below for the external-audio prototype.

The canonical scenarios are:

| ID | Expected risk |
|---|---|
| `bank-otp` | `high_risk` |
| `kecelakaan-transfer` | `high_risk` |
| `kurir-aplikasi` | `high_risk` |
| `tetangga-aman` | `low` |

## Run the external-puck prototype

Generate the Xcode project and open it:

```bash
cd ios
xcodegen generate
open RambuPuck.xcodeproj
```

Use a physical iPhone. Connect the iPhone and Mac to the same network, enter `http://<MAC-LAN-IP>:8000` under **Profile → Pilot keluarga**, and create the family as the parent. The app stores the returned parent credential in Keychain. One iPhone is enough for call analysis; a second is needed only to receive guardian alerts and submit decisions.

Use the current six-digit family invitation to pair the Mac as the temporary puck. The pairing command prints the puck token once; keep it in the shell environment and never add it to `.env` or Git:

```bash
export RAMBU_SERVER_URL='http://<MAC-LAN-IP>:8000'
export RAMBU_PUCK_TOKEN="$(swift run --package-path tools/rambu-puck-agent \
  rambu-puck-agent pair --code 123456 --name 'Mac puck')"
swift run --package-path tools/rambu-puck-agent rambu-puck-agent listen
```

Keep the Mac near the iPhone speaker. With Rambu open on the parent iPhone, place or receive a real call and turn on the phone loudspeaker. Verify this progression on the parent dashboard:

1. `Rambu siap mendeteksi panggilan`
2. `Panggilan terdeteksi · menunggu Puck`
3. `Rambu sedang mendengarkan`
4. `Analisis selesai`, `Tidak ada audio yang dianalisis`, or an explicit failure

The app always obtains normal-runtime assessments from `/api/protection/*`. There is no risk-analysis fallback and no route from the normal composition to scripted scenarios.

## Explicit failures

Protection sessions use stable codes such as `transcription_failed`, `analysis_http`, `analysis_timeout`, `analysis_connection`, `analysis_invalid_json`, `analysis_invalid_response`, `analysis_failed`, and `processing_failed`. The iOS transport can additionally surface `invalid_server_url`, `missing_parent_token`, `transport`, `http_<status>`, `decoding`, and `schema`.

A failed session has `status: "error"`, no assessment, and a structured `error`. The browser clears any stale assessment. The iOS app stops listening, shows the failure, and does not save the failed call to history. Retry starts a new backend session.

## Verification

Unit tests use explicit test doubles and do not spend model quota:

```bash
uv run --project backend pytest backend/tests langflow/tests -q
cd ios
xcodegen generate
xcodebuild -project RambuPuck.xcodeproj -scheme RambuPuck \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The live Langflow contract test is opt-in and fails—not skips—when activated without credentials:

```bash
RAMBU_RUN_LIVE_LANGFLOW=1 \
uv run --project backend pytest backend/tests/test_live_langflow.py -q
```

## Project structure

```text
backend/    FastAPI, faster-whisper, dashboard, pilot API, and tests
ios/        SwiftUI MVVM app and tests
langflow/   prompt, exported Rambu flow, builder, and contract tests
samples/    fictional scripts and generated WAV fixtures
docs/       local demo, test, evidence, and IBM Bob records (gitignored)
```

IBM Bob is a development-time reviewer, not a runtime dependency. A Bob contribution must have a genuine task transcript and accepted diff before it is claimed as complete.
