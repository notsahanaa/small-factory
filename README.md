# small-factory

A lightweight, Linear-native software factory built as Claude Code skills.
Spec → sub-issues → parallel build (with git worktrees) → merge, all driven
from one orchestrator skill.

**For**: solo developers and small teams who use Linear, want a repeatable
spec-driven workflow, and don't want any factory artifacts living in their
project repos.

## Prerequisites

- [Claude Code](https://claude.com/code) installed (the `claude` CLI must be on PATH)
- [Linear MCP server](https://linear.app/changelog/2024-11-claude-mcp) configured (`claude mcp add`)
- `git` ≥ 2.5 (worktree support)
- `bash` (for install / upgrade / doctor scripts)

## Install

```bash
git clone https://github.com/notsahanaa/small-factory.git ~/small-factory
cd ~/small-factory
./install.sh
```

Symlinks the 6 skills into `~/.claude/skills/`. Creates state dir at
`~/.claude/small-factory/`. Optionally prompts you to set global principles
with an explanation + examples shown before you decide.

**Nothing is ever written to your project repos.** All state lives in
`~/.claude/small-factory/`. Bring this to a company codebase and your
colleagues will see zero evidence the factory was used.

## Quickstart

```
$ cd /path/to/your/project
$ claude
> /small-factory
```

**First run on a project**: routes to `small-setup` (~60 seconds to detect
your stack + confirm a handful of choices).

**Subsequent features**:

```
> start LEV-547                     # writes spec, posts to Linear
> spec looks good                   # creates sub-issues in Linear
> build it                          # parallel agents on git worktrees
> merge to staging                  # merges, applies migrations, closes Linear
```

## What gets installed

Six skills at `~/.claude/skills/`:

| Skill              | Purpose                                                          |
| ------------------ | ---------------------------------------------------------------- |
| `small-factory`    | Orchestrator. Always the entry point.                            |
| `small-setup`      | One-time per-project setup. Captures stack, branches, principles.|
| `small-spec`       | Writes a structured design spec from a Linear issue.             |
| `small-subissues`  | Breaks the spec into wave-tagged sub-issues in Linear.           |
| `small-build`      | Parallel agent dispatch on git worktrees, cherry-pick back.      |
| `small-merge`      | Merge, migration apply, Linear status updates.                   |

State directory at `~/.claude/small-factory/`:
- `principles.md` — optional global defaults
- `projects/<slug>/config.yml` — per-project, written by Setup
- `projects/<slug>/principles.md` — optional per-project overrides
- `projects/<slug>/state/<issue-id>-wave-*.md` — Build resume state, cleaned up after merge

## Working with branch-protected repos

By default small-factory operates in **builtin mode**: Build pushes commits
directly to your integration branch, and Merge performs the git-merge, push,
and migration apply itself. That's the right fit for solo work or projects
where the robot owns the integration branch.

For any project with branch protection, required code review, required CI
checks, or a managed deploy platform (Vercel, Fly, Heroku, Railway,
Netlify), switch to **handoff mode** at Setup time:

```yaml
# ~/.claude/small-factory/projects/<slug>/config.yml
ship:
  mode: handoff
  handoff_command: "gh pr create"   # optional — shown to you when Build finishes
```

The workflow becomes **Build → your deploy → Merge**:

1. **Build** cherry-picks onto your current feature branch (not anchor)
   and **does not push** when it finishes. It marks the sub-issues
   **Code Complete** in Linear and posts a "Handed off" comment on the
   parent issue summarizing what's ready for your ship workflow.
2. **You** push the branch, open a PR, run code review, let CI run, let
   your deploy platform (Vercel / Fly / Heroku / Railway) merge and
   deploy. small-factory does **not** push, merge, or run migrations.
3. **Merge** is invoked by you post-deploy with the target you actually
   shipped to (e.g. `"merge done for LEV-547 to staging"`). It skips the
   git/migrate work (already done by your pipeline) and closes out Linear:
   marks sub-issues Done, marks the parent Done/Staged, and posts a
   "Shipped (via handoff)" comment.

Setup detects deploy-platform files (`vercel.json`, `fly.toml`, etc.) and
defaults the mode to `handoff` when one is present, so most managed-platform
users get the right setting on first run.

The `db.migrate_apply` field is also blank-safe — leave it empty in either
mode and small-factory will skip the apply step entirely. That's the right
setting for projects whose CI or hosting platform applies migrations during
deploy.

## Upgrade

```bash
cd ~/small-factory
./upgrade.sh
```

Runs `git pull --ff-only`. Symlinks point at the cloned repo, so the next
`/small-factory` invocation loads the new version immediately.

## Doctor

```bash
./doctor.sh
```

Verifies skill symlinks, state directory, Linear MCP config, and per-project
`config.yml` validity. Exits 0 if all green; prints fix suggestions if not.

## Uninstall

```bash
./uninstall.sh           # removes symlinks; keeps user state
./uninstall.sh --purge   # also removes ~/.claude/small-factory/
```

## License

MIT. See [LICENSE](./LICENSE).
