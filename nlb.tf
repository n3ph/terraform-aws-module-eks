#------------------------------------------------------------------------------#
# Locals
#------------------------------------------------------------------------------#

locals {
  nlb = toset([var.network.nlb_external ? "external" : null, var.network.nlb_internal ? "internal" : null])

  autoscaling_attachments = flatten([
    for subnet in var.network.private_subnet_ids : [
      for nlb in local.nlb : {
        name   = format("%s_%s", subnet, nlb)
        subnet = subnet
        nlb    = nlb
      }
    ]
  ])
}

#------------------------------------------------------------------------------#
# NLB
#------------------------------------------------------------------------------#

resource "aws_lb" "eks_cluster" {
  for_each = local.nlb

  name                             = format("%s-%s", local.eks_cluster_name, each.value)
  internal                         = each.value == "internal" ? true : false
  load_balancer_type               = "network"
  subnets                          = var.network.public_subnet_ids
  enable_cross_zone_load_balancing = true

  tags = var.tags
}

#------------------------------------------------------------------------------#
# Target Group
#------------------------------------------------------------------------------#

resource "aws_lb_target_group" "eks_worker_http" {
  for_each = local.nlb

  name        = format("%s-HTTP-%s", local.eks_cluster_name, each.value)
  port        = 80
  protocol    = "TCP"
  vpc_id      = var.network.vpc_id
  target_type = "instance"

  health_check {
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

resource "aws_autoscaling_attachment" "eks_worker_http" {
  for_each = toset(local.autoscaling_attachments[*].name)

  autoscaling_group_name = [for autoscaling_attachment in local.autoscaling_attachments :
    aws_eks_node_group.eks_worker[autoscaling_attachment.subnet].resources[0].autoscaling_groups[0].name
  if autoscaling_attachment.name == each.value][0]

  alb_target_group_arn = [for autoscaling_attachment in local.autoscaling_attachments :
    aws_lb_target_group.eks_worker_http[autoscaling_attachment.nlb].arn
  if autoscaling_attachment.name == each.value][0]
}

resource "aws_lb_target_group" "eks_worker_https" {
  for_each = local.nlb

  name        = format("%s-HTTPS-%s", local.eks_cluster_name, each.value)
  port        = 443
  protocol    = "TCP"
  vpc_id      = var.network.vpc_id
  target_type = "instance"

  health_check {
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

resource "aws_autoscaling_attachment" "eks_worker_https" {
  for_each = toset(local.autoscaling_attachments[*].name)

  autoscaling_group_name = [for autoscaling_attachment in local.autoscaling_attachments :
    aws_eks_node_group.eks_worker[autoscaling_attachment.subnet].resources[0].autoscaling_groups[0].name
  if autoscaling_attachment.name == each.value][0]

  alb_target_group_arn = [for autoscaling_attachment in local.autoscaling_attachments :
    aws_lb_target_group.eks_worker_https[autoscaling_attachment.nlb].arn
  if autoscaling_attachment.name == each.value][0]
}

#------------------------------------------------------------------------------#
# Listener
#------------------------------------------------------------------------------#

resource "aws_lb_listener" "eks_cluster_http" {
  for_each = local.nlb

  load_balancer_arn = aws_lb.eks_cluster[each.value].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_worker_http[each.value].arn
  }
}

resource "aws_lb_listener" "eks_cluster_https" {
  for_each = local.nlb

  load_balancer_arn = aws_lb.eks_cluster[each.value].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_worker_https[each.value].arn
  }
}
