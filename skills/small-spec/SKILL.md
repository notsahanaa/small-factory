---
name: small-spec
description: >
  Stage 1 of the small-factory pipeline. Uses superpowers:brainstorming to
  refine the feature idea, detects or creates a git branch, writes a structured
  design spec, and posts it as a Linear comment. Stack-agnostic — reads project
  details from the per-project config written by small-setup. Invoked by
  small-factory. Do not invoke directly.
stage:
  number: 1
  pipeline_position: spec
triggers:
  - "start <issue-id>"
  - "write spec for <issue-id>"
  - "new feature"
  - "spec this"
expects_state: "project config exists at ~/.claude/small-factory/projects/<slug>/config.yml"
produces_state: "Design Spec comment posted on parent Linear issue"
---

# Spec — Stage 1

Transforms a Linear issue or user description into a full design spec using
superpowers:brainstorming, then posts it to Linear.

## Notation

`{{config.x.y}}` is a substitution marker, not literal text. When you see it
in this skill, replace it with the value read from
`~/.claude/small-factory/projects/<slug>/config.yml` (loaded in Step 2)
**before** writing the spec body, dispatching any subagent, or running any
shell command. Never let `{{config.*}}` reach a subagent or Linear comment
verbatim — readers (or downstream agents) will see the literal brace string
and stall.

## Inputs

- **Linear issue ID** — must exist before this stage runs.
- **Project config** — must exist at `~/.claude/small-factory/projects/<slug>/config.yml`.
- **User description** (optional) — additional context beyond the Linear issue.

## Workflow

### Step 1 — Read the Linear issue

```
mcp__linear__get_issue      id=<issue-id>
mcp__linear__list_comments  issueId=<issue-id>
```

Read the full issue: title, description, any existing comments.

If there is already a "Design Spec" comment, ask the user:
"A spec already exists for this issue — do you want to iterate on it or start fresh?"

### Step 2 — Read project config

Read the per-project config:

```bash
cat ~/.claude/small-factory/projects/<slug>/config.yml
```

The slug is derived from `git config --get remote.origin.url` (or repo folder
name as fallback) and must match what Setup wrote.

**If config is missing:** stop and tell the orchestrator to route to `small-setup`
first. Do not attempt to detect the stack inline — that's Setup's job, and the
user should only answer those questions once.

