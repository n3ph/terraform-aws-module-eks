#------------------------------------------------------------------------------#
# Locals
#------------------------------------------------------------------------------#

locals {
  eks_cluster_name = replace(format("%s EKS", title(var.name)), " ", "-")
}

#------------------------------------------------------------------------------#
# IAM
#------------------------------------------------------------------------------#

data "aws_iam_policy_document" "eks_cluster" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "Service"

      identifiers = [
        "eks.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = replace(format("%s Cluster", local.eks_cluster_name), " ", "-")
  assume_role_policy = data.aws_iam_policy_document.eks_cluster.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_amazon_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_amazon_eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}

#------------------------------------------------------------------------------#
# EKS
#------------------------------------------------------------------------------#

resource "aws_eks_cluster" "eks_cluster" {
  name = local.eks_cluster_name

  enabled_cluster_log_types = var.settings.cluster.enabled_cluster_log_types
  role_arn                  = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = var.network.private_subnet_ids
    endpoint_private_access = var.settings.cluster.endpoint_private_access
    endpoint_public_access  = var.settings.cluster.endpoint_public_access
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_amazon_eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_cluster_amazon_eks_service_policy,
  ]

  tags = var.tags
}

resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_worker.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes",
        ]
      }
    ])
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

data "aws_eks_cluster_auth" "eks_cluster" {
  name = aws_eks_cluster.eks_cluster.id
}

#------------------------------------------------------------------------------#
# Kubernetes Provider
#------------------------------------------------------------------------------#

provider "kubernetes" {
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority.0.data)
  host                   = aws_eks_cluster.eks_cluster.endpoint
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.eks_cluster.token
}

#------------------------------------------------------------------------------#
# IAM / OIDC -> Service Accounts
#------------------------------------------------------------------------------#
# https://github.com/terraform-providers/terraform-provider-aws/issues/10104
#------------------------------------------------------------------------------#

data "aws_region" "current" {}

data "external" "thumbprint" {
  program = [format("%s/bin/get_thumbprint.sh", path.module), data.aws_region.current.name]
}

resource "aws_iam_openid_connect_provider" "eks_cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.external.thumbprint.result.thumbprint]
  url             = aws_eks_cluster.eks_cluster.identity.0.oidc.0.issuer
}

output "aws_iam_openid_connect_provider" {
  value = aws_iam_openid_connect_provider.eks_cluster
}

#------------------------------------------------------------------------------#
# Security Group
#------------------------------------------------------------------------------#

resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_security_group_rule" "allow_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}
