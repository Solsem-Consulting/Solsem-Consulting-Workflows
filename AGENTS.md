# Agent Instructions — Solsem-Consulting-Workflows

- Priority: system/developer instructions, then explicit user requests, then this file.
- Use concise Norwegian and caveman-mode for operational status; clear prose for safety and irreversible actions.
- Keep secrets out of source, logs and chat.

## Branches, PRs and subscription

Standing authorization from the owner. It takes precedence over the general rule above about commits, pushes and PRs.

- Never commit directly to the default branch. For every change, first create a new branch from the latest default branch, named after the theme. Reuse an open branch for the same theme instead of starting another.
- When the work is committed and verified, push the branch and open a PR to the default branch. Never leave work only in a local commit or on the default branch.
- Right after opening a PR, subscribe to its activity (`subscribe_pr_activity`) without asking, and follow it until it is merged or closed. Never merge, approve, tag or release yourself.
