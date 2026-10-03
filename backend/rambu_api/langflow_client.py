import json
from collections.abc import Callable
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from pydantic import ValidationError

from .models import RiskAssessment, validate_assessment


SAFE_FAILURE_REASONS = frozenset(
    {
        "response_not_json",
        "probe_not_low",
        "response_envelope",
        "message_not_text",
        "message_not_json",
        "schema_validation",
        "low_risk_has_findings",
        "risky_assessment_missing_findings",
        "evidence_not_in_transcript",
        "evidence_signal_missing_from_summary",
        "semantic_validation",
    }
)


class LangflowFailure(RuntimeError):
    def __init__(
        self,
        code: str,
        safe_message: str,
        endpoint: str,
        http_status: int | None = None,
        reason: str | None = None,
    ) -> None:
        super().__init__(safe_message)
        self.code = code
        self.safe_message = safe_message
        self.endpoint = endpoint
        self.http_status = http_status
        self.reason = reason if reason in SAFE_FAILURE_REASONS else None


Transport = Callable[[str, dict[str, str], dict[str, Any]], dict[str, Any]]


class LangflowClient:
    def __init__(
        self,
        base_url: str,
        flow_id: str,
        api_key: str,
        transport: Transport | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.flow_id = flow_id
        self.api_key = api_key
        self.transport = transport or self._http_transport

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        headers = {"Content-Type": "application/json"}
        headers["x-api-key"] = self.api_key
        payload = {
            "input_value": json.dumps(
                {
                    "masked_transcript": transcript,
                    "analysis_mode": "final" if final else "live",
                },
                ensure_ascii=False,
            ),
            "input_type": "chat",
            "output_type": "chat",
        }
        url = f"{self.base_url}/api/v1/run/{self.flow_id}"
        try:
            response = self.transport(url, headers, payload)
        except HTTPError as error:
            raise LangflowFailure(
                "http",
                f"Langflow menolak permintaan (HTTP {error.code}).",
                url,
                error.code,
            ) from error
        except TimeoutError as error:
            raise LangflowFailure(
                "timeout",
                "Langflow tidak merespons sebelum batas waktu.",
                url,
            ) from error
        except (URLError, OSError) as error:
            raise LangflowFailure(
                "connection",
                "Langflow tidak dapat dihubungi.",
                url,
            ) from error
        except json.JSONDecodeError as error:
            raise LangflowFailure(
                "invalid_json",
                "Langflow mengembalikan JSON yang tidak valid.",
                url,
                reason="response_not_json",
            ) from error
        return _extract_assessment(response, transcript, url)

    def probe(self) -> None:
        assessment = self.analyze(
            "Halo Bu, arisan dimulai pukul empat sore.",
            final=True,
        )
        if assessment.risk_level != "low":
            raise LangflowFailure(
                "invalid_response",
                "Probe Langflow tidak menghasilkan risiko rendah yang valid.",
                f"{self.base_url}/api/v1/run/{self.flow_id}",
                reason="probe_not_low",
            )

    @staticmethod
    def _http_transport(
        url: str,
        headers: dict[str, str],
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        request = Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        with urlopen(request, timeout=45) as response:
            return json.loads(response.read().decode("utf-8"))


def _extract_assessment(value: Any, transcript: str, endpoint: str) -> RiskAssessment:
    try:
        text = value["outputs"][0]["outputs"][0]["results"]["message"]["text"]
    except (KeyError, IndexError, TypeError) as error:
        raise LangflowFailure(
            "invalid_response",
            "Respons Langflow tidak sesuai kontrak Rambu.",
            endpoint,
            reason="response_envelope",
        ) from error
    if not isinstance(text, str):
        raise LangflowFailure(
            "invalid_response",
            "Respons Langflow tidak sesuai kontrak Rambu.",
            endpoint,
            reason="message_not_text",
        )
    try:
        candidate = json.loads(text)
    except json.JSONDecodeError as error:
        raise LangflowFailure(
            "invalid_json",
            "Langflow mengembalikan JSON yang tidak valid.",
            endpoint,
            reason="message_not_json",
        ) from error
    try:
        assessment = RiskAssessment.model_validate(candidate)
        return validate_assessment(assessment, transcript)
    except ValidationError as error:
        raise LangflowFailure(
            "invalid_response",
            "Respons Langflow tidak sesuai kontrak Rambu.",
            endpoint,
            reason="schema_validation",
        ) from error
    except ValueError as error:
        reasons = {
            "Low risk cannot contain signals or evidence.": "low_risk_has_findings",
            "Risky assessments require signals and evidence.": "risky_assessment_missing_findings",
            "Evidence must be an exact transcript substring.": "evidence_not_in_transcript",
            "Evidence signals must appear at the top level.": "evidence_signal_missing_from_summary",
        }
        raise LangflowFailure(
            "invalid_response",
            "Respons Langflow tidak sesuai kontrak Rambu.",
            endpoint,
            reason=reasons.get(str(error), "semantic_validation"),
        ) from error
