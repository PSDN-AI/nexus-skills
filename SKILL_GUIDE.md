# Skill Authoring Guide

This guide covers everything you need to write a Skill for the Nexus marketplace. It incorporates the [Agent Skills standard](https://agentskills.io/specification) (the open format adopted by 30+ agent products) and Nexus-specific conventions.

Read this once before writing your first Skill. Refer back to the [Pre-Submission Checklist](#pre-submission-checklist) when you're ready to open a PR.

---

## Quick Reference

A Skill is a directory containing a `SKILL.md` file with YAML frontmatter:

```
my-skill/
├── SKILL.md              # Required — frontmatter + instructions
├── scripts/              # Optional — executable code
├── references/           # Optional — detailed documentation
├── assets/               # Optional — templates, images, data files
├── examples/             # Optional — example outputs
└── tests/                # Optional (recommended) — test suite
```

Minimal valid `SKILL.md`:

```yaml
---
name: my-skill
description: Does X and Y. Use when the user needs to Z.
---

# My Skill

Instructions go here.
```

---

## SKILL.md Format

Every `SKILL.md` starts with YAML frontmatter (between `---` delimiters), followed by Markdown content.

### Required Fields

| Field | Constraints |
|-------|-------------|
| `name` | 1-64 chars. Lowercase letters, numbers, hyphens only. No leading/trailing/consecutive hyphens. **Must match the parent directory name.** |
| `description` | 1-1024 chars. Non-empty. Describes what the skill does **and** when to use it. |

### Optional Fields

| Field | Purpose |
|-------|---------|
| `license` | License name or reference to a bundled LICENSE file. |
| `compatibility` | Environment requirements — tools, system packages, network access. Max 500 chars. |
| `metadata` | Arbitrary key-value map for additional info (author, version, tags, etc.). |
| `allowed-tools` | Space-delimited list of pre-approved tools. Experimental — support varies by agent. |

### Full Example

```yaml
---
name: repo-public-readiness
description: "Scans repositories for hardcoded secrets, API keys, credentials, PII, Web3 private keys, code quality issues, missing documentation, and compliance problems before making them public. Use when preparing to open-source a private repo, auditing a codebase for accidentally committed secrets, or running a pre-release security and compliance checklist."
license: MIT
compatibility: "Requires bash 4.0+, grep, find, file, wc, du, stat. Optional: gitleaks, shellcheck, trivy, jq for enhanced checks."
metadata:
  author: PSDN-AI
  version: "1.0.0"
---
```

### Name Rules

Valid:
- `pdf-processing`
- `repo-public-readiness`
- `code-review`

Invalid:
- `PDF-Processing` (uppercase)
- `-pdf` (leading hyphen)
- `pdf--processing` (consecutive hyphens)
- `my_skill` (underscores)

The `name` must match the directory name exactly. If your directory is `skills/deploy-checker/`, the name must be `deploy-checker`.

---

## Writing Good Descriptions

The `description` field is how agents decide whether to activate your Skill. When an agent starts up, it loads the `name` and `description` from every available Skill (~100 tokens each). When a user asks a question, the agent matches it against these descriptions.

### Rules

1. **Write in third person.** The description is injected into the agent's system prompt.
   - Good: "Scans repositories for secrets and compliance issues."
   - Bad: "I can help you scan repositories."
   - Bad: "Use this to scan repositories."

2. **Include what it does AND when to use it.**
   - Good: "Extracts text and tables from PDF files, fills forms, merges documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction."
   - Bad: "Helps with PDFs."

3. **Include specific keywords** that an agent can match against a user's request. Think: what would someone type that should trigger this Skill?

4. **Keep it under 1024 characters.** One to three sentences is typical.

---

## Progressive Disclosure

Agent products load Skills in three stages:

1. **Startup** — Only `name` + `description` from frontmatter (~100 tokens per Skill)
2. **Activation** — Full `SKILL.md` body is read into context
3. **On demand** — Referenced files (`references/`, `scripts/`, `assets/`) loaded as needed

This means:
- **SKILL.md should be under 500 lines.** Everything loaded at activation competes with conversation history for context window space.
- **Move detailed reference material to separate files.** The agent reads them only when needed.
- **Keep file references one level deep.** Don't chain: SKILL.md → advanced.md → details.md. Instead, link all reference files directly from SKILL.md.

### When to Split

If your SKILL.md is approaching 500 lines, extract content into `references/`:

```
my-skill/
├── SKILL.md                    # Overview, quick start, key instructions
└── references/
    ├── DETAILED_SPEC.md        # Full technical specification
    ├── REPORT_FORMAT.md        # Output format details
    └── API_REFERENCE.md        # API documentation
```

Reference them from SKILL.md:

```markdown
## Detailed Specification

See [references/DETAILED_SPEC.md](references/DETAILED_SPEC.md) for the full check-by-check specification.
```

### Table of Contents for Long Files

If any file exceeds 100 lines, add a table of contents at the top. This helps agents preview the scope before reading the full content.

---

## Writing Instructions

The Markdown body after frontmatter contains instructions for the agent. There are no format restrictions — write whatever helps agents perform the task.

### Be Concise

Agents are already smart. Only add context they don't already have.

Good (concise):
````markdown
## Extract PDF text

Use pdfplumber for text extraction:

```python
import pdfplumber

with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```
````

Bad (over-explains):
```markdown
## Extract PDF text

PDF (Portable Document Format) files are a common file format that contains
text, images, and other content. To extract text from a PDF, you'll need to
use a library. There are many libraries available for PDF processing, but
pdfplumber is recommended because...
```

### Set Appropriate Degrees of Freedom

Match specificity to how fragile the task is.

**High freedom** — multiple valid approaches, context-dependent:
```markdown
## Code review process
1. Analyze the code structure
2. Check for potential bugs or edge cases
3. Suggest improvements for readability
```

**Low freedom** — fragile operations, exact sequence matters:
````markdown
## Database migration

Run exactly this script:
```bash
python scripts/migrate.py --verify --backup
```

Do not modify the command or add additional flags.
````

### Use Workflows for Multi-Step Tasks

Break complex operations into numbered steps. For particularly complex workflows, provide a checklist the agent can track:

````markdown
## Scan workflow

```
Progress:
- [ ] Step 1: Run security checks
- [ ] Step 2: Run code quality checks
- [ ] Step 3: Run documentation checks
- [ ] Step 4: Generate report
- [ ] Step 5: Verify report completeness
```
````

### Include Validation and Feedback Loops

For tasks where output quality matters, include a validate-fix-repeat pattern:

```markdown
## Editing workflow
1. Make your edits
2. Run validation: `python scripts/validate.py`
3. If validation fails — fix the issues and re-run
4. Only proceed when validation passes
```

---

## Scripts

The `scripts/` directory contains executable code agents can run. Scripts are optional — a Skill can be purely instruction-based.

### When to Include Scripts

- The task involves deterministic operations (scanning, validation, formatting)
- Consistency matters more than flexibility
- The operation is error-prone when done manually

### Script Best Practices

1. **Handle errors explicitly.** Don't let scripts fail silently or punt errors to the agent.

2. **Document dependencies.** List required tools in SKILL.md's Prerequisites section and in the `compatibility` frontmatter field.

3. **Degrade gracefully.** If an optional tool is missing, report as SKIPPED — don't fail the entire operation.

4. **Accept paths as arguments.** No hardcoded paths.

5. **Use portable tools.** Prefer tools available on both macOS and Linux. Stick to POSIX utilities (`grep`, `find`, `file`) for core functionality.

6. **Run `shellcheck` on all bash scripts** before submitting.

7. **Make execution intent clear** in SKILL.md:
   - Execute: "Run `scripts/scan.sh` to perform the check"
   - Read as reference: "See `scripts/scan.sh` for the detection algorithm"

---

## Nexus-Specific Conventions

These conventions go beyond the Agent Skills standard and are specific to this repository.

### metadata.yaml

Each Skill should include a `metadata.yaml` alongside `SKILL.md`. This is a Nexus extension (not part of the Agent Skills standard) used by our catalog tooling:

```yaml
name: my-skill
version: 1.0.0
description: "Same one-liner as the SKILL.md frontmatter description"
author: PSDN-AI
license: MIT

tags:
  - category (e.g., security, infrastructure, ci-cd)
  - technology (e.g., aws, terraform, github-actions)

complexity: beginner | intermediate | advanced

inputs:
  - name: target_path
    type: string
    description: "What the user provides"
    required: true

outputs:
  - name: report
    type: file
    description: "What the Skill produces"

dependencies:
  tools:
    - name: tool-name
      required: false
      description: "What it's used for"
  skills: []

tested_with:
  - claude-code
```

### catalog.yaml

After adding a Skill, add an entry to the root `catalog.yaml`:

```yaml
skills:
  - name: my-skill
    version: 1.0.0
    description: "One-liner matching SKILL.md"
    path: skills/my-skill
    complexity: intermediate
    tags:
      - relevant-tag
```

### Tests

Tests are not required by the Agent Skills standard but are strongly recommended in Nexus. If your Skill includes scripts, add a `tests/` directory with:

- `run_tests.sh` — entry point that CI calls
- `test_*.sh` — individual test files

See `skills/repo-public-readiness/tests/` for a reference implementation.

### Three Consumption Models

Nexus Skills are designed to work at multiple layers. When writing your SKILL.md, consider all three:

| Model | How it works |
|-------|-------------|
| **A — Script Execution** | User or agent runs your scripts directly |
| **B — Knowledge-Driven** | An agent reads SKILL.md and performs the task using its own tools |
| **C — Hybrid** | Agent runs scripts AND uses SKILL.md to interpret or extend results |

Not every Skill needs scripts (Model B is valid on its own), but your SKILL.md instructions should be complete enough that an agent could perform the task without scripts.

---

## Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Skill directory | lowercase kebab-case | `repo-public-readiness` |
| Script files | snake_case | `run_scan.sh` |
| YAML keys | snake_case | `tested_with` |
| Reference files | UPPER_CASE.md or descriptive | `SCAN_SPEC.md`, `report_format.md` |

Avoid abbreviations unless universally understood (`eks`, `ci-cd`, `aws`).

---

## Common Anti-Patterns

**Vague descriptions.** "Helps with infrastructure" tells the agent nothing. Be specific about what the Skill does and what triggers it.

**Everything in one file.** If SKILL.md exceeds 500 lines, split it. A 1000-line SKILL.md wastes context window on content the agent may not need.

**Deeply nested references.** SKILL.md links to A.md, which links to B.md, which has the actual content. Agents may only partially read nested files. Keep references one level deep.

**Over-explaining what agents already know.** Don't explain what a PDF is or how pip works. Add context the agent doesn't already have.

**Too many options without a default.** "You can use tool A, or tool B, or tool C..." Pick one default and mention alternatives only when there's a clear reason to diverge.

**Time-sensitive information.** "If you're doing this before August 2025, use the old API." This will become wrong. Use a "Legacy" or "Old patterns" section if historical context is needed.

**Windows-style paths.** Always use forward slashes: `scripts/helper.py`, not `scripts\helper.py`.

**Inconsistent terminology.** Pick one term and stick with it. Don't alternate between "API endpoint", "URL", "route", and "path" for the same concept.

---

## Pre-Submission Checklist

### Frontmatter
- [ ] `name` is lowercase, hyphens only, matches directory name
- [ ] `description` is third-person, includes what + when, has keywords for discovery
- [ ] `license` is specified
- [ ] `compatibility` lists required tools (if any)

### Content
- [ ] SKILL.md body is under 500 lines
- [ ] Detailed reference material is in separate files (if needed)
- [ ] File references are one level deep from SKILL.md
- [ ] Files over 100 lines have a table of contents
- [ ] Instructions are concise — no over-explaining common knowledge
- [ ] Consistent terminology throughout
- [ ] No time-sensitive information
- [ ] No hardcoded paths in scripts

### Quality
- [ ] Answers "What real-world problem do you solve?" in one sentence
- [ ] Fully generic — no company-specific logic, secrets, or internal references
- [ ] Works without paid dependencies
- [ ] Includes validation steps
- [ ] Documents common pitfalls
- [ ] `shellcheck` passes on all bash scripts (if any)
- [ ] Scripts degrade gracefully when optional tools are missing

### Nexus Requirements
- [ ] `metadata.yaml` is present and complete
- [ ] `catalog.yaml` entry is added
- [ ] Tests exist (if scripts are included)
- [ ] Tests pass locally

---

## Further Reading

- [Agent Skills Specification](https://agentskills.io/specification) — the formal standard
- [Skill Authoring Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) — Anthropic's detailed guidance
- [Example Skills](https://github.com/anthropics/skills) — production examples from Anthropic
- [skills-ref Validation Tool](https://github.com/agentskills/agentskills/tree/main/skills-ref) — validate your SKILL.md format
