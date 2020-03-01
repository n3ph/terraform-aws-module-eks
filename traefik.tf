# #------------------------------------------------------------------------------#
# # IAM
# #------------------------------------------------------------------------------#

# data "aws_iam_policy_document" "traefik_ingress_controller_assume_policy" {
#   statement {
#     actions = [
#       "sts:AssumeRoleWithWebIdentity",
#     ]

#     principals {
#       type        = "Federated"
#       identifiers = [aws_iam_openid_connect_provider.eks_cluster.id]
#     }

#     condition {
#       test     = "StringEquals"
#       variable = format("%s:sub", aws_iam_openid_connect_provider.eks_cluster.url)
#       values   = ["system:serviceaccount:kube-system:traefik-ingress-controller"]
#     }
#   }
# }

# resource "aws_iam_role" "traefik_ingress_controller" {
#   name               = "TraefikIngressControllerServiceAccountRole"
#   assume_role_policy = data.aws_iam_policy_document.traefik_ingress_controller_assume_policy.json

#   tags = var.tags
# }

# data "aws_iam_policy_document" "traefik_ingress_controller_policy" {
#   statement {
#     actions = [
#       "route53:GetChange",
#       "route53:ChangeResourceRecordSets",
#       "route53:ListResourceRecordSets",
#     ]

#     resources = [
#       "arn:aws:route53:::hostedzone/*",
#       "arn:aws:route53:::change/*",
#     ]
#   }

#   statement {
#     actions   = ["route53:ListHostedZonesByName"]
#     resources = ["*"]
#   }
# }

# resource "aws_iam_policy" "traefik_ingress_controller_lets_encrypt_acme" {
#   name        = "TraefikIngressControllerLetsEncryptACMEPolicy"
#   description = "Let's Encrypt ACME challenge permissions in Route53"
#   policy      = data.aws_iam_policy_document.traefik_ingress_controller_policy.json
# }

# resource "aws_iam_role_policy_attachment" "traefik_ingress_controller" {
#   policy_arn = aws_iam_policy.traefik_ingress_controller_lets_encrypt_acme.arn
#   role       = aws_iam_role.traefik_ingress_controller.name
# }

#------------------------------------------------------------------------------#
# Authorization / Authentication
#------------------------------------------------------------------------------#

