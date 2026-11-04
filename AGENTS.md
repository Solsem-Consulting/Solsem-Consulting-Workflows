# Agent Instructions — Solsem-Consulting-Workflows

- Priority: system/developer instructions, then explicit user requests, then this file.
- Use concise Norwegian and caveman-mode for operational status; clear prose for safety and irreversible actions.
- Keep secrets out of source, logs and chat.
- Shared rules for every Claude agent in the Solsem Consulting repositories: `docs/agent-regler.md`. Product repositories point to it by URL, so it must never contain secrets, internal addresses or session IDs.

## Branches, PRs and subscription

Standing authorization from the owner. It takes precedence over the general rule above about commits, pushes and PRs.

- Never commit directly to the default branch. For every change, first create a new branch from the latest default branch, named after the theme. Reuse an open branch for the same theme instead of starting another.
- When the work is committed and verified, push the branch and open a PR to the default branch. Never leave work only in a local commit or on the default branch.
- Right after opening a PR, subscribe to its activity (`subscribe_pr_activity`) without asking, and follow it until it is merged or closed. Never merge, approve, tag or release yourself.

## Repository rules

- Merge pull requests with a merge commit, never squash or rebase merge. Product repositories pin this repository by commit SHA, and squash or rebase would leave the pinned commits off `main`. Say this in every PR description.
- Pin every external action and reusable workflow to a full commit SHA with a readable version comment, for example `# v4.2.1`. `workflow-pin-policy.yml` and `scripts/Test-WorkflowPins.ps1` check this.
- Workflows run only for production releases or manually through `workflow_dispatch`. Never add `push`, `pull_request`, `schedule` or other automatic triggers: the free plan has few Actions minutes.
- Keep the attribution trailers in commit messages and PR descriptions, including the `Claude-Session:` link with the session ID. The rule in `docs/agent-regler.md` against session IDs covers that file only.
