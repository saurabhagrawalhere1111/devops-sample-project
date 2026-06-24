# Django app secrets in AWS Secrets Manager.
# External Secrets Operator (Phase 5) syncs this into a Kubernetes Secret,
# so the app never sees raw AWS credentials and we never commit secrets.

resource "random_password" "django_secret_key" {
  length  = 50
  special = true
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${local.name}/app"
  description             = "NotesApp runtime secrets (DB + Django)"
  recovery_window_in_days = 0 # demo: allow immediate re-create
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    DJANGO_SECRET_KEY = random_password.django_secret_key.result
    DB_ENGINE         = "postgres"
    DB_NAME           = var.db_name
    DB_USER           = var.db_username
    DB_PASSWORD       = random_password.db.result
    DB_HOST           = aws_db_instance.this.address
    DB_PORT           = "5432"
  })
}

output "app_secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "app_secret_name" {
  value = aws_secretsmanager_secret.app.name
}
