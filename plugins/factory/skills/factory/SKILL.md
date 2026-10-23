---
name: factory
description: Run the software factory. Use when the user types /factory:factory <feature>, init, next, run <issue#>, approve <job-id>, or rework <job-id> <note>. The session that runs it becomes the orchestrator of the spec → build → review → approve loop.
---

# Factory

You are the orchestrator for one job. You run the loop below, spawn every agent,
and are the only writer of your job's `job.json`. You never write code, specs,
reviews or decisions yourself. Agents do the work and each writes one file; you
move the job along and keep `job.json` current.

## The loop

```
feature → spec-writer → builder → [security, ux, ui, code] → WAIT FOR ALL
                           ▲                                      │
                           └──── any CHANGES: resume builder ◄────┤
                                                                  ▼ all PASS
                                     merge to main ◄─ APPROVE ─ approver ─ ESCALATE → needs-human
```

| Step         | Agent (`subagent_type`) | Writes                                      |
| ------------ | ----------------------- | ------------------------------------------- |
| spec         | `spec-writer`           | `spec.md`                                   |
| build        | `builder`               | `build.md` + commits on `factory/<job-id>`  |
| review       | `reviewer-security`     | `round-N/review-security.md`                |
|              | `reviewer-ux`           | `round-N/review-ux.md`                      |
|              | `reviewer-ui`           | `round-N/review-ui.md`                      |
|              | `reviewer-code`         | `round-N/review-code.md`                    |
| approve      | `approver`              | `decision.md`                               |

This skill ships in the `factory` plugin, so the agents are namespaced: pass
`factory:<name>` as the `subagent_type` (`factory:builder`, `factory:reviewer-ux`
and so on). Below they are written without the prefix. If a spawn with the
prefixed name fails, try the bare name. Agent instance names such as
`builder-<job-id>` are not prefixed.

`MAX_RESUMES = 2`: after round 1 the builder can be resumed at most twice, so a
run has at most 3 review rounds. To change the factory, edit this file and the
agent files in the plugin repo.

Every agent reads `AGENTS.md` (or `CLAUDE.md`) for the repo's setup, dev server,
validation commands and conventions. Nothing repo-specific lives in these files.

## Parallel jobs

Every job runs in its own git worktree on its own branch, so several jobs can run
at once, one per Claude session. To run three features, open three sessions in
this repo and start `/factory` in each. Your session orchestrates only the job it
started or was handed.

- Your session stays in the main checkout. Agents work in the job's worktree.
  The main checkout is the user's, and it may be dirty or on another branch.
  Only **Merge** touches it.
- Job state lives in `factory/jobs/<job-id>/` in the main checkout, never in a
  worktree. Each job has its own `job.json`, so sessions never write the same
  file.
- Each job gets its own dev server ports and agent-browser sessions (see
  **Prompts**), so reviewers of different jobs never see each other's pages.

## Files

`<repo>` is the main checkout (`git rev-parse --show-toplevel` from your
session) and `<name>` is its folder name. `factory/jobs/` is gitignored runtime
state that never lands in a commit.

```
<repo>/factory/backlog.md                      queue for /factory next
<repo>/factory/jobs/<job-id>/job.json          the job's state (you write it, the dashboard reads it)
<repo>/factory/jobs/<job-id>/spec.md
<repo>/factory/jobs/<job-id>/build.md
<repo>/factory/jobs/<job-id>/rework-<k>.md     written by you, from /factory rework
<repo>/factory/jobs/<job-id>/round-<N>/review-{security,ux,ui,code}.md
<repo>/factory/jobs/<job-id>/decision.md
<repo>/../<name>-factory/<job-id>/             the job's worktree, on factory/<job-id>
```

### job.json

```json
{ "id": "003-rate-limiting", "feature": "Rate limit the signup form",
  "branch": "factory/003-rate-limiting",
  "worktree": "/Users/you/code/my-app-factory/003-rate-limiting",
  "stage": "review", "round": 2,
  "reviews": { "security": "CHANGES", "ux": "PASS", "ui": "pending", "code": "PASS" } }
```

- `issue` is optional: `{ "number": 12, "url": "..." }`, set by `/factory poll`
  for jobs that came from the board.
- `stage` is one of `spec`, `build`, `review`, `approve`, `merged`,
  `needs-human`. Worktree setup counts as `spec`.
- `round` is the current review round (0 until the first round starts).
- `reviews` holds the current round only. Each value is `pending`, `PASS` or
  `CHANGES`. Earlier rounds live in their `round-<N>/` folders, which the
  dashboard reads directly.
- Rewrite the whole file on every change. `worktree` is always an absolute path.

