# Issue tracker: GitHub

Issues and specs (including PRDs) for this repository live in GitHub Issues at
`imeankenshin/portainer-t3`. Use the `gh` CLI for all tracker operations.

## Conventions

- Use `.github/ISSUE_TEMPLATE/` forms when creating issues in the browser.
- Give each independently deliverable piece of work its own issue.
- Keep decisions and follow-up discussion in issue comments rather than local tracker files.
- Use the labels in `docs/agents/triage-labels.md` for triage state.
- Link implementation work to its parent spec with a sub-issue. Use native issue dependencies for blocking relationships.
- Do not recreate `.scratch/` as an issue tracker.

## Common operations

- **Create**: `gh issue create --title "..." --body-file <file> --label needs-triage`
- **Read**: `gh issue view <number> --comments`
- **List**: `gh issue list --state open --json number,title,body,labels,assignees,url`
- **Comment**: `gh issue comment <number> --body "..."`
- **Apply or remove a label**: `gh issue edit <number> --add-label <label>` or `gh issue edit <number> --remove-label <label>`
- **Claim**: `gh issue edit <number> --add-assignee @me`
- **Close**: `gh issue close <number> --comment "..."`

Run commands inside this clone so `gh` infers the repository from `origin`. GitHub
shares one number space across issues and pull requests; if a bare `#<number>` is
ambiguous, try `gh pr view <number>` and then `gh issue view <number>`.

## Publishing and fetching

When a skill says "publish to the issue tracker", create a GitHub issue and return
its URL. When a skill says "fetch the relevant ticket", run
`gh issue view <number> --comments` and include its labels and relationships.

## Relationships

Prefer GitHub's native relationships over dependency text in issue bodies.

- **Add a sub-issue**: `gh api --method POST repos/imeankenshin/portainer-t3/issues/<parent>/sub_issues -F sub_issue_id=<child-database-id>`
- **List sub-issues**: `gh api repos/imeankenshin/portainer-t3/issues/<parent>/sub_issues`
- **Blocked by**: `gh api --method POST repos/imeankenshin/portainer-t3/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-database-id>`
- **Database ID**: `gh api repos/imeankenshin/portainer-t3/issues/<number> --jq .id`
- **Verify blockers**: `gh api repos/imeankenshin/portainer-t3/issues/<number> --jq .issue_dependencies_summary`

The relationship APIs require database IDs, not issue numbers or GraphQL node IDs.
If sub-issues are unavailable, add the child to a task list in the parent and add
`Part of #<parent>` to the child body.

## Wayfinding operations

Used by `/wayfinder`. A map is one issue with one sub-issue per ticket.

- **Map**: create an issue labelled `needs-triage` whose body contains Notes, Decisions-so-far, and Fog sections.
- **Child ticket**: create an issue and attach it to the map as a sub-issue.
- **Blocking**: record edges as native issue dependencies; fall back to a `Blocked by: #<number>` line only when the API is unavailable.
- **Frontier**: choose the first open, unassigned child with no open blockers.
- **Claim**: assign the selected child to `@me` before doing work.
- **Resolve**: comment with the answer, close the child, and add a concise context pointer to the map's Decisions-so-far.

## Pull requests as a triage surface

PRs are not a request surface for this repository. Track requested work in an issue
and link the implementation PR to it.
