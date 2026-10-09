from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = ROOT / "backend" / "data" / "rambu.sqlite3"
DEFAULT_OUTPUT = ROOT / "test-results" / "manual-call-tests"
EXPECTED_RISK = {"low-risk": "low", "high-risk": "high_risk"}
TERMINAL_STATUSES = {"completed", "error"}


class RecorderError(RuntimeError):
    pass


def _rows(database: Path, query: str, parameters: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    if not database.is_file():
        raise RecorderError(f"Database not found: {database}")
    try:
        connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=2)
        connection.row_factory = sqlite3.Row
        try:
            return [dict(row) for row in connection.execute(query, parameters).fetchall()]
        finally:
            connection.close()
    except sqlite3.Error as error:
        raise RecorderError(f"Unable to read backend database: {error}") from error


def _session_ids(database: Path) -> set[str]:
    return {row["id"] for row in _rows(database, "SELECT id FROM protection_sessions")}


def _newest_new_session(database: Path, existing: set[str]) -> dict[str, Any] | None:
    rows = _rows(database, "SELECT * FROM protection_sessions ORDER BY started_at DESC")
    return next((row for row in rows if row["id"] not in existing), None)


def _session(database: Path, session_id: str) -> dict[str, Any]:
    rows = _rows(database, "SELECT * FROM protection_sessions WHERE id = ?", (session_id,))
    if not rows:
        raise RecorderError(f"Session disappeared: {session_id}")
    return rows[0]


def wait_for_result(
    database: Path,
    timeout_seconds: float,
    poll_seconds: float = 1.0,
) -> dict[str, Any]:
    existing = _session_ids(database)
    deadline = time.monotonic() + timeout_seconds
    print("Waiting for a new call session. Start and answer the test call now.", flush=True)

    current: dict[str, Any] | None = None
    while time.monotonic() < deadline:
        current = _newest_new_session(database, existing)
        if current is not None:
            print(f"Recording session {current['id']}.", flush=True)
            break
        time.sleep(poll_seconds)
    if current is None:
        raise RecorderError("No new call session appeared before the timeout.")

    last_revision: int | None = None
    while time.monotonic() < deadline:
        current = _session(database, current["id"])
        if current["revision"] != last_revision:
            print(
                f"status={current['status']} chunks={current['next_sequence']}",
                flush=True,
            )
            last_revision = current["revision"]
        if current["status"] in TERMINAL_STATUSES:
            return current
        time.sleep(poll_seconds)
    raise RecorderError(
        f"Session {current['id']} did not finish before the timeout. End the call and try again."
    )


def _decoded(value: str | None) -> dict[str, Any] | None:
    return json.loads(value) if value else None


def _result(scenario: str, session: dict[str, Any]) -> tuple[bool, str, str]:
    assessment = _decoded(session.get("assessment_json"))
    actual = assessment.get("risk_level", "none") if assessment else "none"
    expected = EXPECTED_RISK[scenario]
    if session["status"] != "completed":
        return False, actual, f"Session ended with status `{session['status']}`."
    if session.get("outcome") != "analyzed":
        return False, actual, f"Session outcome was `{session.get('outcome') or 'none'}`."
    if actual != expected:
        return False, actual, f"Expected `{expected}`, received `{actual}`."
    return True, actual, f"Expected and received `{expected}`."


def _title(scenario: str) -> str:
    return "Low Risk" if scenario == "low-risk" else "High Risk"


def write_report(
    scenario: str,
    session: dict[str, Any],
    output_directory: Path,
) -> tuple[Path, bool]:
    assessment = _decoded(session.get("assessment_json")) or {}
    failure = _decoded(session.get("failure_json"))
    passed, actual, reason = _result(scenario, session)
    generated_at = datetime.now().astimezone()
    output_directory.mkdir(parents=True, exist_ok=True)
    filename = (
        f"{generated_at:%Y%m%d-%H%M%S}-{scenario}-{session['id'][:8]}.md"
    )
    path = output_directory / filename

    signals = assessment.get("signals") or []
    evidence = assessment.get("evidence") or []
    signal_lines = "\n".join(f"- `{signal}`" for signal in signals) or "None"
    evidence_lines = "\n".join(
        f'- "{item.get("quote", "")}" — '
        + ", ".join(f"`{signal}`" for signal in item.get("signals", []))
        for item in evidence
    ) or "None"
    failure_text = (
        f"`{failure.get('code', 'unknown')}` — {failure.get('message', '')}"
        if failure
        else "None"
    )
    transcript = (session.get("masked_transcript") or "<empty>").replace("```", "` ` `")

    report = f"""# Call Test: {_title(scenario)}

- **Result:** {'PASS' if passed else 'FAIL'}
- **Reason:** {reason}
- **Expected risk:** `{EXPECTED_RISK[scenario]}`
- **Actual risk:** `{actual}`

## Session

- Generated: {generated_at.isoformat(timespec='seconds')}
- Session ID: `{session['id']}`
- Call ID: `{session['call_id']}`
- Channel: `{session.get('channel') or 'unknown'}`
- Status: `{session['status']}`
- Outcome: `{session.get('outcome') or 'none'}`
- Chunks: {session['next_sequence']}
- Started: {session['started_at']}
- Ended: {session.get('ended_at') or 'not recorded'}
- Failure: {failure_text}

## Masked Transcript

```text
{transcript}
```

## Assessment

- **Explanation:** {assessment.get('explanation', 'None')}
- **Recommended action:** {assessment.get('recommended_action', 'None')}

### Signals

{signal_lines}

### Evidence

{evidence_lines}

## Tester Notes

- Audio clarity:
- Warning shown in app:
- Call ended cleanly:
- Additional notes:
"""
    path.write_text(report)
    return path, passed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Record the next Rambu call test as a local Markdown report."
    )
    parser.add_argument("scenario", choices=sorted(EXPECTED_RISK))
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--timeout", type=float, default=600)
    args = parser.parse_args()

    try:
        session = wait_for_result(args.database, args.timeout)
        path, passed = write_report(args.scenario, session, args.output_dir)
    except (RecorderError, json.JSONDecodeError) as error:
        print(f"Test recorder failed: {error}", file=sys.stderr)
        return 2
    print(f"{'PASS' if passed else 'FAIL'}: {path}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
