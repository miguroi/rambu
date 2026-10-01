import json
from collections.abc import Callable
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from pydantic import ValidationError

from .models import RiskAssessment


class LangflowResponseError(RuntimeError):
    pass


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
        except (HTTPError, URLError, TimeoutError, OSError) as error:
            raise LangflowResponseError(f"Langflow tidak tersedia: {error}") from error
        return _extract_assessment(response)

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


def _extract_assessment(value: Any) -> RiskAssessment:
    candidates: list[Any] = []

    def visit(item: Any) -> None:
        if isinstance(item, dict):
            if set(item) == {
                "risk_level",
                "indicators",
                "explanation",
                "recommended_action",
            }:
                candidates.append(item)
            for nested in item.values():
                visit(nested)
        elif isinstance(item, list):
            for nested in item:
                visit(nested)
        elif isinstance(item, str):
            try:
                parsed = json.loads(item)
            except json.JSONDecodeError:
                return
            visit(parsed)

    visit(value)
    for candidate in candidates:
        try:
            return RiskAssessment.model_validate(candidate)
        except ValidationError:
            continue
    raise LangflowResponseError("Respons Langflow tidak sesuai kontrak Rambu.")
