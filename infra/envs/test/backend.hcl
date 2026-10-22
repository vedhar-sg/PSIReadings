# Remote state for the test environment. Replace the bucket with the
# bootstrap output "state_bucket". No credentials belong in this file.
bucket       = "REPLACE-ME-outsystems-tfstate"
key          = "outsystems/test/terraform.tfstate"
region       = "ap-southeast-1"
encrypt      = true
use_lockfile = true

# Legacy DynamoDB locking instead (only if created in bootstrap):
# dynamodb_table = "REPLACE-ME-outsystems-tfstate-lock"
