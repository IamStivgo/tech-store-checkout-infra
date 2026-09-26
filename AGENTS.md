# AGENTS.md

Guidance for AI coding assistants working in this repository.

## Project

Terraform code for the AWS serverless infrastructure of a tech accessories store checkout: CloudFront + S3 (SPA), API Gateway HTTP API + Lambda (API and reconciliation job), DynamoDB, SSM Parameter Store and EventBridge Scheduler, in `us-east-1`. This repository owns all infrastructure; the web and api repositories only deploy their code through OIDC roles created here.

## Structure

- `bootstrap/`: applied once, manually, with administrator credentials. Creates the Terraform state bucket, the GitHub OIDC provider and the `terraform` role.
- `modules/<name>/`: reusable modules (`static-site`, `api`, `database`, `secrets`, `scheduler`, `ci-roles`).
- `envs/prod/`: the only environment; composes the modules.
- `placeholder/`: minimal handler used to create the Lambda functions. The api repository deploys the real code.

## Conventions

- Resource names: `${var.project}-${var.environment}-<resource>` with `project = "checkout-app"`.
- Tags through the provider `default_tags`: `Project`, `Environment`, `ManagedBy = terraform`, `Repository`.
- Every module declares `required_version` and `required_providers` (enforced by tflint).
- Variables and outputs always have `description` and `type`; sensitive values use `sensitive = true`.
- Files per module: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` and `tests/<module>.tftest.hcl` (plan assertions with `mock_provider "aws"`).
- Explain resources in the pull request, not in comments; comments only for non-obvious constraints.

## Security and cost rules (mandatory)

- Never write the name of the company that proposed this exercise anywhere in the repository: code, comments, variables, tags, commit messages, branch names or docs. Refer to it as "payment provider".
- Never commit state files, real `.tfvars`, secrets or real provider URLs. Secret values never go through the normal `value` argument (it stores them in the state): use write-only arguments or create them outside Terraform.
- Least privilege IAM, scoped by resource ARN or name prefix. CI uses OIDC roles; no static AWS keys.
- Lambda functions are created from the placeholder with `ignore_changes` on the code; Terraform owns memory, timeout, environment and permissions.
- Do not add cost traps: no VPC, NAT Gateway, ALB, RDS, WAF, Secrets Manager or provisioned concurrency.
- Do not add CloudFront custom error responses (they would turn API errors into `index.html`).

## Commands

```bash
npm ci                                          # git hooks (Node.js 24)
tflint --init
terraform -chdir=envs/prod init -backend=false
terraform -chdir=envs/prod validate
npm run lint                                    # terraform fmt -check + tflint
npm test                                        # terraform test for bootstrap and modules (mocked provider)
```

CI (`.github/workflows/ci.yml`) runs `terraform fmt -check`, `tflint`, `validate` of `bootstrap` and `envs/prod` (with `-lockfile=readonly`) and the bootstrap and module tests on every pull request and push to `develop` and `main`. Actions are pinned by commit SHA. When a provider version changes, commit the updated `.terraform.lock.hcl` of every root and module.

## Git workflow

- Branches: `main` (stable), `develop` (integration), `feature/HU-xxx-description`.
- Conventional Commits plus the `infra` type, enforced by commitlint; lint-staged runs `terraform fmt` and `tflint` on staged `.tf` files.
- The developer creates branches and commits; assistants propose changes and commit messages.
