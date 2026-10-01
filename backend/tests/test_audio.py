import io
import wave

from rambu_api.audio import split_wav, validate_wav_bytes

from .conftest import wav_bytes, write_test_wav


def test_split_wav_returns_valid_five_second_chunks(tmp_path) -> None:
    source = write_test_wav(tmp_path / "call.wav", seconds=11)

    chunks = list(split_wav(source, chunk_seconds=5))

    assert len(chunks) == 3
    durations = []
    for chunk in chunks:
        with wave.open(io.BytesIO(chunk), "rb") as audio:
            assert audio.getnchannels() == 1
            assert audio.getsampwidth() == 2
            assert audio.getframerate() == 16_000
            durations.append(audio.getnframes() / audio.getframerate())
    assert durations == [5.0, 5.0, 1.0]


def test_live_chunk_validation_rejects_wrong_format_and_long_audio() -> None:
    assert validate_wav_bytes(wav_bytes(seconds=5)) == 5

    try:
        validate_wav_bytes(wav_bytes(seconds=7))
    except ValueError as error:
        assert "terlalu panjang" in str(error)
    else:
        raise AssertionError("long chunk was accepted")

    try:
        validate_wav_bytes(wav_bytes(sample_rate=8_000))
    except ValueError as error:
        assert "16 kHz" in str(error)
    else:
        raise AssertionError("wrong sample rate was accepted")
