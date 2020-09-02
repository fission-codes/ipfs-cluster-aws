locals {
  env                  = var.env != null ? var.env : lower(local.iam_username)
  maintainer           = var.maintainer != null ? var.maintainer : var.env
  name                 = "${local.env}-ipfs-cluster"
  node_count           = sum(values(var.region_node_counts))
  region_node_names    = { for r, c in var.region_node_counts : r => [for i in range(c) : "ipfs-cluster-${local.env}-${r}-node-${i}"] }
  iam_username         = element(reverse(split("/", data.aws_caller_identity.current.arn)), 0)
  generate_private_key = var.public_key == null
  public_key           = local.generate_private_key ? tls_private_key.this[0].public_key_openssh : var.public_key
  node_ips             = concat(module.ipfs-cluster-aws-region-1.node_ips, module.ipfs-cluster-aws-region-2.node_ips)
  bucket_names         = concat(module.ipfs-cluster-aws-region-1.bucket_names, module.ipfs-cluster-aws-region-2.bucket_names)
}

#
# Data Sources
#

data "local_file" "node_id" {
  count = local.node_count
  # wait until file is created
  filename = "out/node${count.index}/ipfs-cluster-id${replace(null_resource.node_identity[count.index].id, "/.*/", "")}"
}

data "local_file" "node_private_key" {
  count = local.node_count
  # wait until file is created
  filename = "SECRET/node${count.index}/ipfs-cluster-private_key${replace(null_resource.node_identity[count.index].id, "/.*/", "")}"
}

# Get the account details of the currently authenticated AMI user .
data "aws_caller_identity" "current" {}

#
# Resources
#

resource "random_id" "cluster_secret" {
  byte_length = 32
}

resource "null_resource" "node_identity" {
  count = local.node_count
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

#
# Regions
#

# We have to define a module instance for each region since providers cannot be configured dynamically
module "ipfs-cluster-aws-region-1" {
  source        = "./ipfs-cluster-aws-region"
  env           = local.env
  maintainer    = local.maintainer
  name          = local.name
  node_count    = var.region_node_counts["us-east-1"]
  node_names    = local.region_node_names["us-east-1"]
  instance_type = var.instance_type
  public_key    = local.public_key
  volume_size   = var.volume_size
  providers = {
    aws = aws.us-east-1
  }
}

module "ipfs-cluster-aws-region-2" {
  source        = "./ipfs-cluster-aws-region"
  env           = local.env
  name          = local.name
  maintainer    = local.maintainer
  node_count    = var.region_node_counts["eu-north-1"]
  node_names    = local.region_node_names["eu-north-1"]
  instance_type = var.instance_type
  public_key    = local.public_key
  volume_size   = var.volume_size
  providers = {
    aws = aws.eu-north-1
  }
}

#
# Deploy
#

# Generate NixOS configuration file for each node.
resource "local_file" "configuration" {
  count           = local.node_count
  filename        = "out/node${count.index}/configuration.nix"
  file_permission = "0666"
  content         = <<-EOT
    {
      imports = [ ./ipfs-cluster-aws.nix ];

      networking.hostName = "${local.env}-ipfs-cluster-node${count.index}";

      # TODO: ipfs s3 ds config
      # services.ipfs.extraConfig = {
      #   Datastore: {
      #     Spec = {
      #       mounts = [
      #         {
      #           child = {
      #             type = "s3ds";
      #             region = "us-east-1";
      #             bucket = "${local.bucket_names[count.index]}";
      #             rootDirectory = "ipfs-cluster";
      #           };
      #           mountpoint: "/blocks",
      #           prefix: "s3.datastore",
      #           type: "measure"
      #         };
      #       ];
      #     };
      #   };
      # ];

      services.ipfs-cluster.bootstrapPeers = [
        ${join(" ", [for i in range(local.node_count) : "\"/ip4/${local.node_ips[i]}/tcp/9096/ipfs/${data.local_file.node_id[i].content}\"" if i != count.index])}
      ];

      services.ipfs-cluster.bucket_name = "${local.bucket_names[count.index]}";

      systemd.services.ipfs-cluster-init.serviceConfig.EnvironmentFile = "/root/SECRET_ipfs-cluster";
      systemd.services.ipfs-cluster.serviceConfig.EnvironmentFile = "/root/SECRET_ipfs-cluster";
    }
  EOT
}

# Copy secrets to servers
resource "null_resource" "deploy_secrets" {
  count = local.node_count

  triggers = {
    instance       = join(" ", tolist(local.node_ips))
    cluster_secret = random_id.cluster_secret.hex
  }

  depends_on = [local_file.configuration]

  connection {
    host        = local.node_ips[count.index]
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
    content     = jsonencode({ "id" = data.local_file.node_id[count.index].content, "private_key" = data.local_file.node_private_key[count.index].content })
    destination = "/root/SECRET_identity.json"
  }

  provisioner "remote-exec" {
    inline = ["systemctl restart ipfs-cluster-init || echo 'Restarting ipfs-cluster failed.'"]
  }
}

# Deploy NixOS
resource "null_resource" "deploy_nixos" {
  count = local.node_count

  triggers = {
    always = uuid()
  }

  depends_on = [null_resource.deploy_secrets]

  provisioner "local-exec" {
    command = "deploy-nixos root@${local.node_ips[count.index]} --config out/node${count.index}/configuration.nix"
  }
}

#
# Outputs
#

# Save the generated private key to a file, for development only. In production, set public_key.
resource "local_file" "private_key" {
  count             = local.generate_private_key ? 1 : 0
  filename          = "SECRET/private_key"
  sensitive_content = tls_private_key.this[0].private_key_pem
  file_permission   = "0600"
}