From the config, you will use:
- `branches.anchor`, `branches.target`, `branches.prefix_format`, `branches.initials`
- `commands.*` (only to populate the spec's Branch & Delivery section)
- `db.tooling` (only for the spec's DB Migration section)

Also load project principles if present:
```bash
cat ~/.claude/small-factory/projects/<slug>/principles.md 2>/dev/null
cat ~/.claude/small-factory/principles.md 2>/dev/null  # global defaults
```

Project principles override global. Use them as guardrails when writing the spec
(e.g. if principles say "TDD required," the Testing Plan must include agent-testable
items, not just human-testable).

### Step 3 — Detect or create branch

Check current branch:

```bash
git branch --show-current
```

**If already on a feature branch** (not the anchor branch listed in config):
Use the current branch. Note it. Do not create a new one.

**If on the anchor branch** (e.g. `main`, `master`, `staging`, `dev` — read from
`config.branches.anchor`):
Create a new branch using the config's prefix format:

```bash
git pull origin <anchor>
git checkout -b <prefix_format><issue-id>-<short-slug>
```

If `config.branches.prefix_format` is `<initials>/`, expand it with
`config.branches.initials`. Example: `dan/lev-547-people-db`.
If `prefix_format` is empty, the branch is just `<issue-id>-<short-slug>`.

Generate the slug from the Linear issue title (lowercase, hyphens, max 4 words).

Confirm:
```bash
git branch --show-current
```

### Step 4 — Brainstorm (if superpowers is installed)

**Before any technical question — read the code first (HARD REQUIREMENT)**

Before asking the user *any* question that the codebase can answer — which
files? which table? what does the current behavior actually do? — you MUST
read at least one piece of evidence from the repo via Grep, Glob, or Read.
This rule applies through Step 5 (Write the design spec) as much as it
applies here. The magical moment for the user is seeing you grounded in
their actual code on your first question, not running a generic checklist.

Map the user's request to evidence:

- **Concrete file or symbol mentioned** (e.g. "the dashboard is slow",
  "auth.ts fails"): Grep for the symbol, Read the file, cite `path:line`
  in your first question.
- **Project-level prompt** (e.g. "rethink our auth strategy", "we need
  rate limiting"): Read the project structure — the relevant manifest
  (`package.json` / `Cargo.toml` / `go.mod` / `pyproject.toml`), the
  relevant top-level directory, any existing `docs/<topic>.md`. Cite
  what you found: "I checked `package.json` (passport listed as auth dep),
  `/src/auth/` (8 files), `/docs/auth-architecture.md` exists." Then
  ask your technical questions against THAT evidence.

If you genuinely cannot find any related evidence (truly novel greenfield
work), say so explicitly: "I searched for X, Y, Z and found nothing.
Treating this as a greenfield feature." Then proceed.

Do **not** ask "what file should I look at?" first — find it yourself.
Do **not** ask technical questions you can answer by reading the code.
Read first; then ask the questions whose answers aren't in the code.

---

Check whether superpowers is available:

```bash
ls ~/.claude/skills/superpowers/brainstorming/SKILL.md 2>/dev/null || \
  claude --list-plugins 2>/dev/null | grep -i superpowers
```

**If superpowers is installed:**
Load and follow the brainstorming skill. Feed it:
- The Linear issue title and description
- Any user context provided
- The project principles loaded in Step 2
- The goal: produce a design ready to be specced, not just a list of ideas

Use the brainstorming output as the raw material for the spec in Step 5.
Brainstorming surfaces non-goals, edge cases, and interaction details that
plain spec-writing misses — worth running when available.

**If superpowers is not installed:**
Ask the user up to 3 targeted clarifying questions (acceptance criteria,
non-goals, edge cases) before writing the spec. Then proceed to Step 5 using
the Linear issue description + user context + their answers as input.

### Step 5 — Write the design spec

Populate the template below. Every section is required. If a section doesn't
apply, write "N/A — <one line reason>". Do not omit sections.

Populate the **Branch & Delivery** section directly from the project config —
do not ask the user for these values. They were captured in Setup.

---

```markdown
## Design Spec — <Issue Title>

**Issue:** <issue-id>
**Branch:** <branch name>
**Date:** <today's date>

---

### Summary
<2-3 sentences. What is this feature and why does it exist now.>

---

### Goals & Non-Goals

**Goals:**
- <what this must do>

**Non-Goals:**
- <what this explicitly will not do — be specific>

---

### Interaction Flow
<Numbered steps of what the user does and what the system does in response.
Be concrete — name the components, routes, and actions involved.>

---

### UI Surfaces
<Every screen, panel, modal, or component being created or changed.
For each: name, what changes, and what the user sees.>

---

### Data Model
<Every new or modified DB table/column.
For each: field name, type, nullable, default, purpose.
N/A if no DB changes.>

---

### DB Migration & RLS
<Migration approach. RLS policies if applicable.
Note the DB tooling in use (from config.db.tooling).
N/A if no schema changes.>

---

### Analytics
<Every event to track. Format:
- `event_name` — triggered when X, properties: { key: value }
N/A if no analytics.>

---

### Testing Plan

**Agent-testable (automated):**
<Tests the build agents should write. Format: "Test that X when Y.">

**Human-testable (manual):**
<Scenarios for the user to manually verify. Format: "[ ] action → expected result">

---

### Risks & Open Questions
<Anything uncertain, risky, or needing a decision before or during build.
Flag anything that could block implementation.>

---

### Branch & Delivery
**Branch:** <branch name>
**Merges into:** <config.branches.target>
**Package manager:** <config.commands.package_manager>
**Dev command:** <config.commands.dev>
**Test command:** <config.commands.test>
**Build command:** <config.commands.build>
**DB tooling:** <config.db.tooling>
**Deploy notes:** <anything needed post-merge: run migration, set env var, etc.>
```

---

### Step 6 — Post spec to Linear

Post as a comment on the parent issue:

```
mcp__linear__save_comment
  issueId=<issue-id>
  body=<full spec markdown>
```

Do not change issue status at this stage.

### Step 7 — Report to user

```
✓ Spec written and posted to <issue-id>.
→ Review the "Design Spec" comment in Linear: <url>
→ When ready, tell me: "spec looks good, create sub-issues"
   Or: "iterate on the spec — [your feedback]"
```

If the user gives feedback, update the same comment (do not post a new one) and
report again.

## What else could go in the spec?

Consider adding these sections for more complex features:

- **API contracts** — new tRPC routes, REST endpoints, or webhooks
- **Permission model** — who can see/edit/delete the new data
- **Error states** — what the user sees when things go wrong
- **Performance considerations** — pagination, debounce, lazy loading
- **Accessibility** — keyboard nav, ARIA roles, focus management
- **Rollback plan** — how to undo if the feature causes issues post-deploy

Add these when relevant — they are optional and left out of the default template
to keep it lean.

## Rules

- Always read the project config — never assume any specific stack, package
  manager, or DB tooling. If config is missing, stop and route to Setup.
- Run superpowers:brainstorming before writing the spec if it is installed.
  Fall back to 3 targeted clarifying questions if not.
- Read the code before asking any technical question (Grep / Glob / Read).
  Cite path:line in your first question. Applies through Step 5 as well —
  never propose Data Model, DB Migration, or UI Surfaces sections without
  having read the relevant files first.
- Always detect the branch state — never blindly create a branch.
- The Branch & Delivery section in the spec is populated from config, not asked
  of the user. Single source of truth.
- Never proceed to sub-issues automatically. Wait for explicit user approval.
- Do not invent requirements. Flag uncertainty in Risks & Open Questions.
- Honor project principles loaded from `~/.claude/small-factory/.../principles.md`
  when present (e.g. TDD policy, dependency rules).
