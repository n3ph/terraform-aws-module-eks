#------------------------------------------------------------------------------#
# Globals
#------------------------------------------------------------------------------#

variable "name" {
  description = "Name of the Cluster"
  type        = string
}

variable "tags" {
  description = "List of tags to attach to resources"
  default     = []
}

#------------------------------------------------------------------------------#
# Network
#------------------------------------------------------------------------------#

variable "network" {
  description = "config map to describe network config"

  type = object({
    nlb_external       = bool
    nlb_internal       = bool
    private_subnet_ids = set(string)
    public_subnet_ids  = set(string)
    vpc_id             = string
    dns_zone           = string
  })
}

#------------------------------------------------------------------------------#
# Settings
#------------------------------------------------------------------------------#

variable "settings" {
  description = "config map to describe EKS cluster settings"

  default = {
    cluster = {
      enabled_cluster_log_types = [
        "api",
        "audit",
        "authenticator",
        "controllerManager",
        "scheduler"
      ]

      endpoint_private_access = true
      endpoint_public_access  = true
    }

    nodegroup = {
      instance_types       = ["t3.small"]
      asg_desired_capacity = 1
      asg_max_size         = 1
      asg_min_size         = 1
    }

    efs = {
      encrypted                       = true
      performance_mode                = ""
      lifecycle_transition_to_ia      = "AFTER_90_DAYS"
      provisioned_throughput_in_mibps = 100
      throughput_mode                 = "provisioned"
    }
  }

  type = object({
    cluster = object({
      enabled_cluster_log_types = list(string)
      endpoint_private_access   = bool
      endpoint_public_access    = bool
    })

    nodegroup = object({
      instance_types       = list(string)
      asg_desired_capacity = number
      asg_max_size         = number
      asg_min_size         = number
    })

    efs = object({
      encrypted                       = bool
      performance_mode                = string
      lifecycle_transition_to_ia      = string
      provisioned_throughput_in_mibps = number
      throughput_mode                 = string
    })
  })
}
