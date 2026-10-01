import importlib

import pytest


def config_module():
    return importlib.import_module("rambu_api.config")


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("LANGFLOW_URL", None),
        ("LANGFLOW_URL", "   "),
        ("LANGFLOW_FLOW_ID", None),
        ("LANGFLOW_FLOW_ID", "\t"),
        ("LANGFLOW_API_KEY", None),
        ("LANGFLOW_API_KEY", "\n"),
    ],
)
def test_langflow_configuration_rejects_each_missing_or_blank_value(name, value) -> None:
    module = config_module()
    environment = {
        "LANGFLOW_URL": "http://localhost:7861",
        "LANGFLOW_FLOW_ID": "rambu",
        "LANGFLOW_API_KEY": "secret",
    }
    if value is None:
        environment.pop(name)
    else:
        environment[name] = value

    with pytest.raises(module.ConfigurationError, match=f"^{name} is required$"):
        module.LangflowSettings.from_environment(environment)


def test_langflow_configuration_trims_and_preserves_complete_values() -> None:
    module = config_module()

    result = module.LangflowSettings.from_environment(
        {
            "LANGFLOW_URL": "  https://langflow.example  ",
            "LANGFLOW_FLOW_ID": " rambu-production ",
            "LANGFLOW_API_KEY": " key-value ",
        }
    )

    assert result.url == "https://langflow.example"
    assert result.flow_id == "rambu-production"
    assert result.api_key == "key-value"
