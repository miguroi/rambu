import importlib.util
import json
import sys
from pathlib import Path

import pytest

from rambu_api.langflow_client import LangflowFailure
from rambu_api.models import RiskAssessment


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = ROOT / "tools" / "evaluate_audio_dataset.py"
DATASET_PATH = ROOT / "samples" / "datasets" / "rambu-voice-v0.1"


def load_evaluator_module():
    spec = importlib.util.spec_from_file_location("rambu_audio_evaluator", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class StubTranscriber:
    def __init__(self, text: str) -> None:
        self.text = text

    def transcribe(self, path: Path) -> str:
        assert path.suffix == ".mp3"
        return self.text


class FailingTranscriber:
    def transcribe(self, path: Path) -> str:
        raise RuntimeError("raw audio failure sk-or-provider-secret provider-body")


class StubAnalyzer:
    def __init__(self, risk_level: str) -> None:
        self.risk_level = risk_level
        self.calls = 0

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        self.calls += 1
        assert final is True
        if self.risk_level == "low":
            return RiskAssessment(
                risk_level="low",
                signals=[],
                evidence=[],
                explanation="Percakapan aman.",
                recommended_action="Tidak ada tindakan.",
            )
        return RiskAssessment(
            risk_level="high_risk",
            signals=["secret_code"],
            evidence=[{"quote": transcript, "signals": ["secret_code"]}],
            explanation="Ada permintaan kode.",
            recommended_action="Tutup telepon.",
        )


class FailingAnalyzer:
    def __init__(self) -> None:
        self.calls = 0

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        self.calls += 1
        raise RuntimeError("raw transcript sk-or-provider-secret provider-body")


class ContractThenSuccessAnalyzer:
    def __init__(self, risk_level: str, code: str) -> None:
        self.calls = 0
        self.success = StubAnalyzer(risk_level)
        self.code = code

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        self.calls += 1
        if self.calls == 1:
            raise LangflowFailure(
                self.code,
                "Respons Langflow tidak sesuai kontrak Rambu.",
                "http://langflow/api/v1/run/rambu",
                reason="evidence_not_in_transcript",
            )
        return self.success.analyze(transcript, final)


class LangflowFailureThenSuccessAnalyzer:
    def __init__(self, code: str) -> None:
        self.calls = 0
        self.code = code

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        self.calls += 1
        if self.calls == 1:
            raise LangflowFailure(
                self.code,
                "Langflow gagal.",
                "http://langflow/api/v1/run/rambu",
                reason="transport_failure",
            )
        return StubAnalyzer("low").analyze(transcript, final)


class AlwaysInvalidAnalyzer:
    def __init__(self) -> None:
        self.calls = 0

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        self.calls += 1
        raise LangflowFailure(
            "invalid_response",
            "Respons Langflow tidak sesuai kontrak Rambu.",
            "http://langflow/api/v1/run/rambu",
            reason="schema_validation",
        )


class UnsafeReasonThenSuccessAnalyzer:
    def __init__(self, risk_level: str) -> None:
        self.calls = 0
        self.success = StubAnalyzer(risk_level)

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        self.calls += 1
        if self.calls == 1:
            raise LangflowFailure(
                "invalid_response",
                "raw transcript sk-or-provider-secret provider-body",
                "http://langflow/api/v1/run/rambu",
                reason="raw transcript sk-or-provider-secret provider-body",
            )
        return self.success.analyze(transcript, final)


def test_dataset_is_complete_and_has_a_held_out_split() -> None:
    evaluator = load_evaluator_module()

    all_cases = evaluator.load_cases(DATASET_PATH, "all")
    development = evaluator.load_cases(DATASET_PATH, "development")
    test = evaluator.load_cases(DATASET_PATH, "test")

    assert len(all_cases) == 38
    assert len(development) == 24
    assert len(test) == 14
    assert {case.expected_risk for case in all_cases} == {"low", "high_risk"}
    assert not ({case.relative_file for case in development} & {case.relative_file for case in test})


def test_word_error_rate_is_normalized_and_exact() -> None:
    evaluator = load_evaluator_module()

    assert evaluator.word_error_rate("Halo, Ibu!", "halo ibu") == 0
    assert evaluator.word_error_rate("halo ibu", "halo") == 0.5


def test_case_requires_both_correct_risk_and_acceptable_transcription() -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]

    result = evaluator.evaluate_case(
        case,
        StubTranscriber(case.reference_transcript),
        StubAnalyzer(case.expected_risk),
        max_wer=0.35,
    )

    assert result["risk_correct"] is True
    assert result["word_error_rate"] == 0
    assert result["passed"] is True


def test_case_fails_on_wrong_risk_even_with_exact_transcription() -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]
    wrong_risk = "high_risk" if case.expected_risk == "low" else "low"

    analyzer = StubAnalyzer(wrong_risk)
    result = evaluator.evaluate_case(
        case,
        StubTranscriber(case.reference_transcript),
        analyzer,
        max_wer=0.35,
    )

    assert result["risk_correct"] is False
    assert result["passed"] is False
    assert analyzer.calls == 1


