# Call Testing

## Automated audio dataset

The repository includes 38 labeled synthetic calls under `samples/datasets/rambu-voice-v0.1/`. Start Langflow, then run the held-out set:

```bash
uv run --project backend --env-file backend/.env \
  python tools/evaluate_audio_dataset.py
```

This runs real Whisper transcription and Langflow analysis for 14 recordings, checks the exact final risk and a maximum 35% word error rate, and writes JSON and Markdown reports to `test-results/audio-dataset/`. Any audio, transcription, configuration, or analysis failure makes the command fail; no result is substituted.

Use `--split all` for all 38 recordings or `--limit 1` for a quick pipeline check.

## Physical call testing

Run these tests with Langflow, the backend, the iPhone app, and the puck agent already running. Terminal 3 must show `Rambu puck agent is waiting for an active call.`

The recorder watches the backend database. Start it before each call; when the call finishes, it creates a local Markdown report in `test-results/manual-call-tests/`. Reports contain the masked transcript and analysis, never raw audio, and are ignored by Git.

For an iPhone warning while Rambu is behind the Phone or WhatsApp app, enable notifications in iOS and configure all `APNS_*` values in `backend/.env`. Without a registered parent device token, the backend logs `protection push not sent`; it never reports a successful delivery. The Mac puck independently prints and sounds a warning when the backend returns a risky assessment.

## Low-risk conversation

Start the recorder in a fourth terminal:

```bash
uv run --project backend python tools/record_call_test.py low-risk
```

Call the iPhone, answer, enable loudspeaker, and read this clearly near the puck:

> Selamat pagi, Bu Ratna. Ini Wati. Saya ingin mengingatkan bahwa arisan besok dimulai pukul sepuluh di rumah Bu Sari. Saya akan membawa makanan ringan. Sampai bertemu besok.

Wait at least five seconds, then end the call. The expected result is `low` and `PASS`.

## High-risk conversation

Start the recorder again:

```bash
uv run --project backend python tools/record_call_test.py high-risk
```

Call the iPhone, answer, enable loudspeaker, and read this clearly near the puck:

> Selamat siang, saya petugas keamanan bank. Rekening Ibu akan diblokir hari ini. Jangan beri tahu keluarga. Sebutkan kode OTP enam digit yang baru masuk sekarang. Setelah itu, segera transfer dua juta rupiah ke rekening aman yang saya berikan.

Wait at least five seconds, then end the call. The expected result is `high_risk` and `PASS`. This is a spoken test script only; never use real credentials, codes, account numbers, or transfers.

## Read the result

The recorder prints the generated report path when processing finishes:

```text
PASS: .../test-results/manual-call-tests/20261003-153000-low-risk-ab12cd34.md
```

Each report records:

- session and call identifiers;
- start and end timestamps;
- number of audio chunks;
- masked transcript;
- expected and actual risk;
- detected signals and evidence;
- failure details and tester notes.

`high-risk` passes only when the model returns exactly `high_risk`; `needs_review` is recorded as a failure so borderline results remain visible.

## Troubleshooting

- No session appears: confirm the app reports `Panggilan terdeteksi` and uses the Mac's current Wi-Fi address.
- Puck remains waiting during the call: confirm `RAMBU_SERVER_URL` and `RAMBU_PUCK_TOKEN` in Terminal 3.
- Session never finishes: end the call, bring Rambu to the foreground, and wait for the puck's final chunk.
- `no_speech`: enable loudspeaker, increase the volume, and move the iPhone closer to the puck microphone.
