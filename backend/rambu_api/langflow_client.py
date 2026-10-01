import json
from collections.abc import Callable
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from pydantic import ValidationError

from .models import RiskAssessment, validate_assessment


class LangflowFailure(RuntimeError):
    def __init__(
        self,
        code: str,
        safe_message: str,
        endpoint: str,
        http_status: int | None = None,
    ) -> None:
        super().__init__(safe_message)
        self.code = code
        self.safe_message = safe_message
        self.endpoint = endpoint
        self.http_status = http_status


Transport = Callable[[str, dict[str, str], dict[str, Any]], dict[str, Any]]


class LangflowClient:
    def __init__(
        self,
        base_url: str,
        flow_id: str,
        api_key: str | None = None,
        transport: Transport | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.flow_id = flow_id
        self.api_key = api_key
        self.transport = transport or self._http_transport

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        headers = {"Content-Type": "application/json"}
        if self.api_key:
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
        ) from error
    if not isinstance(text, str):
        raise LangflowFailure(
            "invalid_response",
            "Respons Langflow tidak sesuai kontrak Rambu.",
            endpoint,
        )
    try:
        candidate = json.loads(text)
    except json.JSONDecodeError as error:
        raise LangflowFailure(
            "invalid_json",
            "Langflow mengembalikan JSON yang tidak valid.",
            endpoint,
        ) from error
    try:
        assessment = RiskAssessment.model_validate(candidate)
        return validate_assessment(assessment, transcript)
    except (ValidationError, ValueError) as error:
        raise LangflowFailure(
            "invalid_response",
            "Respons Langflow tidak sesuai kontrak Rambu.",
            endpoint,
        ) from error
