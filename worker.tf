#------------------------------------------------------------------------------#
# Locals
#------------------------------------------------------------------------------#

locals {
  eks_worker_name = replace(format("%s EKS", title(var.name)), " ", "-")
}

#------------------------------------------------------------------------------#
# IAM
#------------------------------------------------------------------------------#

data "aws_iam_policy_document" "eks_worker" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "Service"

      identifiers = [
        "ec2.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role" "eks_worker" {
  name               = replace(format("%s Worker", local.eks_worker_name), " ", "-")
  assume_role_policy = data.aws_iam_policy_document.eks_worker.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_worker.name
}

resource "aws_iam_role_policy_attachment" "eks_worker_Amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_worker.name
}

resource "aws_iam_role_policy_attachment" "eks_worker_amazon_ec2_container_registry_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_worker.name
}

resource "aws_iam_instance_profile" "eks_worker" {
  name = "eks_worker"
  role = aws_iam_role.eks_worker.name
}

#------------------------------------------------------------------------------#
# EKS
#------------------------------------------------------------------------------#

resource "aws_eks_node_group" "eks_worker" {
  for_each = var.network.private_subnet_ids

  cluster_name    = aws_eks_cluster.eks_cluster.name
  instance_types  = var.settings.nodegroup["instance_types"]
  node_group_name = format("%s-%s", local.eks_worker_name, each.value)
  node_role_arn   = aws_iam_role.eks_worker.arn
  subnet_ids      = toset([each.value])

  scaling_config {
    desired_size = lookup(var.settings.nodegroup, "asg_desired_capacity", 1)
    max_size     = lookup(var.settings.nodegroup, "asg_max_size", 1)
    min_size     = lookup(var.settings.nodegroup, "asg_min_size", 1)
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_worker_Amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.eks_worker_amazon_ec2_container_registry_readonly,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

locals {
  eks_worker_version = split("-", aws_eks_node_group.eks_worker[tolist(var.network.private_subnet_ids)[0]].release_version)[0]
}
