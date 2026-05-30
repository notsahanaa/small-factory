---
name: small-merge
description: >
  Stage 4 of the small-factory pipeline. Merges the feature branch to the
  target, applies any pending migrations, marks all sub-issues Done in Linear, and
  posts a merge summary comment. Stack-agnostic — every command, DB tool, and
  branch is read from the per-project config written by small-setup. Invoked
  by small-factory. Do not invoke directly.
stage:
  number: 4
  pipeline_position: merge
triggers:
  - "merge to <branch>"
  - "done testing"
  - "ship it"
expects_state: "sub-issues in Code Complete or Done under parent issue"
produces_state: "feature branch merged to target; sub-issues Done; parent Staged or Done"
---

# Merge — Stage 4

The final stage. Merges the feature branch, closes out Linear, and hands off cleanly.

## Notation

`{{config.x.y}}` is a substitution marker, not literal text. When you see it
in this skill, replace it with the value read from
`~/.claude/small-factory/projects/<slug>/config.yml` (loaded in Step 1)
**before** running any shell command or constructing any output. Never let
`{{config.*}}` reach a Linear comment or shell prompt verbatim — readers
(or downstream agents) will see the literal brace string and stall.

## Inputs

- **Linear issue ID** with sub-issues in Code Complete (or Done) status.
- **Target branch** from user instruction (e.g. "merge to staging" or "merge to main").
- **Project config** at `~/.claude/small-factory/projects/<slug>/config.yml` — single
  source of truth for branches, commands, and DB tooling.

## Workflow

### Step 1 — Read project config

```bash
cat ~/.claude/small-factory/projects/<slug>/config.yml
```

If config is missing, stop and route to `small-setup`.

From the config you will use:
- `branches.anchor` — the feature branch's base
- `branches.target` — the default target (cross-check against the user's instruction)
- `commands.test`, `commands.typecheck`, `commands.build` — for final validation
- `verification_gates` — the ordered list of gates that must pass before merge
- `db.tooling`, `db.migrate_apply` — for migration apply

**If the user said "merge to <X>" and X differs from `config.branches.target`,
flag and ask:**
```
You said "merge to <X>" but the project config has target = <config.branches.target>.
Which is right?
  a) merge to <X> (override config this time)
  b) merge to <config.branches.target> (use the configured default)
  c) update config so <X> becomes the new default
```

Do not merge until the user confirms.

### Step 2 — Pre-merge check

```
mcp__linear__list_issues  parentId=<issue-id>
```

Check: are all sub-issues in Code Complete or Done?

If any are still in Todo or In Progress:
```
⚠ Cannot merge — these sub-issues are not complete:
- <issue-id>: <title> (status: <status>)

Tell me how to proceed:
- "skip <issue-id> and merge anyway"
- "build <issue-id> first"
```

Do not merge until the user responds.

Also verify the anchor branch is clean:

```bash
git checkout <config.branches.anchor>
git status          ← must be clean working tree
git log -1 --oneline
```

### Step 3 — Final validation

Run each gate from the config, plus a full build. From the anchor checkout:

```bash
{{for each gate in config.verification_gates:}}
  {{config.commands.<gate>}}
{{end}}

{{config.commands.build}}
```

If anything fails, stop and report. Do not merge a broken branch.

### Step 4 — Merge

```bash
git checkout <target-branch>           # the confirmed target from Step 1
git pull origin <target-branch>
git merge --no-ff <config.branches.anchor> -m "feat: <issue title> (<issue-id>)"
git push origin <target-branch>
```

Use `--no-ff` to preserve the merge commit in history.

If there are conflicts:
- Resolve conservatively — prefer the target-branch state for anything ambiguous
- Do not silently drop code — document every conflict resolution in the merge notes
- If conflicts are complex, stop and ask the user before proceeding

### Step 5 — Apply pending migrations

Branch on `config.db.tooling`:

**If `none`:** skip this step entirely.

**Otherwise:**
```bash
{{config.db.migrate_apply}}
```

Run from the target-branch checkout (NOT a worktree). The exact command lives in
config — whether it's `npx prisma migrate deploy`, `supabase db push`,
`alembic upgrade head`, `psql $DATABASE_URL -f <file>`, or a project-specific
script. The config is authoritative.

Note what was applied in the merge comment.

### Step 6 — Update all sub-issues to Done

```
mcp__linear__save_issue
  id=<each sub-issue id>
  stateId=<Done state id>
```

Update all sub-issues including any that were already Done before this stage.

### Step 7 — Update parent issue status

```
mcp__linear__save_issue
  id=<parent-issue-id>
  stateId=<Staged state id>    ← if merged to a staging branch
  stateId=<Done state id>      ← if merged to main / production
```

"Staging" vs "main" is determined by whether the target branch matches the
project's staging convention (typically `staging` or `dev`) or its production
convention (typically `main` or `master`). When ambiguous, ask.

### Step 8 — Post merge comment on parent issue

```
mcp__linear__save_comment
  issueId=<parent-issue-id>
  body=<see template below>
```

```markdown
## 🚢 Shipped

**`<config.branches.anchor>` → `<target-branch>`**
Merged: <date and time>
Merge commit: `<short-sha>`

**What's live:**
<2-3 sentences plain English — what was built and is now in <target-branch>.>

**Sub-issues shipped:**
- ✓ <issue-id>: <title>
- ✓ <issue-id>: <title>

**Migrations applied:** <list what ran, or "none">

**Deploy notes:**
<From the spec's deploy notes section. If nothing needed: "No action required.">

**Next steps:**
<If staging: "Ready for QA on staging.">
<If main: "Live in production.">
```

### Step 9 — Report to user

```
🚢 Merged to <target-branch>.

<issue-id> is now <Staged / Done> in Linear.
All <N> sub-issues marked Done.

Merge commit: <sha>
<Migration note if applicable>
<Deploy note if applicable>
```

### Step 10 — Cleanup feature state

After a successful merge, remove the wave-summary files that `(Build)SKILL.md`
wrote for this feature. They were a resume aid; once the feature is shipped
they're noise.

```bash
rm -f ~/.claude/small-factory/projects/<slug>/state/<issue-id>-wave-*.md
```

Do **not** remove the state directory itself (other features may have files
in flight) and do **not** remove other projects' files. Scope the deletion
to this `<slug>` and this `<issue-id>` only.

If the state directory ends up empty after this delete, leave it — it's
harmless and saves a `mkdir -p` next time Build runs.

## Rules

- Always read project config — never assume any specific stack, DB tooling, or branch.
- Never merge if any sub-issue is not Code Complete or Done — always ask first.
- Never merge if any verification gate or the build is failing.
- Always use `--no-ff` — preserve merge history.
- If user says "merge to <X>" but config target is <Y>, flag and confirm before merging.
- Parent issue → Staged if merged to a staging branch, Done if merged to production.
- The DB migration apply command always comes from `config.db.migrate_apply` —
  never hardcode a tool-specific command here.
