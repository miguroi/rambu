# Rambu

Rambu detects an active iPhone call, records its loudspeaker audio through an external puck, transcribes it, and asks Langflow to assess scam risk. For now, the Mac runs as the temporary puck. Rambu has no analysis fallback: configuration and processing failures are shown as errors.

The iPhone does not record call audio. Keep Rambu open during the call and place the Mac near the phone's loudspeaker. One iPhone is enough; a second iPhone is only needed for guardian alerts.

## Requirements

- macOS with Xcode 26 and XcodeGen
- A physical iPhone running iOS 26
- Python 3.12 and `uv`
- Langflow 1.12.x
- OpenRouter and Langflow API keys
- Mac and iPhone on the same Wi-Fi network

Run every command below from the repository root unless stated otherwise.

## Run the App

### 1. Start Langflow

```bash
uv venv langflow/.venv --python 3.12
source langflow/.venv/bin/activate
uv pip install 'langflow>=1.12,<1.13'
langflow run --host 127.0.0.1 --port 7861
```

For later runs, activate the existing environment and start Langflow:

```bash
source langflow/.venv/bin/activate
langflow run --host 127.0.0.1 --port 7861
```

Open <http://127.0.0.1:7861>, then:

1. Import `langflow/flows/Rambu.json`.
2. Open the **Language Model** component and add the OpenRouter API key.
3. Save the flow. Its endpoint name is `rambu`.
4. Create a Langflow API key under **Settings → API Keys**.

Keep this terminal running.

### 2. Start the Backend

If `backend/.env` does not exist:

```bash
cp backend/.env.example backend/.env
```

Set these values in `backend/.env`:

```dotenv
LANGFLOW_URL=http://127.0.0.1:7861
LANGFLOW_FLOW_ID=rambu
LANGFLOW_API_KEY=<your-langflow-api-key>
```

Start the backend in a new terminal:

```bash
uv sync --project backend
uv run --project backend uvicorn rambu_api.app:app \
  --host 0.0.0.0 --port 8000 --env-file backend/.env
```

It is ready when <http://127.0.0.1:8000/health> returns `{"status":"ready"}`. Keep this terminal running.

### 3. Run the iPhone App

Find the Mac's Wi-Fi IP address:

```bash
ipconfig getifaddr en0
```

Generate and open the Xcode project:

```bash
cd ios
xcodegen generate
open RambuPuck.xcodeproj
```

In Xcode:

1. Select your development team for both app targets.
2. Select the connected physical iPhone.
3. Press **Run**.

In Rambu on the iPhone:

1. Complete onboarding as the parent.
2. Open **Profile → Pilot keluarga**.
3. Set the server URL to `http://<MAC-IP>:8000`.
4. Create the family and note its six-digit invitation code.

### 4. Connect the Puck

Return to the repository root in a new terminal. Replace the IP and invitation code:

```bash
export RAMBU_SERVER_URL='http://<MAC-IP>:8000'
export RAMBU_PUCK_TOKEN="$(swift run --package-path tools/rambu-puck-agent \
  rambu-puck-agent pair --code 123456 --name 'Mac puck')"
swift run --package-path tools/rambu-puck-agent rambu-puck-agent listen
```

Allow microphone access when macOS asks. Keep this terminal running.

### 5. Test a Call

1. Keep Rambu open on the iPhone.
2. Place or receive a real call.
3. Turn on the iPhone loudspeaker and keep the Mac nearby.
4. Confirm the app progresses from call detected, to listening, to an assessment or an explicit error.

## Troubleshooting

| Problem | Fix |
|---|---|
| `langflow: command not found` | Activate `langflow/.venv`. If it does not exist, run all first-time commands in step 1. |
| Backend exits during startup | Check that Langflow is running, all three `LANGFLOW_*` values are correct, and the imported flow works in Langflow. |
| iPhone cannot reach the backend | Use the Mac's Wi-Fi IP, not `127.0.0.1`, and keep both devices on the same network. |
| Call is detected but remains waiting for the puck | Keep the puck `listen` command running and pair it with the current family invitation code. |
| No call is detected | Use a physical iPhone, keep Rambu open, and grant requested permissions. |
