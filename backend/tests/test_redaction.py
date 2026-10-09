from rambu_api.redaction import mask_sensitive_text


def test_masks_phone_account_and_otp_numbers() -> None:
    text = (
        "Hubungi 0812-3456-7890, transfer ke rekening 8800000001, "
        "lalu sebutkan OTP 482913."
    )

    masked = mask_sensitive_text(text)

    assert "0812" not in masked
    assert "8800000001" not in masked
    assert "482913" not in masked
    assert "[NOMOR_TELEPON]" in masked
    assert "[NOMOR_REKENING]" in masked
    assert "OTP [KODE]" in masked


def test_masks_punctuated_otp_and_spoken_account_number() -> None:
    text = (
        "Sebutkan kode OTP 482.913 sekarang. Transfer ke rekening "
        "delapan miliar delapan ratus juta satu untuk pengamanan."
    )

    masked = mask_sensitive_text(text)

    assert "482.913" not in masked
    assert "delapan miliar" not in masked
    assert "OTP [KODE]" in masked
    assert "rekening [NOMOR_REKENING]" in masked

    joined = mask_sensitive_text("Transfer kerekening delapan miliar delapan ratus juta satu.")
    assert "delapan miliar" not in joined
    assert "[NOMOR_REKENING]" in joined
