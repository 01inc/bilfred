FROM ghcr.io/astral-sh/uv:0.9.13 AS uv
FROM python:3.12-slim
COPY --from=uv /uv /uvx /bin/
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY bilfred ./bilfred
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1
ENV BILFRED_ROOT=/app
RUN useradd --uid 10001 --create-home bilfred
USER bilfred
CMD ["uvicorn", "bilfred.app:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
