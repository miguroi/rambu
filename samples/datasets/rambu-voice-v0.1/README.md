# Rambu Voice Dataset v0.1

This dataset contains 38 synthetic Indonesian phone conversations: 8 safe calls and 30 scam calls across bank/OTP, authority impersonation, family emergency, prize, and courier scenarios.

## Layout

- `audio/`: MP3 recordings grouped by scenario.
- `metadata/labels.csv`: one expected final risk and scenario label per recording.
- `metadata/transkrip.jsonl`: turn-level reference transcripts, speakers, timestamps, and indicators.
- `documentation/briefing.docx`: original dataset briefing.

The automated split follows the dataset briefing: files numbered `01` through `04` are development cases; files numbered `05` and above are held-out test cases. This produces 24 development and 14 test recordings.

## Evaluation

Start Langflow, then run from the repository root:

```bash
uv run --project backend --env-file backend/.env \
  python tools/evaluate_audio_dataset.py
```

The default evaluates the 14 held-out recordings. It performs real local Whisper transcription, masks sensitive-looking values, calls the configured Langflow flow, and requires both:

- the exact expected final risk (`low` or `high_risk`); and
- word error rate at or below 35%.

Reports are written to `test-results/audio-dataset/`. The command returns a nonzero exit code if any recording fails or a dependency is unavailable.

Evaluate all 38 recordings with:

```bash
uv run --project backend --env-file backend/.env \
  python tools/evaluate_audio_dataset.py --split all
```

For a quick pipeline check:

```bash
uv run --project backend --env-file backend/.env \
  python tools/evaluate_audio_dataset.py --limit 1
```

The recordings are synthetic and suitable for pipeline evaluation, not acoustic-model training or production accuracy claims.
