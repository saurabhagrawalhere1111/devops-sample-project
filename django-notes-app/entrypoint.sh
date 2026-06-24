#!/bin/sh
# Run DB migrations on startup, then exec the main process (gunicorn).
# In K8s you'd typically move migrate into an initContainer / Job; for the
# demo, running it here is simplest and idempotent.
set -e

echo "[entrypoint] Applying database migrations..."
python manage.py migrate --noinput

echo "[entrypoint] Starting: $*"
exec "$@"
