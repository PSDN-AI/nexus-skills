# Output Schema

Detailed specification for the prd-decomposer output format.

## Table of Contents

- [meta.yaml](#metayaml)
- [Domain spec.md](#domain-specmd)
- [Domain boundary.yaml](#domain-boundaryyaml)
- [Domain config.yaml](#domain-configyaml)
- [Contracts](#contracts)
- [Dependency Graph](#dependency-graph)

## meta.yaml

Top-level project metadata generated at the output root.

```yaml
project:
  name: "{extracted from PRD title}"
  prd_source: "{filename}"
  generated_at: "{ISO 8601 timestamp}"
  generator: "prd-decomposer@0.1.0"

decomposition:
  total_sections: {N}
  domains_identified: [frontend, backend, ...]
  uncategorized_sections: {N}
  cross_domain_contracts: {N}

completeness:
  coverage_percent: {0-100}
  ambiguity_flags: {N}
  missing_info_flags: {N}
```

## Domain spec.md

Each domain folder contains a `spec.md` with extracted requirements.

```markdown
# {Domain Name} Specification

> Extracted from: {PRD title}
> Generated: {timestamp}
> Source sections: {list of PRD section headings}

## Overview
[GENERATED] {summary of what this domain needs to implement}

## Requirements
[EXTRACTED] {extracted requirements relevant to this domain}

## Technical Details
[EXTRACTED] {extracted technical details, architecture notes}

## Dependencies
[GENERATED] {list of dependencies on other domains, with references}

## Open Questions
[GENERATED] {any ambiguities or missing information detected}
```

Content marked `[EXTRACTED]` is quoted verbatim from the PRD. Content marked `[GENERATED]` is synthesized by the decomposer.

## Domain boundary.yaml

Acceptance criteria and constraints for each domain.

```yaml
domain: {domain_name}
generated_from: {prd_filename}
generated_at: {timestamp}

acceptance_criteria:
  - id: AC-001
    description: "{extracted criterion}"
    source_section: "{PRD section heading}"
    priority: P0|P1|P2

constraints:
  - type: performance|security|compatibility|scalability
    description: "{extracted constraint}"

test_hints:
  - scenario: "{what to test}"
    expected: "{expected outcome}"
```

Priority mapping:
- **P0**: Keywords "must", "shall", "required", "mandatory"
- **P1**: Keywords "should", "recommended", "expected"
- **P2**: Keywords "may", "nice-to-have", "optional", "consider"

## Domain config.yaml

Agent configuration template. Human fills in deployment-specific values.

```yaml
domain: {domain_name}
target_repo: ""
target_branch: ""
pr_template: "default"
agent_model: ""
max_iterations: 3
review_required: true
```

## Contracts

### api-contracts.yaml

```yaml
contracts:
  - name: "{contract name}"
    provider: {domain}
    consumers: [{domain}, ...]
    source_section: "{PRD section heading}"
    endpoints:
      - method: GET|POST|PUT|DELETE
        path: /api/v1/...
        description: "{extracted from PRD}"
    status: draft
```

### data-contracts.yaml

```yaml
contracts:
  - name: "{contract name}"
    provider: {domain}
    consumers: [{domain}, ...]
    source_section: "{PRD section heading}"
    schemas:
      - name: "{schema name}"
        description: "{extracted from PRD}"
    status: draft
```

### infra-requirements.yaml

```yaml
requirements:
  - name: "{requirement name}"
    requester: {domain}
    source_section: "{PRD section heading}"
    resources:
      - type: compute|storage|network|cache
        description: "{extracted from PRD}"
    status: draft
```

## Dependency Graph

`contracts/dependency-graph.md` contains a Mermaid diagram:

```markdown
# Dependency Graph

\`\`\`mermaid
graph LR
    FE[Frontend] -->|API calls| BE[Backend]
    BE -->|queries| DATA[Data]
    BE -->|deploys on| INFRA[Infrastructure]
    DEVOPS -->|builds| FE
    DEVOPS -->|builds| BE
    SEC[Security] -.->|audits| BE
    SEC -.->|audits| INFRA
\`\`\`

## Dependencies Detail

| From | To | Contract | Type |
|------|-----|----------|------|
| Frontend | Backend | api-contracts.yaml | runtime |
| Backend | Data | data-contracts.yaml | runtime |
| Backend | Infra | infra-requirements.yaml | deploy-time |
```
