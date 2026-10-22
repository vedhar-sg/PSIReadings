<#
.SYNOPSIS
  Run Terraform for one OutSystems environment against the shared stack.

.EXAMPLE
  .\scripts\tf.ps1 dev init
  .\scripts\tf.ps1 dev plan -out dev.tfplan
  .\scripts\tf.ps1 dev apply dev.tfplan

  Each environment gets its own TF_DATA_DIR, so switching environments never
  re-points an initialised backend at the wrong state file.
#>
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('dev', 'test', 'prod', 'lifetime')]
  [string] $Environment,

  [Parameter(Mandatory = $true, Position = 1)]
  [string] $Command,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Rest = @()
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envDir = Join-Path $root "envs\$Environment"
$stack = Join-Path $root 'stack'
$backend = Join-Path $envDir 'backend.hcl'
$tfvars = Join-Path $envDir 'terraform.tfvars'

if (-not (Select-String -Path $backend -Pattern "^key\s*=\s*`"outsystems/$Environment/" -Quiet)) {
  throw "envs/$Environment/backend.hcl key does not point at outsystems/$Environment/; refusing to run"
}

$env:TF_DATA_DIR = Join-Path $stack ".terraform-$Environment"

switch ($Command) {
  'init' { & terraform "-chdir=$stack" init "-backend-config=$backend" @Rest }
  { $_ -in 'plan', 'apply', 'destroy', 'import', 'refresh', 'console' } {
    & terraform "-chdir=$stack" $Command "-var-file=$tfvars" @Rest
  }
  default { & terraform "-chdir=$stack" $Command @Rest }
}
exit $LASTEXITCODE
