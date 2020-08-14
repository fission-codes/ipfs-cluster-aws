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

data "local_file" "node_id" {
  count = var.node_count
  # wait until file is created
  filename = "out/node${count.index}/ipfs-cluster-id${replace(null_resource.node_identity[count.index].id, "/.*/", "")}"
}

data "local_file" "node_private_key" {
  count = var.node_count
  # wait until file is created
  filename = "SECRET/node${count.index}/ipfs-cluster-private_key${replace(null_resource.node_identity[count.index].id, "/.*/", "")}"
}

#
# Resources
#

resource "random_id" "cluster_secret" {
  byte_length = 32
}

resource "null_resource" "node_identity" {
  count = var.node_count
  provisioner "local-exec" {
    command = <<-EOT
      true && \
        mkdir -p out/node${count.index} && \
        mkdir -p SECRET/node${count.index} && \
        ipfs-key -type ed25519 -f -pidout out/node${count.index}/ipfs-cluster-id -prvout SECRET/node${count.index}/ipfs-cluster-private_key
    EOT
  }
}

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
  vpc_id      = data.aws_vpc.default.id
  tags        = local.tags

  ingress {
    description = "Allow inbound SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow inbound IPFS swarm"
    from_port   = 4001
    to_port     = 4001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow inbound ipfs-cluster swarm"
    from_port   = 9096
    to_port     = 9096
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

  depends_on = [aws_key_pair.this, aws_security_group.this]

  root_block_device {
    volume_size = var.volume_size
  }

}

#
# Deploy
#

# Copy secrets to servers
resource "null_resource" "deploy_secrets" {
  count = var.node_count

  triggers = {
    instance = aws_instance.this[count.index].id
    cluster_secret = random_id.cluster_secret.hex
  }

  depends_on = [local_file.private_key, local_file.configuration, local_file.node_ip ]

  connection {
    host        = aws_instance.this[count.index].public_ip
    private_key = local.generate_private_key ? tls_private_key.this[0].private_key_pem : null
  }

  # Wait until the host is up.
  provisioner "remote-exec" {
    inline = ["echo 'Hello, World!'"]
  }

  provisioner "file" {
    content     = "CLUSTER_SECRET=${random_id.cluster_secret.hex}"
    destination = "/root/SECRET_ipfs-cluster"
  }

  provisioner "file" {
    content     = jsonencode({"id"=data.local_file.node_id[count.index].content, "private_key"=data.local_file.node_private_key[count.index].content})
    destination = "/root/SECRET_identity.json"
  }

  provisioner "remote-exec" {
    inline = ["systemctl restart ipfs-cluster-init || echo 'Restarting ipfs-cluster failed.'"]
  }
}

# Deploy NixOS
resource "null_resource" "deploy_nixos" {
  count = var.node_count

  triggers = {
    always   = uuid()
  }

  depends_on = [null_resource.deploy_secrets]

  provisioner "local-exec" {
    command = "deploy-nixos root@${aws_instance.this[count.index].public_ip} --config out/node${count.index}/configuration.nix"
  }
}

#
# Output Files
#

# Save the generated private key to a file, for development only. In production, set public_key.
resource "local_file" "private_key" {
  count             = local.generate_private_key ? 1 : 0
  filename          = "SECRET/private_key"
  sensitive_content = tls_private_key.this[0].private_key_pem
  file_permission   = "0600"
}

# Save node IPs in files for easy access
resource "local_file" "node_ip" {
  count    = var.node_count
  filename = "out/node${count.index}/ip"
  content  = aws_instance.this[count.index].public_ip
}

# Generate NixOS configuration file for each node.
resource "local_file" "configuration" {
  count    = var.node_count
  filename = "out/node${count.index}/configuration.nix"
  file_permission   = "0666"
  content  = <<-EOT
    {
      imports = [ ./ipfs-cluster-aws.nix ];

      networking.hostName = "${local.name}-${count.index}";

      services.ipfs-cluster.bootstrapPeers = [
        ${join(" ", [for i in range(var.node_count): "\"/ip4/${aws_instance.this[i].public_ip}/tcp/9096/ipfs/${data.local_file.node_id[i].content}\"" if i != count.index])}
      ];

      systemd.services.ipfs-cluster-init.serviceConfig.EnvironmentFile = "/root/SECRET_ipfs-cluster";
      systemd.services.ipfs-cluster.serviceConfig.EnvironmentFile = "/root/SECRET_ipfs-cluster";
    }
  EOT
}


#
# Outputs
#

output "node_ips" {
  value = aws_instance.this.*.public_ip
}
