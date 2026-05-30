---
name: small-factory
description: >
  Master orchestrator for a spec-driven software factory (v1.0.0). Routes to
  the correct stage skill based on user intent and Linear issue state. Works
  across any project, stack, or team. Invoke on phrases like "start LEV-XXX",
  "create sub-issues", "build it", "merge to staging/main". Always the entry
  point — never invoke stage skills directly.
stage:
  number: null
  pipeline_position: orchestrator
triggers:
  - "start <issue-id>"
  - "write spec for <issue-id>"
  - "create sub-issues"
  - "spec looks good"
  - "build it"
  - "go build"
  - "merge to <branch>"
  - "ship it"
expects_state: "any"
produces_state: "stage skill completed; user has next-action handoff"
---

# Factory Orchestrator

One entry point for the full feature pipeline. Reads the Linear issue state and the
user's intent, then loads and executes the right stage skill.

## Pipeline Overview

```
Stage 0 — Setup        small-setup     "set up project" / "configure factory"
Stage 1 — Spec         small-spec      "start LEV-XXX" / "write spec for LEV-XXX"
Stage 2 — Sub-issues   small-subissues "create sub-issues" / "spec looks good"
Stage 3 — Build        small-build     "build it" / "go build" / "start building"
Stage 4 — Merge        small-merge     "merge to <branch>" / "done testing"
```

## Step 0 — Project config check

Before anything else, derive the project slug and check for a config file:

```bash
git config --get remote.origin.url   # or `git rev-parse --show-toplevel` for slug fallback
ls ~/.claude/small-factory/projects/<slug>/config.yml 2>/dev/null
```

**If config exists:** load it (used implicitly by downstream stages) and continue.

**If config is missing:** route to `small-setup` immediately, regardless of the
user's intent. Tell the user:
```
No small-factory config found for this project at:
  ~/.claude/small-factory/projects/<slug>/config.yml

Running Setup first — takes about a minute.
```

Once Setup completes, the user can re-issue their original request.

## Step 1 — Identify the issue

(Skip this step if routing to `small-setup` — Setup doesn't need a Linear issue.)

Extract the Linear issue ID from:
- User message (e.g. "start LEV-547")
- Current git branch name (e.g. `dan/lev-547-people-db` → `LEV-547`)
- If neither, ask: "Which Linear issue are we working on?"

## Step 2 — Read Linear state

```
mcp__linear__get_issue        id=<issue-id>
mcp__linear__list_comments    issueId=<issue-id>
mcp__linear__list_issues      parentId=<issue-id>
```

## Step 3 — Determine stage from intent + state

| User says | Linear state | Route to |
|---|---|---|
| "set up project", "configure factory", "first time" | config.yml missing | small-setup |
| "start", "write spec", "new feature" | Any | small-spec |
| "create sub-issues", "spec looks good" | Has spec comment | small-subissues |
| "build it", "go build", "start building" | Has sub-issues in Todo | small-build |
| "merge to X", "done testing", "ship it" | Sub-issues in Code Complete | small-merge |

If state and intent conflict (e.g. user says "build it" but no sub-issues exist),
stop and tell the user what's missing before proceeding.

## Step 4 — Load and execute the stage skill

Read the relevant SKILL.md before executing:
- `~/.claude/skills/small-setup/SKILL.md`
- `~/.claude/skills/small-spec/SKILL.md`
- `~/.claude/skills/small-subissues/SKILL.md`
- `~/.claude/skills/small-build/SKILL.md`
- `~/.claude/skills/small-merge/SKILL.md`

Then follow that skill's workflow exactly.

## Step 5 — End of stage handoff

After every stage completes, always close with:

```
✓ [Stage name] complete.
→ Review [what to review] in Linear: <link>
→ When ready, tell me: "[exact phrase to continue]"
```

Example after spec:
```
✓ Spec written.
→ Review the "Design Spec" comment on LEV-547 in Linear.
→ When ready, tell me: "spec looks good, create sub-issues"
```

## Rules

- Always run Step 0 first. Setup is the one stage that can pre-empt the user's intent.
- Never skip a stage unless the user explicitly asks.
- Never proceed to build without sub-issues in Todo status.
- Never merge without the user explicitly initiating it.
- If blocked at any point, report clearly and stop. Do not guess.
- This orchestrator is project-agnostic — do not assume any specific stack,
  package manager, or port. Those live in the per-project config, written by Setup.
- The routing table above is the source of truth. Stage manifests (the `triggers`
  and `expects_state` blocks in each SKILL.md) are documentation for humans and
  future tooling; they do not override this routing.
