# Remote state in S3 + DynamoDB locking.
# Fill in the bucket/table names printed by the bootstrap module, then run:
#   terraform init -migrate-state
terraform {
  backend "s3" {
    # bucket         = "notesops-tfstate-<YOUR_ACCOUNT_ID>"   # from bootstrap output
    # key            = "platform/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "notesops-tflock"
    # encrypt        = true
  }
}
