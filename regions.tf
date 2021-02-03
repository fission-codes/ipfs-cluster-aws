#
# Instantiate per-region cloud resources.
#
# Terraform can not use providers dynamically, so there is a lot of duplication here.

#
# Local variables
#

locals {
  all_regions = [
    "us-east-2",
    "us-east-1",
    "us-west-1",
    "us-west-2",
    "af-south-1",
    "ap-east-1",
    "ap-south-1",
    "ap-northeast-3",
    "ap-northeast-2",
    "ap-southeast-1",
    "ap-southeast-2",
    "ap-northeast-1",
    "ca-central-1",
    "cn-north-1",
    "cn-northwest-1",
    "eu-central-1",
    "eu-west-1",
    "eu-west-2",
    "eu-south-1",
    "eu-west-3",
    "eu-north-1",
    "me-south-1",
    "sa-east-1",
  ]

  node_ips = concat(
    module.ipfs-cluster-aws-region-us-east-1.node_ips,
    module.ipfs-cluster-aws-region-eu-north-1.node_ips,
  )
  bucket_names = concat(
    module.ipfs-cluster-aws-region-us-east-1.bucket_names,
    module.ipfs-cluster-aws-region-eu-north-1.bucket_names
  )

}

#
# Providers
#

provider "aws" {}

provider "aws" {
  alias  = "us-east-2"
  region = "us-east-2"
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us-west-1"
  region = "us-west-1"
}

provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
}

provider "aws" {
  alias  = "af-south-1"
  region = "af-south-1"
}

provider "aws" {
  alias  = "ap-east-1"
  region = "ap-east-1"
}

provider "aws" {
  alias  = "ap-south-1"
  region = "ap-south-1"
}

provider "aws" {
  alias  = "ap-northeast-3"
  region = "ap-nrotheast-3"
}

provider "aws" {
  alias  = "ap-northeast-2"
  region = "ap-northeast-2"
}

provider "aws" {
  alias  = "ap-southeast-1"
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "ap-southeast-2"
  region = "ap-southeast-2"
}

provider "aws" {
  alias  = "ap-northeast-1"
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "ca-central-1"
  region = "ca-central-1"
}

provider "aws" {
  alias  = "cn-north-1"
  region = "cn-north-1"
}

provider "aws" {
  alias  = "cn-northwest-1"
  region = "cn-northwest-1"
}

provider "aws" {
  alias  = "eu-central-1"
  region = "eu-central-1"
}

provider "aws" {
  alias  = "eu-west-1"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "eu-west-2"
  region = "eu-west-2"
}

provider "aws" {
  alias  = "eu-south-1"
  region = "eu-south-1"
}

provider "aws" {
  alias  = "eu-west-3"
  region = "eu-west-3"
}

provider "aws" {
  alias  = "eu-north-1"
  region = "eu-north-1"
}

provider "aws" {
  alias  = "me-south-1"
  region = "me-south-1"
}

provider "aws" {
  alias  = "sa-east-1"
  region = "sa-east-1"
}


#
# Region Modules
#
# We need to define a module instance for each region since providers cannot be configured dynamically.
# If you need more regions, please copy and paste the code, and replace the region name everywhere


module "ipfs-cluster-aws-region-us-east-1" {
  providers       = { aws = aws.us-east-1 }
  nodes           = local.region_nodes_map["us-east-1"]
  region_fqdn     = local.region_map["us-east-1"].region_fqdn
  tags            = merge(local.tags, { Name = local.region_map["us-east-1"].region_prefix })
  source          = "./ipfs-cluster-aws-region"
  public_key      = local.public_key
  instance_type   = var.instance_type
  volume_size     = var.volume_size
  fqdn            = local.fqdn
  api_cidr_block  = var.api_cidr_block
  s3_bucket_id    = var.s3_bucket_ids["us-east-1"]
}

module "ipfs-cluster-aws-region-eu-north-1" {
  providers       = { aws = aws.eu-north-1 }
  nodes           = local.region_nodes_map["eu-north-1"]
  region_fqdn     = local.region_map["eu-north-1"].region_fqdn
  tags            = merge(local.tags, { Name = local.region_map["eu-north-1"].region_prefix })
  source          = "./ipfs-cluster-aws-region"
  instance_type   = var.instance_type
  public_key      = local.public_key
  volume_size     = var.volume_size
  fqdn            = local.fqdn
  api_cidr_block  = var.api_cidr_block
  s3_bucket_id    = var.s3_bucket_ids["eu-north-1"]
}
