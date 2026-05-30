---
name: small-setup
description: >
  Stage 0 of the small-factory pipeline. One-time setup per project. Detects the
  project's stack from the repo, asks the user a handful of confirmation questions,
  and writes a per-project config (and optional principles) to ~/.claude/small-factory/.
  Nothing is ever written to the project repo. Invoked by small-factory when no
  config exists for the current project. Do not invoke directly.
stage:
  number: 0
  pipeline_position: setup
triggers:
  - "set up project"
  - "set up small-factory"
  - "configure factory"
  - "first time"
  - "initialize project"
expects_state: "no config.yml at ~/.claude/small-factory/projects/<slug>/"
produces_state: "config.yml written at ~/.claude/small-factory/projects/<slug>/"
---

# Setup — Stage 0

One-time per project. Captures the stack and conventions the rest of the pipeline
needs to be stack-agnostic. **Every file written by this skill lives under
`~/.claude/small-factory/`. Nothing is ever written to the project repo.**

## Inputs

- A working directory inside a git repository
- (Optional) a Linear team ID the user can provide

## Outputs

```
~/.claude/small-factory/
├── principles.md                          # optional global defaults
└── projects/
    └── <project-slug>/
        ├── config.yml                     # always written
        └── principles.md                  # optional project overrides
```

## Workflow

### Step 1 — Resolve project slug

```bash
git config --get remote.origin.url
git rev-parse --show-toplevel
```

Derive the **base slug** from the origin URL (e.g. `git@github.com:dan/people-db.git` → `people-db`).
If no remote, fall back to the basename of the repo root.

**Sub-step 1b — Detect monorepo subdir**

```bash
TOPLEVEL=$(git rev-parse --show-toplevel)
CWD=$(pwd)
```

If `TOPLEVEL` equals `CWD`, the user is at the repo root — use the base slug
unchanged and continue.

If `TOPLEVEL` differs from `CWD`, the user is in a subdir. This may be a
monorepo where each package wants its own config + principles. Compute the
relative subpath and slugify it (replace `/` with `-`, lowercase):
e.g. cwd `apps/web` → subpath-slug `apps-web`.

Pick a default based on whether the subpath looks like a package: if the
first segment is `apps`, `packages`, `services`, or `crates`, default to
**per-package**; otherwise default to **whole-repo**.

Ask the user:

> You're in `<relative subpath>` inside `<base-slug>`. How should I scope
> the config?
>
> a) Whole repo — one config for `<base-slug>` (shared by every subdir)
> b) Per-package — config for `<base-slug>-<subpath-slug>` only
>
> [default: <chosen default per the rule above>]

If they pick per-package (or accept the per-package default), the **final
slug** becomes `<base-slug>-<subpath-slug>` (e.g. `my-monorepo-apps-web`).
Otherwise the final slug stays as the base slug. Use the final slug
everywhere downstream as the project key.

Check whether `~/.claude/small-factory/projects/<slug>/config.yml` already exists.
If yes:
```
A config already exists for this project at:
  ~/.claude/small-factory/projects/<slug>/config.yml

Want to:
  a) overwrite (start fresh)
  b) edit specific fields
  c) cancel
```

Do not proceed until the user picks.

### Step 2 — Detect everything possible

Scan the repo silently. Detect:

- **Package manager** — by lockfile / manifest:
  - `bun.lock` → bun
  - `yarn.lock` → yarn
  - `pnpm-lock.yaml` → pnpm
  - `package-lock.json` → npm
  - `Cargo.toml` → cargo
  - `go.mod` → go
  - `pyproject.toml` with poetry section → poetry
  - `pyproject.toml` with uv/setuptools → uv or pip
  - `requirements.txt` → pip
  - `Gemfile` → bundler
- **Anchor branch** — `git symbolic-ref refs/remotes/origin/HEAD` (typically main or master)
- **Commands** — from the appropriate manifest:
  - `package.json` → parse `scripts`
  - `Cargo.toml` → use `cargo check / cargo test / cargo build`
  - `go.mod` → use `go vet ./... / go test ./... / go build ./...`
  - `pyproject.toml` → look for `[tool.poetry.scripts]`, `mypy`, `ruff`, `pytest` configs
- **DB tooling** — by presence:
  - `prisma/schema.prisma` → prisma
  - `supabase/config.toml` or `supabase/migrations/` → supabase
  - `sqlc.yaml` → sqlc
  - `alembic.ini` → alembic
  - any `migrations/*.sql` without the above → raw_sql
  - none of the above → none
- **Worktree strategy** — based on package manager:
  - bun → symlink (`ln -s ../../../node_modules .`)
  - npm / yarn / pnpm → install
  - cargo / go / poetry → none (build artifacts per worktree)
- **Cache clear paths** — based on detected framework:
  - Next.js (next in package.json) → `.next .turbo .next-dev`
  - Vite → `dist node_modules/.vite`
  - Cargo → `target`
  - Python → `__pycache__ .pytest_cache .mypy_cache`
  - none detected → empty list

### Step 3 — Present detection block (single confirmation)

Show the user one screen with everything detected:

```
✓ Detected the following for project <slug> — review and confirm:

  Project slug:    <slug>            (from git remote)
  Anchor branch:   <main|master>     (from origin/HEAD)
  Package manager: <pm>              (from <lockfile>)

  Commands:
    install:    <install cmd>
    dev:        <dev cmd>
    test:       <test cmd>
    lint:       <lint cmd>
    typecheck:  <typecheck cmd>
    build:      <build cmd>

  DB tooling:      <tool>            (from <evidence>)
    migrate_apply:   <command>
    client_generate: <command, or N/A>

  Worktree strategy: <strategy>      (based on package manager)
  Cache clear paths: <paths>         (based on framework)

Looks right? Reply "y" to accept, or tell me what to change
(e.g. "test should be vitest", "no DB", "add ruff to verification").
```

