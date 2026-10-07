# syntax=docker/dockerfile:1
FROM python:3.12-slim-bookworm

# uv をコピー(公式配布イメージからバイナリだけ取得)
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# 依存だけ先に解決してレイヤキャッシュを効かせる
# (Cloud Build の既定のビルド方式は BuildKit ではないため、RUN --mount=type=cache は使わない。spec 035)
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

COPY . .
RUN uv sync --frozen

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
