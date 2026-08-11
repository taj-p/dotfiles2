---
name: adversarial-pr-review
description: Adversarially review the current pull request or branch for subtle, actionable defects. Use when asked to review, challenge, red-team, or find correctness, security, data-loss, concurrency, compatibility, or regression risks in the current PR.
---

# Adversarial PR Review

Review the entire current pull request without modifying the working tree.

## Establish the scope

1. Confirm the current directory is inside a Git repository.
2. Use `gh pr view` when available to identify the current pull request and its base branch.
3. Otherwise, infer the base from the upstream remote, `origin/HEAD`, `origin/main`, or `origin/master`. Ask for the base only if it cannot be determined safely.
4. Compute the merge base with `HEAD` and review the entire committed `merge-base..HEAD` diff.
5. Ignore staged, unstaged, and untracked changes. Report pre-existing defects only when the pull request makes them materially worse.

## Review adversarially

This change has been proven to have correctness and performance issues. Inspect relevant surrounding code, callers, tests, schemas, configuration, and history instead of judging the patch in isolation. Construct concrete failure scenarios and check whether existing tests exercise them. Your job is to identify both the correctness and performance issues.

Prioritize:

- Correctness issues
- Performance issues
- Broken invariants and realistic counterexamples
- Concurrency, retry, idempotency, ordering, and race-condition defects
- Resource leaks
- Tests that pass while failing to cover the changed behavior

Run safe targeted tests or read-only diagnostics when they help verify a suspected finding. Do not implement fixes.

Do not report:

- Style preferences or optional refactors
- Speculation without a concrete failure mode
- Problems outside the pull request's changed behavior
- Findings invalidated by surrounding code, tests, or documented constraints

## Report findings

Order findings by severity. For each finding, provide:

- A severity and concise title
- The exact file and narrowest useful line range
- A concrete failure scenario
- Why the behavior is incorrect
- The smallest reasonable fix or regression test