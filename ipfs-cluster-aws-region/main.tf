# Infrastructure Definition

provider "aws" {}

# Local variables
locals {
  maintainer = var.maintainer != null ? var.maintainer : var.env
  name       = var.name != null ? var.name : "${var.env}-ipfs-cluster-${data.aws_region.current.name}"
  node_names = [for i in range(var.node_count) : length(var.node_names) > i ? var.node_names[i] : "${local.name}-node${i}"]

  tags = {
    Name       = local.name
    Env        = var.env
    Maintainer = local.maintainer
    ManagedBy  = "Terrafrom"
    DoNotEdit  = "This resource is managed by Terraform. Do not edit manually. Contact the maintainer to request changes."
  }
}

#
# Data sources
#

data "aws_region" "current" {}

data "aws_route53_zone" "this" {
  name = "${var.domain}."
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Look up NixOS machine image.
module "ami" {
  source  = "git::https://github.com/tweag/terraform-nixos//aws_image_nixos?ref=fa6ba97b51873817b279840dcb619725ea9793ac"
  release = "20.03"
}

#
# Resources
#

resource "aws_s3_bucket" "this" {
  bucket_prefix = "${local.name}-"
  acl           = "private"
  tags          = local.tags
  # # to destroy buckets with objects in them, uncomment this, apply the configuration, and then destroy
  # force_destroy = true
}

resource "aws_vpc" "this" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true
  tags                             = local.tags
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = local.tags
}

resource "aws_subnet" "this" {
  count             = var.node_count
  vpc_id            = aws_vpc.this.id
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  cidr_block        = "10.0.${count.index}.0/24"
  tags              = local.tags
  lifecycle {
    ignore_changes = [availability_zone]
  }
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id
  tags   = local.tags

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "this" {
  count          = var.node_count
  subnet_id      = aws_subnet.this[count.index].id
  route_table_id = aws_route_table.this.id
}

# Firewall
resource "aws_security_group" "this" {
  name   = local.name
  vpc_id = aws_vpc.this.id
  tags   = local.tags

  ingress {
    description      = "Allow inbound SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow inbound ICMP"
    protocol = "icmp"
    from_port = -1
    to_port = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow inbound ICMPv6"
    protocol = "icmpv6"
    from_port = -1
    to_port = -1
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow inbound HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow inbound HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow inbound IPFS swarm TCP"
    from_port        = 4001
    to_port          = 4001
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow inbound IPFS swarm QUIC"
    from_port        = 4001
    to_port          = 4001
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow inbound IPFS swarm Secure Websocket"
    from_port        = 4003
    to_port          = 4003
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow inbound IPFS Cluster swarm"
    from_port        = 9096
    to_port          = 9096
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Upload the public key to AWS to use it for accessing the EC2 instances.
resource "aws_key_pair" "this" {
  key_name   = local.name
  public_key = var.public_key
}

resource "aws_instance" "this" {
  count                       = var.node_count
  ami                         = module.ami.ami
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.this[count.index].id
  vpc_security_group_ids      = [aws_security_group.this.id]
  depends_on                  = [aws_route_table_association.this, aws_security_group.this, aws_s3_bucket.this]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.this.key_name
  iam_instance_profile        = aws_iam_instance_profile.this.name
  tags                        = merge(local.tags, { Name = local.node_names[count.index] })

  root_block_device {
    volume_size = var.volume_size
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_iam_instance_profile" "this" {
  name = local.name
  role = aws_iam_role.this.name
}

resource "aws_iam_role" "this" {
  name = local.name
  tags = local.tags

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
      ]
    }
  EOT
}

resource "aws_iam_role_policy" "this" {
  name   = "this"
  role   = aws_iam_role.this.id
  policy = <<-EOT
  {
    "Version": "2012-10-17",
    "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "s3:ListBucket"
          ],
        "Resource": [
            "arn:aws:s3:::${aws_s3_bucket.this.id}"
          ]
        },
        {
          "Effect": "Allow",
          "Action": [
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:PutObjectAcl"
          ],
          "Resource": [
            "arn:aws:s3:::${aws_s3_bucket.this.id}/*"
          ]
        }
      ]
    }
  EOT
}

resource "aws_route53_record" "this" {
  count   = var.node_count
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${local.node_names[count.index]}.${data.aws_route53_zone.this.name}"
  type    = "A"
  ttl     = "600"
  records = [aws_instance.this[count.index].public_ip]
}


resource "aws_route53_record" "round-robin" {
  count = var.node_count
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.name
  type    = "CNAME"
  ttl     = "5"

  set_identifier = local.node_names[count.index]
  records = aws_route53_record.this.*.fqdn

  weighted_routing_policy {
    weight = 1
  }
}


#
# Outputs
#

output "node_ips" {
  value = aws_instance.this.*.public_ip
  # wait until everything is ready
  depends_on = [aws_instance.this, aws_s3_bucket.this, aws_route53_record.this]
}

output "node_fqdns" {
  value = aws_route53_record.this.*.fqdn
  # wait until everything is ready
  depends_on = [aws_instance.this, aws_s3_bucket.this, aws_route53_record.this]
}

output "bucket_names" {
  value = [for x in range(var.node_count) : aws_s3_bucket.this.id]
  # wait until everything is ready
  depends_on = [aws_instance.this, aws_s3_bucket.this, aws_route53_record.this]
}
