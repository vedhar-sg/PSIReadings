locals {
  default_tags = merge(var.tags, {
    Application = "OutSystems11"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

provider "aws" {
  region              = var.region
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = local.default_tags
  }
}

# Disaster-recovery region (cross-region backup copies).
provider "aws" {
  alias               = "dr"
  region              = var.dr_region
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = local.default_tags
  }
}
