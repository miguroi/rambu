from dataclasses import dataclass
from typing import Mapping


class ConfigurationError(RuntimeError):
    pass


@dataclass(frozen=True)
class LangflowSettings:
    url: str
    flow_id: str
    api_key: str

    @classmethod
    def from_environment(cls, environment: Mapping[str, str]) -> "LangflowSettings":
        values: dict[str, str] = {}
        for name in ("LANGFLOW_URL", "LANGFLOW_FLOW_ID", "LANGFLOW_API_KEY"):
            value = environment.get(name, "").strip()
            if not value:
                raise ConfigurationError(f"{name} is required")
            values[name] = value
        return cls(
            url=values["LANGFLOW_URL"],
            flow_id=values["LANGFLOW_FLOW_ID"],
            api_key=values["LANGFLOW_API_KEY"],
        )
