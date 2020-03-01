#------------------------------------------------------------------------------#
# Authorization / Authentication
#------------------------------------------------------------------------------#

resource "kubernetes_cluster_role" "efs_provisioner_runner" {
  metadata {
    name = "efs-provisioner-runner"
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumes"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "update"]
  }


  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "update", "patch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_cluster_role_binding" "efs_provisioner_runner" {
  metadata {
    name = "efs-provisioner-runner"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.efs_provisioner_runner.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.efs_provisioner.metadata[0].name
    namespace = "kube-system"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_cluster_role" "efs_provisioner_leader" {
  metadata {
    name = "efs-provisioner-leader"
  }

  rule {
    api_groups = [""]
    resources  = ["endpoints"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_cluster_role_binding" "efs_provisioner_leader" {
  metadata {
    name = "efs-provisioner-leader"

  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.efs_provisioner_leader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.efs_provisioner.metadata[0].name
    namespace = "kube-system"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_service_account" "efs_provisioner" {
  metadata {
    name      = "efs-provisioner"
    namespace = "kube-system"
  }

  automount_service_account_token = true

  depends_on = [aws_eks_cluster.eks_cluster]
}

#------------------------------------------------------------------------------#
# Storage
#------------------------------------------------------------------------------#

resource "aws_kms_key" "eks_cluster" {
  count = var.settings.efs.encrypted ? 1 : 0

  deletion_window_in_days = 10
  description             = format("Encryption Key for EFS of %s", local.eks_cluster_name)
}

resource "aws_efs_file_system" "eks_cluster" {
  creation_token                  = local.eks_cluster_name
  encrypted                       = lookup(var.settings.efs, "encrypted", false)
  kms_key_id                      = var.settings.efs.encrypted ? aws_kms_key.eks_cluster[0].arn : null
  performance_mode                = lookup(var.settings.efs, "performance_mode", null)
  provisioned_throughput_in_mibps = lookup(var.settings.efs, "provisioned_throughput_in_mibps", null)
  throughput_mode                 = lookup(var.settings.efs, "throughput_mode", null)

  dynamic "lifecycle_policy" {
    for_each = [for bool in [lookup(var.settings.efs, "lifecycle_transition_to_ia", null)] : {
      transition_to_ia = bool
    } if var.settings.efs.lifecycle_transition_to_ia != null]

    content {
      transition_to_ia = lifecycle_policy.value.transition_to_ia
    }
  }

  tags = var.tags
}

resource "aws_efs_mount_target" "eks_cluster" {
  for_each = var.network.private_subnet_ids

  file_system_id  = aws_efs_file_system.eks_cluster.id
  security_groups = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
  subnet_id       = each.value
}

resource "kubernetes_storage_class" "efs_provisioner" {
  metadata {
    name = "aws-efs"
  }

  storage_provisioner = "ACME/aws-efs"
}

resource "kubernetes_config_map" "aws_efs" {
  metadata {
    name      = "efs-provisioner"
    namespace = "kube-system"
  }

  data = {
    aws_region     = data.aws_region.current.name
    file_system_id = aws_efs_file_system.eks_cluster.id
    provisioner    = "ACME/aws-efs"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

#------------------------------------------------------------------------------#
# Service
#------------------------------------------------------------------------------#

resource "kubernetes_deployment" "efs_provisioner" {
  metadata {
    name      = "efs-provisioner"
    namespace = "kube-system"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "efs-provisioner"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "efs-provisioner"
        }
      }
      spec {
        automount_service_account_token = true

        container {
          image = "quay.io/external_storage/efs-provisioner"
          name  = "efs-provisioner"

          env {
            name = "FILE_SYSTEM_ID"

            value_from {

              config_map_key_ref {
                name = "efs-provisioner"
                key  = "file_system_id"
              }
            }
          }

          env {
            name = "AWS_REGION"

            value_from {

              config_map_key_ref {
                name = "efs-provisioner"
                key  = "aws_region"
              }
            }
          }

          env {
            name = "PROVISIONER_NAME"

            value_from {
              config_map_key_ref {
                name = "efs-provisioner"
                key  = "provisioner"
              }
            }
          }

          volume_mount {
            name       = "aws-efs"
            mount_path = "/persistentvolumes"
          }
        }

        service_account_name = kubernetes_service_account.efs_provisioner.metadata[0].name

        volume {
          name = "aws-efs"

          nfs {
            server = aws_efs_file_system.eks_cluster.dns_name
            path   = "/"
          }
        }
      }
    }
  }

  depends_on = [
    aws_eks_cluster.eks_cluster,
    aws_efs_mount_target.eks_cluster
  ]
}
