---
name: small-subissues
description: >
  Stage 2 of the small-factory pipeline. Reads the Design Spec from Linear,
  breaks it into small well-scoped sub-issues with title, description, scope, and
  acceptance criteria, creates them in Linear, and posts a summary comment.
  Stack-agnostic — uses project config for team ID and conventions. Invoked
  by small-factory. Do not invoke directly.
stage:
  number: 2
  pipeline_position: subissues
triggers:
  - "create sub-issues"
  - "spec looks good"
  - "break down the spec"
expects_state: "Design Spec comment exists on parent issue"
produces_state: "sub-issues created under parent, all set to Todo"
---

# Sub-issues — Stage 2

Breaks the approved design spec into the smallest meaningful units of work and
creates them as Linear sub-issues under the parent.

## Inputs

- **Linear issue ID** with an approved "Design Spec" comment.
- **Project config** at `~/.claude/small-factory/projects/<slug>/config.yml` (used
  for the team ID and to inform sub-issue vocabulary).

## Workflow

### Step 1 — Read the spec and config

```
mcp__linear__get_issue       id=<issue-id>
mcp__linear__list_comments   issueId=<issue-id>
```

```bash
cat ~/.claude/small-factory/projects/<slug>/config.yml
```

If config is missing, stop and route to `small-setup`.

Find the "Design Spec" comment. Extract:
- UI Surfaces → likely one or more sub-issues each
- Data Model changes → schema changes get their own sub-issue
- DB Migration → its own sub-issue if non-trivial
- Analytics → one sub-issue grouping all tracking events
- Testing Plan → agent-testable items become each sub-issue's acceptance criteria

The team ID for `mcp__linear__save_issue` comes from `config.project.linear_team_id`.

### Step 2 — Draft sub-issues

**Sizing rule:** A sub-issue must be completable by one agent in one pass.
If you can't describe it in one sentence, it's too big — split it.
One sub-issue = one component OR one behavior OR one data change.

**Sub-issue format — all four fields required:**

```
Title:       <Verb + component or behavior> (max 8 words)
Description: <What to change. One sentence on what, one on constraint or approach.>
Scope:       <Files, components, routes, or layers this touches. Be specific.>
Acceptance:  <One sentence — what does done look like from the user's perspective.>
```

> The examples below are written in a JS/React idiom for illustration. Your
> sub-issues should use your project's actual file paths, framework vocabulary,
> and conventions. The shape of each sub-issue (title/description/scope/acceptance)
> is what matters — the language adapts to the stack.

**Good examples:**

```
Title:       Remove header controls from card preview
Description: The preview version of a pipeline block shows header buttons that don't
             function in preview mode. Remove all header control elements from the
             card variant, leaving only the table or kanban view content.
Scope:       src/components/canvas/PipelineCard.tsx — card variant only, not the
             full block header.
Acceptance:  Pipeline card on canvas shows only the data view with no header buttons.
```

```
Title:       Add person via side panel instead of modal
Description: Replace the add-prospect modal with a Sheet side panel consistent with
             the rest of the app. Panel opens from the right.
Scope:       src/components/people/AddPersonTrigger.tsx,
             src/components/atoms/primitives/Sheet.tsx (reuse, don't modify)
Acceptance:  Clicking "Add person" opens a right side panel, not a modal.
```

```
Title:       Add PostHog events for pipeline interactions
Description: Instrument the four pipeline interaction events defined in the spec
             analytics section. Use the existing useAnalytics hook.
Scope:       src/hooks/useAnalytics.ts, src/components/canvas/PipelineBoard.tsx
Acceptance:  Events appear in PostHog when user moves a card, adds a stage,
             renames a stage, and deletes a stage.
```

**Bad examples — too vague or too large:**

```
❌ "Build the people DB feature"
❌ "Update the UI"
❌ "Add people and companies with tabs, filters, side panel, and activity log"
```

**Categories to always consider when generating sub-issues:**

| Category | Size | Notes |
|---|---|---|
| Schema change + migration | 1 sub-issue per table | Keep schema and migration together |
| New component (UI only) | 1 sub-issue | No data wiring yet |
| Wire component to data | 1 sub-issue | Separate from component creation |
| RLS policy / auth rule | 1 sub-issue | Only if non-trivial |
| Analytics events | 1 sub-issue | Group all events for the feature |
| Delete / remove code | 1 sub-issue | Always Wave 1 — build first |
| Bug fix within scope | 1 sub-issue | Only if the spec called it out |

### Step 3 — Assign waves

Tag every sub-issue before creating:

- **Wave 1 — Foundation:** Schema, migrations, deleted code, shared primitives.
  Nothing else can start until these land.
- **Wave 2 — Core:** New components, data wiring, main behaviors.
- **Wave 3 — Polish:** Analytics, edge cases, visual refinements.

A sub-issue belongs in the earliest wave where all its dependencies are satisfied.

### Step 4 — Create sub-issues in Linear

Create each sub-issue with status **Backlog** while creating:

```
mcp__linear__save_issue
  parentId=<issue-id>
  teamId=<config.project.linear_team_id>
  title=<title>
  description=<full markdown below>
  stateId=<Backlog state id>
```

Description body format:

```markdown
<Description text>

**Scope:** <scope text>

**Acceptance:** <acceptance text>

**Wave:** <1 / 2 / 3>
```

Get state IDs before creating:
```
mcp__linear__list_issue_statuses  teamId=<config.project.linear_team_id>
```

Create ALL sub-issues before changing any status.

### Step 5 — Move all sub-issues to Todo

After all sub-issues are created, batch-update each to **Todo**:

```
mcp__linear__save_issue
  id=<sub-issue-id>
  stateId=<Todo state id>
```

### Step 6 — Post summary comment on parent issue

```markdown
## Sub-issues Created

<N> sub-issues ready across <N> waves.

**Wave 1 — Foundation**
- <issue-id>: <title>

**Wave 2 — Core**
- <issue-id>: <title>
- <issue-id>: <title>

**Wave 3 — Polish**
- <issue-id>: <title>

⚠ Needs attention: <any sub-issue that had an ambiguity or assumption — flag it>

All set to Todo. Ready to build when you are.
```

### Step 7 — Report to user

```
✓ <N> sub-issues created for <issue-id>.
→ Review sub-issues in Linear: <url>
→ When ready, tell me: "build it"
   Or: "adjust sub-issues — [your feedback]"
```

If the user gives feedback, create, edit, or delete sub-issues as needed and
update the summary comment (do not post a new one).

## Rules

- All four fields (title, description, scope, acceptance) are required on every sub-issue.
- Schema change and its migration go in the same sub-issue.
- Create all sub-issues as Backlog first, then batch-update to Todo.
- Wave assignment is mandatory — small-build depends on it for ordering.
- Team ID always comes from config.project.linear_team_id — never hardcode it.
- Do not start building. Wait for explicit user instruction.
