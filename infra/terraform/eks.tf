module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = "${local.name}-eks"
  cluster_version = var.kubernetes_version

  # Public endpoint so you can reach it from your laptop for the demo.
  # For production, set this false and use a bastion / VPN.
  cluster_endpoint_public_access = true

  # Give the Terraform caller cluster-admin via EKS access entries (no aws-auth editing).
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Core add-ons managed by EKS.
  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      # Needed by Cluster Autoscaler / Karpenter discovery (Phase 5).
      labels = {
        role = "general"
      }
    }
  }

  tags = {
    "karpenter.sh/discovery" = "${local.name}-eks"
  }
}

# OIDC provider URL for IRSA-based service accounts (used by add-ons in Phase 5/8).
output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}
