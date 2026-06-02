---
name: small-build
description: >
  Stage 3 of the small-factory pipeline. Reads sub-issues from Linear, groups
  them into waves, dispatches parallel subagents on git worktrees, cherry-picks back
  to the anchor branch, and updates Linear per sub-issue. Stack-agnostic — every
  command, DB tool, and worktree rule is read from the per-project config written
  by small-setup. Invoked by small-factory. Do not invoke directly.
stage:
  number: 3
  pipeline_position: build
triggers:
  - "build it"
  - "go build"
  - "start building"
  - "ship the tickets"
expects_state: "sub-issues exist in Todo status under parent issue"
produces_state: "sub-issues in Code Complete; commits pushed on anchor branch"
---

# Build — Stage 3

Executes the sub-issues in parallel using a subagent-per-ticket model on git
worktrees. One branch. Parallel workers. Clean cherry-pick back.

## Notation

`{{config.x.y}}` is a substitution marker, not literal text. When you see it
in this skill, replace it with the value read from
`~/.claude/small-factory/projects/<slug>/config.yml` (loaded in Step 0)
**before** dispatching any subagent, constructing any agent prompt, or
running any shell command. Never let `{{config.*}}` reach a subagent
verbatim — they'll see the literal brace string and stall.

## Inputs

- **Linear issue ID** with sub-issues in Todo status.
- **Project config** at `~/.claude/small-factory/projects/<slug>/config.yml` — the
  single source of truth for every command, DB tool, and worktree rule used below.

## Step 0 — Read the project config

Before dispatching any agents, read the per-project config:

```bash
cat ~/.claude/small-factory/projects/<slug>/config.yml
```

If the config is missing, stop and route to `small-setup`. The user should never
be asked stack questions inline here — that's Setup's job.

From the config you will use:

- `commands.package_manager`, `commands.install`, `commands.test`, `commands.lint`,
  `commands.typecheck`, `commands.build` — for agent prompts and validation
- `db.tooling`, `db.migration_create`, `db.migrate_apply`, `db.client_generate`,
  `db.worktree_rule` — for schema handling
- `worktree.node_modules_strategy`, `worktree.cache_clear` — for worktree setup
  and post-merge cache hygiene
- `verification_gates` — the ordered list of gates that must pass before commit
- `commit_format` — the commit message template
- `branches.anchor` — the branch to cherry-pick onto in `ship.mode = builtin`
- `ship.mode`, `ship.handoff_command` — selects between pushing to anchor
  (builtin) and stopping at code-complete on the current branch (handoff)

Also load project principles if present:
```bash
cat ~/.claude/small-factory/projects/<slug>/principles.md 2>/dev/null
cat ~/.claude/small-factory/principles.md 2>/dev/null  # global defaults
```

Principles get injected into every agent prompt as a `## Principles` block so
agents honor them (TDD policy, dependency rules, etc.).

**Resume check — read any existing wave summaries for this feature.**

```bash
STATE_DIR=~/.claude/small-factory/projects/<slug>/state
mkdir -p "$STATE_DIR"
ls "$STATE_DIR"/<issue-id>-wave-*.md 2>/dev/null
```

If any `<issue-id>-wave-N.md` files exist, read them. Each file represents a
wave already completed and cherry-picked in a prior session (possibly killed
mid-feature). For every such file:
- Treat that wave as **done** — do not re-dispatch its sub-issues, do not
  re-cherry-pick.
- Keep its summary block in working memory; it will be injected into the
  next wave's agent prompts the same way a freshly-built summary would be.

After identifying which waves are already done, resume at the first wave
that has no summary file. If all waves are done, jump straight to Step 8
(Update Linear) for any sub-issues not yet marked Code Complete, then
Step 9 (Report).

## Workflow

### Step 1 — Read all sub-issues

```
mcp__linear__list_issues  parentId=<issue-id>  limit=100
```

For each sub-issue extract: ID, title, description, scope, acceptance, wave number.
Only process sub-issues in **Todo** status. Skip everything else.

Group into Wave 1, Wave 2, Wave 3.

### Step 2 — Resolve cherry-pick base

The cherry-pick base depends on `ship.mode`:

