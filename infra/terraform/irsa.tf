# ---------------------------------------------------------------------------
# IRSA roles for cluster add-ons (keyless pod -> AWS access via OIDC).
# Used by Phase 5 (ALB controller, External Secrets) and Phase 9 (Bedrock).
# ---------------------------------------------------------------------------

# AWS Load Balancer Controller
module "alb_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name                              = "${local.name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# External Secrets Operator: read the app secret from Secrets Manager.
data "aws_iam_policy_document" "external_secrets" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["${aws_secretsmanager_secret.app.arn}*"]
  }
}

resource "aws_iam_policy" "external_secrets" {
  name   = "${local.name}-external-secrets"
  policy = data.aws_iam_policy_document.external_secrets.json
}

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${local.name}-external-secrets"
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = module.external_secrets_irsa.iam_role_name
  policy_arn = aws_iam_policy.external_secrets.arn
}

# Bedrock invoke for the AI triage agent (Phase 9).
data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    actions   = ["bedrock:InvokeModel"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bedrock_invoke" {
  name   = "${local.name}-bedrock-invoke"
  policy = data.aws_iam_policy_document.bedrock_invoke.json
}

module "ai_agent_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${local.name}-ai-agent"
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["aiops:ai-agent"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ai_agent_bedrock" {
  role       = module.ai_agent_irsa.iam_role_name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

output "alb_controller_role_arn" {
  value = module.alb_irsa.iam_role_arn
}
output "external_secrets_role_arn" {
  value = module.external_secrets_irsa.iam_role_arn
}
output "ai_agent_role_arn" {
  value = module.ai_agent_irsa.iam_role_arn
}
