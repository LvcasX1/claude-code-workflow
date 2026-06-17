# Claude Code Capabilities (June 2026)

A snapshot of what Claude Code can do as of **June 17, 2026**. The CLI has moved well past "chat that can edit files." The defining shift of 2026 is **orchestration**: a single session can now plan work as code, fan out hundreds of subagents, run unattended on a schedule, and resume long jobs after interruption.

This document is the capability map. For the mechanics underneath it, read [Under the Hood — The Agent Loop](under-the-hood.md). For how the pieces fit a daily workflow, read [The Workflow](workflow.md).

- [The model lineup](#the-model-lineup)
- [Dynamic workflows](#dynamic-workflows)
- [Subagents vs agent teams vs workflows](#subagents-vs-agent-teams-vs-workflows)
- [/goal and /loop](#goal-and-loop)
- [Scheduled and background agents](#scheduled-and-background-agents)
- [ToolSearch and deferred tools](#toolsearch-and-deferred-tools)
- [Plan mode](#plan-mode)
- [Skills, commands, and memory](#skills-commands-and-memory)
- [Worktree isolation](#worktree-isolation)
- [Capability cheat sheet](#capability-cheat-sheet)

---

## The model lineup

| Model | Model ID | Role |
|-------|----------|------|
| Fable 5 | `claude-fable-5` | Newest frontier model |
| Opus 4.8 | `claude-opus-4-8` | Highest-capability coding/agentic model; `[1m]` variant gives a 1M-token context window |
| Sonnet 4.6 | `claude-sonnet-4-6` | Balanced default for everyday coding |
| Haiku 4.5 | `claude-haiku-4-5-20251001` | Fast, cheap — file search, simple lookups, high-throughput subagents |

"Fast mode" (`/fast`) runs Opus with faster output — it does **not** silently downgrade to a smaller model. Available on Opus 4.8/4.7/4.6.

Pick the model per task, not per session: a cheap Haiku subagent for read-only exploration, an Opus orchestrator for reasoning, Sonnet for the bulk of implementation. See [model selection per task](workflow.md#model-selection-per-task).

---

## Dynamic workflows

**The headline feature of 2026.** A dynamic workflow is a JavaScript orchestration script that Claude *writes for the task you describe*, then a runtime executes it in the background — spawning tens to hundreds of subagents in a single session, checking the work before anything reaches you.

The mental model is a promotion: **a workflow moves the plan out of the conversation and into code.** Instead of Claude holding the loop, the branching, and every intermediate result in its context window, the script holds them. Claude's context holds only the final answer.

```
Plan in conversation                  Plan in code (workflow)
─────────────────────                 ─────────────────────────
Claude tracks each step      →        Script tracks each step
Results pile into context    →        Results stay in the script
One agent, sequential        →        Hundreds of agents, parallel
Re-derives state each turn   →        Deterministic control flow
```

Why this matters beyond "more agents at once":

- **Context stays clean.** Hundreds of file reads and intermediate findings never pollute the main conversation — only the synthesized result returns.
- **Repeatable quality patterns.** Because control flow is code, a workflow can make agents *adversarially review each other* before a finding is reported: N independent skeptics try to refute each claim, and it survives only if the majority can't. This is hard to do reliably by hand.
- **Resumable.** Progress is journaled as the run proceeds. A job that's interrupted (or whose script you edit) picks up from the longest unchanged prefix instead of starting over.
- **Pipelines, not barriers.** Items flow through stages independently — item A can be in stage 3 while item B is still in stage 1 — so wall-clock time is the slowest single chain, not the sum of slowest-per-stage.

Common single-phase shapes:

| Shape | What it does |
|-------|--------------|
| Understand | Parallel readers over subsystems → structured map |
| Design | Panel of N independent approaches → scored synthesis |
| Review | Dimensions → find → adversarially verify each finding |
| Research | Multi-modal sweep → deep-read → synthesize with citations |
| Migrate | Discover sites → transform each (in isolated worktrees) → verify |

**Real-world scale:** the canonical proof point is Bun's creator porting roughly a million lines of Zig to Rust — file by file, faithfully, with the existing test suite passing at the end — in about **eleven days from first commit to merge** (~750,000 lines of Rust). That class of task used to be scoped in quarters.

**When to reach for a workflow vs. just talking to Claude:** workflows spawn a lot of agents and burn a lot of tokens. Use one when the task is genuinely large and parallelizable (codebase-wide audits, big migrations, exhaustive research) or when independent verification materially raises confidence. For a normal feature or bug fix, a single session — or a handful of subagents — is cheaper and just as good.

Availability: generally available in the Claude Code CLI, Desktop app, and VS Code extension for Pro, Max, Team, and Enterprise plans, plus the Claude API, Amazon Bedrock, Vertex AI, and Microsoft Foundry.

> Reference: [Introducing dynamic workflows in Claude Code](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) · [Orchestrate subagents at scale (docs)](https://code.claude.com/docs/en/workflows)

---

## Subagents vs agent teams vs workflows

Three mechanisms for doing more than one thing at once. They are not interchangeable — they differ in how work is coordinated and where the results land.

| | Subagents | Agent teams | Dynamic workflows |
|--|-----------|-------------|-------------------|
| What it is | Helpers spawned inside one session | Separate full Claude Code sessions | A JS script orchestrating subagents |
| Coordination | Orchestrator assigns; no peer messaging | Shared task list, self-claiming, peer-to-peer messaging | Deterministic code (loops, branches, pipelines) |
| Context | Each isolated; summary returns to main | Each is its own full session | Intermediate state lives in the script |
| Parallelism | Up to ~10 at once | 3–5 practical | Tens to hundreds |
| Control flow | Model-driven | Model-driven | Code — repeatable, journaled, resumable |
| Token cost | Lower | Higher (scales per teammate) | Highest |
| Status | Stable | Experimental | Generally available |
| Best for | Focused isolated tasks (explore, verify) | Work needing debate across independent sessions | Large, parallel, verification-heavy jobs |

Rule of thumb: **subagents** to keep noise out of the main context, **agent teams** when independent sessions need to challenge each other, **workflows** when the plan itself should become code. Detail and diagrams in [Agent Dispatch](workflow.md#agent-dispatch).

---

## /goal and /loop

Two commands that turn a one-shot prompt into something self-terminating or recurring:

- **`/goal`** defines *when the work is done* — a completion condition Claude must satisfy before it stops. It converts "try this" into "keep going until this is true."
- **`/loop`** repeats a task on an interval or until a condition is met. Useful for recurring reviews, monitoring, polling external state, or verification passes. Omit the interval and Claude self-paces the iterations.

```
/loop 5m /review                 # run /review every 5 minutes
/loop check the deploy until it goes green
/goal all tests pass and the diff is under 200 lines
```

`/loop` is for **in-session** recurrence (the session stays open). For recurrence that survives the session closing, use scheduled agents below.

---

## Scheduled and background agents

Claude Code can now run **unattended**:

- **Background tasks.** Long shell commands and even whole subagents can run detached; you're notified when they finish and re-invoked automatically, so there's no need to poll.
- **Scheduled cloud agents (routines).** Via the `/schedule` skill, register an agent to run on a cron schedule in the cloud — nightly dependency-bump checks, a morning PR-triage pass, a weekly security sweep — or a one-time future run ("run this once at 3pm"). These execute without your session open.

```
/schedule every weekday at 9am, triage new issues and label them
/schedule run the flaky-test hunt nightly at 2am
```

This is the capability that closes the gap with "always-on" agent platforms: work no longer has to happen while you watch.

---

## ToolSearch and deferred tools

Claude Code can connect to dozens of MCP servers, each exposing many tools — far more than fit usefully in one context window. To handle this, most tools are now **deferred**: only their names are loaded up front. When Claude needs one, it calls **`ToolSearch`** to fetch the full schema on demand, then calls the tool normally.

The payoff: you can have Slack, GitHub, Jira, a database MCP, Figma, and a dozen others connected at once without paying the token cost of all their tool descriptions on every turn. Tool schemas load only when relevant. This is why a session can scale to a large MCP surface without bloating context.

---

## Plan mode

Plan mode is a first-class, built-in state (`EnterPlanMode` / `ExitPlanMode`). In plan mode Claude researches and designs but **does not edit** — it presents a plan and waits for explicit approval before touching anything. Approval is the gate between "thinking" and "doing."

This is distinct from Superpowers' planning skills, which add spec-writing, structured review loops, and a separate execution phase on top. The two are complementary and frequently confused — [Planning: Plan Mode vs Superpowers](planning.md) compares them head to head and shows where grilling fits.

---

## Skills, commands, and memory

- **Skills** are model-invoked (or user-invoked) capability packages — instructions plus optional bundled scripts and references — that Claude loads when relevant. They encode *how* to do something well.
- **Commands** (`/name`) are user-triggered prompt templates — shortcuts you type to kick off a known action.
- **Memory** is a persistent, file-based store of facts about you, your preferences, and the project that carries across sessions.

These three are easy to conflate. [Skills vs Commands](skills-vs-commands.md) draws the lines and gives a decision guide; [Memory & Rules](memory-and-rules.md) covers how to encode standing rules (and why some rules belong in a hook instead).

---

## Worktree isolation

Subagents and tasks can run in their own **git worktree** — an isolated checkout — so parallel agents editing files don't collide and changes don't touch your working tree until merged. Workflows use this for parallel migrations: each file's transformation happens in its own worktree, auto-removed if unchanged. Custom subagents opt in with `isolation: worktree` in their definition.

---

## Capability cheat sheet

| You want to… | Reach for |
|--------------|-----------|
| Keep exploration noise out of the main context | Subagents (`Explore`) |
| Have independent sessions debate a problem | Agent teams |
| Run a huge parallel job with built-in verification | Dynamic workflow |
| Keep going until a condition is true | `/goal` |
| Repeat a task on an interval this session | `/loop` |
| Run a task on a schedule with no session open | `/schedule` (routines) |
| Plan safely without edits, then approve | Plan mode |
| Enforce a structured process (TDD, review) | Skills |
| Type a shortcut for a known action | Command |
| Carry facts across sessions | Memory |
| Connect many MCP servers cheaply | ToolSearch / deferred tools |
| Edit files in parallel without collisions | Worktree isolation |

> Sources: [Introducing dynamic workflows in Claude Code](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) · [Claude Code workflows docs](https://code.claude.com/docs/en/workflows) · [InfoQ: Dynamic Workflows for Parallel Agent Coordination](https://www.infoq.com/news/2026/06/dynamic-workflows-claude-code/)
