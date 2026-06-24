# ---------------------------------------------------------------------------
# GitHub Actions OIDC -> AWS IAM role (keyless CI). No long-lived AWS keys.
# Set the github_repo variable to "owner/repo" so only that repo can assume it.
# ---------------------------------------------------------------------------
variable "github_repo" {
  description = "GitHub repo allowed to assume the CI role, as owner/repo"
  type        = string
  default     = "saurabhagrawalhere1111/devops-sample-project"
}

data "aws_iam_openid_connect_provider" "github" {
  # If this provider doesn't exist yet, comment this data source and uncomment
  # the resource block below to create it.
  url = "https://token.actions.githubusercontent.com"
}

# resource "aws_iam_openid_connect_provider" "github" {
#   url             = "https://token.actions.githubusercontent.com"
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
# }

data "aws_iam_policy_document" "ci_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${local.name}-github-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_assume.json
}

# Push images to ECR.
data "aws_iam_policy_document" "ci_ecr" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [for r in aws_ecr_repository.this : r.arn]
  }
}

resource "aws_iam_role_policy" "ci_ecr" {
  name   = "ecr-push"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_ecr.json
}

output "github_ci_role_arn" {
  value = aws_iam_role.ci.arn
}
