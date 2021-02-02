# Infrastructure Input Variables

variable "tags" {
  description = "Tags to use for resources."
  type        = map(string)
}

variable "nodes" {
  description = "List of node definitions."
  type        = list(map(string))
}

variable "region_fqdn" {
  description = "Fully qualified domain name for this region."
  type        = string
}

variable "fqdn" {
  description = "Fully qualified domain name for the cluster."
  type        = string
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

variable "api_cidr_block" {
  description = "CIDR Block of Web API that can access IPFS HTTP API"
  type        = string
}

variable "s3_bucket_id" {
  description = "CIDR Block of Web API that can access IPFS HTTP API"
  type        = string
}
