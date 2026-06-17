# Working Across Sessions

A Claude Code session is ephemeral. As established in [Under the Hood](under-the-hood.md#the-core-idea-its-just-a-message-array), the only state is the message array — when the session ends (or the context fills and gets compacted), that state is gone. Tools like **opencode**, Aider, and Cursor face the same wall: the model doesn't *remember* yesterday; it re-reads whatever you put in front of it.

So "resuming work" is really a documentation problem. The trick is to **externalize the state** that matters into durable files, so the next session — or the next agent — can rebuild context in seconds instead of re-deriving it. This document is the playbook.

- [The problem, precisely](#the-problem-precisely)
- [The layers of durable state](#the-layers-of-durable-state)
- [Handoff documents](#handoff-documents)
- [A progress / scratchpad file](#a-progress--scratchpad-file)
- [Plans and specs as resumable state](#plans-and-specs-as-resumable-state)
- [Git history as memory](#git-history-as-memory)
- [Searching past conversations](#searching-past-conversations)
- [/compact and /clear](#compact-and-clear)
- [A practical routine](#a-practical-routine)

---

## The problem, precisely

Three things end a session's working memory:

1. **You close it.** Tomorrow's session starts blank.
2. **Context fills up.** Long sessions get auto-compacted — older turns are summarized, and detail is lost.
3. **You hand off** to a teammate, a subagent, or a scheduled run that has none of your context.

In all three, the cure is the same: the information that's expensive to reconstruct (decisions, current state, what's left to do, what went wrong) must live somewhere outside the array.

---

## The layers of durable state

Think in layers, cheapest-to-richest:

| Layer | Lifespan | Holds | When it's read |
|-------|----------|-------|----------------|
| **`CLAUDE.md`** | Permanent, per-repo | Standing facts: what the project is, conventions, do-not-touch | Every session, automatically |
| **Memory** | Permanent, cross-repo | Facts about you and recurring preferences | Recalled when relevant ([Memory & Rules](memory-and-rules.md)) |
| **Spec / plan files** | Per-feature | The agreed design and the step-by-step plan | When you resume that feature |
| **Progress / scratchpad doc** | Per-task, short-lived | "Where I am right now, what's next, what's blocked" | At the start of the next work session |
| **Handoff doc** | One-shot | A compaction of *this* conversation for a pickup | By whoever continues |
| **Git history** | Permanent | What changed and why | On demand |

`CLAUDE.md` and memory are covered in [Memory & Rules](memory-and-rules.md). The rest are below.

---

## Handoff documents

The `handoff` skill exists exactly for this: it **compacts the current conversation into a handoff document** another agent (or future you) can pick up. Run it when a session is getting long, before you stop for the day, or before delegating.

```
/handoff
```

A good handoff captures what the message array would otherwise lose:

```markdown
# Handoff: rate-limiting feature

## Goal
Add per-tenant rate limiting to the public API.

## Status
- DONE: middleware skeleton in src/middleware/rateLimit.ts
- DONE: Redis token-bucket store, unit tested
- IN PROGRESS: wiring middleware into the router — see src/api/router.ts:88
- NOT STARTED: per-tenant config loading, docs

## Key decisions
- Token bucket, not sliding window (simpler, good enough) — see plan.md
- Limits read from tenant config, NOT env vars
- 429 response includes Retry-After header

## Open questions / blocked
- Need product to confirm default limit (assumed 100 req/min)

## How to resume
- Run `npm test` — 2 failing tests in router.test.ts are expected (next task)
- Next step: finish router wiring, then config loading
```

The skill produces something like this automatically; the structure is what matters — **goal, status, decisions, open questions, how to resume.**

---

## A progress / scratchpad file

For multi-day work, keep a single living file in the repo — `docs/PROGRESS.md`, `NOTES.md`, or a per-feature `docs/superpowers/specs/<feature>/progress.md`. Unlike a handoff (a snapshot), this is *updated as you go*. Ask Claude to maintain it:

> Keep `docs/PROGRESS.md` updated: a "Now / Next / Blocked" section and a running decision log. Update it whenever we finish a step or make a decision.

Then every new session starts with:

```
Read docs/PROGRESS.md and pick up where we left off.
```

This is the closest equivalent to how persistent-session tools feel: the file *is* the continuity, and any agent can read it.

---

## Plans and specs as resumable state

This is the biggest advantage of [Superpowers planning](planning.md#superpowers-planning): the spec and plan are **files on disk**, not chat. A plan written today is fully resumable next week — open the plan file, see which steps are checked off, continue. If you plan with durable artifacts, you get cross-session continuity almost for free. Native plan mode doesn't give you this unless you explicitly save the plan.

For long-running [dynamic workflows](capabilities.md#dynamic-workflows), resumability is built in: progress is journaled, and an interrupted run picks up from the longest unchanged prefix.

---

## Git history as memory

Commits are durable, searchable, and already part of your repo. They're a free continuity layer **if** they're written for a reader:

- **Atomic, well-described commits** mean `git log` reconstructs the *why* of recent work — see [Memory & Rules → atomic commits](memory-and-rules.md).
- Starting a session with `git log --oneline -20` and `git diff` orients Claude on recent changes faster than re-reading files.
- A draft PR with a filled description is itself a handoff doc that lives on the platform.

This is why the [commit discipline](code-review-and-git.md) in this workflow isn't just tidiness — small, meaningful commits are a continuity mechanism.

---

## Searching past conversations

When you don't even remember which session held a decision, the **episodic-memory** plugin can search prior Claude Code conversations semantically:

```
/episodic-memory:search-conversations  how did we decide to handle idempotency keys?
```

Use it to recover decisions, solutions, and lessons from past work before re-deriving them. It's a safety net, not a substitute for writing things down — but it turns "I know we discussed this" into a retrievable fact.

---

## /compact and /clear

Two built-ins for managing the array directly:

- **`/compact`** summarizes the conversation so far, freeing context while keeping the gist. Do it *after* writing a handoff or progress note, so nothing important depends solely on the soon-to-be-summarized detail.
- **`/clear`** wipes the conversation entirely. Safe only once durable state is written. Pair it with "read PROGRESS.md and continue" to start fresh without losing the thread.

---

## A practical routine

The habit that makes sessions feel continuous:

1. **Start:** `Read docs/PROGRESS.md` (or the plan file), then `git log --oneline -10`.
2. **During:** keep `PROGRESS.md` updated — Now / Next / Blocked + decision log.
3. **Before a long pause or context fills:** `/handoff` (or update `PROGRESS.md`), commit atomically, then `/compact`.
4. **Handing to someone/something else:** `/handoff` → share the doc, the plan file, and a draft PR.
5. **Lost a decision:** `/episodic-memory:search-conversations`.

Externalize the state, and the next session — human or agent — resumes in seconds.
