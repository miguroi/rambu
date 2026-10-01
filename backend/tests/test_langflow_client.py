import json
from urllib.error import HTTPError, URLError

import pytest

from rambu_api.langflow_client import LangflowClient


def assessment(
    *,
    risk_level: str = "high_risk",
    signals: list[str] | None = None,
    evidence: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    return {
        "risk_level": risk_level,
        "signals": ["secret_code"] if signals is None else signals,
        "evidence": (
            [{"quote": "berikan OTP [KODE]", "signals": ["secret_code"]}]
            if evidence is None
            else evidence
        ),
        "explanation": "Penelepon meminta kode rahasia.",
        "recommended_action": "Akhiri panggilan dan hubungi kanal resmi.",
    }


def envelope(value: object) -> dict[str, object]:
    text = value if isinstance(value, str) else json.dumps(value)
    return {
        "outputs": [
            {"outputs": [{"results": {"message": {"text": text}}}]}
        ]
    }


def failure_from(call) -> Exception:
    with pytest.raises(Exception) as captured:
        call()
    assert type(captured.value).__name__ == "LangflowFailure"
    return captured.value


def test_parses_only_the_exact_langflow_envelope_and_sends_authentication() -> None:
    calls: list[tuple[str, dict[str, str], dict[str, object]]] = []

    def transport(url, headers, payload):
        calls.append((url, headers, payload))
        return envelope(assessment())

    client = LangflowClient(
        base_url="http://localhost:7861",
        flow_id="rambu",
        api_key="secret",
        transport=transport,
    )

    result = client.analyze("Tolong berikan OTP [KODE] sekarang.", final=False)

    assert result.risk_level == "high_risk"
    assert result.signals == ["secret_code"]
    assert result.evidence[0].quote == "berikan OTP [KODE]"
    assert calls[0][0] == "http://localhost:7861/api/v1/run/rambu"
    assert calls[0][1]["x-api-key"] == "secret"
    assert "Tolong berikan OTP [KODE] sekarang." in calls[0][2]["input_value"]


@pytest.mark.parametrize(
    "invalid",
    [
        {**assessment(), "invented_caller": "Bank palsu"},
        assessment(risk_level="critical"),
        assessment(signals=["cryptocurrency"]),
        assessment(
            risk_level="low",
            signals=[],
            evidence=[{"quote": "halo", "signals": []}],
        ),
        assessment(risk_level="needs_review", signals=["urgency"], evidence=[]),
        assessment(
            signals=["secret_code"],
            evidence=[{"quote": "berikan OTP [KODE]", "signals": ["urgency"]}],
        ),
        assessment(
            signals=["secret_code"],
            evidence=[{"quote": "kutipan yang tidak ada", "signals": ["secret_code"]}],
        ),
    ],
)
def test_rejects_schema_and_semantic_contract_violations(invalid) -> None:
    client = LangflowClient(
        "http://localhost:7861",
        "rambu",
        "secret",
        transport=lambda *_: envelope(invalid),
    )

    error = failure_from(
        lambda: client.analyze("Tolong berikan OTP [KODE] sekarang.", final=True)
    )

    assert getattr(error, "code") == "invalid_response"


def test_rejects_assessment_outside_the_documented_envelope() -> None:
    client = LangflowClient(
        "http://localhost:7861",
        "rambu",
        "secret",
        transport=lambda *_: {"unexpected": assessment()},
    )

    error = failure_from(lambda: client.analyze("contoh", final=True))

    assert getattr(error, "code") == "invalid_response"


def test_reports_malformed_message_json_distinctly() -> None:
    client = LangflowClient(
        "http://localhost:7861",
        "rambu",
        "secret",
        transport=lambda *_: envelope("not-json"),
    )

    error = failure_from(lambda: client.analyze("contoh", final=True))

    assert getattr(error, "code") == "invalid_json"


@pytest.mark.parametrize(
    ("raised", "code", "status"),
    [
        (TimeoutError("slow"), "timeout", None),
        (URLError("offline"), "connection", None),
        (HTTPError("http://localhost", 401, "secret-key provider-body", None, None), "http", 401),
        (HTTPError("http://localhost", 404, "missing", None, None), "http", 404),
        (HTTPError("http://localhost", 503, "provider-body", None, None), "http", 503),
    ],
)
def test_reports_transport_failures_with_safe_context(raised, code, status) -> None:
    def transport(*_):
        raise raised

    client = LangflowClient("http://localhost:7861", "rambu", "secret-key", transport=transport)

    error = failure_from(lambda: client.analyze("contoh", final=True))

    assert getattr(error, "code") == code
    assert getattr(error, "endpoint").endswith("/api/v1/run/rambu")
    assert getattr(error, "http_status") == status
    assert "secret-key" not in str(error)
    assert "provider-body" not in str(error)


def test_probe_requires_a_valid_low_risk_result() -> None:
    received: list[str] = []

    def transport(_url, _headers, payload):
        received.append(payload["input_value"])
        return envelope(assessment())

    client = LangflowClient("http://localhost:7861", "rambu", "secret", transport=transport)

    error = failure_from(lambda: client.probe())

    assert getattr(error, "code") == "invalid_response"
    assert "analysis_mode" in received[0]
