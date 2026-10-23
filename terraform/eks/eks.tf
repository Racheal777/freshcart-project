module "eks" {
    source          = "terraform-aws-modules/eks/aws"
    version         = "~> 20.0"

    cluster_name = "freshcart-eks-cluster"
    cluster_version = "1.36"

    cluster_endpoint_public_access = true
    enable_cluster_creator_admin_permissions = true

    access_entries = {
      github_actions = {
        principal_arn = "arn:aws:iam::055505191746:role/github-actions-ecr-push"

        policy_associations = {
          deploy = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            access_scope = {
              type       = "namespace"
              namespaces = ["freshcart"]
            }
          }
        }
      }
    }

    vpc_id = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnets

    eks_managed_node_groups = {
        default = {
            
            ami_type       = "AL2023_x86_64_STANDARD"
            instance_types = ["t3.medium"]
            min_size       = 2
            max_size       = 4
            desired_size   = 3

           

            tags = {
                Name        = "freshcart-eks-node"
                Environment = "dev"
                project     = "freshcart"
            }
        }
    }

  
}