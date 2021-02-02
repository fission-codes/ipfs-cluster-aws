# Terraform cloud infrastructure and deployment

terraform {
  required_providers {
    acme = {
      source  = "getstackhead/acme"
      version = "1.5.0-patched"
    }
    shell = {
      source  = "nixpkgs/shell"
      version = "1.6.0"
    }
  }
}

#
# Local variables
#

locals {
  environment          = var.environment != null ? var.environment : lower(local.iam_username)
  maintainer           = var.maintainer != null ? var.maintainer : local.environment
  prefix               = "${local.environment}-ipfs-cluster"
  iam_username         = element(reverse(split("/", data.aws_caller_identity.current.arn)), 0)
  generate_private_key = var.public_key == null
  public_key           = local.generate_private_key ? tls_private_key.deploy[0].public_key_openssh : var.public_key
  subdomain            = var.subdomain != null ? var.subdomain : local.prefix
  fqdn                 = "${local.subdomain}.${var.domain}"

  tags = merge(
    {
      Environment = local.environment
      Maintainer  = local.maintainer
      ManagedBy   = "Terrafrom"
      DoNotEdit   = "This resource is managed by Terraform. Do not edit manually. Contact the maintainer to request changes."
    },
    var.tags == null ? var.tags : {},
    {
      Name = local.prefix
    }
  )

  regions = [for r in local.all_regions : {
    region_name       = r
    region_node_count = var.region_node_counts[r]
    region_prefix     = "${local.prefix}-${r}"
    region_fqdn       = "${local.prefix}-${r}.${var.domain}"
  } if contains(keys(var.region_node_counts), r)]

  nodes = flatten([for r in local.regions : [for i in range(r.region_node_count) : {
    node_index        = i
    node_prefix       = "${r.region_prefix}-node${i}"
    node_fqdn         = "${r.region_prefix}-node${i}.${var.domain}"
    region_name       = r.region_name
    region_prefix     = r.region_prefix
    region_fqdn       = r.region_fqdn
    region_node_count = r.region_node_count
  }]])

  region_map       = { for r in local.regions : r.region_name => r }
  region_nodes_map = { for r in local.regions : r.region_name => [for n in local.nodes : n if n.region_name == r.region_name] }
}

#
# Data Sources
#

# Get the account details of the currently authenticated AMI user .
data "aws_caller_identity" "current" {}

# Get the Hosted Zone ID for the domain
data "aws_route53_zone" "this" {
  name = "${var.domain}."
}

#
# DNS
#

# Route to region with lowest latency
resource "aws_route53_record" "this" {
  count          = length(local.regions)
  zone_id        = data.aws_route53_zone.this.zone_id
  name           = "${local.fqdn}."
  type           = "A"
  set_identifier = "${local.prefix}-${local.regions[count.index].region_name}"
  alias {
    name                   = "${aws_route53_record.regions[count.index].fqdn}."
    zone_id                = data.aws_route53_zone.this.zone_id
    evaluate_target_health = false
  }

  latency_routing_policy {
    region = local.regions[count.index].region_name
  }
}

# Distribute among nodes within region
resource "aws_route53_record" "regions" {
  count          = length(local.nodes)
  zone_id        = data.aws_route53_zone.this.zone_id
  name           = local.nodes[count.index].region_fqdn
  type           = "A"
  set_identifier = local.nodes[count.index].node_prefix

  alias {
    name                   = "${aws_route53_record.nodes[count.index].fqdn}."
    zone_id                = data.aws_route53_zone.this.zone_id
    evaluate_target_health = false
  }

  weighted_routing_policy {
    weight = 1
  }
}

# Records per node
resource "aws_route53_record" "nodes" {
  count   = length(local.nodes)
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${local.nodes[count.index].node_fqdn}."
  type    = "A"
  ttl     = "600"
  records = [local.node_ips[count.index]]
}

#
# ACME TLS certificate
#

provider "acme" {
  server_url = var.acme_url
}

resource "tls_private_key" "https" {
  algorithm = "RSA"
}

resource "acme_registration" "this" {
  account_key_pem = tls_private_key.https.private_key_pem
  email_address   = var.acme_email
}

resource "acme_certificate" "this" {
  account_key_pem = acme_registration.this.account_key_pem
  common_name     = local.fqdn
  subject_alternative_names = concat(var.gateway_urls, [
    for n in local.nodes : n.node_fqdn
  ])
  recursive_nameservers = data.aws_route53_zone.this.name_servers

  dns_challenge {
    provider = "route53"
    config = {
      AWS_HOSTED_ZONE_ID      = data.aws_route53_zone.this.zone_id
      AWS_REGION              = "us-east-1"
      AWS_PROPAGATION_TIMEOUT = 600
      AWS_POLLING_INTERVAL    = 60
    }
  }
}


#
# Secrets
#

# Generate a deployment key pair if public_key is not provided.
resource "tls_private_key" "deploy" {
  count     = local.generate_private_key ? 1 : 0
  algorithm = "RSA"
}

# IPFS Cluster secret
resource "random_id" "cluster_secret" {
  byte_length = 32
}

# IPFS Cluster node id and private key
resource "shell_script" "node_identity" {
  count = length(local.nodes)

  lifecycle_commands {
    create = "ipfs-key"
    delete = "true"
  }
}

