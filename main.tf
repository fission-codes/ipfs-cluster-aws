# Infrastructure Definition

provider "aws" {}

#
# Local Variables
#

locals {
  name                 = "ipfs-cluster-${local.env}"
  iam_username         = element(reverse(split("/", data.aws_caller_identity.current.arn)), 0)
  env                  = var.env != null ? var.env : lower(local.iam_username)
  maintainer           = var.maintainer != null ? var.maintainer : var.env
  generate_private_key = var.public_key == null
  public_key           = local.generate_private_key ? tls_private_key.this[0].public_key_openssh : var.public_key
  tags = {
    Name       = local.name
    Env        = local.env
    Maintainer = local.maintainer
    ManagedBy  = "Terrafrom"
    DoNotEdit  = "Do not edit this resource manually. Your changes will be overwritten. Contact the maintainer to request changes."
  }
}

#
# Data Sources
#

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

module "ami" {
  source  = "git::https://github.com/tweag/terraform-nixos//aws_image_nixos?ref=fa6ba97b51873817b279840dcb619725ea9793ac"
  release = "20.03"
}

#
# Resources
#

# Generate a key pair if public_key is not provided.
resource "tls_private_key" "this" {
  count     = local.generate_private_key ? 1 : 0
  algorithm = "RSA"
}

# Upload the public key to AWS to use it for accessing the EC2 instances.
resource "aws_key_pair" "this" {
  key_name   = local.name
  public_key = local.public_key
}

# Firewall
resource "aws_security_group" "this" {
  name        = local.name
  description = "Allow inbound ssh"
  vpc_id      = data.aws_vpc.default.id
  tags        = local.tags

  ingress {
    description = "ssh from all"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "this" {
  count                       = var.node_count
  ami                         = module.ami.ami
  instance_type               = var.instance_type
  subnet_id                   = tolist(data.aws_subnet_ids.all.ids)[0]
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.this.key_name
  tags                        = local.tags

  depends_on = [aws_key_pair.this]

  root_block_device {
    volume_size = "32"
  }

  connection {
    user        = "root"
    host        = self.public_ip
    private_key = local.generate_private_key ? tls_private_key.this[0].private_key_pem : null
  }

  # Wait until the host is up.
  provisioner "remote-exec" {
    inline = ["echo 'Hello, World!'"]
  }
}

#
# Output Files
#

# Save the generated private key to a file. Development only. In production, set public_key.
resource "local_file" "private_key" {
  count             = local.generate_private_key ? 1 : 0
  filename          = "SECRET_private_key"
  sensitive_content = tls_private_key.this[0].private_key_pem
  file_permission   = "0600"
}

resource "local_file" "node_ip" {
  count    = var.node_count
  filename = "out_node_ip_${count.index}"
  content  = aws_instance.this[count.index].public_ip
}

#
# Outputs
#

output "node_ips" {
  value = aws_instance.this.*.public_ip
}
