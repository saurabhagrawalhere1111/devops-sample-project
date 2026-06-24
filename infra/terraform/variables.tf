variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource names"
  type        = string
  default     = "notesops"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS control-plane version"
  type        = string
  default     = "1.30"
}

# --- Cost-conscious defaults (override for production-like) ------------------
variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT (SPOT is cheaper for a demo)"
  type        = string
  default     = "SPOT"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "rds_allocated_storage" {
  type    = number
  default = 20
}

variable "rds_multi_az" {
  description = "Multi-AZ RDS (true for production-like, false for cheap demo)"
  type        = bool
  default     = false
}

variable "db_name" {
  type    = string
  default = "notesdb"
}

variable "db_username" {
  type    = string
  default = "notes"
}
