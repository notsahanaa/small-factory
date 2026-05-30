# small-factory

A lightweight, Linear-native software factory built as Claude Code skills.
Spec → sub-issues → parallel build (with git worktrees) → merge, all driven
from one orchestrator skill.

**For**: solo developers and small teams who use Linear, want a repeatable
spec-driven workflow, and don't want any factory artifacts living in their
project repos.

## Prerequisites

- [Claude Code](https://claude.com/code) installed
- [Linear MCP server](https://linear.app/changelog/2024-11-claude-mcp) configured in `~/.claude.json`
- `git` ≥ 2.5 (worktree support)
- `bash` (for install / upgrade / doctor scripts)
- Optional: `jq` (better Linear MCP detection in install + doctor)

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
