

# Set account-wide variables. These are automatically pulled in to configure the remote state bucket in the root
# terragrunt.hcl configuration.
locals {
  region     = "us-central1"
  project_id = "logsr-life-production"
}