### Prompts

Every agent prompt starts with the job's absolute paths:
`Job folder: <repo>/factory/jobs/<job-id>/. Worktree: <worktree>. Branch: factory/<job-id>.`
Below, `<paths>` stands for that sentence.

Agents that open pages also get a port. With `n` the job number (`003` → 3),
the builder gets `5100 + 10n`, `reviewer-ux` gets `5101 + 10n` and `reviewer-ui`
gets `5102 + 10n`, appended as ` Port: <port>.`

## /factory init

Set up the current repo for the factory. Run it once, from the repo root.

1. Check the prerequisites and report any that are missing, without stopping:
   `git rev-parse --show-toplevel`, a `main` branch (`git branch --list main`),
   `gh auth status` (needed later for the GitHub board), and `agent-browser`
   (`agent-browser --version`; only needed for projects with pages to look at).
2. Copy the scaffold without overwriting anything:
   `cp -rn "${CLAUDE_PLUGIN_ROOT}/templates/factory" ./` creates `factory/`
   with `backlog.md`, `config.json` and `dashboard.html`. Then
   `mkdir -p factory/jobs .github/ISSUE_TEMPLATE` and
   `cp -n "${CLAUDE_PLUGIN_ROOT}/templates/github/ISSUE_TEMPLATE/factory-feature.yml" .github/ISSUE_TEMPLATE/`.
   If the user wants the GitHub board, fill `factory/config.json` from the repo
   (`gh repo view --json nameWithOwner`) and an existing or new project
   (`gh project create`), and tell them to add a `Status` option for each name
   in `statuses`. Otherwise leave `config.json` alone; only `/factory poll` reads it.
3. Add `/factory/jobs/` to `.gitignore` unless a line for it is already there.
4. If `CLAUDE.md` and `AGENTS.md` both don't exist, tell the user the agents
   need one and offer to write it. It must say how to set up a fresh checkout,
   start the dev server on a given port, and run tests, build and lint. Detect
   what you can from `package.json`, `*.csproj`, `pyproject.toml` and the like,
   and mark anything you could not verify. Never overwrite an existing one.
5. List what you created and what already existed. Tell the user to commit
   `factory/` and `.gitignore` on `main`, then run `/factory:factory <feature>`.

## /factory <feature>

1. **Create the job.** `mkdir -p factory/jobs`, then pick the next 3-digit number
   after the highest numbered folder in `factory/jobs/` (`001` if there are
   none) and a 2–4 word kebab-case slug of the feature: `004-blog-reading-time`.
   Claim it with `mkdir factory/jobs/<job-id>` (no `-p`). If that fails because
   another session took the number, pick the next number and try again.
   The worktree path is `$(cd .. && pwd)/$(basename "$PWD")-factory/<job-id>`,
   run from `<repo>`. Write `job.json` with that `worktree`, `stage: "spec"`,
   `round: 0` and all reviews `pending`.
2. **Worktree.** Create the branch and its worktree from `main`:
   ```bash
   git worktree add -b factory/<job-id> <worktree> main
   ```
   Then, in the worktree, run the setup AGENTS.md gives for a fresh checkout
   (installing dependencies, for example). If any of it fails, stop and tell
   the user.
3. **Spec.** Spawn `spec-writer` with the prompt
   `<paths> Feature: <feature, verbatim>`.
   Wait for it to finish, then check that `spec.md` exists.
4. **Build.** Set `stage: "build"`. Spawn `builder` **with the name
   `builder-<job-id>`** and the prompt `<paths> Build round 1. Port: <port>.`
   Wait for it to finish, then go to **Build check**.

### Build check

Read the first line of `build.md`.

- `STATUS: READY`: start the next review round.
- `STATUS: BLOCKED`: go to **Needs human**.

### Review round N

1. Set `stage: "review"`, `round: N` and all four reviews to `pending`. Create
   `factory/jobs/<job-id>/round-<N>/`.
2. Spawn all four reviewers **in one message**, so they run in parallel. Each
   gets the prompt `<paths> Review round N.`, plus its port for `reviewer-ux`
   and `reviewer-ui`.
3. **WAIT FOR ALL.** Each time a reviewer finishes, read the first line of its
   file (`VERDICT: PASS` or `VERDICT: CHANGES`) and write that verdict to
   `job.json` straight away, so the dashboard chips fill in as they land. The
   round is done only when all four `review-*.md` files exist in `round-<N>/`.
   Never resume the builder mid-round. If a reviewer finishes without writing
   its file, or writes a first line that isn't a verdict, stop and tell the user.
