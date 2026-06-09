#!/usr/bin/env bash
# Apply the mobile-iam Terraform module.
# Creates IAM roles mobile-ci and mobile-release for GitHub Actions OIDC.
# Run from: paperclip-terraform/mobile-iam/
# Prerequisite: AWS credentials with iam:CreateRole, iam:PutRolePolicy, and
#               iam:GetOpenIDConnectProvider (to reference the existing GitHub IdP).
# ROC-719
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"

cd "$MODULE_DIR"

echo "==> Verifying AWS identity..."
aws sts get-caller-identity

echo ""
echo "==> Verifying existing GitHub OIDC IdP..."
aws iam list-open-id-connect-providers | \
  grep -q "token.actions.githubusercontent.com" || {
    echo "ERROR: GitHub OIDC IdP not found in this account."
    echo "The IdP must already exist — this module reuses it, it does not create one."
    exit 1
  }
echo "    OIDC IdP found."

echo ""
echo "==> Initialising Terraform..."
terraform init

echo ""
echo "==> Planning..."
terraform plan -out=tfplan

echo ""
echo "==> Apply? (ctrl-c to abort)"
read -r -p "Press ENTER to apply... "
terraform apply tfplan

echo ""
echo "==> Done. Role ARNs:"
terraform output -json | jq -r 'to_entries[] | "    \(.key): \(.value.value)"'

echo ""
echo "==> Next step: run github-setup.sh once rockethot/rockethot-mobile-monorepo exists (ROC-718)."
