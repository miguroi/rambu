from rambu_api.transcription import FasterWhisperTranscriber

from .conftest import write_test_wav


def test_ignores_tiny_trailing_audio_chunk(tmp_path) -> None:
    path = write_test_wav(tmp_path / "tail.wav", seconds=0.2)

    assert FasterWhisperTranscriber("small").transcribe(path) == ""
