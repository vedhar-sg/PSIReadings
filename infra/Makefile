# Task runner for the OutSystems 11 AWS infrastructure.
#
#   make help
#   make plan ENV=dev
#
# Every target that touches AWS goes through scripts/tf.sh, which pairs
# envs/$(ENV)/backend.hcl with envs/$(ENV)/terraform.tfvars and keeps a
# separate .terraform directory per environment.

ENV       ?= dev
PLAN_FILE ?= $(ENV).tfplan
TF        := scripts/tf.sh $(ENV)

.DEFAULT_GOAL := help
.PHONY: help init plan apply plan-destroy output fmt validate test lint scan docs check lock bootstrap-plan bootstrap-apply clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo "\n  ENV=$(ENV)  (dev | test | lifetime | prod)"

# --- Environment lifecycle (needs AWS credentials) ---------------------------

init: ## Initialise the backend for ENV
	$(TF) init

plan: ## Plan ENV into $(PLAN_FILE)
	$(TF) plan -out=$(PLAN_FILE)

apply: ## Apply the saved plan $(PLAN_FILE) (never applies an unreviewed plan)
	@test -f stack/$(PLAN_FILE) || { echo "stack/$(PLAN_FILE) not found: run 'make plan ENV=$(ENV)' first"; exit 1; }
	$(TF) apply $(PLAN_FILE)

plan-destroy: ## Plan destruction of ENV into $(ENV)-destroy.tfplan
	$(TF) plan -destroy -out=$(ENV)-destroy.tfplan

output: ## Show outputs for ENV
	$(TF) output

bootstrap-plan: ## Plan the one-off account bootstrap
	terraform -chdir=bootstrap init
	terraform -chdir=bootstrap plan -out=bootstrap.tfplan

bootstrap-apply: ## Apply the reviewed bootstrap plan
	terraform -chdir=bootstrap apply bootstrap.tfplan

# --- Offline validation (no credentials) -------------------------------------

fmt: ## Format all Terraform files
	terraform fmt -recursive

validate: ## terraform validate every root and module
	scripts/test.sh validate

test: ## terraform test: module unit tests + stack tests for every environment
	scripts/test.sh test

lint: ## tflint with the AWS ruleset
	scripts/test.sh lint

scan: ## Checkov security scan
	scripts/test.sh scan

docs: ## Regenerate module READMEs with terraform-docs
	@for m in modules/*/; do terraform-docs --config .terraform-docs.yml $$m; done

check: ## Everything CI runs: fmt, validate, test, lint, scan, docs
	scripts/test.sh

lock: ## Refresh provider lock files for Linux and Windows
	terraform -chdir=stack providers lock -platform=linux_amd64 -platform=windows_amd64 -platform=darwin_arm64
	terraform -chdir=bootstrap providers lock -platform=linux_amd64 -platform=windows_amd64 -platform=darwin_arm64

clean: ## Remove local .terraform directories and plan files
	find . -type d \( -name .terraform -o -name '.terraform-*' \) -prune -exec rm -rf {} +
	find . -name '*.tfplan' -delete
