# Remote state for the prod environment (bucket in the prod account). Replace the bucket with the
# bootstrap output "state_bucket". No credentials belong in this file.
bucket       = "REPLACE-ME-outsystems-prod-tfstate"
key          = "outsystems/prod/terraform.tfstate"
region       = "ap-southeast-1"
encrypt      = true
use_lockfile = true

# Legacy DynamoDB locking instead (only if created in bootstrap):
# dynamodb_table = "REPLACE-ME-outsystems-prod-tfstate-lock"
