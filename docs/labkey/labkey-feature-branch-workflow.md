# LabKey Feature Branch Workflow

## Branch naming

| Pattern | When to Use | Example |
|---|---|---|
| `fb_<label>_<id>` | Feature/bug fix targeting `develop` | `fb_infopane_11111` |
| `XX.Y_fb_<label>_<id>` | Feature/bug fix targeting a specific release | `25.11_fb_pubmed-notification_22222` |
| `releaseXX.Y-SNAPSHOT` | Primary beta release branch | `release25.11-SNAPSHOT` |
| `releaseXX.Y` | Final non-beta/patch release branch | `release25.11` |

- `<label>` = short, unique description; `<id>` = issue ID or spec ID (optional)
- **Branch names must be identical across repositories** so TeamCity matches them. For example, if `25.11_fb_pubmed-notification` in the panoramapublic repo relies on changes in the targetedms repo, the targetedms branch must also be named `25.11_fb_pubmed-notification`
- Feature branches targeting a release should be created from `releaseXX.Y-SNAPSHOT`, not from `releaseXX.Y` directly
- Feature branches should never be merged directly to `releaseXX.Y` — they go through the SNAPSHOT branch

**Common mistake:** Using `feature/...` naming will be rejected by LabKey CI.

## Before merging
- All features and tests complete
- All tests passing
- Manual acceptance testing done
- Code-reviewed pull request

## PR target branch

- Branches named `fb_<label>` (no version prefix) → target **`develop`**
- Branches named `XX.Y_fb_<label>` (with version prefix) → target **`releaseXX.Y-SNAPSHOT`**, **not** `develop`

**Example:** `25.11_fb_pubmed-publication-notification` must target `release25.11-SNAPSHOT`, not `develop`.

## Merge rules
- **Update feature branch from upstream:** `git pull --rebase` for your own changes, standard merge (not rebase) when pulling `develop` into the feature branch.
- **Merge to develop:** Use **Squash and Merge** via the GitHub PR UI.
- **Multi-repo features:** Merges should be done simultaneously across repositories.
- **Always build and run tests before pushing.**
- **Feature branch cleanup:** LabKey GitHub repositories are configured to automatically delete feature branches after merge. Post-merge bugs go on a new branch.