resource "kubernetes_cluster_role" "traefik_ingress_controller" {
  metadata {
    name = "traefik-ingress-controller"

    labels = {
      k8s-app = "traefik-ingress-controller"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "secrets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses/status"]
    verbs      = ["update"]
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_cluster_role_binding" "traefik_ingress_controller" {
  metadata {
    name = "traefik-ingress-controller"

    labels = {
      k8s-app = "traefik-ingress-controller"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.traefik_ingress_controller.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "traefik-ingress-controller"
    namespace = "kube-system"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_service_account" "traefik_ingress_controller" {
  metadata {
    name      = "traefik-ingress-controller"
    namespace = "kube-system"

    labels = {
      k8s-app = "traefik-ingress-controller"
    }

    # annotations = {
    #   "eks.amazonaws.com/role-arn" = aws_iam_role.traefik_ingress_controller.arn
    # }
  }

  automount_service_account_token = true

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "random_password" "traefik_ingress_controller_basic_auth" {
  length           = 24
  upper            = true
  lower            = true
  number           = true
  override_special = "_%@"

  keepers = {
    renew = true
  }
}

resource "vault_generic_secret" "traefik_ingress_controller_basic_auth" {
  path = "devops/data/team/eks/traefik/web-ui/basic-auth"
  data_json = jsonencode({
    "user"     = "admin"
    "password" = random_password.traefik_ingress_controller_basic_auth.result
  })
}

resource "kubernetes_secret" "traefik_ingress_controller_basic_auth" {
  metadata {
    name      = "traefik-ingress-controller-basic-auth"
    namespace = "kube-system"

    labels = {
      k8s-app = "traefik-ingress-controller"
    }
  }

  data = {
    data = format("%s:%s", "admin", bcrypt(random_password.traefik_ingress_controller_basic_auth.result, 6))
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

#------------------------------------------------------------------------------#
# Storage
#------------------------------------------------------------------------------#

resource "kubernetes_persistent_volume_claim" "traefik_ingress_controller" {
  metadata {
    name      = "traefik-ingress-controller"
    namespace = "kube-system"

    labels = {
      k8s-app = "traefik-ingress-controller"
    }
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "aws-efs"

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }

  depends_on = [
    aws_eks_cluster.eks_cluster,
    kubernetes_deployment.efs_provisioner
  ]
}

#------------------------------------------------------------------------------#
# Service
#------------------------------------------------------------------------------#

resource "kubernetes_daemonset" "traefik_ingress_controller" {
  metadata {
    name      = "traefik-ingress-controller"
    namespace = "kube-system"

    labels = {
      k8s-app = "traefik-ingress-controller"
    }
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "traefik-ingress-controller"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app = "traefik-ingress-controller"
          name    = "traefik-ingress-controller"
        }
      }

      spec {
        automount_service_account_token  = true
        service_account_name             = kubernetes_service_account.traefik_ingress_controller.metadata[0].name
        termination_grace_period_seconds = 60

        container {
          args = [
            "--acme",
            "--acme.acmelogging=true",
            # "--acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory",
            "--acme.caServer=https://acme-v02.api.letsencrypt.org/directory",
            # "--acme.dnschallenge=true",
            # "--acme.dnschallenge.delaybeforecheck=0",
            # "--acme.dnschallenge.provider=route53",
            # "--acme.domains=traefik.${var.network.dns_zone},traefik-int.${var.network.dns_zone}",
            "--acme.httpchallenge=true",
            "--acme.httpChallenge.entryPoint=http",
            "--acme.email=devops+aws-test-dev-eks-traefik@ACME.de",
            "--acme.entrypoint=https",
            "--acme.keytype=EC384",
            "--acme.onhostrule=true",
            "--acme.storage=/var/traefik/acme.json",
            "--api",
            "--defaultentrypoints=http,https",
            "--entrypoints=Name:http Address::80 Redirect.EntryPoint:https",
            "--entrypoints=Name:https Address::443 Compress:true TLS",
            "--kubernetes",
            # "--logLevel=DEBUG",
            "--ping",
          ]

          image             = "traefik:v1.7"
          image_pull_policy = "IfNotPresent"
          name              = "traefik-ingress-lb"

          port {
            name           = "http"
            container_port = 80
            host_port      = 80
          }

          port {
            name           = "https"
            container_port = 443
            host_port      = 443
          }

          port {
            name           = "admin"
            container_port = 8080
            host_port      = 8080
          }

          security_context {
            capabilities {
              add  = ["NET_BIND_SERVICE"]
              drop = ["ALL"]
            }
          }

          volume_mount {
            mount_path = "/var/traefik"
            name       = "traefik-dir"
          }
        }

        dns_config {
          nameservers = ["172.20.0.10"]

          searches = [
            "kube-system.svc.cluster.local",
            "svc.cluster.local",
            "cluster.local",
          ]
        }

        dns_policy = "None"

        volume {
          name = "traefik-dir"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.traefik_ingress_controller.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_service" "traefik_ingress_controller" {
  metadata {
    name      = "traefik-ingress-service"
    namespace = "kube-system"

    labels = {
      k8s-app = "traefik-ingress-controller"
    }
  }

  spec {
    selector = {
      k8s-app = "traefik-ingress-controller"
    }

    port {
      name     = "http"
      port     = 80
      protocol = "TCP"
    }

    port {
      name     = "https"
      port     = 443
      protocol = "TCP"
    }

    port {
      name     = "admin"
      port     = 8080
      protocol = "TCP"
    }

    type = "NodePort"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

#------------------------------------------------------------------------------#
# Admin Interface
#------------------------------------------------------------------------------#

resource "kubernetes_service" "traefik_web_ui" {
  metadata {
    name      = "traefik-web-ui"
    namespace = "kube-system"

    labels = {
      k8s-app = "traefik-ingress-controller"
    }
  }

  spec {
    selector = {
      k8s-app = "traefik-ingress-controller"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    type = "NodePort"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_ingress" "traefik_web_ui" {
  metadata {
    name      = "traefik-web-ui"
    namespace = "kube-system"

    labels = {
      k8s-app = "traefik-ingress-controller"
    }

    annotations = {
      "kubernetes.io/ingress.class"               = "traefik"
      "traefik.ingress.kubernetes.io/auth-type"   = "basic"
      "traefik.ingress.kubernetes.io/auth-secret" = "traefik-ingress-controller-basic-auth"
    }
  }

  spec {
    rule {
      host = format("traefik.%s", replace(data.aws_route53_zone.ACME_cloud.name, "/.$/", ""))
      http {
        path {
          path = "/"

          backend {
            service_name = "traefik-web-ui"
            service_port = 80
          }
        }
      }
    }
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}