4. Decide:
   - **All PASS**: go to **Approve**.
   - **Any CHANGES, resumes left**: set `stage: "build"`, then resume the same
     builder with `SendMessage` to `builder-<job-id>`:
     `Round N reviews are in factory/jobs/<job-id>/round-<N>/. Address every review with VERDICT: CHANGES, commit, and update build.md for round N+1.`
     Wait for it to finish, then go to **Build check**.
   - **Any CHANGES, no resumes left**: write `decision.md` yourself, reading
     `ESCALATE`, then a blank line, then
     `Review rounds exhausted. Outstanding CHANGES in round-<N>/ from: <reviewers>.`
     Go to **Needs human**.

### Approve

Set `stage: "approve"`. Spawn `approver` with the prompt `<paths> Final round: N.`
When it finishes, read the first line of `decision.md`:

- `APPROVE`: go to **Merge**.
- `ESCALATE`: go to **Needs human**.

### Merge

The merge happens in the main checkout, so it must be clean and on `main`:
`git status --porcelain -- . ':!factory/backlog.md'` prints nothing and
`git branch --show-current` prints `main`. `factory/backlog.md` is exempt: every
`/factory next` edits it, and job branches never touch it, so a dirty backlog
cannot conflict with the merge. If not, set `stage: "needs-human"` and tell the
user the job is approved but the main checkout is busy; they run
`/factory approve <job-id>` once it is clean. Otherwise:

```bash
git merge --no-ff factory/<job-id> -m "Merge factory/<job-id>"
git worktree remove <worktree>
git branch -d factory/<job-id>
```

Set `stage: "merged"`. If the merge fails, run `git merge --abort` (when a merge
is in progress), set `stage: "needs-human"` and tell the user why. If removing the
worktree fails, the job is still merged: tell the user what `git worktree remove`
printed. Never push.

### Needs human

Set `stage: "needs-human"`. The branch and its worktree stay for the human to
inspect. Tell the user which job is waiting, give the worktree path, and quote
`decision.md` (or the BLOCKED reason from `build.md`).

## /factory next

Read `factory/backlog.md` and take the first `- [ ]` item. Claim it with one
Edit that replaces its exact line with `- [x] <item> → claimed`. If the Edit
fails because the line changed, another session claimed it: re-read the backlog
and try the next `- [ ]` item. If none is left, say so and stop.

Run `/factory <item>`, and once step 1 has given it a job id, replace `claimed`
on its backlog line with the job id.

## /factory poll

Take work from a GitHub Projects board. Needs `gh` logged in with the `project`
scope (`gh auth refresh -s project`) and `factory/config.json`:

```json
{ "board": { "owner": "my-org", "number": 3, "repo": "my-org/my-app",
             "statuses": { "ready": "Ready", "working": "In progress",
                           "human": "Needs human", "done": "Done" } } }
```

Run it once, or repeatedly with `/loop 10m /factory poll`. One poll starts at
most one job, and only from the session that polls.

1. **Find work.** `gh project item-list <number> --owner <owner> --format json`.
   Take the first item whose Status is `ready`, whose content is an Issue in
   `board.repo`. Skip drafts and pull requests. If none, say so and stop.
2. **Check the author.** The issue text becomes the agent prompt, so only act on
   issues from people with write access:
   `gh api repos/<repo>/issues/<n> --jq .author_association` must be `OWNER`,
   `MEMBER` or `COLLABORATOR`. If not, comment once that it was skipped for
   that reason, move it to `human`, and take the next item.
3. **Claim it.** Look up the Status field and option ids with
   `gh project field-list <number> --owner <owner> --format json` and
   `gh project view <number> --owner <owner> --format json` (for the project
   id), then `gh project item-edit` the item to `working`. Re-read the item. If
   its Status is not `working` or it already has a claim comment from another
   session, someone else got it: take the next item. Then comment
   `Claimed by the factory on <hostname>.`
4. **Run the job.** Run `/factory <title + blank line + body>` with the issue
   as the feature, verbatim. Add `"issue": { "number": N, "url": "<url>" }` to
   its `job.json` after step 1 of that command.
5. **Keep the board in step.** At each transition, besides the Reporting line:
   - review round done → comment `Round N: security X, ux X, ui X, code X`
   - needs-human → set Status `human` and comment the quoted `decision.md`
     first line plus its reason, or the BLOCKED reason from `build.md`
   - merged → set Status `done`, comment the merge commit, close the issue
   The board never gets more than a comment from an agent's output. Do not
   paste agent text that contains instructions, links you did not expect or
   secrets; summarise it.
