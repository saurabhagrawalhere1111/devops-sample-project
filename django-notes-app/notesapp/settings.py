"""
Django settings for notesapp project.

Hardened, environment-driven configuration for the NotesOps DevOps platform.
Everything that differs between local / CI / staging / prod is read from the
environment so the same image runs everywhere (12-factor).
"""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent


def env_bool(name: str, default: bool = False) -> bool:
    return os.getenv(name, str(default)).lower() in ("1", "true", "yes", "on")


def env_list(name: str, default: str = "") -> list:
    raw = os.getenv(name, default)
    return [item.strip() for item in raw.split(",") if item.strip()]


# --- Core security -----------------------------------------------------------
# SECRET_KEY MUST come from the environment in every non-local context.
SECRET_KEY = os.getenv(
    "DJANGO_SECRET_KEY",
    "django-insecure-local-only-do-not-use-in-prod",
)

DEBUG = env_bool("DJANGO_DEBUG", default=False)

# e.g. "notes.example.com,localhost,127.0.0.1"
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")

# Behind the ALB/nginx we terminate TLS upstream and forward the scheme.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")

# Production hardening (no-ops when DEBUG=True / overridable via env)
SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", default=not DEBUG)
SESSION_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_SECURE = not DEBUG
SECURE_HSTS_SECONDS = int(os.getenv("DJANGO_HSTS_SECONDS", "0" if DEBUG else "31536000"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = not DEBUG
SECURE_HSTS_PRELOAD = not DEBUG
SECURE_CONTENT_TYPE_NOSNIFF = True

# --- Applications ------------------------------------------------------------
INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "api.apps.ApiConfig",
    "rest_framework",
    "corsheaders",
    "django_prometheus",  # exposes /metrics for Prometheus scraping
]

MIDDLEWARE = [
    # django-prometheus must wrap the stack: first in, last out.
    "django_prometheus.middleware.PrometheusBeforeMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "django_prometheus.middleware.PrometheusAfterMiddleware",
]

ROOT_URLCONF = "notesapp.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "mynotes/build"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework.authentication.TokenAuthentication",
    )
}

WSGI_APPLICATION = "notesapp.wsgi.application"

# --- Database ----------------------------------------------------------------
# DB_ENGINE: postgres (default) | mysql | sqlite
DB_ENGINE = os.getenv("DB_ENGINE", "postgres").lower()

_ENGINES = {
    "postgres": "django_prometheus.db.backends.postgresql",
    "mysql": "django_prometheus.db.backends.mysql",
    "sqlite": "django_prometheus.db.backends.sqlite3",
}

if DB_ENGINE == "sqlite":
    DATABASES = {
        "default": {
            "ENGINE": _ENGINES["sqlite"],
            "NAME": os.getenv("DB_NAME", str(BASE_DIR / "db.sqlite3")),
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": _ENGINES.get(DB_ENGINE, _ENGINES["postgres"]),
            "NAME": os.getenv("DB_NAME", "notesdb"),
            "USER": os.getenv("DB_USER", "notes"),
            "PASSWORD": os.getenv("DB_PASSWORD", ""),
            "HOST": os.getenv("DB_HOST", "localhost"),
            "PORT": os.getenv("DB_PORT", "5432" if DB_ENGINE == "postgres" else "3306"),
            "CONN_MAX_AGE": int(os.getenv("DB_CONN_MAX_AGE", "60")),
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# --- i18n --------------------------------------------------------------------
LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

# --- Static files (WhiteNoise) ----------------------------------------------
STATIC_URL = "static/"
# Only include the React build dir when it exists, so the backend-only image
# (which doesn't ship the frontend) can still run collectstatic for admin assets.
_frontend_static = os.path.join(BASE_DIR, "mynotes/build/static")
STATICFILES_DIRS = [_frontend_static] if os.path.isdir(_frontend_static) else []
STATIC_ROOT = os.path.join(BASE_DIR, "staticfiles")
STORAGES = {
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# --- CORS --------------------------------------------------------------------
# Lock this down in prod via DJANGO_CORS_ALLOWED_ORIGINS; default-open only locally.
CORS_ALLOWED_ORIGINS = env_list("DJANGO_CORS_ALLOWED_ORIGINS")
CORS_ORIGIN_ALLOW_ALL = env_bool("DJANGO_CORS_ALLOW_ALL", default=DEBUG)

# --- Logging (JSON-friendly to stdout for Loki/Promtail) --------------------
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {
            "format": "%(asctime)s %(levelname)s %(name)s %(message)s",
        },
    },
    "handlers": {
        "console": {"class": "logging.StreamHandler", "formatter": "verbose"},
    },
    "root": {"handlers": ["console"], "level": os.getenv("DJANGO_LOG_LEVEL", "INFO")},
}
