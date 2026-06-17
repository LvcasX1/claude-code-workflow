# Memory & Project Rules

How to make a rule *stick* — like "every commit must be atomic, short, and have no co-author line." There are three places a rule can live, and they trade off **reach** against **reliability**. Picking the wrong one is why rules get ignored.

- [Three places a rule can live](#three-places-a-rule-can-live)
- [How to write a memory rule](#how-to-write-a-memory-rule)
- [Worked example: atomic commits, no co-authoring](#worked-example-atomic-commits-no-co-authoring)
- [Making it deterministic with a hook](#making-it-deterministic-with-a-hook)
- [Writing good rules](#writing-good-rules)
- [Decision guide](#decision-guide)

---

## Three places a rule can live

| Where | Scope | Reliability | Good for |
|-------|-------|-------------|----------|
| **`CLAUDE.md`** | One repo, every session | High (always in context) but model *follows*, can lapse | Project conventions, do-not-touch, stack facts |
| **Memory** | All repos, recalled when relevant | Medium (recalled, not always present) | Personal preferences, how *you* like to work |
| **Hook** | Wherever configured | Deterministic — the harness runs it, not the model | Hard rules that must hold *every single time* |

The crucial distinction: **`CLAUDE.md` and memory are instructions Claude reads and usually obeys. A hook is enforced by the harness, so it cannot be skipped.** If a rule is a strong preference, an instruction is enough. If it must be guaranteed, you need a hook.

---

## How to write a memory rule

Memory is a persistent, file-based store. The simplest way to add a rule is to just tell Claude in plain language:

```
Remember: all commits must be atomic, short and concise, no co-authoring line.
```

Claude writes it to a memory file and indexes it. Each memory is one fact in its own file with frontmatter, plus a one-line pointer in `MEMORY.md` (the index loaded each session). A `feedback`-type memory — guidance on *how you want Claude to work* — looks like this:

```markdown
---
name: atomic-commits
description: Commit style — atomic, short, no co-author line
metadata:
  type: feedback
---

All commits must be atomic (one logical change each), with short, concise
messages. Do NOT add a "Co-Authored-By" / "Generated with Claude Code" trailer.

**Why:** keeps `git log` a clean, reviewable history and keeps authorship honest.
**How to apply:** one change per commit; imperative subject ≤ ~50 chars; body only
when the *why* isn't obvious; never append co-author or tool-attribution trailers.

Related: [[branch-naming]]
```

Key points about memory entries:

- **One fact per file.** Don't cram unrelated rules together.
- **`type: feedback`** for "how to work" rules; `user` for who you are; `project` for ongoing work; `reference` for links.
- **Include the *why*.** A rule with a reason survives edge cases better than a bare command.
- **Link related rules** with `[[name]]`.

> Memory is recalled *when relevant*, not injected on every turn. For a rule you want present in **every** session of a given repo, also (or instead) put it in that repo's `CLAUDE.md`.

---

## Worked example: atomic commits, no co-authoring

This exact rule is a good case study because it benefits from **all three** layers, depending on how strict you need to be.

### Layer 1 — `CLAUDE.md` (per-repo, recommended baseline)

Add to the repo's `CLAUDE.md` so it's in context every session:

```markdown
## Commit rules
- One logical change per commit. No "WIP" or "misc fixes" commits.
- Subject: imperative mood, ≤ 50 chars. Body only to explain *why*.
- Do NOT add a "Co-Authored-By" or "Generated with Claude Code" trailer.
```

### Layer 2 — Memory (cross-repo, your default everywhere)

If you want this in *every* project without editing each `CLAUDE.md`, save it as the `feedback` memory shown above. It'll be recalled whenever you're committing.

### Layer 3 — Hook (deterministic, can't be skipped)

If "no co-author line" must be *guaranteed*, enforce it outside the model with a git hook. A `commit-msg` hook that strips the trailer:

```bash
# .git/hooks/commit-msg  (or a tracked hooks dir via core.hooksPath)
#!/usr/bin/env bash
# Strip any co-author / tool-attribution trailers before the commit lands.
sed -i.bak -E '/^Co-Authored-By:.*Claude/d; /^🤖 Generated with/d' "$1"
rm -f "$1.bak"
```

Make it executable (`chmod +x`). Now the trailer is removed regardless of what any tool writes — the rule holds even if an instruction is ever missed.

> The repo already documents this discipline in [Code Review & Git Flow](code-review-and-git.md), and the `ship-pr` skill is built to write *short, concise commits without co-authoring* by default — so the skill and the rule reinforce each other.

---

## Making it deterministic with a hook

A general principle, and the single most common mistake with rules: **anything phrased as "from now on, always / never / whenever X" is asking for deterministic behavior, and the model can't guarantee it — only the harness can.** Those belong in [hooks](setup.md#hooks) in `settings.json`, not in memory.

Examples that *must* be hooks, not memory:

| Desired rule | Mechanism |
|--------------|-----------|
| "Run the linter before every file write" | `PreToolUse` hook on `Edit`/`Write` |
| "Never let a commit keep a co-author trailer" | `commit-msg` git hook |
| "Block task completion until tests pass" | `TaskCompleted` hook |
| "Notify me when a long task finishes" | `Stop` hook |

Examples that are fine as memory / `CLAUDE.md` instructions (preferences, not guarantees):

| Desired rule | Mechanism |
|--------------|-----------|
| "Prefer atomic commits with short messages" | `CLAUDE.md` + memory |
| "Use async/await, not callbacks" | `CLAUDE.md` |
| "I like terse, caveman-style answers" | memory (`feedback`) |

The `update-config` skill can set up hooks for you when you describe an automated behavior.

---

## Writing good rules

- **Be specific and testable.** "Good commits" is unenforceable; "≤ 50-char imperative subject, one logical change, no co-author trailer" is.
- **State the why.** Rules with rationale generalize to cases you didn't enumerate.
- **Don't duplicate the repo.** Don't memorize things already obvious from the code, `CLAUDE.md`, or git history. If asked to remember something obvious, capture *what was non-obvious about it* instead.
- **Prune.** Wrong or stale rules are worse than none — delete them.
- **Match reach to reliability.** Preference → instruction (`CLAUDE.md`/memory). Guarantee → hook.

---

## Decision guide

```
Rule must hold EVERY time, no exceptions?        → Hook (settings.json / git hook)
Rule is a strong preference for THIS repo?       → CLAUDE.md
Rule is how YOU like to work, everywhere?        → Memory (feedback type)
One-off for this task only?                      → Just say it in the prompt
```

For the atomic-commit example: put it in `CLAUDE.md` as the baseline, add it to memory if you want it everywhere, and add the `commit-msg` hook if the no-co-author rule must be airtight.