```bash
if [[ "{{config.ship.mode}}" == "handoff" ]]; then
  CHERRY_BASE=$(git branch --show-current)
  if [[ "$CHERRY_BASE" == "{{config.branches.anchor}}" ]]; then
    echo "✗ Refusing to build directly on anchor branch ({{config.branches.anchor}}) in handoff mode."
    echo "  In handoff mode, Build cherry-picks onto the current feature branch."
    echo "  Run Spec first to create a feature branch, or 'git checkout' an existing one."
    exit 1
  fi
  # Don't pull — the user owns this branch and may have local-only commits.
  git log -1 --oneline
else
  CHERRY_BASE="{{config.branches.anchor}}"
  git checkout "$CHERRY_BASE"
  git pull origin "$CHERRY_BASE"
  git log -1 --oneline
fi
```

Record the HEAD commit hash. Every agent worktree must start from this exact
hash. In builtin mode `$CHERRY_BASE` equals the configured anchor branch; in
handoff mode it's the current feature branch.

### Step 3 — Dispatch agents by wave

Process one wave at a time. Within a wave, dispatch all agents in a single message
with multiple Agent tool calls so they run concurrently.

**Max 5 parallel agents per wave.**
If a wave has more than 5 tickets, split into batches of 5.

```
Agent({
  description: "<issue-id> <title>",
  subagent_type: "general-purpose",
  isolation: "worktree",
  run_in_background: true,
  prompt: "<see agent prompt template below>",
})
```

Wait for all Wave N agents to complete and be cherry-picked before dispatching Wave N+1.
Wave N+1 agents start from the cherry-picked Wave N state. **Before dispatching
Wave N+1, build the Wave N summary (Step 5.5) and include it in every Wave N+1
agent prompt.**

---

### Agent Prompt Template

Populate every field exactly — do not paraphrase or summarize ticket content.
Where you see `{{config.x.y}}`, substitute the value from the per-project config
loaded in Step 0.

```
You are implementing a single Linear sub-issue. Follow these instructions exactly.

## Your ticket
ID: <issue-id>
Title: <verbatim title>
Description: <verbatim description>
Scope: <verbatim scope — these are the files/components you should focus on>
Acceptance: <verbatim acceptance criteria>

## Branch setup
Cherry-pick base: {{cherry_base}}            # the branch your commit will be cherry-picked onto
Expected HEAD:    <commit hash>

First, verify your worktree is at the right base:
  git log -1 --oneline
If the hash does not match <commit hash>, run:
  git reset --hard <commit hash>

## Environment
Package manager: {{config.commands.package_manager}}
DB tooling:      {{config.db.tooling}}

Commands you will use:
  install:   {{config.commands.install}}
  test:      {{config.commands.test}}
  lint:      {{config.commands.lint}}
  typecheck: {{config.commands.typecheck}}
  build:     {{config.commands.build}}

If dependencies are missing in the worktree, follow the strategy below:
  {{config.worktree.node_modules_strategy}}:
    - symlink → ln -s ../../../node_modules .
                then run {{config.db.client_generate}} if {{config.db.tooling}} != none
    - install → {{config.commands.install}}
    - none    → no action needed (e.g. cargo / go / poetry build artifacts are per-worktree)

Pre-commit hooks may not be executable in worktrees — this is not an error.
Run all checks manually before committing.

## Principles (read and honor these)
<full body of principles.md if loaded>

## Schema rule (only if this ticket touches the DB)
DB tooling:           {{config.db.tooling}}
Migration create cmd: {{config.db.migration_create}}    (blank → hand-write fallback)

If tooling is "none":
  No schema work to coordinate.

Else if migration_create is set:
  1. Choose a descriptive snake_case <slug> for this migration (e.g. "add_user_invites").
  2. Run the configured creation command, replacing the literal "<slug>" with your slug:
       {{config.db.migration_create}}
     (For Prisma this is typically `prisma migrate dev --create-only --name <slug>`,
     which writes the migration file but does NOT apply it — exactly what we want.
     For other tools the config defines the equivalent.)
  3. Inspect the generated migration file. Edit if needed to make it correct
     and idempotent. Keep the file exactly where the tool wrote it.
  4. Run the client/codegen step so types match the new schema:
       {{config.db.client_generate}}
  5. Do NOT apply the migration. The orchestrator applies via
     {{config.db.migrate_apply}} from the main checkout after cherry-pick.

Else (migration_create is blank — fall back to hand-writing the file):
  If tooling is "prisma":
    Write migration SQL to prisma/migrations/<YYYYMMDDHHMMSS>_<slug>/migration.sql.
    After writing, run: {{config.db.client_generate}}.
  If tooling is "supabase":
    Write migration SQL to supabase/migrations/<YYYYMMDDHHMMSS>_<slug>.sql.
  If tooling is "alembic":
    Hand-write the migration revision file under the alembic versions dir.
  If tooling is "sqlc":
    Update the SQL files. The orchestrator runs {{config.db.client_generate}}
    after cherry-pick.
  If tooling is "raw_sql":
    Follow project conventions.
  Do NOT apply the migration — orchestrator handles apply per ship.mode.

Worktree rule reminder: {{config.db.worktree_rule}}

## Verification (all required — blocking commit)
Run in this order. All must pass before you commit. Use the project's own commands:

{{for each gate in config.verification_gates:}}
  {{config.commands.<gate>}}    ← gate "<gate>" must pass

If any gate fails, fix it before committing. Do not commit a broken state.

## Commit message format
  {{config.commit_format}}
Substitute the placeholders: <type>, <scope>, <summary>, <issue-id>, <parent-issue-id>.

## DO NOT push.

## Return to orchestrator — include all of:
- Worktree path
- Branch name
- Commit hash (short SHA)
- Files changed (list)
- Test pass count
- Verification log summary (each gate's output)
- Any blockers encountered

STOP and report if blocked. Do not ship a blind fix when verification cannot run.
```

