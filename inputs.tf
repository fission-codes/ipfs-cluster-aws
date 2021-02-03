# Infrastructure Input Variables

variable "environment" {
  description = "Name for the infrastructure environment. It will appear in AWS resource names, tags, and domain names. Set to your username for development (or 'staging', 'production' for permanent deployments). Leave empty to use the AWS key's IAM users's alias."
  type        = string
  default     = null
}

variable "maintainer" {
  description = "Handle of person responsible for this infrastructure. Defaults to the value of `env`."
  type        = string
  default     = null
}

variable "region_node_counts" {
  description = "Map from AWS regions to number of ipfs-cluster nodes."
  default     = { "eu-north-1" = 1, "us-east-1" = 2 }
  type        = map(number)
}

variable "instance_type" {
  description = "The EC2 instance type to use. See https://aws.amazon.com/ec2/instance-types/"
  type        = string
  default     = "t3.small"
}

variable "public_key" {
  description = "This SSH public key will be granted root access on the nodes. If not set, will generate a private key file and save it to `SECRET_private_key`."
  type        = string
  default     = null
}

variable "authorized_keys" {
  description = "List of public keys to grant ssh access to nodes."
  type        = list(string)
  default     = []
}

variable "volume_size" {
  description = "Size of root volumes in GB."
  type        = number
  default     = 50
}

variable "domain" {
  description = "Domain name of AWS Route53 Hosted Zone to which records are added for subdomains."
  type        = string
}

variable "subdomain" {
  description = "Subdomain of domain where the global load-balanced IPFS cluster gateway will be available."
  type        = string
  default     = null
}

variable "api_cidr_block" {
  description = "CIDR Block of Web API that can access IPFS HTTP API"
  type        = string
}

variable "acme_email" {
  description = "Email address where Let's Encrypt can contact you regarding ACME certificates."
  type        = string
}

variable "acme_url" {
  description = "ACME URL that Let's Encrypt uses for SSL certificates"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "tags" {
  description = "Tags to use for resources. Name will be overwritten."
  type        = map(string)
  default     = null
}

variable "s3_bucket_ids" {
  description = "Map from AWS regions to number of ipfs-cluster nodes."
  type        = map(string)
}