def test_case_does_not_retry_analysis_for_unacceptable_wer() -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]
    analyzer = StubAnalyzer(case.expected_risk)

    result = evaluator.evaluate_case(
        case,
        StubTranscriber("completely unrelated words"),
        analyzer,
        max_wer=0,
    )

    assert result["transcription_passed"] is False
    assert result["passed"] is False
    assert result["analysis_attempts"] == 1
    assert analyzer.calls == 1


def test_case_does_not_analyze_when_transcription_fails() -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]
    analyzer = StubAnalyzer(case.expected_risk)

    with pytest.raises(RuntimeError):
        evaluator.evaluate_case(case, FailingTranscriber(), analyzer, max_wer=0.35)

    assert analyzer.calls == 0


@pytest.mark.parametrize("code", ["invalid_response", "invalid_json"])
def test_case_retries_one_contract_failure_and_records_sanitized_reason(code) -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]
    analyzer = ContractThenSuccessAnalyzer(case.expected_risk, code)

    result = evaluator.evaluate_case(
        case,
        StubTranscriber(case.reference_transcript),
        analyzer,
        max_wer=0.35,
    )

    assert result["passed"] is True
    assert result["analysis_attempts"] == 2
    assert result["analysis_retry"] == {
        "code": code,
        "reason": "evidence_not_in_transcript",
    }
    assert analyzer.calls == 2


def test_case_still_fails_when_the_contract_retry_is_invalid() -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]
    analyzer = AlwaysInvalidAnalyzer()

    result = evaluator.evaluate_case(
        case,
        StubTranscriber(case.reference_transcript),
        analyzer,
        max_wer=0.35,
    )

    assert result["passed"] is False
    assert result["analysis_attempts"] == 2
    assert result["analysis_retry"] == {
        "code": "invalid_response",
        "reason": "schema_validation",
    }
    assert result["error"] == (
        "LangflowFailure: Respons Langflow tidak sesuai kontrak Rambu."
    )
    assert analyzer.calls == 2


@pytest.mark.parametrize("code", ["timeout", "connection", "http"])
def test_case_does_not_retry_non_contract_langflow_failures(code: str) -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]
    analyzer = LangflowFailureThenSuccessAnalyzer(code)

    result = evaluator.evaluate_case(
        case,
        StubTranscriber(case.reference_transcript),
        analyzer,
        max_wer=0.35,
    )

    assert result["passed"] is False
    assert result["analysis_attempts"] == 1
    assert result["analysis_retry"] is None
    assert analyzer.calls == 1


def test_markdown_report_discloses_recovered_analysis_retries(tmp_path: Path) -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]
    result = evaluator.evaluate_case(
        case,
        StubTranscriber(case.reference_transcript),
        ContractThenSuccessAnalyzer(case.expected_risk, "invalid_response"),
        max_wer=0.35,
    )

    _, markdown_path, _ = evaluator.write_reports(
        [result], tmp_path, "test", "small", 0.35
    )
    report = markdown_path.read_text()

    assert "Analysis retries: 1" in report
    assert "invalid_response" in report
    assert "evidence_not_in_transcript" in report


def test_reports_never_persist_untrusted_error_text_or_retry_reasons(
    tmp_path: Path,
) -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]
    analyzer = UnsafeReasonThenSuccessAnalyzer(case.expected_risk)

    result = evaluator.evaluate_case(
        case,
        StubTranscriber(case.reference_transcript),
        analyzer,
        max_wer=0.35,
    )
    json_path, markdown_path, _ = evaluator.write_reports(
        [result], tmp_path, "test", "small", 0.35
    )
    serialized = json.dumps(result) + json_path.read_text() + markdown_path.read_text()

    assert result["analysis_retry"] == {
        "code": "invalid_response",
        "reason": "unspecified",
    }
    assert "raw transcript" not in serialized
    assert "sk-or-provider-secret" not in serialized
    assert "provider-body" not in serialized


def test_analysis_failure_preserves_transcription_metrics() -> None:
    evaluator = load_evaluator_module()
    case = evaluator.load_cases(DATASET_PATH, "test")[0]
    analyzer = FailingAnalyzer()

    result = evaluator.evaluate_case(
        case,
        StubTranscriber(case.reference_transcript),
        analyzer,
        max_wer=0.35,
    )

    assert result["word_error_rate"] == 0
    assert result["transcription_passed"] is True
    assert result["actual_risk"] is None
    assert result["passed"] is False
    assert result["error"] == "analysis_error: Analysis failed unexpectedly."
    assert result["analysis_attempts"] == 1
    assert result["analysis_retry"] is None
    assert analyzer.calls == 1
    serialized = json.dumps(result)
    assert "raw transcript" not in serialized
    assert "sk-or-provider-secret" not in serialized
    assert "provider-body" not in serialized