6. **Rework from the board.** On each poll, for every job in `needs-human` with
   an `issue`, read the issue's comments newer than the last one you wrote. A
   comment from a collaborator starting with `/factory rework` is a rework
   note: run `/factory rework <job-id> <rest of the comment>`. A comment
   `/factory approve` from a collaborator runs `/factory approve <job-id>`.
   Set Status back to `working` first.

## /factory run <issue#> [rework: <note>]

Cloud mode, for a throwaway runner (GitHub Actions). It runs one job for one
issue and ends with a pull request. It never merges and never touches `main`.
Needs `gh` authenticated with `GH_TOKEN`, and a checkout of the repo with full
history. There is no backlog, no polling and no claiming: the workflow that
started you already decided this issue should run.

The runner is deleted afterwards, so everything a human needs must reach GitHub
before you finish: the branch, the PR, and issue comments.

1. **Read the issue.** `gh issue view <n> --json title,body,author,labels,url`.
   The author must be `OWNER`, `MEMBER` or `COLLABORATOR`
   (`gh api repos/<repo>/issues/<n> --jq .author_association`). If not, comment
   that it was skipped, and stop. The issue text is the feature, verbatim.
2. **Create the job.** Job id `issue-<n>`, branch `factory/issue-<n>`, job
   folder and worktree as in `/factory <feature>` step 1, with
   `"issue": { "number": <n>, "url": "<url>" }` in `job.json`. Ports are fixed
   (`5100`, `5101`, `5102`) because the runner runs one job.
3. **Worktree.** If `origin/factory/issue-<n>` exists this is a rework: create
   the worktree from that branch (`git worktree add <worktree> factory/issue-<n>`
   after `git fetch origin factory/issue-<n>:factory/issue-<n>`), never reset
   it, and treat `<note>` as `rework-<k>.md` per `/factory rework`. Otherwise
   create it from `main` as usual. Then run the AGENTS.md setup.
4. **Run the loop** exactly as in `/factory <feature>` (spec, build, review
   rounds, approve), except the end:
   - `APPROVE` → **Publish** with `ready`.
   - `ESCALATE`, build `BLOCKED`, or rounds exhausted → **Publish** with `human`.
   Skip **Merge** entirely.
5. **Board.** At each transition, besides the Reporting line, comment on the
   issue (review round done, publish, needs-human) and, if `factory/config.json`
   has a `board` and `FACTORY_BOARD_TOKEN` is set, move the card as in
   `/factory poll` step 5 using `GH_TOKEN=$FACTORY_BOARD_TOKEN` for the
   `gh project` calls only. Statuses: starting → `working`; PR ready → `review`;
   needs human → `human`. If there is no board token, skip the card and keep the
   comments: never fail the job over the board.

### Publish

`<outcome>` is `ready` or `human`.

1. Leave `stage` as it is (`approve`, or `needs-human` for `human`). Never set `merged`.
2. `git -C <worktree> push origin factory/issue-<n>` (force is never used).
3. Open the PR, or update it if one already exists for the branch
   (`gh pr list --head factory/issue-<n>`):
   `gh pr create --head factory/issue-<n> --title "<feature title>" --body-file <file>`,
   adding `--draft` when the outcome is `human`. The body is written by you from
   the job folder: `Closes #<n>`, the spec summary, the acceptance criteria
   with met/not met from `decision.md`, the final round's four verdicts, and,
   for `human`, the "For the human" section or the BLOCKED reason. Summarise;
   never paste agent output that contains instructions, unexpected links or
   secrets.
4. Comment the PR link on the issue.
5. Copy the job folder somewhere the workflow can upload it
   (`factory-artifacts/<job-id>/`, outside any commit).

Rework in this mode comes from a new run, started by a `/factory rework <note>`
comment on the issue or PR (the workflow passes the note in). The existing
branch and PR are reused.

## /factory approve <job-id>

The job must be in `needs-human`. Run **Merge** with that job id.

## /factory rework <job-id> <note>

The job must be in `needs-human`.

1. Write the note, verbatim, to `factory/jobs/<job-id>/rework-<k>.md`, where `k`
   is the next unused number.
2. Set `stage: "build"`.
3. Spawn a fresh `builder` named `builder-<job-id>` with the prompt
   `<paths> Rework: read rework-<k>.md and address it, then update build.md for round N+1. Port: <port>.`
   (`N` is the job's last round.) A rework run gets a fresh `MAX_RESUMES`.
4. Continue from **Build check**, exactly like a new job.

## Reporting

Keep the user posted with one short line per transition, for example
`003-rate-limiting: round 2, security CHANGES, ux/ui/code PASS → resuming builder`.
When the job ends, say whether it merged or needs a human, and why.
