# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# NotesOps backend image: Django REST API served by gunicorn.
# Multi-stage: build wheels with a toolchain, then ship a slim non-root runtime.
# ---------------------------------------------------------------------------

# --- Stage 1: build dependencies into wheels --------------------------------
FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# psycopg2 build deps (postgres). gcc only needed at build time.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip wheel --wheel-dir /wheels -r requirements.txt

# --- Stage 2: slim runtime --------------------------------------------------
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=notesapp.settings

# libpq for psycopg2 at runtime; curl for the container healthcheck.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 curl \
    && rm -rf /var/lib/apt/lists/* \
    && addgroup --system app && adduser --system --ingroup app app

WORKDIR /app/backend

COPY --from=builder /wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels

COPY . /app/backend
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && python manage.py collectstatic --noinput \
    && chown -R app:app /app/backend

USER app
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://localhost:8000/livez || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gunicorn", "notesapp.wsgi", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "60", "--access-logfile", "-", "--error-logfile", "-"]
