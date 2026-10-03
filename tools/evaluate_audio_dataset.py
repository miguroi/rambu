from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
import unicodedata
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any, NamedTuple, Protocol

from rambu_api.langflow_client import (
    SAFE_FAILURE_REASONS,
    LangflowClient,
    LangflowFailure,
)
from rambu_api.models import RiskAssessment
from rambu_api.redaction import mask_sensitive_text
from rambu_api.transcription import FasterWhisperTranscriber


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATASET = ROOT / "samples" / "datasets" / "rambu-voice-v0.1"
DEFAULT_OUTPUT = ROOT / "test-results" / "audio-dataset"
EXPECTED_RISK = {"AMAN": "low", "WASPADA": "needs_review", "TINGGI": "high_risk"}
RETRYABLE_ANALYSIS_ERRORS = {"invalid_json", "invalid_response"}
SAFE_LANGFLOW_FAILURE_MESSAGES = {
    "invalid_json": "LangflowFailure: Langflow mengembalikan JSON yang tidak valid.",
    "invalid_response": "LangflowFailure: Respons Langflow tidak sesuai kontrak Rambu.",
    "timeout": "LangflowFailure: Langflow tidak merespons sebelum batas waktu.",
    "connection": "LangflowFailure: Langflow tidak dapat dihubungi.",
    "http": "LangflowFailure: Langflow menolak permintaan.",
}


class EvaluationError(RuntimeError):
    pass


class Transcriber(Protocol):
    def transcribe(self, path: Path) -> str: ...


class Analyzer(Protocol):
    def analyze(self, transcript: str, final: bool) -> RiskAssessment: ...


class AudioCase(NamedTuple):
    relative_file: str
    path: Path
    category: str
    expected_risk: str
    reference_transcript: str
    duration_seconds: float
    critical_signal_seconds: float | None
    indicators: tuple[str, ...]
    split: str


def _safe_langflow_error(error: LangflowFailure) -> str:
    return SAFE_LANGFLOW_FAILURE_MESSAGES.get(
        error.code,
        "analysis_error: Analysis failed unexpectedly.",
    )


def _safe_retry_reason(error: LangflowFailure) -> str:
    if error.reason in SAFE_FAILURE_REASONS:
        return error.reason
    return "unspecified"


def _split_for(relative_file: str) -> str:
    match = re.search(r"_(\d+)\.mp3$", relative_file)
    if match is None:
        raise EvaluationError(f"Dataset filename has no numeric case suffix: {relative_file}")
    return "development" if int(match.group(1)) <= 4 else "test"


def _safe_relative_file(value: str) -> str:
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.suffix.lower() != ".mp3":
        raise EvaluationError(f"Unsafe dataset audio path: {value}")
    return path.as_posix()


def load_cases(dataset: Path, split: str = "test") -> list[AudioCase]:
    labels_path = dataset / "metadata" / "labels.csv"
    transcripts_path = dataset / "metadata" / "transkrip.jsonl"
    if not labels_path.is_file() or not transcripts_path.is_file():
        raise EvaluationError(f"Dataset metadata is incomplete: {dataset}")

    transcripts: dict[str, dict[str, Any]] = {}
    with transcripts_path.open(encoding="utf-8") as source:
        for line_number, line in enumerate(source, start=1):
            try:
                value = json.loads(line)
                relative_file = _safe_relative_file(value["file"])
            except (json.JSONDecodeError, KeyError, TypeError) as error:
                raise EvaluationError(
                    f"Invalid transcript record at line {line_number}."
                ) from error
            if relative_file in transcripts:
                raise EvaluationError(f"Duplicate transcript record: {relative_file}")
            transcripts[relative_file] = value

    cases: list[AudioCase] = []
    label_files: set[str] = set()
    with labels_path.open(encoding="utf-8", newline="") as source:
        for row_number, row in enumerate(csv.DictReader(source), start=2):
            try:
                relative_file = _safe_relative_file(row["file"])
                expected_risk = EXPECTED_RISK[row["risiko"]]
                transcript_record = transcripts[relative_file]
                turns = transcript_record["turns"]
                reference = " ".join(turn["text"].strip() for turn in turns).strip()
                duration = float(row["durasi_detik"])
                critical = (
                    float(row["detik_sinyal_kritis_pertama"])
                    if row["detik_sinyal_kritis_pertama"].strip()
                    else None
                )
            except (KeyError, TypeError, ValueError) as error:
                raise EvaluationError(f"Invalid label record at row {row_number}.") from error
            if relative_file in label_files:
                raise EvaluationError(f"Duplicate label record: {relative_file}")
            label_files.add(relative_file)
            audio_path = dataset / "audio" / Path(relative_file)
            if not audio_path.is_file():
                raise EvaluationError(f"Audio file is missing: {audio_path}")
            case_split = _split_for(relative_file)
            if split == "all" or case_split == split:
                cases.append(
                    AudioCase(
                        relative_file=relative_file,
                        path=audio_path,
                        category=row["kategori"],
                        expected_risk=expected_risk,
                        reference_transcript=reference,
                        duration_seconds=duration,
                        critical_signal_seconds=critical,
                        indicators=tuple(filter(None, row["indikator"].split("|"))),
                        split=case_split,
                    )
                )

    if label_files != set(transcripts):
        missing_labels = sorted(set(transcripts) - label_files)
        missing_transcripts = sorted(label_files - set(transcripts))
        raise EvaluationError(
            "Dataset labels and transcripts do not match. "
            f"Missing labels={missing_labels}; missing transcripts={missing_transcripts}."
        )
    if not cases:
        raise EvaluationError(f"Dataset contains no cases for split: {split}")
    return sorted(cases, key=lambda case: case.relative_file)


