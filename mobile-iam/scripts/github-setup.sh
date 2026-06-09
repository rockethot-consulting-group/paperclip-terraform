#!/usr/bin/env bash
# Wire GitHub repo secrets + Environment after Terraform has been applied.
# Run AFTER:
#   1. mobile-iam Terraform applied (apply.sh)
#   2. rockethot/rockethot-mobile-monorepo exists (ROC-718 done)
# ROC-719
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"
REPO="rockethot/rockethot-mobile-monorepo"
ENVIRONMENT="mobile-release"

# ---- Resolve role ARNs from Terraform outputs ----
cd "$MODULE_DIR"

echo "==> Reading role ARNs from Terraform state..."
MOBILE_CI_ARN=$(terraform output -raw mobile_ci_role_arn 2>/dev/null) || {
  echo "ERROR: could not read mobile_ci_role_arn. Has Terraform been applied? (apply.sh)"
  exit 1
}
MOBILE_RELEASE_ARN=$(terraform output -raw mobile_release_role_arn 2>/dev/null) || {
  echo "ERROR: could not read mobile_release_role_arn. Has Terraform been applied? (apply.sh)"
  exit 1
}

echo "    mobile-ci ARN:      $MOBILE_CI_ARN"
echo "    mobile-release ARN: $MOBILE_RELEASE_ARN"

# ---- Verify repo exists ----
echo ""
echo "==> Checking repo $REPO..."
gh repo view "$REPO" --json name --jq '.name' > /dev/null || {
  echo "ERROR: $REPO does not exist yet. Complete ROC-718 first."
  exit 1
}

# ---- Resolve CTO + SecurityEngineer GitHub user IDs ----
# Adjust these usernames to match the actual GitHub accounts.
CTO_USER="${CTO_GITHUB_USER:-}"
SE_USER="${SE_GITHUB_USER:-}"

if [[ -z "$CTO_USER" || -z "$SE_USER" ]]; then
  echo ""
  echo "ERROR: CTO_GITHUB_USER and SE_GITHUB_USER env vars must be set."
  echo "  export CTO_GITHUB_USER=<github-username>"
  echo "  export SE_GITHUB_USER=<github-username>"
  exit 1
fi

CTO_ID=$(gh api "users/$CTO_USER" --jq '.id')
SE_ID=$(gh api "users/$SE_USER" --jq '.id')
echo "    CTO GitHub user ID:              $CTO_ID ($CTO_USER)"
echo "    SecurityEngineer GitHub user ID: $SE_ID ($SE_USER)"

# ---- Repo-level secret: AWS_OIDC_ROLE_ARN_MOBILE_CI ----
echo ""
echo "==> Setting repo secret AWS_OIDC_ROLE_ARN_MOBILE_CI..."
gh secret set AWS_OIDC_ROLE_ARN_MOBILE_CI \
  --repo "$REPO" \
  --body "$MOBILE_CI_ARN"
echo "    Set."

# ---- Create GitHub Environment: mobile-release ----
echo ""
echo "==> Creating GitHub Environment '$ENVIRONMENT' with required reviewers..."
gh api \
  --method PUT \
  "repos/$REPO/environments/$ENVIRONMENT" \
  --field "wait_timer=0" \
  --field "reviewers[][type]=User" \
  --field "reviewers[][id]=$CTO_ID" \
  --field "reviewers[][type]=User" \
  --field "reviewers[][id]=$SE_ID" \
  --field "deployment_branch_policy=null" \
  --silent
echo "    Environment created with CTO ($CTO_USER) + SecurityEngineer ($SE_USER) as required reviewers."

# ---- Environment secret: AWS_OIDC_ROLE_ARN_MOBILE_RELEASE ----
echo ""
echo "==> Setting environment secret AWS_OIDC_ROLE_ARN_MOBILE_RELEASE..."
gh secret set AWS_OIDC_ROLE_ARN_MOBILE_RELEASE \
  --repo "$REPO" \
  --env "$ENVIRONMENT" \
  --body "$MOBILE_RELEASE_ARN"
echo "    Set."

echo ""
echo "==> Complete. Summary:"
echo "    Repo secret:    AWS_OIDC_ROLE_ARN_MOBILE_CI       = $MOBILE_CI_ARN"
echo "    Environment:    $ENVIRONMENT (reviewers: $CTO_USER, $SE_USER)"
echo "    Env secret:     AWS_OIDC_ROLE_ARN_MOBILE_RELEASE  = $MOBILE_RELEASE_ARN"
echo ""
echo "==> ROC-719 items 10-12 complete."
