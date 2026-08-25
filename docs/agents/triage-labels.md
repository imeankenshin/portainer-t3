# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to GitHub labels in this repository.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

An issue should have at most one canonical triage label. New issues start with
`needs-triage`. Replace that label with `needs-info`, `ready-for-agent`, or
`ready-for-human` after evaluation. Apply `wontfix` when closing work that will not
be actioned.

Manage labels with `gh label create --force` and issue state with
`gh issue edit --add-label` / `--remove-label`.
