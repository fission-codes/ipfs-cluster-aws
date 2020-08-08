# Infrastructure Definition

provider "aws" {}

# Local variables
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
# Data sources
#


# Get the account details of the currently authenticated AMI user .
data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

# Look up NixOS machine image.
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
  description = "Allow inbound SSH and all outbound traffic"
  vpc_id      = data.aws_vpc.default.id
  tags        = local.tags

  ingress {
    description = "Allow inbound SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
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
    volume_size = var.volume_size
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
# Deploy NixOS
#

resource "null_resource" "deploy-nixos" {
  count = var.node_count

  triggers = {
    instance = aws_instance.this[count.index].id
    always   = uuid()
  }

  depends_on = [local_file.private_key, local_file.configuration, local_file.node_ip]

  provisioner "local-exec" {
    command = "deploy-nixos root@${aws_instance.this[count.index].public_ip} --config out_node${count.index}_configuration.nix"
  }
}


#
# Output Files
#

# Save the generated private key to a file, for development only. In production, set public_key.
resource "local_file" "private_key" {
  count             = local.generate_private_key ? 1 : 0
  filename          = "SECRET_private_key"
  sensitive_content = tls_private_key.this[0].private_key_pem
  file_permission   = "0600"
}

# Save node IPs in files for easy access
resource "local_file" "node_ip" {
  count    = var.node_count
  filename = "out_node${count.index}_ip"
  content  = aws_instance.this[count.index].public_ip
}

# Generate NixOS configuration file for each node.
resource "local_file" "configuration" {
  count    = var.node_count
  filename = "out_node${count.index}_configuration.nix"
  content  = <<-EOT
    {
      imports = [ ./ipfs-cluster-aws.nix ];
      networking.hostName = "${local.name}-${count.index}";
    }
  EOT
}


#
# Outputs
#

output "node_ips" {
  value = aws_instance.this.*.public_ip
}
