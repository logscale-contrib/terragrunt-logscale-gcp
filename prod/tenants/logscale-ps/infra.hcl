# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  codename    = ""
  environment = "prod"
  geo         = "us"

  #values are "none","pre",bootstrap,ui,inputs
  recover_mode         = "none"
  active_cluster       = "2"
  active_bucket        = "1"
  recoverFromReplaceID = ""
  recoverFromBucketID  = ""
  prefix               = "1"
  one                  = "1"
  two                  = "2"
}