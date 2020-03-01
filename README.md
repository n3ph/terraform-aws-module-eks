# README #

The setup was guided by [HashiCorp Terraform EKS tutorial](https://learn.hashicorp.com/terraform/aws/eks-intro) and the [official AWS docs](https://docs.aws.amazon.com/de_de/eks/latest/userguide/getting-started.html).

## Requirements ##
You need to install at least these tools:
* kubectl
* aws-iam-authenticator

## Bootstrap ##

If you plan to create a new EKS Cluster you need to do some extra tasks as EKS does not work fully automated.
To be able to add Worker nodes you need to apply a configmap after Cluster creation, otherwise the workernodes are not able to join master.

1. Run `````terraform apply`````
2. Configure your kubectl ````aws eks --region eu-central-1 update-kubeconfig --name <EKS-name> --profile <target profile (where cluster lives)>````
3. You can watch the nodes joining your cluster ```kubectl get nodes --watch```
4. Be happy :)

# Docs #

https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md

