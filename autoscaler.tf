#------------------------------------------------------------------------------#
# IAM
#------------------------------------------------------------------------------#

data "aws_iam_policy_document" "cluster_autoscaler_assume_policy" {
  statement {
    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks_cluster.id]
    }

    condition {
      test     = "StringEquals"
      variable = format("%s:sub", aws_iam_openid_connect_provider.eks_cluster.url)
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "ClusterAutoscalerServiceAccountRole"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_policy.json

  tags = var.tags
}

data "aws_iam_policy_document" "cluster_autoscaler_policy" {
  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "cluster_autoscaler_lets_encrypt_acme" {
  name        = "ClusterAutoscalerPolicy"
  description = "Autoscaling permissions for EKS"
  policy      = data.aws_iam_policy_document.cluster_autoscaler_policy.json
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  policy_arn = aws_iam_policy.cluster_autoscaler_lets_encrypt_acme.arn
  role       = aws_iam_role.cluster_autoscaler.name
}

#------------------------------------------------------------------------------#
# Authorization / Authentication
#------------------------------------------------------------------------------#

resource "kubernetes_cluster_role" "cluster_autoscaler" {
  metadata {
    name = "cluster-autoscaler"

    labels = {
      k8s-addon = "cluster-autoscaler.addons.k8s.io"
      k8s-app   = "cluster-autoscaler"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["events", "endpoints"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/eviction"]
    verbs      = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/status"]
    verbs      = ["update"]
  }

  rule {
    api_groups     = [""]
    resource_names = ["cluster-autoscaler"]
    resources      = ["endpoints"]
    verbs          = ["get", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["watch", "list", "get", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "replicationcontrollers", "persistentvolumeclaims", "persistentvolumes"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["replicasets", "daemonsets"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["watch", "list"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets", "replicasets", "daemonsets"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses", "csinodes"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["batch", "extensions"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch", "patch"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["create"]
  }

  rule {
    api_groups     = ["coordination.k8s.io"]
    resource_names = ["cluster-autoscaler"]
    resources      = ["leases"]
    verbs          = ["get", "update"]
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_cluster_role_binding" "cluster_autoscaler" {
  metadata {
    name = "cluster-autoscaler"

    labels = {
      k8s-addon = "cluster-autoscaler.addons.k8s.io"
      k8s-app   = "cluster-autoscaler"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cluster_autoscaler.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.cluster_autoscaler.metadata[0].name
    namespace = "kube-system"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_role" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"

    labels = {
      k8s-addon = "cluster-autoscaler.addons.k8s.io"
      k8s-app   = "cluster-autoscaler"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["create", "list", "watch"]
  }

  rule {
    api_groups     = [""]
    resource_names = ["cluster-autoscaler-status", "cluster-autoscaler-priority-expander"]
    resources      = ["configmaps"]
    verbs          = ["delete", "get", "update", "watch"]
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_role_binding" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"

    labels = {
      k8s-addon = "cluster-autoscaler.addons.k8s.io"
      k8s-app   = "cluster-autoscaler"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.cluster_autoscaler.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.cluster_autoscaler.metadata[0].name
    namespace = "kube-system"
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}

resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"

    labels = {
      k8s-addon = "cluster-autoscaler.addons.k8s.io"
      k8s-app   = "cluster-autoscaler"
    }

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }
  }

  automount_service_account_token = true

  depends_on = [aws_eks_cluster.eks_cluster]
}

#------------------------------------------------------------------------------#
# Service
#------------------------------------------------------------------------------#

resource "kubernetes_deployment" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"

    labels = {
      k8s-app = "cluster-autoscaler"
    }

    annotations = {
      "cluster-autoscaler.kubernetes.io/safe-to-evict" = false
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        k8s-app = "cluster-autoscaler"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app = "cluster-autoscaler"
        }

        # annotations = {
        #   "prometheus.io/scrape" = true
        #   "prometheus.io/port"   = 8085
        # }
      }

      spec {
        automount_service_account_token  = true
        service_account_name             = kubernetes_service_account.cluster_autoscaler.metadata[0].name
        termination_grace_period_seconds = 60

        container {
          command = [
            "./cluster-autoscaler",
            "--v=3",
            "--stderrthreshold=info",
            "--cloud-provider=aws",
            "--skip-nodes-with-local-storage=false",
            "--expander=least-waste",
            "--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${local.eks_cluster_name}",
            "--balance-similar-node-groups",
            "--skip-nodes-with-system-pods=false",

          ]

          image             = "k8s.gcr.io/cluster-autoscaler:v${local.eks_worker_version}"
          image_pull_policy = "IfNotPresent"
          name              = "cluster-autoscaler"

          resources {
            limits {
              cpu    = "100m"
              memory = "512Mi"
            }
            requests {
              cpu    = "100m"
              memory = "512Mi"
            }
          }

          volume_mount {
            mount_path = "/etc/ssl/certs/ca-certificates.crt"
            name       = "ssl-certs"
            read_only  = true
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
          name = "ssl-certs"

          host_path {
            path = "/etc/ssl/certs/ca-bundle.crt"
          }
        }
      }
    }
  }

  depends_on = [aws_eks_cluster.eks_cluster]
}
