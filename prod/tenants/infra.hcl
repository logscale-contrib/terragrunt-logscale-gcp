# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  codename    = ""
  environment = "prod"
  geo         = "us"

  active = "1"
  prefix = "1"
  one    = "1"
  two    = "2"
}