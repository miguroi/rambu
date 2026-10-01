import json

import pytest

from rambu_api.langflow_client import LangflowClient, LangflowResponseError


def test_parses_strict_assessment_from_langflow_response() -> None:
    assessment = {
        "risk_level": "high_risk",
        "indicators": ["Meminta OTP [KODE]"],
        "explanation": "Penelepon meminta kode rahasia.",
        "recommended_action": "Akhiri panggilan dan hubungi kanal resmi.",
    }
    transport_calls = []

    def transport(url, headers, payload):
        transport_calls.append((url, headers, payload))
        return {
            "outputs": [
                {"outputs": [{"results": {"message": {"text": json.dumps(assessment)}}}]}
            ]
        }

    client = LangflowClient(
        base_url="http://localhost:7861",
        flow_id="rambu",
        api_key="secret",
        transport=transport,
    )

    result = client.analyze("Tolong berikan OTP [KODE].", final=False)

    assert result.risk_level == "high_risk"
    assert result.indicators == ["Meminta OTP [KODE]"]
    assert transport_calls[0][0] == "http://localhost:7861/api/v1/run/rambu"
    assert transport_calls[0][1]["x-api-key"] == "secret"
    assert "Tolong berikan OTP [KODE]." in transport_calls[0][2]["input_value"]


def test_rejects_malformed_or_extra_model_fields() -> None:
    def transport(_url, _headers, _payload):
        return {
            "outputs": [
                {
                    "outputs": [
                        {
                            "results": {
                                "message": {
                                    "text": json.dumps(
                                        {
                                            "risk_level": "high_risk",
                                            "indicators": [],
                                            "explanation": "Tidak valid",
                                            "recommended_action": "Tutup telepon",
                                            "invented_caller": "Bank palsu",
                                        }
                                    )
                                }
                            }
                        }
                    ]
                }
            ]
        }

    client = LangflowClient("http://localhost:7861", "rambu", transport=transport)

    with pytest.raises(LangflowResponseError):
        client.analyze("contoh", final=True)
