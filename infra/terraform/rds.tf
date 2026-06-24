# Generated DB password — never hardcoded, stored in Secrets Manager (secrets.tf).
resource "random_password" "db" {
  length  = 24
  special = false # keep it URL/connection-string safe
}

# Security group: allow Postgres only from inside the VPC (EKS nodes/pods).
resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds-"
  description = "Allow Postgres from within the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Postgres from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name}-postgres"
  engine         = "postgres"
  engine_version = "15"
  instance_class = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_allocated_storage * 2 # autoscaling cap
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = var.rds_multi_az
  publicly_accessible    = false

  backup_retention_period = 7
  deletion_protection     = false # set true for production
  skip_final_snapshot     = true  # demo convenience; false for production

  performance_insights_enabled = true
}
