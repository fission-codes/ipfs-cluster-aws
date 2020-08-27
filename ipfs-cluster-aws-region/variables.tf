# Infrastructure Input Variables

variable "env" {
  description = "Name for the infrastructure environment. It will appear in AWS resource names, tags, and domain names. Set to your username for development (or 'staging', 'production' for permanent deployments). Leave empty to use the AWS key's IAM users's alias."
  type        = string
}

variable "maintainer" {
  description = "Handle of person responsible for this infrastructure. Defaults to the value of `env`."
  type        = string
  default     = null
}

variable "region" {
  description = "AWS region to create the resources in."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name to use for resources."
  type        = string
  default     = null
}

variable "node_count" {
  description = "Number of ipfs-cluster EC2 instances to provision."
  default     = 3
  type        = number
}

variable "node_names" {
  description = "Node names. Optional."
  default     = null
  type        = list(string)
}

variable "instance_type" {
  description = "The EC2 instance type to use. See https://aws.amazon.com/ec2/instance-types/"
  type        = string
  default     = "t3.small"
}

variable "public_key" {
  description = "This SSH public key will be granted root access on the nodes. If not set, will generate a private key file and save it to `SECRET_private_key`."
  type        = string
}

variable "volume_size" {
  description = "Size of root volumes in GB."
  type        = number
  default     = 20
}
