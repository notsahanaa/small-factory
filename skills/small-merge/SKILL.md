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
expects_state: "sub-issues in Code Complete or Done under parent issue (builtin: pre-merge; handoff: post-deploy)"
produces_state: "sub-issues Done; parent Staged or Done; Shipped comment on parent. In builtin mode also: feature branch merged to target + migrations applied. In handoff mode the git merge + deploy + migrations were done by the user's pipeline; small-factory only closes out Linear."
---

# Merge — Stage 4

The final stage. Closes out Linear and (in builtin mode) merges + applies migrations.

**Mode summary:**
- `ship.mode = builtin` — runs immediately after Build. Validates, merges
  feature branch to target, pushes, applies migrations, marks Linear Done.
- `ship.mode = handoff` — runs **after the user's deploy lands**. Skips the
  git/migrate work (the user's PR + CI + platform already did all of it) and
  acts as a Linear close-out: marks sub-issues Done, marks the parent
  Done/Staged, posts a Shipped comment noting that the merge happened via
  handoff. The handoff comment itself is posted earlier, by Build.

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
- `ship.mode`, `ship.handoff_command` — selects between builtin merge (today's
  behavior) and handoff (small-factory stops at code-complete; user/CI takes over)
- `branches.anchor` — the feature branch's base
- `branches.target` — the default target (only consulted in `ship.mode = builtin`)
- `commands.test`, `commands.typecheck`, `commands.build` — for final validation
- `verification_gates` — the ordered list of gates that must pass before merge
- `db.tooling`, `db.migrate_apply` — for migration apply

**Target-branch reconciliation runs in both modes.** In builtin mode the
target tells small-factory where to merge. In handoff mode the target tells
small-factory which Linear state to set (`Staged` for staging-like branches,
`Done` for production-like branches) — the user already deployed somewhere
and we need to know where.

**If the user said "merge to <X>" (or "merge done for <id> to <X>") and X
differs from `config.branches.target`, flag and ask:**
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

**In `ship.mode = builtin`**, verify the feature branch is clean before we
do git work on it:

```bash
git checkout {{config.branches.anchor}}
git status          ← must be clean working tree
git log -1 --oneline
```

**In `ship.mode = handoff`** the user's pipeline already merged + deployed
by this point. The local feature branch may not exist, the user may have
checked out anything, and none of it matters because small-factory isn't
doing any git operations here. Skip the feature-branch verification.

### Steps 3-5 — Validate, merge, and migrate (builtin only)

**If `ship.mode == handoff`, skip Steps 3-5 entirely** and print one line
acknowledging that the user's pipeline already did this work:

```
ℹ Handoff mode — skipping validation, git-merge, push, and migrate
   (your PR/CI/deploy pipeline already ran these). Closing out Linear.
```

Continue to Step 6.

In **`ship.mode = builtin`** the three steps run as today:

#### Step 3 — Final validation (builtin only)

Run each gate from the config, plus a full build. From the `$FEATURE_BRANCH`
checkout:

```bash
{{for each gate in config.verification_gates:}}
  {{config.commands.<gate>}}
{{end}}

{{config.commands.build}}
```

If anything fails, stop and report. Do not merge a broken branch.

#### Step 4 — Merge (builtin only)

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

#### Step 5 — Apply pending migrations (builtin only)

Skip this step entirely if **any** of the following is true:
- `config.db.tooling` is `none`
- `config.db.migrate_apply` is blank (right setting for CI/platform-managed
  migrations on Vercel / Fly / Heroku / Railway — those apply during deploy,
  so small-factory should not double-apply)

Otherwise:
```bash
{{config.db.migrate_apply}}
```

Run from the target-branch checkout (NOT a worktree). The exact command lives in
config — whether it's `npx prisma migrate deploy`, `supabase db push`,
`alembic upgrade head`, `psql $DATABASE_URL -f <file>`, or a project-specific
script. The config is authoritative.

Note what was applied in the merge comment.

### Step 6 — Update all sub-issues to Done

Same in both modes — Merge runs once the work is shipped (builtin: just
merged + migrated; handoff: user's deploy pipeline landed):

```
mcp__linear__save_issue
  id=<each sub-issue id>
  stateId=<Done state id>
```

Update all sub-issues including any that were already Done before this stage.

### Step 7 — Update parent issue status

Same in both modes:

```
mcp__linear__save_issue
  id=<parent-issue-id>
  stateId=<Staged state id>    ← if target is a staging branch
  stateId=<Done state id>      ← if target is main / production
```

"Staging" vs "main" is determined by whether the target branch matches the
project's staging convention (typically `staging` or `dev`) or its production
convention (typically `main` or `master`). When ambiguous, ask.

In handoff mode the "target" is the branch the user told you their deploy
landed on ("merge done for <id> to staging" → Staged; "...to main" → Done).

### Step 8 — Post Shipped comment on parent issue

```
mcp__linear__save_comment
  issueId=<parent-issue-id>
  body=<see template below>
```

In **`ship.mode = builtin`**:

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

In **`ship.mode = handoff`** (the user's PR + CI + platform did the actual
merge and deploy — small-factory is closing out Linear):

```markdown
## 🚢 Shipped (via handoff)

**Target:** `<target-branch>` (user's deploy pipeline)
**Closed out:** <date and time>

The handoff comment posted by Build summarized the code-complete state.
This comment marks the close-out: deploy has landed and Linear is now in
sync.

**Sub-issues shipped:**
- ✓ <issue-id>: <title>
- ✓ <issue-id>: <title>

**Deploy notes from the spec:**
<From the spec's deploy notes section. If nothing needed: "No action required.">

**Next steps:**
<If staging: "Ready for QA on staging.">
<If main: "Live in production.">
```

### Step 9 — Report to user

In **`ship.mode = builtin`**:
```
🚢 Merged to <target-branch>.

<issue-id> is now <Staged / Done> in Linear.
All <N> sub-issues marked Done.

Merge commit: <sha>
<Migration note if applicable>
<Deploy note if applicable>
```

In **`ship.mode = handoff`** (close-out after the user's deploy):
```
🚢 Closed out for <target-branch> (handoff mode).

<issue-id> is now <Staged / Done> in Linear.
All <N> sub-issues marked Done.

Posted Shipped (via handoff) comment on the parent.
The actual merge + deploy happened in your pipeline; small-factory only
closed out Linear.
```

### Step 10 — Cleanup feature state

After a successful Step 8, remove the wave-summary files that `(Build)SKILL.md`
wrote for this feature. They were a resume aid; once Merge has run (in either
mode) the feature is closed out and the files are noise.

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
- Never close out Linear if any sub-issue is not Code Complete or Done — always ask first.
- In `ship.mode = builtin`: never merge if any verification gate or the build
  is failing; always use `--no-ff`; if user says "merge to <X>" but config
  target is <Y>, flag and confirm before merging.
- In `ship.mode = handoff`: **never** perform git-merge, push, or migrate-apply
  — that's the user's pipeline's job, and it has already happened by the time
  this skill is invoked. Merge in handoff mode is purely a Linear close-out
  (sub-issues → Done, parent → Done/Staged, Shipped-via-handoff comment).
- Parent issue → Staged if target is a staging branch, Done if production.
  Same in both modes.
- The DB migration apply command always comes from `config.db.migrate_apply` —
  never hardcode a tool-specific command here. Treat a blank value as a clean
  skip (right setting for projects whose CI/platform owns migration apply).
