from pathlib import Path

import pytest

from rambu_api.demo import DemoService
from rambu_api.transcription import FasterWhisperTranscriber


class RecordingModel:
    def transcribe(self, path: str, **kwargs):
        return iter(()), None


class RecordingFactory:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, object]]] = []

    def __call__(self, model_name: str, **kwargs):
        self.calls.append((model_name, kwargs))
        return RecordingModel()


def test_probe_initializes_the_configured_model_exactly_once() -> None:
    factory = RecordingFactory()
    transcriber = FasterWhisperTranscriber(
        "small",
        device="cuda",
        compute_type="float16",
        device_index=0,
        model_factory=factory,
    )

    transcriber.probe()
    transcriber.probe()

    assert factory.calls == [
        (
            "small",
            {"device": "cuda", "compute_type": "float16", "device_index": 0},
        )
    ]


def test_probe_propagates_model_initialization_failure() -> None:
    failure = RuntimeError("CUDA runtime unavailable")

    def failing_factory(*_args, **_kwargs):
        raise failure

    transcriber = FasterWhisperTranscriber(model_factory=failing_factory)

    with pytest.raises(RuntimeError) as captured:
        transcriber.probe()

    assert captured.value is failure


def test_transcribe_reuses_the_model_initialized_by_probe(tmp_path: Path) -> None:
    factory = RecordingFactory()
    transcriber = FasterWhisperTranscriber(model_factory=factory)
    audio = tmp_path / "sample.mp3"
    audio.write_bytes(b"not-decoded-by-the-fake")

    transcriber.probe()
    assert transcriber.transcribe(audio) == ""

    assert len(factory.calls) == 1


def test_demo_service_probe_checks_transcriber_before_analyzer() -> None:
    calls: list[str] = []

    class ProbedTranscriber:
        def probe(self) -> None:
            calls.append("transcriber")

        def transcribe(self, _path: Path) -> str:
            return ""

    class ProbedAnalyzer:
        def probe(self) -> None:
            calls.append("analyzer")

    service = DemoService({}, ProbedTranscriber(), ProbedAnalyzer(), delay_seconds=0)

    service.probe()

    assert calls == ["transcriber", "analyzer"]