---

### Step 4 — Handle agent returns

For each returning agent:

**If successful** (all verification gates pass, commit hash provided):
→ Proceed to cherry-pick (Step 5)
→ Post implementation comment on sub-issue (Step 8)
→ Mark sub-issue Code Complete (Step 8)

**If blocked** (agent reported a blocker or verification failed):
→ Do NOT cherry-pick
→ Do NOT mark Code Complete
→ Post blocker comment on sub-issue (see blocker template below)
→ Post a one-line update on the **parent issue** so it's visible without opening sub-issues
→ Flag in final report

**Blocker comment template (on the sub-issue):**

```markdown
### ⚠ Build Blocked

**Sub-issue:** <issue-id> — <title>
**Blocked at:** <which verification gate or what the agent hit>
**Details:** <what failed, error output if relevant>
**Suggested fix:** <agent's best guess at what's needed>

Needs manual review before this ticket can proceed.
```

**Parent issue update when a blocker occurs:**

```
mcp__linear__save_comment
  issueId=<parent-issue-id>
  body="⚠ Build blocker on <issue-id> (<title>) — <one line summary of blocker>. See sub-issue for details."
```

### Step 5 — Cherry-pick to the resolved base

Cherry-pick in wave order, then by issue ID within each wave (lowest ID first).
The base is `$CHERRY_BASE` from Step 2 — anchor in builtin mode, the current
feature branch in handoff mode.

```bash
git checkout "$CHERRY_BASE"
git cherry-pick <hash>
```

**Common conflicts and resolutions:**

| Conflict | Resolution |
|---|---|
| `Recent Changes` docblock collision | Keep both entries, newest-first |
| Two agents added method to same service | Keep both, one merge commit |
| Agent A added what Agent B removed | B wins — drop A's tests for the removed entity |
| Agent referenced a now-removed value | Trim the reference from tests/fixtures inline |
| Lock file conflict | Keep all changes, re-run install if deps actually changed |

### Step 5.5 — Build Wave N summary and persist it

Before dispatching the next wave, capture HEAD hashes, build a summary of what
just landed, and **write it to disk** so a session that dies mid-feature can
be resumed without losing this context.

**Capture HEAD hashes for this wave.**

The "HEAD before wave N" is the HEAD of the anchor branch immediately *before*
this wave's first cherry-pick. For Wave 1, that's the hash recorded in Step 2.
For Wave N (N>1), it's the hash captured right after Wave N-1's last
cherry-pick — capture it then, not stale from Step 2.

After all of Wave N's cherry-picks land:

```bash
HEAD_AFTER_WAVE_N=$(git rev-parse HEAD)
```

Hold onto `HEAD_AFTER_WAVE_N` as the "HEAD before wave N+1" for the next round.

**Generate the summary.**

```bash
git diff <head-before-wave>..<head-after-wave> --stat
git log <head-before-wave>..<head-after-wave> --pretty=format:"%s%n%b"
```

Synthesize a short block covering:
- **New files created** (paths)
- **Function/method signatures changed** (before → after)
- **Types/interfaces added or modified** (names + shape change)
- **Removed APIs** that downstream code might still reference

**Persist the summary to disk.**

```bash
cat > ~/.claude/small-factory/projects/<slug>/state/<issue-id>-wave-<N>.md <<EOF
# Wave <N> summary for <issue-id>

HEAD before wave: <head-before-wave>
HEAD after wave:  <head-after-wave>

<summary block: new files, signature changes, types, removed APIs>
EOF
```

