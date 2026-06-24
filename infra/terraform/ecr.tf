locals {
  ecr_repos = ["notes-backend", "notes-frontend"]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.ecr_repos)

  name                 = "${var.project}/${each.value}"
  image_tag_mutability = "IMMUTABLE" # supply-chain: tags can't be silently overwritten

  image_scanning_configuration {
    scan_on_push = true # native ECR scanning in addition to Trivy in CI
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Expire untagged images after 14 days to control storage cost.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images older than 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}

output "ecr_repository_urls" {
  value = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}
