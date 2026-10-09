import os

import pytest

from rambu_api.langflow_client import LangflowClient
from rambu_api.models import validate_assessment


pytestmark = pytest.mark.live_langflow


def live_client() -> LangflowClient:
    if os.getenv("RAMBU_RUN_LIVE_LANGFLOW") != "1":
        pytest.skip("Set RAMBU_RUN_LIVE_LANGFLOW=1 to use the live Langflow service.")

    required = ("LANGFLOW_URL", "LANGFLOW_FLOW_ID", "LANGFLOW_API_KEY")
    missing = [name for name in required if not os.getenv(name, "").strip()]
    if missing:
        pytest.fail(f"Live Langflow configuration missing: {', '.join(missing)}")

    return LangflowClient(
        os.environ["LANGFLOW_URL"],
        os.environ["LANGFLOW_FLOW_ID"],
        os.environ["LANGFLOW_API_KEY"],
    )


@pytest.mark.parametrize(
    ("transcript", "expected"),
    [
        ("Halo Bu, arisan dimulai pukul empat sore.", "low"),
        ("Ibu harus segera memastikan data ini hari ini.", "needs_review"),
        ("Saya dari bank, berikan OTP [KODE] sekarang.", "high_risk"),
        (
            "Saya Richard dari Bank BMI. Ada pengeluaran dari rekening ibu. "
            "Akan ada neko day untuk dikirim di SMS. Lihat nih bu, dan bisa "
            "dikasih tau ke saya juga.",
            "high_risk",
        ),
    ],
)
def test_live_langflow_returns_expected_valid_assessment(transcript: str, expected: str) -> None:
    result = live_client().analyze(transcript, final=True)

    assert result.risk_level == expected
    assert validate_assessment(result, transcript) == result
