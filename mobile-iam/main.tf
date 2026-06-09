# mobile-iam/main.tf
# ROC-719: OIDC IAM roles for rockethot/rockethot-mobile-monorepo CI/CD
#
# Reuses the existing token.actions.githubusercontent.com OIDC IdP.
# Do not create a new IdP — reference it here via data source.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---- Data Sources ----

# Reference the existing GitHub OIDC IdP — do not create a second one.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_caller_identity" "current" {}

# ---- Trust policies ----

# Shared trust for CI builds: all refs in rockethot-mobile-monorepo.
# Used by mobile-ci only. mobile-release uses the tighter environment-scoped trust below.
data "aws_iam_policy_document" "mobile_ci_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:rockethot/rockethot-mobile-monorepo:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Release trust scoped to the mobile-release GitHub Environment subject.
# This is tighter than the issue spec's wildcard: when the workflow runs under
# the mobile-release environment (which carries the required-reviewer gate), the
# OIDC sub claim is exactly this value. Using StringEquals here ensures the
# prod-scoped role cannot be assumed by any branch run that bypasses the gate.
data "aws_iam_policy_document" "mobile_release_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:rockethot/rockethot-mobile-monorepo:environment:mobile-release"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ---- IAM Role: mobile-ci ----
# Grants CI builds read access to /rockethot/ci/mobile/* secrets only.

resource "aws_iam_role" "mobile_ci" {
  name               = "mobile-ci"
  assume_role_policy = data.aws_iam_policy_document.mobile_ci_trust.json

  tags = {
    ManagedBy   = "terraform"
    IssueRef    = "ROC-719"
    Purpose     = "GitHub Actions OIDC — rockethot-mobile-monorepo CI builds"
  }
}

data "aws_iam_policy_document" "mobile_ci_secrets" {
  statement {
    sid     = "ReadCIMobileSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    # Scoped to CI secrets prefix only — no wildcard account (uses actual account ID)
    resources = [
      "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:/rockethot/ci/mobile/*"
    ]
  }
}

resource "aws_iam_role_policy" "mobile_ci_secrets" {
  name   = "mobile-ci-secrets"
  role   = aws_iam_role.mobile_ci.id
  policy = data.aws_iam_policy_document.mobile_ci_secrets.json
}

# ---- IAM Role: mobile-release ----
# Grants release workflow read access to /rockethot/prod/mobile/* secrets only.
# Trust is env-scoped — see mobile_release_trust comment above.

resource "aws_iam_role" "mobile_release" {
  name               = "mobile-release"
  assume_role_policy = data.aws_iam_policy_document.mobile_release_trust.json

  tags = {
    ManagedBy   = "terraform"
    IssueRef    = "ROC-719"
    Purpose     = "GitHub Actions OIDC — rockethot-mobile-monorepo release builds (mobile-release env)"
  }
}

data "aws_iam_policy_document" "mobile_release_secrets" {
  statement {
    sid     = "ReadProdMobileSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:/rockethot/prod/mobile/*"
    ]
  }
}

resource "aws_iam_role_policy" "mobile_release_secrets" {
  name   = "mobile-release-secrets"
  role   = aws_iam_role.mobile_release.id
  policy = data.aws_iam_policy_document.mobile_release_secrets.json
}
