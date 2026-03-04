---
name: your-skill-name
description: Does X and Y. Use when the user needs to Z.
license: MIT
compatibility:
metadata:
  author:
  version: "1.0.0"
---

# Skill Name

> What real-world problem do you solve? One sentence.

## When Should You Use This?

-
-
-

## Prerequisites

**Required**:
-

**Optional**:
-

## Instructions

1.
2.
3.

## Validation

-
-

## Common Pitfalls

- **Pitfall**: Description and how to avoid it.

---

## Trigger Tests

Create `evals/triggers.yaml` to verify your description triggers correctly:

```yaml
# evals/triggers.yaml
should_trigger:
  - "prompt that should activate this skill"
  - "another way a user might phrase the request"
  - "indirect request that implies this skill"
  #  ... aim for 5-10 entries

should_not_trigger:
  - "prompt from an adjacent domain that should NOT match"
  - "common generic request that is not this skill's job"
  - "confusingly similar request meant for a different skill"
  #  ... aim for 5-10 entries
```

See [SKILL_GUIDE.md — Description Trigger Testing](SKILL_GUIDE.md#description-trigger-testing) for writing guidance.
