#!/usr/bin/env bash
# Full offline validation suite for infra/. Needs no AWS credentials.
#
#   scripts/test.sh            # everything
#   scripts/test.sh fmt        # one stage: fmt | validate | test | lint | scan | docs
#
# Set TF_CMD to run Terraform some other way, e.g. through Docker:
#   TF_CMD="docker run --rm -v $PWD:/work -w /work hashicorp/terraform:1.13.5" scripts/test.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

TF_CMD="${TF_CMD:-terraform}"
TFLINT_CMD="${TFLINT_CMD:-tflint}"
CHECKOV_CMD="${CHECKOV_CMD:-checkov}"
TFDOCS_CMD="${TFDOCS_CMD:-terraform-docs}"
# Config path as seen by tflint (differs when tflint runs in a container).
TFLINT_CONFIG="${TFLINT_CONFIG:-$root/.tflint.hcl}"

modules=(network security database edge platform observability dr-backup)
# dr-backup requires an aliased provider (aws.dr) supplied by its caller, so it
# cannot be validated standalone; stack validation and its own tests cover it.
standalone_modules=(network security database edge platform observability)
roots=(stack bootstrap)
environments=(dev test lifetime prod)
stage="${1:-all}"
failures=0

tf() { $TF_CMD "$@"; }
section() { printf '\n==> %s\n' "$*"; }
run_stage() { [[ "$stage" == "all" || "$stage" == "$1" ]]; }
have() { command -v "${1%% *}" >/dev/null 2>&1; }

if run_stage fmt; then
  section "terraform fmt -check"
  tf fmt -check -recursive -diff || failures=$((failures + 1))
fi

if run_stage validate || run_stage test; then
  section "terraform init (no backend)"
  for dir in "${roots[@]}" "${modules[@]/#/modules/}"; do
    tf -chdir="$dir" init -backend=false -input=false -no-color >/dev/null
  done
fi

if run_stage validate; then
  section "terraform validate"
  for dir in "${roots[@]}" "${standalone_modules[@]/#/modules/}"; do
    printf '%-28s' "$dir"
    tf -chdir="$dir" validate -no-color || failures=$((failures + 1))
  done
fi

if run_stage test; then
  section "terraform test: modules"
  for dir in bootstrap "${modules[@]/#/modules/}"; do
    echo "--- $dir"
    tf -chdir="$dir" test -no-color || failures=$((failures + 1))
  done

  section "terraform test: stack per environment"
  for env in "${environments[@]}"; do
    echo "--- stack ($env)"
    tf -chdir=stack test -no-color -var-file="../envs/$env/terraform.tfvars" || failures=$((failures + 1))
  done
fi

if run_stage lint; then
  section "tflint"
  if have "$TFLINT_CMD"; then
    if $TFLINT_CMD --init --config "$TFLINT_CONFIG" >/dev/null; then
      $TFLINT_CMD --recursive --config "$TFLINT_CONFIG" || failures=$((failures + 1))
    else
      echo "tflint --init failed"; failures=$((failures + 1))
    fi
  else
    echo "tflint not found; skipped (set TFLINT_CMD or install tflint)"
  fi
fi

if run_stage scan; then
  section "checkov"
  if have "$CHECKOV_CMD"; then
    $CHECKOV_CMD -d . --framework terraform --config-file .checkov.yaml --compact --quiet || failures=$((failures + 1))
  else
    echo "checkov not found; skipped (set CHECKOV_CMD or pip install checkov)"
  fi
fi

if run_stage docs; then
  section "terraform-docs up to date"
  if have "$TFDOCS_CMD"; then
    for m in "${modules[@]}"; do
      $TFDOCS_CMD --config .terraform-docs.yml --output-check "modules/$m" >/dev/null ||
        { echo "modules/$m/README.md is stale: run 'make docs'"; failures=$((failures + 1)); }
    done
  else
    echo "terraform-docs not found; skipped (set TFDOCS_CMD or install terraform-docs)"
  fi
fi

echo
if [[ $failures -gt 0 ]]; then
  echo "FAILED: $failures check(s) failed"
  exit 1
fi
echo "All checks passed"