def _words(text: str) -> list[str]:
    normalized = unicodedata.normalize("NFKC", text).casefold()
    return re.findall(r"[^\W_]+", normalized, flags=re.UNICODE)


def word_error_rate(reference: str, hypothesis: str) -> float:
    expected = _words(reference)
    actual = _words(hypothesis)
    if not expected:
        return 0.0 if not actual else 1.0
    previous = list(range(len(actual) + 1))
    for row, expected_word in enumerate(expected, start=1):
        current = [row]
        for column, actual_word in enumerate(actual, start=1):
            current.append(
                min(
                    current[column - 1] + 1,
                    previous[column] + 1,
                    previous[column - 1] + (expected_word != actual_word),
                )
            )
        previous = current
    return previous[-1] / len(expected)


def evaluate_case(
    case: AudioCase,
    transcriber: Transcriber,
    analyzer: Analyzer,
    max_wer: float,
) -> dict[str, Any]:
    started = time.monotonic()
    transcript = transcriber.transcribe(case.path).strip()
    if not transcript:
        raise EvaluationError("Transcription was empty.")
    masked = mask_sensitive_text(transcript)
    wer = word_error_rate(case.reference_transcript, transcript)
    common = {
        "file": case.relative_file,
        "category": case.category,
        "split": case.split,
        "duration_seconds": case.duration_seconds,
        "critical_signal_seconds": case.critical_signal_seconds,
        "expected_indicators": list(case.indicators),
        "expected_risk": case.expected_risk,
        "word_error_rate": wer,
        "max_word_error_rate": max_wer,
        "transcription_passed": wer <= max_wer,
        "transcript": transcript,
        "masked_transcript": masked,
    }
    analysis_attempts = 0
    analysis_retry: dict[str, str | None] | None = None
    while True:
        analysis_attempts += 1
        try:
            assessment = analyzer.analyze(masked, final=True)
            break
        except LangflowFailure as error:
            if analysis_attempts == 1 and error.code in RETRYABLE_ANALYSIS_ERRORS:
                analysis_retry = {
                    "code": error.code,
                    "reason": _safe_retry_reason(error),
                }
                continue
            return {
                **common,
                "actual_risk": None,
                "risk_correct": False,
                "passed": False,
                "analysis_attempts": analysis_attempts,
                "analysis_retry": analysis_retry,
                "elapsed_seconds": time.monotonic() - started,
                "assessment": None,
                "error": _safe_langflow_error(error),
            }
        except Exception:
            return {
                **common,
                "actual_risk": None,
                "risk_correct": False,
                "passed": False,
                "analysis_attempts": analysis_attempts,
                "analysis_retry": analysis_retry,
                "elapsed_seconds": time.monotonic() - started,
                "assessment": None,
                "error": "analysis_error: Analysis failed unexpectedly.",
            }
    risk_correct = assessment.risk_level == case.expected_risk
    transcription_passed = wer <= max_wer
    return {
        **common,
        "actual_risk": assessment.risk_level,
        "risk_correct": risk_correct,
        "transcription_passed": transcription_passed,
        "passed": risk_correct and transcription_passed,
        "analysis_attempts": analysis_attempts,
        "analysis_retry": analysis_retry,
        "elapsed_seconds": time.monotonic() - started,
        "assessment": assessment.model_dump(),
        "error": None,
    }