#
# Deploy
#

# Copy secrets to servers
resource "null_resource" "deploy_secrets" {
  count = length(local.nodes)

  triggers = {
    instance       = join(" ", tolist(local.node_ips))
    cluster_secret = sha256(random_id.cluster_secret.hex)
    node_identity  = sha256(jsonencode(shell_script.node_identity[count.index].output))
    cert           = sha256("${acme_certificate.this.certificate_pem}${acme_certificate.this.issuer_pem}")
    key            = sha256(acme_certificate.this.private_key_pem)
  }

  connection {
    host        = local.node_ips[count.index]
    private_key = local.generate_private_key ? tls_private_key.deploy[0].private_key_pem : null
  }

  # Wait until the host is up.
  provisioner "remote-exec" {
    inline = ["echo 'Hello, World!'"]
  }

  # Create SSL cert dir and chown to nginx (which is not installed yet so we use the permanent NixOS uid and gid)
  # See https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/ids.nix
  provisioner "remote-exec" {
    inline = ["mkdir -p /var/lib/ssl/ && chown 60.60 /var/lib/ssl && chmod 500 /var/lib/ssl"]
  }

  provisioner "file" {
    content     = "CLUSTER_SECRET=${random_id.cluster_secret.hex}"
    destination = "/root/SECRET_ipfs-cluster"
  }

  provisioner "file" {
    content     = jsonencode(shell_script.node_identity[count.index].output)
    destination = "/root/SECRET_identity.json"
  }

  provisioner "file" {
    content     = acme_certificate.this.private_key_pem
    destination = "/var/lib/ssl/key"
  }

  provisioner "file" {
    content     = "${acme_certificate.this.certificate_pem}${acme_certificate.this.issuer_pem}"
    destination = "/var/lib/ssl/cert"
  }

  provisioner "remote-exec" {
    inline = [
      "chown 60.60 /var/lib/ssl/key /var/lib/ssl/cert && chmod 400 /var/lib/ssl/key /var/lib/ssl/cert",
      "systemctl restart ipfs-cluster-init || echo 'Restarting ipfs-cluster failed.'"
    ]
  }
}

data "external" "payload" {
  program = ["bash", "-c", "cd ${path.module}; echo { \\\"hash\\\": \\\"$(nix-hash nix)$(nix-hash nixos)\\\" }"]
}

# Deploy NixOS
resource "null_resource" "deploy_nixos" {
  count = length(local.nodes)

  triggers = {
    payload       = data.external.payload.result.hash
    configuration = sha256(data.null_data_source.configuration[count.index].outputs.content)
    secrets = null_resource.deploy_secrets[count.index].id
  }

  depends_on = [null_resource.deploy_secrets]

  connection {
    host        = local.node_ips[count.index]
    private_key = local.generate_private_key ? tls_private_key.deploy[0].private_key_pem : null
  }

  provisioner "file" {
    content     = data.null_data_source.configuration[count.index].outputs.content
    destination = "/etc/nixos/configuration.nix"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /root/ipfs-cluster-aws"]
  }

  provisioner "file" {
    source      = "${path.module}/nix"
    destination = "/root/ipfs-cluster-aws"
  }

  provisioner "file" {
    source      = "${path.module}/nixos"
    destination = "/root/ipfs-cluster-aws"
  }

  provisioner "remote-exec" {
    inline = [
      "nixos-rebuild build --show-trace > /dev/null",
      "nixos-rebuild switch --show-trace -j 1",
    ]
  }
}

# Generate NixOS configuration file for each node.
data "null_data_source" "configuration" {
  count = length(local.nodes)
  inputs = { content = <<-EOT
    {
      imports = [ /root/ipfs-cluster-aws/nixos/ipfs-cluster-aws.nix ];

      networking.hostName = "${local.nodes[count.index].node_prefix}";

      security.acme.email = "${var.acme_email}";

      services.ipfs-cluster.bootstrapPeers = [
        ${join(" ", [for i in range(length(local.nodes)) : "\"/ip4/${local.node_ips[i]}/tcp/9096/ipfs/${shell_script.node_identity[i].output["id"]}\"" if i != count.index])}
      ];

      services.ipfs-cluster-aws = {
        enable = true;
        region = "${local.nodes[count.index].region_name}";
        bucket = "${local.bucket_names[count.index]}";
        nodeFqdn = "${local.nodes[count.index].node_fqdn}";
        regionFqdn = "${local.nodes[count.index].region_fqdn}";
        fqdn = "${local.fqdn}";
      };
    }
  EOT
  }
}

#
# Outputs
#

# Save the generated private key to a file, for development only. In production, set public_key.
resource "local_file" "private_key" {
  count             = local.generate_private_key ? 1 : 0
  filename          = "SECRET/private_key"
  sensitive_content = tls_private_key.deploy[0].private_key_pem
  file_permission   = "0600"
}

output "node_ips" {
  value = local.node_ips
}

output "node_fqdns" {
  value      = [for n in local.nodes : n.node_fqdn]
  depends_on = [null_resource.deploy_nixos]
}

output "fqdn" {
  value = local.fqdn
}