If the user requests changes, apply them and re-present until they accept.

**Ambiguity handling:** if two package managers are detected (e.g. both `bun.lock`
and `package-lock.json`), present both as options and ask which is authoritative.
Do not silently pick one.

### Step 4 — Ask the 5 things that can't be detected

**Ask one at a time, conversationally.** Do not dump all five in one
message — the user needs to be able to answer each in isolation, accept
the default by replying "ok" / "enter" / etc., or edit one without
re-typing the others.

For each question below: show the prompt + the default value inline, wait
for the user's response, then move to the next. Use **AskUserQuestion**
for questions 2 (target branch — multiple choice) and 3 (branch prefix —
multiple choice). Use **natural chat prompts** for questions 1, 4, 5
(free-text or accept-default).

The questions:

```
1. Linear team ID? (e.g. LEV, ACME)
   → [user types]

2. Default target branch when you say "merge to staging"?
   Options: main / staging / dev   [default: staging]
   → [user picks]

3. Branch prefix format?
   "<initials>/"  (e.g. dan/issue-547-people-db)
   none           (e.g. issue-547-people-db)
   [default: <initials>/]
   → [user picks; if prefix, ask for initials]

4. Commit format?
   Default: `<type>(<scope>): <summary> (<issue-id>, <parent-issue-id>)`
   [enter to accept, or edit]
   → [user accepts or edits]

5. Verification gates (must all pass before commit)?
   Default: [typecheck, lint, test]
   [enter to accept, or edit — names must match commands.* keys above]
   → [user accepts or edits]
```

### Step 5 — Principles

Check whether `~/.claude/small-factory/principles.md` already exists.

**If yes**, ask:
```
Project principles? (e.g. TDD policy, library rules, comment style)

  a) inherit ~/.claude/small-factory/principles.md (your global defaults)
  b) write a project-specific override
  c) skip both
```

**If no**, ask:
```
You don't have global principles set yet — these apply to all future projects
unless overridden per-project. Want to set them now?

  a) yes, write global principles (and inherit them here)
  b) write project-specific principles only
  c) skip both
```

If the user picks "write", open a prompt for free-form markdown. Suggest a starter:

```markdown
# Principles

- Tests required for new behavior; bug fixes start with a failing test.
- Prefer composition over inheritance.
- No new external dependencies without a one-line justification.
- Comments only when the WHY is non-obvious.
- <add your own>
```

### Step 6 — Write & confirm

Create the directory if it doesn't exist:
```bash
mkdir -p ~/.claude/small-factory/projects/<slug>
```

Write `~/.claude/small-factory/projects/<slug>/config.yml` with all captured values.
Use the schema below.

If principles were provided, write `~/.claude/small-factory/projects/<slug>/principles.md`
(and/or `~/.claude/small-factory/principles.md` for global).

Report to user:
```
✓ Setup complete for <slug>.

  Config:     ~/.claude/small-factory/projects/<slug>/config.yml
  Principles: ~/.claude/small-factory/projects/<slug>/principles.md  (if written)

These files are plain yaml + markdown — edit them directly any time, or re-run me
to redo the whole flow.

→ Ready for Stage 1. Tell me "start LEV-XXX" (or your team's issue ID) when ready.
```

## config.yml schema

```yaml
project:
  slug: <auto-detected>
  linear_team_id: <user-provided>            # e.g. "LEV"

branches:
  anchor: main                                # detected from origin/HEAD
  target: staging                             # user-confirmed default
  prefix_format: "<initials>/"                # or "" for no prefix
  initials: "dan"                             # used in prefix; omit if no prefix

commands:
  package_manager: bun                        # bun | npm | yarn | pnpm | cargo | go | poetry | uv | pip | other
  install:   bun install
  dev:       bun run dev
  test:      bun run test:ci
  lint:      bun run lint
  typecheck: bun run typecheck
  build:     bun run build

db:
  tooling: prisma                             # prisma | supabase | sqlc | alembic | raw_sql | none
  migrate_apply:   npx prisma migrate deploy
  client_generate: npx prisma generate
  worktree_rule:   "hand-write SQL; never run migrate dev in worktree"

worktree:
  node_modules_strategy: symlink              # symlink | install | none
  cache_clear:                                # commands to run when build cache is stale
    - "rm -rf .next .turbo .next-dev"

commit_format: "<type>(<scope>): <summary> (<issue-id>, <parent-issue-id>)"

verification_gates:                           # ordered; all must pass before commit
  - typecheck
  - lint
  - test
```

### Omission rules
- `db.tooling: none` → other `db.*` fields ignored by downstream stages
- `worktree.node_modules_strategy: none` → no install/symlink step in agent prompts
- `worktree.cache_clear: []` → no cache clear step
- `branches.prefix_format: ""` → branches are `<issue-id>-<slug>` with no prefix

## Rules

- Never write anything to the project repo. Every file goes under `~/.claude/small-factory/`.
- Always confirm before overwriting an existing config.
- If detection is ambiguous, present options and ask — never silently pick one.
- Detection is best-effort. The user's answer always wins over what was detected.
- This skill is re-runnable. The user should never feel locked in to early choices.
- Do not validate command strings by running them. The user is responsible for accuracy.