def _summary(results: list[dict[str, Any]]) -> dict[str, Any]:
    completed = [result for result in results if result.get("word_error_rate") is not None]
    safe = [result for result in results if result["expected_risk"] == "low"]
    scams = [result for result in results if result["expected_risk"] == "high_risk"]
    return {
        "total": len(results),
        "passed": sum(bool(result["passed"]) for result in results),
        "failed": sum(not result["passed"] for result in results),
        "risk_correct": sum(bool(result.get("risk_correct")) for result in results),
        "risk_accuracy": (
            sum(bool(result.get("risk_correct")) for result in results) / len(results)
            if results
            else 0.0
        ),
        "safe_accuracy": (
            sum(bool(result.get("risk_correct")) for result in safe) / len(safe)
            if safe
            else None
        ),
        "scam_recall": (
            sum(bool(result.get("risk_correct")) for result in scams) / len(scams)
            if scams
            else None
        ),
        "average_word_error_rate": (
            sum(result["word_error_rate"] for result in completed) / len(completed)
            if completed
            else None
        ),
    }


def write_reports(
    results: list[dict[str, Any]],
    output_directory: Path,
    split: str,
    model_name: str,
    max_wer: float,
) -> tuple[Path, Path, dict[str, Any]]:
    generated_at = datetime.now().astimezone()
    output_directory.mkdir(parents=True, exist_ok=True)
    stem = f"{generated_at:%Y%m%d-%H%M%S}-{split}"
    json_path = output_directory / f"{stem}.json"
    markdown_path = output_directory / f"{stem}.md"
    summary = _summary(results)
    payload = {
        "generated_at": generated_at.isoformat(timespec="seconds"),
        "dataset": "rambu-voice-v0.1",
        "split": split,
        "whisper_model": model_name,
        "max_word_error_rate": max_wer,
        "summary": summary,
        "results": results,
    }
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    rows = []
    for result in results:
        wer = result.get("word_error_rate")
        rows.append(
            "| {file} | {expected} | {actual} | {wer} | {attempts} | {status} |".format(
                file=result["file"],
                expected=result["expected_risk"],
                actual=result.get("actual_risk") or "error",
                wer=f"{wer:.1%}" if wer is not None else "—",
                attempts=result.get("analysis_attempts", 0),
                status="PASS" if result["passed"] else "FAIL",
            )
        )
    failures = [result for result in results if not result["passed"]]
    failure_lines = []
    for result in failures:
        reason = result.get("error") or (
            f"expected risk `{result['expected_risk']}`, received "
            f"`{result.get('actual_risk')}`; WER "
            f"{result.get('word_error_rate', 0):.1%}"
        )
        failure_lines.append(f"- `{result['file']}` — {reason}")
    retried = [result for result in results if result.get("analysis_retry")]
    retry_lines = []
    for result in retried:
        retry = result["analysis_retry"]
        outcome = "accepted" if result.get("assessment") else "failed"
        retry_lines.append(
            f"- `{result['file']}` — first attempt `{retry['code']}` "
            f"(`{retry.get('reason') or 'unspecified'}`); {outcome} after "
            f"{result['analysis_attempts']} attempts"
        )
    average_wer = summary["average_word_error_rate"]
    markdown = f"""# Rambu Audio Dataset Evaluation

- Generated: {payload['generated_at']}
- Dataset: `rambu-voice-v0.1`
- Split: `{split}`
- Whisper model: `{model_name}`
- Maximum WER: {max_wer:.0%}
- Result: **{'PASS' if summary['failed'] == 0 else 'FAIL'}**
- Passed: {summary['passed']}/{summary['total']}
- Risk accuracy: {summary['risk_accuracy']:.1%}
- Safe-call accuracy: {f"{summary['safe_accuracy']:.1%}" if summary['safe_accuracy'] is not None else 'unavailable'}
- Scam recall: {f"{summary['scam_recall']:.1%}" if summary['scam_recall'] is not None else 'unavailable'}
- Average WER: {f'{average_wer:.1%}' if average_wer is not None else 'unavailable'}
- Analysis retries: {len(retried)}

| File | Expected | Actual | WER | Analysis attempts | Result |
|---|---|---|---:|---:|---|
{chr(10).join(rows)}

## Analysis retries

{chr(10).join(retry_lines) if retry_lines else 'None'}

## Failures

{chr(10).join(failure_lines) if failure_lines else 'None'}
"""
    markdown_path.write_text(markdown, encoding="utf-8")
    return json_path, markdown_path, summary


