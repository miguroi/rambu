import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = ROOT / "tools" / "record_call_test.py"


def load_recorder_module():
    spec = importlib.util.spec_from_file_location("rambu_record_call_test", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_low_risk_report_passes_and_contains_masked_results(tmp_path: Path) -> None:
    recorder = load_recorder_module()
    session = {
        "id": "session-low",
        "call_id": "call-low",
        "channel": "cellular",
        "status": "completed",
        "started_at": "2026-10-03T08:00:00+00:00",
        "ended_at": "2026-10-03T08:00:20+00:00",
        "outcome": "analyzed",
        "masked_transcript": "Besok arisan dimulai pukul sepuluh.",
        "assessment_json": (
            '{"risk_level":"low","signals":[],"evidence":[],'
            '"explanation":"Percakapan wajar.",'
            '"recommended_action":"Lanjutkan seperti biasa."}'
        ),
        "failure_json": None,
        "next_sequence": 4,
    }

    path, passed = recorder.write_report("low-risk", session, tmp_path)

    report = path.read_text()
    assert passed is True
    assert "# Call Test: Low Risk" in report
    assert "**Result:** PASS" in report
    assert "**Actual risk:** `low`" in report
    assert "Besok arisan dimulai pukul sepuluh." in report
    assert "Percakapan wajar." in report


def test_high_risk_report_fails_when_model_returns_review(tmp_path: Path) -> None:
    recorder = load_recorder_module()
    session = {
        "id": "session-review",
        "call_id": "call-review",
        "channel": "whatsapp",
        "status": "completed",
        "started_at": "2026-10-03T09:00:00+00:00",
        "ended_at": "2026-10-03T09:00:20+00:00",
        "outcome": "analyzed",
        "masked_transcript": "Berikan kode [KODE] sekarang.",
        "assessment_json": (
            '{"risk_level":"needs_review","signals":["secret_code"],'
            '"evidence":[{"quote":"Berikan kode [KODE] sekarang.",'
            '"signals":["secret_code"]}],'
            '"explanation":"Ada permintaan kode.",'
            '"recommended_action":"Jangan berikan kode."}'
        ),
        "failure_json": None,
        "next_sequence": 4,
    }

    path, passed = recorder.write_report("high-risk", session, tmp_path)

    report = path.read_text()
    assert passed is False
    assert "**Result:** FAIL" in report
    assert "Expected `high_risk`, received `needs_review`." in report
    assert "- `secret_code`" in report
    assert '"Berikan kode [KODE] sekarang." — `secret_code`' in report
