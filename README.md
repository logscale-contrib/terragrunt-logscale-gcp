# terragrunt-logscale-gcp

## Requirements

* Terragrunt <https://terragrunt.gruntwork.io/docs/getting-started/install/>
* Terraform >=1.5.1
* GCP bucket with versioning enabled for terraform state

Login to GCP

```bash
gcloud auth application-default login
```

Review and update prod/*/*.hcl update as needed

```
cd prod
terragrunt run-all apply --terragrunt-non-interactive
``

## DR Process

### Site Switch


*