def _configuration() -> LangflowClient:
    required = ("LANGFLOW_URL", "LANGFLOW_FLOW_ID", "LANGFLOW_API_KEY")
    missing = [name for name in required if not os.getenv(name, "").strip()]
    if missing:
        raise EvaluationError(f"Missing configuration: {', '.join(missing)}")
    return LangflowClient(
        os.environ["LANGFLOW_URL"],
        os.environ["LANGFLOW_FLOW_ID"],
        os.environ["LANGFLOW_API_KEY"],
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate Rambu transcription and final risk classification on the voice dataset."
    )
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--split", choices=("test", "development", "all"), default="test")
    parser.add_argument("--file", help="Evaluate one metadata-relative audio path.")
    parser.add_argument("--limit", type=int, help="Evaluate only the first N selected files.")
    parser.add_argument("--model", default=os.getenv("RAMBU_WHISPER_MODEL", "small"))
    parser.add_argument("--max-wer", type=float, default=0.35)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    try:
        if not 0 <= args.max_wer <= 1:
            raise EvaluationError("--max-wer must be between 0 and 1.")
        if args.limit is not None and args.limit < 1:
            raise EvaluationError("--limit must be at least 1.")
        cases = load_cases(args.dataset, args.split)
        if args.file:
            selected = _safe_relative_file(args.file)
            cases = [case for case in cases if case.relative_file == selected]
            if not cases:
                raise EvaluationError(
                    f"File is not present in the selected split: {selected}"
                )
        if args.limit is not None:
            cases = cases[: args.limit]
        analyzer = _configuration()
        print("Checking Langflow contract...", flush=True)
        analyzer.probe()
        transcriber = FasterWhisperTranscriber(args.model)
    except EvaluationError as error:
        print(f"Audio dataset evaluation could not start: {error}", file=sys.stderr)
        return 2
    except LangflowFailure as error:
        print(
            f"Audio dataset evaluation could not start: {_safe_langflow_error(error)}",
            file=sys.stderr,
        )
        return 2
    except Exception:
        print(
            "Audio dataset evaluation could not start: unexpected startup failure.",
            file=sys.stderr,
        )
        return 2

    results: list[dict[str, Any]] = []
    for index, case in enumerate(cases, start=1):
        print(f"[{index}/{len(cases)}] {case.relative_file}", flush=True)
        try:
            result = evaluate_case(case, transcriber, analyzer, args.max_wer)
            if result["error"]:
                print(
                    f"  ERROR {result['error']} WER={result['word_error_rate']:.1%} ",
                    file=sys.stderr,
                    flush=True,
                )
            else:
                print(
                    f"  {'PASS' if result['passed'] else 'FAIL'} "
                    f"risk={result['actual_risk']} WER={result['word_error_rate']:.1%} "
                    f"attempts={result['analysis_attempts']} "
                    f"elapsed={result['elapsed_seconds']:.1f}s",
                    flush=True,
                )
        except Exception:
            result = {
                "file": case.relative_file,
                "category": case.category,
                "split": case.split,
                "expected_risk": case.expected_risk,
                "actual_risk": None,
                "risk_correct": False,
                "word_error_rate": None,
                "transcription_passed": False,
                "passed": False,
                "analysis_attempts": 0,
                "analysis_retry": None,
                "error": "case_error: Audio case processing failed unexpectedly.",
            }
            print(f"  ERROR {result['error']}", file=sys.stderr, flush=True)
        results.append(result)

    json_path, markdown_path, summary = write_reports(
        results, args.output_dir, args.split, args.model, args.max_wer
    )
    print(f"JSON report: {json_path}")
    print(f"Markdown report: {markdown_path}")
    print(
        f"Result: {'PASS' if summary['failed'] == 0 else 'FAIL'} "
        f"({summary['passed']}/{summary['total']})"
    )
    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
