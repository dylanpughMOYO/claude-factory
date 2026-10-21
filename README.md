# claude-factory

A Claude Code plugin that runs a software factory: `/factory:factory <feature>`
writes a spec, builds it on its own branch in its own git worktree, reviews it
from four angles (security, UX, UI, code), and merges it or hands it to you.

## Install

```
/plugin marketplace add <owner>/claude-factory
/plugin install factory@claude-factory
```

Then, in the repo you want to use it in:

```
/factory:factory init
```

`init` creates `factory/` (backlog and dashboard), ignores `factory/jobs/`, and
checks that `gh`, `agent-browser` and a `main` branch are available. It offers
to write a `CLAUDE.md` if the repo has none. The agents read that file for
setup, dev server, test and build commands.

## Commands

```
/factory:factory init                       set up the current repo
/factory:factory <feature>                  run a new job through the loop
/factory:factory next                       run the first unchecked backlog item
/factory:factory poll                       take the first Ready card from the GitHub board
/factory:factory approve <job-id>           merge a needs-human job into main
/factory:factory rework <job-id> <note>     send a needs-human job back to the builder
```

## Layout

```
.claude-plugin/marketplace.json
plugins/factory/
  .claude-plugin/plugin.json
  skills/factory/SKILL.md        the orchestrator
  agents/                        spec-writer, builder, four reviewers, approver
  templates/factory/             copied into a repo by init
```

## Updating

Bump `version` in `plugins/factory/.claude-plugin/plugin.json` when you change
the skill or an agent. Users then run `/plugin marketplace update claude-factory`
and `/reload-plugins`.

## Check before publishing

```
claude plugin validate .
claude plugin validate ./plugins/factory
```
