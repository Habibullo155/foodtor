FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
RUN useradd --create-home --uid 10001 appuser && mkdir -p /app/media && chown -R appuser /app
USER appuser

EXPOSE 8000
# Миграции при старте (идемпотентно), затем API. --proxy-headers: реальный IP клиента от Caddy → rate limit по нему
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*' --no-server-header --workers 2"]
