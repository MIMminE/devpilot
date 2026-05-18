# PAS

PAS is a macOS-first personal automation app for developers. It brings daily Jira work, local Git repositories, Codex task prompts, reports, notes, and overtime records into one local menu bar workflow.

## Core Workflow

```text
Jira issue -> repository mapping -> branch creation -> Codex task prompt -> Git summary -> daily report
```

## What It Does

- Shows Jira work and team flow in a local dashboard.
- Tracks local repositories, base branches, dirty state, rebase/pull needs, and today's commits.
- Creates structured Codex prompts for repo work, memo cleanup, and report drafting.
- Generates daily work report drafts from commits, merges, Jira context, and notes.
- Keeps submitted reports, quick memos, and overtime records locally.
- Supports work/personal profiles with separate local settings.

## Project Layout

```text
apps/macos/        SwiftUI menu bar app
src/               Python automation CLI and integrations
examples/          Example config, assignee, and report-agent files
scripts/           Local helper scripts
ops/launchd/       macOS launchd templates
docs/              Product notes and detailed usage
```

## Quick Start

```bash
just setup
just install-dev
just check
just macos-app-build
```

Example settings live in [`examples/`](examples/). Runtime settings are created under:

```text
~/Library/Application Support/PAS/
```

## Documentation

- [Detailed usage](docs/USAGE.md)
- [Product plan](docs/PRODUCT_PLAN.md)

