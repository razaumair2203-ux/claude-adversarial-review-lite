# Claude Adversarial Review - Lite (Claude AR-L)

**Codex builds. Claude audits.** You decide.

Claude Adversarial Review - Lite is a Codex skill for independent, audit-first review through Claude Code CLI. It freezes a focused review bundle, invokes Claude non-interactively with read-only permissions and schema-constrained output, detects repository mutation, and requires Codex to validate findings before fixes.

It is the reversed companion to [Adversarial Reviewer Lite](https://github.com/razaumair2203-ux/adversarial-reviewer-lite). The two are deliberately kept as mirror siblings: the same policy layer (human-review floor, rubric checklists, strict mode) and the same reporting procedure (finding evaluation, audit report, HTML report structure, terminal operator summary) — differing only in direction and transport. Here Codex builds and Claude reviews through schema-constrained JSON; there Claude Code builds and Codex reviews through a markdown verdict contract:

- frozen bundle by default instead of reviewer repository access;
- JSON Schema output instead of textual verdict parsing;
- native PowerShell and POSIX runners;
- no subagent required for dispatch;
- explicit turn, cost, permission, and session-persistence controls;
- critical/high/medium findings only.

This workflow reduces correlated mistakes. It does not prove correctness or replace tests and human judgment.

## Workflow

1. Codex builds or proposes a plan.
2. You invoke `$claude-adversarial-review-lite`.
3. Codex creates a focused bundle containing intent, acceptance criteria, diff/plan, relevant context, and verification.
4. Claude reviews the frozen bundle without repository write access.
5. The runner validates structured output and Codex checks that the repository did not change during review.
6. Codex accepts, rejects, re-scopes, defers, or verifies every finding.
7. You see the report before approving fixes.

## Install

Prerequisites:

- Git
- Codex CLI or IDE extension
- Claude Code CLI, installed and authenticated
- PowerShell 5.1+ on Windows, or Bash plus `jq` and `timeout` on macOS/Linux/WSL

The runners find Claude through `CLAUDE_REVIEW_CLI`, `CLAUDE_BIN`, `claude` on `PATH`, common local install paths, and on Windows the VS Code Claude extension's native binary.

Clone and install:

```powershell
git clone https://github.com/razaumair2203-ux/claude-adversarial-review-lite.git
cd claude-adversarial-review-lite
.\scripts\install.ps1
```

```bash
git clone https://github.com/razaumair2203-ux/claude-adversarial-review-lite.git
cd claude-adversarial-review-lite
bash scripts/install.sh
```

Restart Codex if it is already open.

## Use

```text
Use $claude-adversarial-review-lite to audit this change.
Use $claude-adversarial-review-lite in plan mode.
Use $claude-adversarial-review-lite for a feasibility review.
Use $claude-adversarial-review-lite to audit this change with rubric:docs/compliance-checklist.md.
Use $claude-adversarial-review-lite strict rubric:docs/compliance-checklist.md.
Use $claude-adversarial-review-lite selftest.
```

`rubric:<path>` makes the review checkable against named domain rules: the reviewer returns PASS/FAIL/UNVERIFIABLE per checklist item with evidence, and any FAIL forces `revise`. `strict` is the one-flag safe configuration for high-consequence repos: it requires a rubric, floor-gates every change for human review, and disables autonomous fixing.

Direct dependency check:

```powershell
.\skills\claude-adversarial-review-lite\scripts\selftest.ps1
.\skills\claude-adversarial-review-lite\scripts\selftest.ps1 -LiveProbe
```

```bash
bash skills/claude-adversarial-review-lite/scripts/selftest.sh
bash skills/claude-adversarial-review-lite/scripts/selftest.sh --live-probe
```

Run it after non-trivial changes, auth or data work, migrations, billing changes, multi-file refactors, architecture decisions, or claims whose verification feels thin. Skip it for typo-only or cosmetic edits.

## Safety and privacy

- The default reviewer starts in an empty temp directory with built-in tools, slash commands, hooks, filesystem setting sources, and MCP servers disabled; it receives only the bundle Codex constructs.
- Ignored files, secrets, tokens, and full environment dumps must never enter the bundle.
- Repository text is treated as untrusted evidence, not reviewer instructions.
- Claude runs with `dontAsk`; unapproved operations fail instead of prompting invisibly.
- Pre/post snapshots include Git state and hashes of dirty tracked files.
- Neither Claude nor Codex is automatically trusted.
- No fix is applied until reviewer findings are independently assessed and the user signs off, unless autonomous fixing was explicitly requested (strict mode voids that authorization).
- An `approved` verdict on auth, billing, migration/destructive-data, secret, or regulatory changes is floor-gated: you review the diff yourself before the audit completes. Tag repo-specific floor paths in a `.advreview-floor` file (one regex per line) at the repo root.

For sensitive repositories, inspect the bundle before dispatch and commit or stash unrelated work first.

## Repository layout

```text
skills/claude-adversarial-review-lite/
  SKILL.md
  agents/openai.yaml
  references/
  scripts/
scripts/
tests/
```

The skill is the workflow. The runner scripts are deterministic transport and validation. The reviewer prompt and schema are separate resources so they can evolve without bloating the skill instructions.

## Limits

- Claude Code CLI is a separate product with its own authentication, usage, and model availability.
- Schema-valid output can still contain incorrect findings.
- Frozen bundles can omit relevant context; the runner surfaces insufficient context as degraded review quality.
- Snapshot checks detect project mutation but are not an operating-system security boundary.
- Whole-codebase review is intentionally opt-in because it increases privacy and prompt-injection exposure.

## License

MIT
