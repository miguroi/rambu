import re


PHONE_PATTERN = re.compile(r"(?<!\d)(?:\+62|0)[\d -]{8,15}\d")
ACCOUNT_PATTERN = re.compile(r"(?<!\d)\d{9,18}(?!\d)")
OTP_PATTERN = re.compile(
    r"(?i)(\b(?:otp|kode)(?:\s+otp)?\s*[:=-]?\s*)\d[\d .-]{2,12}\d\b"
)
SPOKEN_ACCOUNT_PATTERN = re.compile(
    r"(?i)(\b(?:ke\s*)?rekening\s+)(?:(?:nol|satu|dua|tiga|empat|lima|enam|tujuh|delapan|"
    r"sembilan|sepuluh|sebelas|belas|puluh|ratus|ribu|juta|miliar)\s*){2,}"
)


def mask_sensitive_text(text: str) -> str:
    masked = PHONE_PATTERN.sub("[NOMOR_TELEPON]", text)
    masked = ACCOUNT_PATTERN.sub("[NOMOR_REKENING]", masked)
    masked = SPOKEN_ACCOUNT_PATTERN.sub(r"\1[NOMOR_REKENING] ", masked)
    return OTP_PATTERN.sub(r"\1[KODE]", masked)
