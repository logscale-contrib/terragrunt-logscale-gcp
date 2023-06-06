# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  codename    = ""
  environment = "prod"
  geo         = "us"

  #values are "none",bootstrap,ui,inputs
  recover_mode   = "none"
  active_cluster = "1"
  active_bucket  = "1"
  recover_bucket_id = ""
  prefix         = "1"
  one            = "1"
  two            = "2"
}