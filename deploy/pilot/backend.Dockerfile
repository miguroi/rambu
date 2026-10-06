FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_PROJECT_ENVIRONMENT=/opt/rambu-venv \
    PATH=/opt/rambu-venv/bin:$PATH

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates python3 python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 rambu

COPY --from=ghcr.io/astral-sh/uv:0.8.22 /uv /uvx /bin/

WORKDIR /app/backend
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY backend/rambu_api ./rambu_api
RUN uv sync --frozen --no-dev \
    && mkdir -p /app/backend/data /var/cache/rambu-models \
    && chown -R rambu:rambu /app/backend/data /var/cache/rambu-models

USER rambu
EXPOSE 8000

CMD ["uvicorn", "rambu_api.app:app", "--host", "0.0.0.0", "--port", "8000"]
