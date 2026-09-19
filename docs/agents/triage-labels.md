# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the
actual label strings used in this repo's issue tracker. It also defines the **priority**
convention triage applies alongside them.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | *(no label)*         | Maintainer needs to evaluate this issue  |
| `needs-info`               | *(no label)*         | Waiting on reporter for more information |
| `ready-for-agent`          | `Ready For Agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | *(no label)*         | Requires human implementation            |
| `wontfix`                  | *(no label)*         | Will not be actioned                     |

When a skill mentions a role, use the string from the table. Where the string is *(no label)*,
express the role as described below — do **not** invent a label to fill the gap.

## Why four of the five roles have no label

Boxbow has no label for four of the five triage roles; it models them in Linear **workflow
states**, or a comment where no state applies. The workspace labels are:

- **Category**: `Feature`, `Bug`, `Improvement` — pick one per issue
- **State**: `Ready For Agent`
- **Parking**: `Deferred`

The four roles without a label resolve like this:

| Role              | How it is expressed                                                            |
| ----------------- | ------------------------------------------------------------------------------ |
| `needs-triage`    | Simply unlabeled — the skill's own "Unlabeled" bucket; post nothing             |
| `needs-info`      | No label and no state change; post triage notes as a comment                   |
| `ready-for-human` | Expressed by the **absence** of `Ready For Agent`; post the brief as a comment |
| `wontfix`         | The `Won't Fix` canceled state, or `Canceled`                                  |

## Triage labels are orthogonal to workflow states

Linear tracks board state via statuses (`Todo`, `In Progress`, `Done`, …) and `/triage` applies
the role mapping above. Both namespaces coexist on the same issue; don't conflate
`Ready For Agent` with the `Todo` status (triage role vs. workflow state).

## Priority

Triage assigns a Linear **priority** alongside the category and state role. Priority says how
soon the work should happen. It is not size, effort, or abstract importance.

| Priority   | Linear | Use for                                                                                                                                                            |
| ---------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Urgent** | 1      | Actively costing something now, or the follow-up to a live incident — an unobserved failure, a broken security control, a footgun that will bite again. Start next. |
| **High**   | 2      | A real defect, or a correctness/reliability gap with no workaround, or the open half of a resolved incident.                                                        |
| **Medium** | 3      | Well-specified work that is not harming anything yet — correctness drift, quality, a declared source of truth that has quietly stopped being true.                  |
| **Low**    | 4      | Refactors, watch items, and anything blocked on an external release. Also the default for a `Deferred` issue.                                                       |
| **None**   | 0      | Unset. Triage should not leave an issue here.                                                                                                                      |

Two rules:

- **Never leave priority unset after triage.** An issue that has been through triage has a
  category, a state role, and a priority. `0` means nobody has looked at it yet.
- **`Deferred` implies `Low`.** A ticket parked on an external gate is not urgent, and a higher
  number would misrepresent it on the board.

Priority is orthogonal to the triage roles: a `wontfix` issue can carry any priority, and the
roles expressed as nothing at all (`needs-triage`, `needs-info`) still get a priority once a
maintainer has made a first pass.

```sh
linear issue update BOX-<n> --priority <1-4>
```
