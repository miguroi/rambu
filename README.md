# Rambu

Rambu is a digital prototype of a future external call-safety device. It replays a synthetic Indonesian call, transcribes five-second audio chunks locally, masks sensitive numbers, and sends only the masked transcript to Langflow for risk analysis.

This prototype does **not** capture a live phone call. Testing on one Android 13 phone found that third-party microphone input was unavailable during the tested cellular and WhatsApp calls.

## What the demo shows

```text
Synthetic WAV → faster-whisper → masked transcript → Langflow + OpenRouter → warning
```

- Three fictional scenarios: normal, unclear, and OTP/payment request.
- Incremental Indonesian transcription.
- `low`, `needs_review`, or `high_risk` assessment.
- Exact indicators, short explanation, and recommended action.
- Browser dashboard and a SwiftUI product app with an optional two-iPhone pilot mode.
- Raw audio stays local and temporary chunks are deleted.

## Requirements

- Python 3.12
- [uv](https://docs.astral.sh/uv/)
- Langflow 1.12.x
- An OpenRouter API key

## Run

1. Add `OPENROUTER_API_KEY` to the environment used by Langflow.
2. Start Langflow on port `7861`.
3. Import [`langflow/flows/Rambu.json`](langflow/flows/Rambu.json) and run the flow once in Playground.
4. Start the Rambu backend:

```bash
cd backend
cp .env.example .env
uv sync
uv run uvicorn rambu_api.app:app --host 0.0.0.0 --port 8000 --env-file .env
```

5. Open <http://127.0.0.1:8000> and select a scenario.

The first local transcription may download the Whisper `small` model. If the imported flow receives a different endpoint name, place that value in `backend/.env` as `LANGFLOW_FLOW_ID`.

## Tests

```bash
uv run --project backend pytest backend/tests langflow/tests -q
```

Tests use fake transcription and Langflow clients; they do not spend API quota.

## Project structure

```text
backend/    FastAPI, faster-whisper, dashboard, and tests
langflow/   prompt, flow builder, exported Rambu.json, and tests
samples/    fictional scripts and generated WAV files
docs/       demo, Android finding, project plan, and IBM Bob record
```

See [`docs/DEMO.md`](docs/DEMO.md) for the demo script and [`docs/IBM_BOB_USAGE.md`](docs/IBM_BOB_USAGE.md) before submission.

## iOS app

[`ios/RambuPuck.xcodeproj`](ios/RambuPuck.xcodeproj) is the canonical iOS app. Its ordinary mode is a complete one-phone synthetic demo. **Profile → Pilot dua HP** connects separate parent and guardian iPhones through the backend with expiring invite codes, shared alerts, first-decision-wins locking, SQLite persistence, Keychain device credentials, and optional APNs delivery.

The app still does not record an iPhone call. `POST /api/analyze-chunk` is ready for consented mono 16 kHz WAV chunks from future puck hardware, but BLE requires an agreed firmware/GATT specification. See [`docs/IOS_TEST.md`](docs/IOS_TEST.md) and [`docs/PILOT.md`](docs/PILOT.md).
