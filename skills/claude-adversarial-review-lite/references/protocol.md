# Protocol and result contract

## Dispatch boundary

The reviewer receives one frozen Markdown bundle through standard input. Launch it from an empty temp directory with `--tools ""`, `--disable-slash-commands`, empty setting sources, hooks and auto-memory disabled, strict empty MCP configuration, and a replacement system prompt. This is both more independent and safer than granting repository access. Keep the bundle focused enough to audit but complete enough to test the builder's claims.

Write bundles, snapshots, runner results, and stderr only under the OS temp directory, never inside the reviewed repository. Otherwise the workflow's own artifacts change Git status and invalidate mutation comparison.

## Result envelope

The runner writes JSON with:

- `result`: `success`, `setup_needed`, `launch_failure`, `timeout`, or `invalid_output`
- `verdict`: `approved`, `revise`, or `null`
- `review_quality`: `valid`, `degraded_content`, `degraded_environmental`, or `unknown`
- `review`: the schema-validated Claude object or `null`
- `errors`: a concise diagnostic or `null`
- `session_id`: Claude session id when returned

Accept `success` only when Claude exits successfully, its outer JSON parses, and the review object is available either as `structured_output` or as a JSON string in `result`. Apply these semantic invariants:

- `approved` has no findings;
- `revise` has at least one finding;
- `valid` contains concrete review content;
- every reported finding is critical, high, or medium;
- `approved` has no `rubric_results` entry with result `FAIL` (the runners reject this combination as `invalid_output`);
- when a rubric was supplied, the builder additionally checks coverage: every rubric item answered exactly once, missing items treated as UNVERIFIABLE, more than half skipped means `degraded_content`, and an `approved` with zero PASS entries verified nothing and is `degraded_content`.

## Self-test

1. Run `scripts/selftest.ps1` or `scripts/selftest.sh`.
2. Confirm `git`, Claude CLI discovery, Claude version, authentication status, required runner resources, mock parsing, and writable temp behavior.
3. Optionally dispatch a synthetic bundle containing no repository content with `-LiveProbe` or `--live-probe` after user approval. Confirm structured parsing and snapshot stability.
4. Report authentication or CLI absence as setup needed.

## Failure policy

- Retry once for timeout, missing output, malformed JSON, or a likely transient CLI error.
- Do not retry clear authentication, quota, model, configuration, or permission errors.
- Never fabricate a verdict around an error.
- Keep stderr concise and never include tokens or a full environment dump.

## Builder evaluation

For each finding, record decision, reason, and verification. Accept only findings supported by inspected code or empirical evidence. Re-scope valid concerns whose proposed remedy is too broad. Defer valid but out-of-scope work explicitly.

## Reporting

This reporting procedure is shared verbatim with the sibling skill Adversarial Reviewer Lite (Claude Code builder / Codex reviewer) so both directions produce the same report regardless of which model built and which reviewed.

Present findings as a readable report before any code changes. For each finding: what the reviewer found in plain language, why it matters for the user's product (concrete scenario, not theory), the builder's recommended action with reasoning (`accept`, `reject`, `re-scope`, `defer`, `needs verification`), and the verification evidence or "not yet verified". Short audits may collect decisions per finding; longer audits present all recommendations first, then a batch decision table. Batching never weakens the sign-off rule.

Offer an optional self-contained HTML audit report before fixes (ask first; it may create an `audits/` folder). Required structure, identical in both skills: metadata (repo, mode, reviewer backend and model, strict on/off, timestamp), top-level status badge, scorecard, executive summary, one card per finding (reviewer claim, impact, builder recommendation, verification evidence, user decision), rubric-results table when a rubric was provided (per-item PASS/FAIL/UNVERIFIABLE with evidence and skipped items), floor-gate status when floor-gated (categories and user outcome), glossary, and an update log if fixes were applied. Never include secrets or environment dumps.

End every terminal state with an operator summary containing exactly these fields:

- `Final status`: approved, revise, failed, not verified, or stopped by user.
- `What changed`: files or sections changed by the builder, or "nothing changed".
- `Reviewer findings`: accepted, rejected, re-scoped, deferred.
- `Verification`: commands run and results, or why not run.
- `Floor gate`: not applicable, or `floor-gated (<categories>)` with the user's review outcome.
- `Rubric`: not provided, or `<n> PASS / <n> FAIL / <n> UNVERIFIABLE`.
- `Structural changes`: list or "none".
- `Remaining risks`: concise, honest list.
- `Next step`: one practical action for the user.

State explicitly whether the user signed off on fixes; if not, say no fixes were applied.
