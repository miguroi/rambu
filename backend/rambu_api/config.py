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


@dataclass(frozen=True)
class WhisperSettings:
    model_name: str
    device: str
    compute_type: str
    device_index: int

    @classmethod
    def from_environment(cls, environment: Mapping[str, str]) -> "WhisperSettings":
        model_name = environment.get("RAMBU_WHISPER_MODEL", "small").strip() or "small"
        device = environment.get("RAMBU_WHISPER_DEVICE", "cpu").strip().lower()
        if device not in {"cpu", "cuda"}:
            raise ConfigurationError("RAMBU_WHISPER_DEVICE must be cpu or cuda")

        compute_type = environment.get("RAMBU_WHISPER_COMPUTE_TYPE", "int8").strip()
        if not compute_type:
            raise ConfigurationError("RAMBU_WHISPER_COMPUTE_TYPE is required")

        raw_device_index = environment.get("RAMBU_WHISPER_DEVICE_INDEX", "0").strip()
        try:
            device_index = int(raw_device_index)
        except ValueError as error:
            raise ConfigurationError("RAMBU_WHISPER_DEVICE_INDEX must be an integer") from error
        if device_index < 0:
            raise ConfigurationError("RAMBU_WHISPER_DEVICE_INDEX must be zero or greater")

        return cls(
            model_name=model_name,
            device=device,
            compute_type=compute_type,
            device_index=device_index,
        )
