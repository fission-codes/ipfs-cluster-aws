## [ipfs-cluster](https://cluster.ipfs.io/) on AWS

Deploys a load balanced multi-region network of [ipfs-cluster](https://cluster.ipfs.io/) nodes running on [NixOS](https://nixos.org/) on AWS [EC2](https://aws.amazon.com/ec2/) cloud servers using [Terraform](https://www.terraform.io/).

First, Install [nix](https://nixos.org/download.html), clone this repo and `cd` in.


### Zero to Hero

Set up or choose an existing, public [Route53 Hosted zone](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-working-with.html) to use for subdomains.

Get or [create](https://docs.aws.amazon.com/IAM/latest/UserGuide/getting-started_create-admin-group.html) an AWS access key with appropriate permissions.

[Configure](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#environment-variables) credentials and default region for Terraform's AWS provider. For example, using environment variables:

```
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-west-2"
```

Set Terraform [imput variable values](https://learn.hashicorp.com/terraform/getting-started/variables.html#assigning-variables), for example by copying [`terraform.tfvars.example`](terraform.tfvars.example) to `terraform.tfvars` and editing it. See `inputs.tf` for all variables and documentation. If you do not set variables, Terraform will ask you for the required ones on every run.

Start the deployment:

```
nix-shell --run 'terraform apply'
```

Read the plan and accept it if you are satisfied. When the deployment is done, read the outputs and rejoice.

Connect to a server and run some commands:

```
ssh root@<node-ip-or-fqdn> -i SECRET/private_key 'ipfs-cluster-ctl peers ls'
```

When you're done, don't forget to destroy the cloud resources so as not to waste power and money:

```
nix-shell --run 'terraform destroy'
```


### Develop

Start the deployment shell to see a list of available commands:

```
nix-shell
```


### What? Where?

- infrastructure
  - [`main.tf`](main.tf) defines global cloud resources
  - [`regions.tf`](regions.tf) instantiates resources per region
  - [`ipfs-cluster-aws-region/main.tf`] defines per-region AWS cloud resources (vpc, sg, acl, ec2, ebs, r53, etc.), ie. a network of cloud servers running NixOS
- operating sysem configuration
  - [`nixos/ipfs-cluster-aws.nix`](nixos/ipfs-cluster-aws.nix) is a NixOS profile for running an `ipfs-cluster` node on AWS EC2 with required services and configuration
  - [`nixos/ipfs-cluster.nix`](nixos/ipfs-cluster.nix) is a NixOS module for configuring and running the `ipfs-cluster` service
- deployment environment
  - [`shell.nix`](shell.nix) is loaded by `nix-shell` and includes dependencies and scripts used for infrastructure deployment
- [`nix/`](nix/) package definitions and dependencies
  - [`sources.json`](nix/sources.json) locations and hashes managed by `niv`


### Security

The Terraform state `terraform.tfstate` contains [sensitive data](https://www.terraform.io/docs/state/sensitive-data.html) such as the cluster secret. The state should be encrypted and may be [stored remotely](https://www.terraform.io/docs/state/remote.html).

If you don't specify a `public_key` variable, a private key without a passphrase is generated and saved to `SECRET/private_key`. For production use, generate a key with passphrase (stored in your keychain), specify this variable and let ssh find the private key, eg. via `.ssh/config`.
