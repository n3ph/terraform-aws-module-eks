
#------------------------------------------------------------------------------#
# DNS
#------------------------------------------------------------------------------#

data "aws_route53_zone" "ACME_cloud" {
  name = var.network.dns_zone
}

resource "aws_route53_record" "traefik_ACME_cloud_ipv4" {
  for_each = local.nlb

  zone_id = data.aws_route53_zone.ACME_cloud.id
  name    = each.value == "internal" ? "traefik-int" : "traefik"
  type    = "A"

  alias {
    name    = aws_lb.eks_cluster[each.value].dns_name
    zone_id = aws_lb.eks_cluster[each.value].zone_id

    evaluate_target_health = true
  }
}
