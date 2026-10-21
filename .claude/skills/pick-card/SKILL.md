---
name: pick-card
description: "Use when asked to work the roadmap — 'pick a card', 'work the next card', 'implement card 0004', 'continue the roadmap'. Claims the next eligible card from roadmap.md, implements it strictly TDD reusing existing code, gets the diff code-reviewed, opens a PR and merges to main only when CI is green. For writing cards use new-card instead."
---

# pick-card — claim, build (TDD), review, merge

The roadmap protocol (statuses, pick rule, claim/release) lives in `roadmap.md` at the
repo root — it is authoritative. This skill is the worker's execution procedure.

## 1 · Sync & pick

- `git switch main && git pull`, then `just gitnexus-sync` and let it finish.
- Read `roadmap.md`. Pick per its Pick rule: topmost Queue row with status `todo`
  whose deps are all `done`. If the PO named a card, take that one — after verifying
  its deps; unmet deps → report and stop. Nothing eligible → report what blocks and stop.
- One claimed card at a time. Never reorder the Queue.

## 2 · Claim

Three writes together, before any code: card frontmatter `status: claimed`; Queue row
→ `claimed`; Journal line `YYYY-MM-DD · NNNN · claimed`. Then
`git switch -c card/NNNN-slug`.

## 3 · Load context

Read exactly what the card's Context points at, plus the conventions for the areas
touched (`testing` + `swift` always; others per the CLAUDE.md list) and
`docs/engineering/swift-quality-playbook.md` §10 for the card's row. Do not re-explore
what the card already answers; do not skip what it points at.

## 4 · Implement — strict TDD, reuse first

- Per todo: **red** — write the test, run it, watch it fail for the right reason;
  **green** — minimal change to pass; **refactor** — with the suite green. Tick todos
  in the card file as you go.
- Before writing any new function: Grep/Glob the Swift kits (gitnexus for the legacy Go,
  `repo:"astronomy"`, to find the rule being ported) for an existing one to reuse or extend. Duplicating existing logic is a review blocker.
- All new code ships with tests (table-driven, colocated, per
  `conventions/testing-conventions.md`; a port is pinned by a recorded oracle). Never weaken or delete an existing test
  without justification recorded in the PR body.
- **Sanity valve** — if the card's approach forces a weird pattern, a special-case
  cascade, or a fight with the existing architecture (`impact` will show it): STOP.
  Do not force it. Write what you learned into the card's Approach, set `blocked`
  (card + Queue + Journal, one-line reason), leave main untouched, and report a
  proposed rescope to the PO.

## 5 · Verify & review

- `just check` (hygiene + lint + build + full host suite, live tests included) must pass.
- Run the code-review skill on the working diff (`/code-review`). Fix every finding you
  agree with; record the ones you reject and why (they go in the PR body). Re-run
  `just check` after fixes. The pass is recorded on the PR in §6.

## 6 · Ship

- Commit per `conventions/commit-conventions.md` (scope = the card's area; no AI
  attribution anywhere in history).
- Push and `gh pr create` — title = the card title in commit style, body = card ID,
  the acceptance criteria as a checklist, and the review notes.
- Record the review pass from the pushed branch: **`just review-pass <n> "<findings fixed
  / rejected and why>"`** — it posts `code-review: passed <head sha>` on the PR (refusing a
  dirty tree or a local commit that is not the PR head), and `just merge` refuses without
  it. The marker is bound to the head: any later push (a CI fix, a rebase) needs a fresh
  `/code-review` of the new diff and a new `just review-pass`.
- CI (`.github/workflows/tests.yml`) runs two jobs on the PR: `test continuity`
  (Linux: the suite may only grow — a deleted or edited existing test, or a lower
  test count, fails unless the PR body has a `Test-change: <why>` line) and
  `hygiene · lint · build · test` (macOS: `just ci`, live suites self-skip).
- **The worker merges; the PO is not in the loop** (PO decision 2026-10-20), and the
  only way to do it is **`just merge <n>`** (`scripts/merge-pr.sh`): it waits for the
  checks, refuses unless every CI job exists and is green on the PR's current head
  **and** a `just review-pass` marker names that head, then squash-merges and deletes the
  branch (works from a worktree). Never call `gh pr merge` directly, never
  `--auto` (no branch protection here). A refusal → fix on the branch and push; after
  **two** red rounds on the same card, stop, set `blocked` with the failing check in
  the Journal, and report. Never weaken a test to get green, never skip the
  `/code-review` of §5.
- The `test continuity` job also refuses production code without tests: a PR that
  touches `apps/macos/Sources` must touch `Tests/` or raise the test count, or carry a
  `No-test: <why>` line in the body (pure configuration, wiring — nothing else).
- `Manual:` acceptance items (open the app, take a screenshot) are performed by the
  worker with `just app-run` and recorded in the PR body; they never wait for the PO.

## 7 · Release

After the merge: card frontmatter `done` (acceptance boxes ticked), Queue row `done`,
Journal line `YYYY-MM-DD · NNNN · done (PR #N) · next: <one line the next card must
know — a seam, a decision, a tolerance, a gotcha>`. `git switch main && git pull`,
delete the local branch, then **`just check` on main** so the next card starts from a
proven green state (host-tool drift shows up here, not in the middle of a port). If
`just coverage` exceeds `apps/macos/.coverage-floor`, raise the floor to the new whole
percent on the next card's branch. If the session must end before the merge, leave a
Journal line saying exactly where the card stands — a claim without a journal trail
is a protocol violation.

## 8 · Chain

The PO works the roadmap by the epic, not by the card: unless told to stop after one
card, go back to **§1** after every release and claim the next eligible card. The
chain stops by itself, with a report, when:

- nothing is eligible (blocked dependencies, or the Queue is empty);
- the next card is a **planning** card (0058, 0062, 0063, 0065: they produce cards
  and need PO decisions) — write it as far as the card allows, then stop;
- a card hits the sanity valve (§4) or two red CI rounds (§6);
- a card needs something only the PO can provide (an install, a capture, a licence).

Continuity between cards is mechanical, never remembered: the previous card's
`next:` Journal line is read in §3; every module ships a `README.md` that says how to
extend it (cards 0044 and 0049 demand one — keep them current); the full suite of
every earlier card runs on each PR; the test-continuity job refuses a shrinking
suite. A test that no longer describes the behaviour is changed in the open, with a
`Test-change:` line and the reason in the PR body, never silently.

## Report

After each card: one short paragraph — what merged (PR link), the tests that now pin
the behaviour, the `next:` line. At the end of a chain: the cards merged, the card
that stopped the chain and why, and what the PO must decide or provide.
