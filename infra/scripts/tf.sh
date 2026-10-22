#!/usr/bin/env bash
# Run Terraform for one OutSystems environment against the shared stack.
#
#   scripts/tf.sh <dev|test|prod|lifetime> <terraform command> [args...]
#
# Each environment gets its own TF_DATA_DIR, so switching environments never
# re-points an initialised backend at the wrong state file.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <dev|test|prod|lifetime> <terraform command> [args...]" >&2
  exit 2
fi

env_name="$1"; shift
cmd="$1"; shift

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_dir="$root/envs/$env_name"

if [[ ! -f "$env_dir/terraform.tfvars" || ! -f "$env_dir/backend.hcl" ]]; then
  echo "unknown environment '$env_name' (expected envs/$env_name/{backend.hcl,terraform.tfvars})" >&2
  exit 2
fi

# The state key must name the same environment as the tfvars.
if ! grep -Eq "^key[[:space:]]*=[[:space:]]*\"outsystems/$env_name/" "$env_dir/backend.hcl"; then
  echo "envs/$env_name/backend.hcl key does not point at outsystems/$env_name/; refusing to run" >&2
  exit 2
fi

export TF_DATA_DIR="$root/stack/.terraform-$env_name"

case "$cmd" in
  init)
    exec terraform -chdir="$root/stack" init -backend-config="$env_dir/backend.hcl" "$@" ;;
  plan|apply|destroy|import|refresh|console)
    exec terraform -chdir="$root/stack" "$cmd" -var-file="$env_dir/terraform.tfvars" "$@" ;;
  *)
    exec terraform -chdir="$root/stack" "$cmd" "$@" ;;
esac
