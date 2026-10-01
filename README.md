# Rambu

Rambu is a digital prototype of a future external call-safety device. It replays a synthetic Indonesian call, transcribes five-second audio chunks locally, masks sensitive numbers, and sends only the masked transcript to Langflow for risk analysis.

The prototype deliberately has no runtime analysis fallback. If configuration, transcription, Langflow, the model provider, transport, or response validation fails, the browser and iOS app show a failure instead of manufacturing a risk result.

This prototype does **not** capture a live phone call. Testing on one Android 13 phone found that third-party microphone input was unavailable during the tested cellular and WhatsApp calls.

## What the demo shows

```text
Synthetic WAV -> faster-whisper -> masked transcript -> Langflow + OpenRouter -> warning
```

- Four fictional scenarios: bank OTP, emergency transfer, malicious courier app, and a safe neighbour call.
- Incremental Indonesian transcription.
- Strict `low`, `needs_review`, or `high_risk` assessments.
- Validated signals, transcript-backed evidence, explanation, and recommended action.
- A browser dashboard and SwiftUI app that both consume the backend result.
- Optional two-iPhone family-alert synchronization.
- Raw audio stays local and temporary chunks are deleted.

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

Start Langflow on port `7861`, then run:

```bash
uv sync --project backend
uv run --project backend uvicorn rambu_api.app:app \
  --host 0.0.0.0 --port 8000 --env-file backend/.env
```

Open <http://127.0.0.1:8000>. The first transcription may download the Whisper `small` model.

The canonical scenarios are:

| ID | Expected risk |
|---|---|
| `bank-otp` | `high_risk` |
| `kecelakaan-transfer` | `high_risk` |
| `kurir-aplikasi` | `high_risk` |
| `tetangga-aman` | `low` |

## Run the iOS prototype

Generate the Xcode project and open it:

```bash
cd ios
xcodegen generate
open RambuPuck.xcodeproj
```

The simulator uses `http://127.0.0.1:8000`. A physical iPhone cannot use the Mac's loopback address: connect both devices to the same network, enter `http://<MAC-LAN-IP>:8000` under **Profile -> Pilot dua HP**, create or join the pilot so the address is saved, then relaunch the app. One iPhone is enough for call analysis; two are needed only to demonstrate the parent/guardian synchronization flow.

The app always obtains call assessments from the backend. It does not use the scripted scenario text to calculate a risk result.

## Explicit failures

Backend demo sessions use stable codes such as `transcription_failed`, `analysis_http`, `analysis_timeout`, `analysis_connection`, `analysis_invalid_json`, `analysis_invalid_response`, `analysis_failed`, and `processing_failed`. The iOS transport can additionally surface `invalid_server_url`, `invalid_scenario`, `transport`, `http_<status>`, `decoding`, and `schema`.

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
