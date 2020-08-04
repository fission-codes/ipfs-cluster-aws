## [ipfs-cluster](https://cluster.ipfs.io/) on AWS

Deploy a network of [ipfs-cluster](https://cluster.ipfs.io/) nodes running on [NixOS](https://nixos.org/) on AWS [EC2](https://aws.amazon.com/ec2/) cloud servers using [Terraform](https://www.terraform.io/).


### Zero to Hero

Install [nix](https://nixos.org/download.html), clone this repo and `cd` in.

Get or [create](https://docs.aws.amazon.com/IAM/latest/UserGuide/getting-started_create-admin-group.html) an AWS access key, then [configure](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#environment-variables) credentials and default region for Terraform's AWS provider. For example, using environment variables:

```
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-west-2"
```

Start the deployment:

```
TODO nix-shell --run 'terraform apply'
```

Terraform will ask you for an environment name (eg. your handle). You can [save variables](https://learn.hashicorp.com/terraform/getting-started/variables.html#assigning-variables) eg. in a file named `terraform.tfvars`. Read the plan and accept it if you are satisfied. When the deployment is done, read the outputs.

Connect to a server and run some commands:

```
TODO ssh $(cat out_node1_ip) -i SECRET_ssh_private_key 'journalctl -f -n 200'
```

When you're done, don't forget to destroy the cloud resources so as not to waste power and money:

```
TODO nix-shell --run 'terraform destroy'
```


### What? Where?

- deployment environment
  - TODO [`shell.nix`](shell.nix) is loaded by `nix-shell` and includes dependencies and scripts used for infrastructure deployment
- infrastructure
  - [`variables.tf`](variables.tf) defines inputs to the infrastructure that you can configure
  - TODO [`main.tf`](main.tf) defines the AWS cloud resources (vpc, sg, acl, ec2, ebs, r53, etc.) deployed via Terraform, ie. a bunch of cloud servers running NixOS
- operating sysem configuration
  - TODO [`ipfs-cluster-node.nix`](ipfs-cluster-node.nix`) is a NixOS profile for running an `ipfs-cluster` node with all required services and configuration
  - TODO [`ipfs-cluster.nix`](ipfs-cluster.nix) is a NixOS module for running the `ipfs-cluster` service