(The state directory was created in Step 0's resume check.)

**Inject into Wave N+1 agent prompts** verbatim, as today:

```
## Previous wave changes (read before you start)
<summary block here>
```

Repeat: Wave 1 → summary file → injected into Wave 2 prompts.
Wave 2 → summary file → injected into Wave 3 prompts.

These summary files are cleaned up by `(Merge)SKILL.md` after a successful
merge — they're a resume aid, not permanent state.

### Step 6 — Validate merged state

Run from the `$CHERRY_BASE` checkout (NOT a worktree) after each wave. Iterate
the configured verification gates and run each gate's command:

```bash
{{config.db.client_generate}}        # only if {{config.db.tooling}} != none AND wave had schema changes

{{for each gate in config.verification_gates:}}
  {{config.commands.<gate>}}
{{end}}

{{config.commands.build}}             # always, in addition to gates
```

If the wave had schema changes, apply migrations from the `$CHERRY_BASE` checkout
(NOT a worktree):

```bash
{{config.db.migrate_apply}}
```

Skip the apply step if any of:
- `config.db.tooling` is `none`
- `config.db.migrate_apply` is blank (project's CI/platform applies migrations)

If validation fails after merge, fix inline on anchor branch. Common fixes:
- Drop test fixtures referencing removed entities
- Re-run `{{config.db.client_generate}}` after schema cherry-pick
- Clear caches as configured:
  ```bash
  for cmd in {{config.worktree.cache_clear}}:
    eval "$cmd"
  ```
- Kill stale dev server: `pkill -f "dev"` (or your project's equivalent)

### Step 7 — Push (or hand off)

Behavior depends on `ship.mode`:

```bash
if [[ "{{config.ship.mode}}" == "handoff" ]]; then
  echo "✓ Build complete on $CHERRY_BASE."
  echo ""
  echo "Hand-off — small-factory will NOT push or merge in handoff mode."
  echo "  Commits are on:  $CHERRY_BASE"
  echo "  Anchor branch:   {{config.branches.anchor}} (untouched)"
  echo "  No push happened."
  if [ -n "{{config.ship.handoff_command}}" ]; then
    echo "  Your next step:  {{config.ship.handoff_command}}"
  else
    echo "  Your next step:  push the branch and open a PR (or run your normal ship workflow)."
  fi
else
  git push origin "$CHERRY_BASE"
fi
```

In builtin mode `$CHERRY_BASE` equals `{{config.branches.anchor}}` (today's
behavior — push the anchor branch). In handoff mode no remote mutation
happens; the commits sit on the current feature branch for the user's
PR/CI/deploy pipeline to take over.

Add `--no-verify` to the builtin-mode push only if the project has a known
pre-push hook issue AND the validation in Step 6 is verified green. Document
the bypass in the report if used.

### Step 8 — Update Linear per sub-issue

Do this as each wave completes — not at the end. User sees real-time progress.

For each successfully shipped sub-issue:

**Post implementation comment:**

```markdown
### Implementation Notes

Shipped on `<branch>` — commit `<short-sha>`.

**What was built:**
<1-2 sentences plain English. What the user will now see or experience differently.>

**Technical details:**
- Files changed: <list>
- Key decisions: <any non-obvious choices>
- Tests added: <count and what they cover>

**Verification:**
<one line per gate in config.verification_gates: "<gate>: <result>">
```

**Update status to Code Complete:**

```
mcp__linear__save_issue
  id=<sub-issue-id>
  stateId=<Code Complete state id>
```

For blocked sub-issues: leave status as **Todo**. Do not advance it.

### Step 8.5 — Post handoff comment on parent issue (handoff mode only)

In `ship.mode = handoff`, Build is the end of small-factory's involvement
until the user comes back post-deploy. Post a comment on the **parent**
issue that summarizes what's code-complete and points the user at their
ship workflow. The exact template depends on whether any sub-issues are
blocked.

In `ship.mode = builtin`, skip this step. The corresponding "Shipped"
comment for builtin mode is posted by Merge's Step 8.

**If all sub-issues completed successfully — post "Handed off":**

```
mcp__linear__save_comment
  issueId=<parent-issue-id>
  body=<see template below>
```

```markdown
## 🤝 Handed off

**Feature branch:** `$CHERRY_BASE`
**Anchor branch:** `{{config.branches.anchor}}` (untouched)
**Handed off:** <date and time>

small-factory finished code-complete work on `$CHERRY_BASE` and stopped.
No merge, push, or migration apply happened — your PR review, CI, and
deploy pipeline take over from this point.

**Sub-issues code-complete:**
- ✓ <issue-id>: <title>
- ✓ <issue-id>: <title>

**Deploy notes from the spec:**
<From the spec's deploy notes section. If nothing needed: "No special action.">

**Next steps:**
<If ship.handoff_command set: "Run `<ship.handoff_command>` to start the ship workflow.">
<Else: "Push the branch and open a PR; let your CI/deploy pipeline take it from here.">

Once your deploy lands, tell small-factory:
  `merge done for <parent-issue-id> to staging` (or `to production`)
to mark sub-issues Done and post a Shipped comment.
```

**If some sub-issues are blocked — post "Partial handoff":**

```markdown
## 🤝 Partial handoff

**Feature branch:** `$CHERRY_BASE`
**Handed off:** <date and time>

<X> of <Y> sub-issues are code-complete on `$CHERRY_BASE`. <Z> are blocked
and need attention before this feature can fully ship.

**Code-complete:**
- ✓ <issue-id>: <title>

**⚠ Blocked:**
- <issue-id>: <title> — see sub-issue for details

Resolve the blockers, then run `build it` again to pick up the remaining work.
Once everything is code-complete and deployed, run `merge done for <parent-issue-id>`.
```

**Note: wave-summary files are NOT cleaned up here.** They live until Merge
runs (post-deploy in handoff mode, post-merge in builtin mode), so Build
remains safely re-runnable for the partial-handoff case (resolve a blocker
→ run Build again → resumes from wave summaries on disk).

### Step 9 — Report to user

Tail of the report depends on `ship.mode`. In **builtin** mode:

```
✓ Build complete. <X>/<Y> sub-issues shipped.

<issue-id> — <one line outcome>
<issue-id> — <one line outcome>
...

<gate-1>: <result> | <gate-2>: <result> | build: <result>

⚠ Blockers (<N> tickets need attention):
- <issue-id>: <one line blocker summary> — see sub-issue for details

→ Shipped tickets are Code Complete in Linear.
→ Test the feature and tell me: "merge to <branch>" when ready.
```

In **handoff** mode:

```
✓ Build complete. <X>/<Y> sub-issues code-complete on $CHERRY_BASE.

<issue-id> — <one line outcome>
<issue-id> — <one line outcome>
...

<gate-1>: <result> | <gate-2>: <result> | build: <result>

⚠ Blockers (<N> tickets need attention):
- <issue-id>: <one line blocker summary> — see sub-issue for details

→ Sub-issues are Code Complete in Linear; anchor branch ({{config.branches.anchor}}) untouched.
→ Posted a <Handed off | Partial handoff> comment on the parent issue.
→ Your next step: <ship.handoff_command or "push the branch and open a PR">.
→ Once deploy lands, tell me "merge done for <parent-issue-id> to <target>" to close out Linear.
```

## Known pitfalls

Each pitfall lists which stacks it applies to. Skip the ones that don't match
your `config.commands` / `config.db` / `config.worktree` values.

**Stale build cache after migration**
*Applies to: Next.js / Vite / similar frontend frameworks with on-disk caches.*
Symptom: routes return errors against data that demonstrably exists.
Fix: kill dev server, run the cache_clear commands from config, regenerate DB
client (`{{config.db.client_generate}}`), restart.

**Worktree at wrong base**
*Applies to: every stack using git worktrees.*
Always verify with `git log -1 --oneline` at worktree start.
If wrong: `git reset --hard <hash>`.

**Agent writing to main checkout instead of worktree**
*Applies to: every stack.*
After each wave, run `git status` in main checkout.
If leaked changes: `git checkout -- .` (agent's commit already has the work).

**Pre-commit hook "ignored because not executable"**
*Applies to: husky users (JS projects) and other hook frameworks installed via
package manager.* This is an environment quirk, not a `--no-verify` situation.
Run all checks manually before committing.

**DB advisory lock across worktrees (Prisma)**
*Applies to: Prisma only.*
Never run plain `prisma migrate dev` in a worktree — it takes a DB advisory
lock that conflicts with sibling worktrees. Use `prisma migrate dev
--create-only` (which only writes the migration file and does not connect
to the DB) — that's what `config.db.migration_create` defaults to. Apply
via `{{config.db.migrate_apply}}` from the main checkout only.

**Cherry-pick conflicts in docblocks**
*Applies to: every stack.*
These are the majority of conflicts. Merge both entries chronologically.
Do not lose either ticket's history.
