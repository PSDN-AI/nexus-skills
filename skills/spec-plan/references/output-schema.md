# Output Schema: tasks.yaml

Detailed field specification for the `tasks.yaml` output format.

## Table of Contents

- [Top-Level Fields](#top-level-fields)
- [Task Fields](#task-fields)
- [Execution Plan Fields](#execution-plan-fields)
- [Validation Fields](#validation-fields)
- [Task ID Convention](#task-id-convention)
- [Complexity Levels](#complexity-levels)

## Top-Level Fields

```yaml
version: "0.1.0"              # Schema version (required)
domain: "frontend"             # Domain name matching the source folder (required)
generated_at: "ISO-8601"       # Timestamp of generation (required)
generated_from:                # Source traceability (required)
  spec: "frontend/spec.md"    # Path to source spec
  boundary: "frontend/boundary.yaml"  # Path to boundary file
  contracts: []                # List of contract files consulted
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | string | yes | Schema version, currently `"0.1.0"` |
| `domain` | string | yes | Domain name, must match source directory name |
| `generated_at` | string | yes | ISO 8601 timestamp |
| `generated_from.spec` | string | yes | Relative path to the spec file |
| `generated_from.boundary` | string | yes | Relative path to boundary file |
| `generated_from.contracts` | list | yes | Contract files used (empty list if none) |

## Task Fields

Each entry in the `tasks` list represents one discrete work unit.

```yaml
tasks:
  - id: FE-001                    # Unique task identifier (required)
    name: "Project scaffolding"   # Human-readable name (required)
    depends_on: []                # Task IDs this task depends on (required)
    estimated_complexity: low     # low | medium | high (required)
    files_touched:                # Files this task will create/modify (required)
      - "package.json"
      - "src/main.tsx"
    acceptance_criteria:          # AC IDs from boundary.yaml (required)
      - AC-001
    prompt_context: |             # Self-contained context for sub-agent (required)
      Instructions for the agent implementing this task...
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Format: `PREFIX-NNN` (e.g., FE-001, BE-002) |
| `name` | string | yes | Concise description of the work unit |
| `depends_on` | list | yes | Task IDs that must complete first. Empty list `[]` for root tasks |
| `estimated_complexity` | string | yes | One of: `low`, `medium`, `high` |
| `files_touched` | list | yes | Files the task will create or modify |
| `acceptance_criteria` | list | yes | AC IDs from boundary.yaml that this task satisfies |
| `prompt_context` | string | yes | Self-contained instructions for the implementing agent |

### files_touched Rules

- Must list every file the task will create or modify
- Be conservative: false negatives cause merge conflicts in parallel execution
- Use relative paths from the target repository root
- Directories can be listed with trailing `/` for broad scope (e.g., `prisma/migrations/`)
- Two tasks in the same parallel phase must have **zero overlap** in files_touched

### prompt_context Rules

- Must be self-contained: the implementing agent reads only this field, not the full spec
- Include all relevant requirements, constraints, and technical details
- Reference specific technologies, libraries, and patterns to use
- Do not reference other tasks or assume context from other tasks
- Keep under 500 words per task

## Execution Plan Fields

The `execution_plan` defines the order and parallelization of tasks.

```yaml
execution_plan:
  - phase: 1                        # Phase number, sequential (required)
    tasks:                           # Task IDs in this phase (required)
      - FE-001
    parallel: false                  # Whether tasks run in parallel (required)
    reason: "Scaffolding first"      # Justification for ordering (required)
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `phase` | integer | yes | Phase number, starting from 1, sequential |
| `tasks` | list | yes | Task IDs to execute in this phase |
| `parallel` | boolean | yes | `true` if tasks can run simultaneously |
| `reason` | string | yes | Human-readable justification for phase ordering |

### Parallelization Rules

- `parallel: true` requires that all tasks in the phase have zero overlap in `files_touched`
- `parallel: false` for single-task phases or when file overlap exists
- All `depends_on` must be satisfied by earlier phases
- Every task must appear in exactly one phase

## Validation Fields

The `validation` section provides a machine-readable summary for downstream tools.

```yaml
validation:
  total_tasks: 6                    # Count of tasks (required)
  total_phases: 4                   # Count of execution phases (required)
  parallelizable_tasks: 3           # Tasks in parallel phases (required)
  acceptance_criteria_mapped: 9     # ACs assigned to tasks (required)
  acceptance_criteria_unmapped: 1   # ACs not assigned (required)
  unmapped_criteria:                # List of unmapped AC IDs (required)
    - AC-010
  files_conflict_check: pass        # pass | fail (required)
  spec_coverage: "95%"              # Percentage of spec covered (required)
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `total_tasks` | integer | yes | Total number of tasks |
| `total_phases` | integer | yes | Total number of execution phases |
| `parallelizable_tasks` | integer | yes | Tasks in phases with `parallel: true` |
| `acceptance_criteria_mapped` | integer | yes | ACs assigned to at least one task |
| `acceptance_criteria_unmapped` | integer | yes | ACs not assigned to any task |
| `unmapped_criteria` | list | yes | IDs of unmapped ACs (empty list if all mapped) |
| `files_conflict_check` | string | yes | `pass` or `fail` |
| `spec_coverage` | string | yes | Percentage of spec requirements covered |

## Task ID Convention

Task IDs use a domain prefix to prevent collisions when multiple domains are planned concurrently:

| Domain | Prefix | Example |
|--------|--------|---------|
| Frontend | FE | FE-001, FE-002 |
| Backend | BE | BE-001, BE-002 |
| Infrastructure | INFRA | INFRA-001, INFRA-002 |
| DevOps | DEVOPS | DEVOPS-001 |
| Security | SEC | SEC-001 |
| Data | DATA | DATA-001 |
| Web3 | WEB3 | WEB3-001 |

IDs are sequential within each domain, starting at 001.

## Complexity Levels

| Level | Guideline | Typical Scope |
|-------|-----------|---------------|
| `low` | 1-3 files, < 100 LOC, straightforward | Config, scaffolding, simple CRUD |
| `medium` | 3-8 files, 100-500 LOC, moderate logic | Feature pages, API endpoints, modules |
| `high` | 5+ files, 500+ LOC, complex logic | Payment integration, auth systems, complex state |
