# Protocol 2 reliability upgrade (2026-10-10)

- Executable, mirrored CLI transport with persistent status/results, heartbeats,
  process-tree cancellation, and retained diagnostics. Direct dispatch in the
  builder agent; no transport subagent required.
- Full local validation of the declared JSON contract for both providers, exact
  rubric coverage, and automatic mutation checks. No fabricated approval on errors.
- CLI/account defaults instead of hard-coded aging models; explicit pins,
  optional availability-only fallback, custom Codex provider preservation.
- Self-contained installed offline self-tests and opt-in synthetic live probes.
- Staged, backup-preserving installers; documented current/legacy paths and the
  earlier Claude skill name. Python 3.11+ replaces multiple shell dependencies.
- Short host-native skill instructions, corrected Claude frontmatter, failure
  regressions, and Windows/Linux/macOS CI.

Compatibility changes: structured JSON replaces the Claude-hosted Markdown verdict
contract. Old full-access/inherit sandbox switches and approval aliases are no
longer supported; use frozen read-only review. Test-only mock runner flags are
replaced by executable CLI doubles in the regression suite.

# Changelog
