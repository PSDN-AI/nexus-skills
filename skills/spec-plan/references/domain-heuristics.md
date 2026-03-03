# Domain-Specific Planning Heuristics

Guidance for task decomposition and ordering by domain. These are defaults; override when the spec dictates a different approach.

## Table of Contents

- [Frontend](#frontend)
- [Backend](#backend)
- [Infrastructure](#infrastructure)
- [DevOps](#devops)
- [Security](#security)
- [General Rules](#general-rules)

## Frontend

### Task Ordering

1. **Phase 1: Project scaffolding** — always first. Includes package.json, build config, framework setup, base routing, main entry point.
2. **Phase 2: Shared UI components** — buttons, inputs, modals, navigation, layout primitives. These are dependencies for all page-level tasks.
3. **Phase 3+: Pages and features** — each page is typically one task unless it has 5+ complex sub-features.

### Decomposition Rules

- One page = one task, unless the page has 5+ complex interactive features (e.g., checkout with multi-step forms, real-time collaboration).
- Shared state stores (e.g., Zustand, Redux slices) belong to the task that introduces the primary consumer.
- Hooks that serve multiple pages get their own task or belong to the shared components task.
- Route definitions belong to scaffolding, not individual page tasks.

### Parallelization Patterns

- Pages that don't share components or state can run in parallel.
- Pages that consume the same store can still parallelize if they only read (not write) shared state.
- Form-heavy pages that share validation logic should be sequential or share a validation utilities task.

### Common Pitfalls

- Forgetting to include type definition files in files_touched.
- Shared component index (barrel) files cause conflicts if multiple tasks export from them. Assign the barrel file to the shared components task only.

## Backend

### Task Ordering

1. **Phase 1: Database schema and migrations** — always first. No code can compile without the schema.
2. **Phase 2: Shared middleware and utilities** — auth middleware, error handling, logging, validation helpers.
3. **Phase 3+: API endpoints grouped by resource** — each REST resource (users, products, orders) is typically one task.
4. **Late phases: Integration tasks** — payment processing, email services, third-party API integrations.

### Decomposition Rules

- Database migration is always a standalone Phase 1 task.
- Group API endpoints by resource, not by HTTP method.
- Middleware (auth, rate limiting, CORS) is a separate task if used by multiple resources.
- Background jobs and queue consumers are separate tasks from their API triggers.
- Seed data and test fixtures belong to the database task.

### Parallelization Patterns

- API resources with independent database tables can parallelize.
- Resources that share foreign keys should be ordered (parent before child).
- Service classes that import from each other cannot parallelize.

### Common Pitfalls

- Missing the shared types/interfaces file in files_touched for multiple endpoint tasks.
- Forgetting that ORM model files are shared between migration and API tasks.

## Infrastructure

### Task Ordering

1. **Phase 1: Project scaffolding** — Terraform backend config, provider setup, variable definitions.
2. **Phase 2: Networking** — VPC, subnets, security groups, NAT gateways. Everything else depends on networking.
3. **Phase 3: Compute and storage** — ECS/EKS clusters, RDS databases, S3 buckets. Can parallelize if they only share VPC outputs.
4. **Phase 4: Monitoring and observability** — CloudWatch, dashboards, alarms. Depends on compute and storage resources.

### Decomposition Rules

- Each Terraform module = one task.
- Networking is always the first infrastructure module after scaffolding.
- IAM roles and policies belong to the task that creates the resource needing them.
- DNS and certificate management can parallelize with compute if they don't depend on ALB ARNs.

### Parallelization Patterns

- Compute and database modules can parallelize if they only reference VPC/subnet IDs from networking.
- S3 buckets typically parallelize with everything except the task that configures bucket policies.
- Monitoring must wait for all resources it monitors.

### Common Pitfalls

- Terraform output references create implicit dependencies. Check that module outputs used by other modules are reflected in depends_on.
- State file conflicts when two modules try to modify the same resource.

## DevOps

### Task Ordering

1. **Phase 1: Dockerfile and build configuration** — always first.
2. **Phase 2: CI pipeline** — build, lint, test stages.
3. **Phase 3: CD pipeline** — deployment stages, environment promotion.
4. **Phase 4: Monitoring integration** — deployment notifications, health checks, rollback triggers.

### Decomposition Rules

- Dockerfile setup is Phase 1 because CI/CD pipelines reference it.
- Separate CI (build/test) from CD (deploy) into different tasks.
- Environment-specific configs (staging, production) are part of the CD task.
- Secret management setup is a prerequisite for any task that uses secrets.

### Parallelization Patterns

- CI and CD pipeline definitions can parallelize if they're in separate files.
- Environment configs for staging and production can parallelize.

### Common Pitfalls

- Workflow files that reference shared actions or reusable workflows create hidden dependencies.
- Docker layer caching configuration affects both CI and CD tasks.

## Security

### Task Ordering

1. **Phase 1: Auth setup** — authentication service, identity provider integration. This is a dependency for all backend tasks that require auth.
2. **Phase 2: Secret management** — vault setup, secret rotation. Precedes any service that consumes secrets.
3. **Phase 3: Security hardening** — CORS, CSP, rate limiting, input validation.
4. **Phase 4: Compliance and auditing** — audit logging, compliance checks, penetration test setup.

### Decomposition Rules

- Auth setup is a dependency for backend tasks, not a standalone security-only concern. Coordinate with backend planning.
- Secret management precedes any service that uses secrets (database passwords, API keys, JWT signing keys).
- WAF rules and network policies are separate from application-level security.
- Compliance scanning (SAST, DAST, dependency audit) is a separate task from implementing fixes.

### Parallelization Patterns

- Security hardening tasks (CORS, CSP, rate limiting) can parallelize if they modify different files.
- Compliance scanning can run in parallel with everything — it's read-only.

### Common Pitfalls

- Auth middleware files are shared between security and backend domains. Assign ownership to one domain and add a cross-domain reference for the other.
- Secret management impacts multiple domains. List it as a dependency in the tasks of consuming domains.

## General Rules

These apply across all domains:

1. **Scaffolding is always Phase 1** — project setup, config files, base structure.
2. **Shared utilities precede consumers** — if multiple tasks use the same helper, the helper gets an earlier phase.
3. **Database before code** — schema/migration tasks always precede application code tasks.
4. **Integration tasks come last** — tasks that connect two subsystems depend on both being complete.
5. **Keep tasks to 1-3 files, 100-500 LOC** — if a task exceeds this, consider splitting.
6. **Generated infrastructure tasks** (linting, formatting, CI config) are marked `[GENERATED]` with P2 priority.
