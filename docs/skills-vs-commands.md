# Skills vs Commands (and Subagents, and MCP)

Four extension mechanisms in Claude Code get confused constantly because they overlap in what they *can* do. The distinction that actually matters is **who triggers them** and **what they contain**. Get that right and the choice is usually obvious.

- [The one-paragraph version](#the-one-paragraph-version)
- [What is a Skill?](#what-is-a-skill)
- [What is a Command?](#what-is-a-command)
- [What is a Subagent?](#what-is-a-subagent)
- [What is an MCP?](#what-is-an-mcp)
- [Side-by-side](#side-by-side)
- [Decision guide](#decision-guide)
- [When NOT to use each](#when-not-to-use-each)

---

## The one-paragraph version

A **command** is a shortcut *you* type to fire a known prompt. A **skill** is a packaged procedure *Claude* loads when it's relevant, to do something the right way every time. A **subagent** is a *separate context window* you delegate a chunk of work to. An **MCP** is a *set of tools* that connects Claude to an external system or data source. Commands and skills change *what Claude does*; subagents change *where it does it*; MCP changes *what it can reach*.

---

## What is a Skill?

A skill is a folder — a `SKILL.md` with instructions, optionally plus bundled scripts, reference files, and templates. It encodes **how to do something well**: the steps, the discipline, the gotchas.

The defining trait: **skills are (primarily) model-invoked.** Claude reads the short description of every available skill and, when your task matches, loads the full skill and follows it — often without you naming it. Superpowers leans on this hard: ask to "build a feature" and the brainstorming skill activates on its own; hit a bug and the systematic-debugging skill kicks in.

Skills can also be user-invoked (`/skill-name`) when you want to force one.

```
my-skill/
  SKILL.md          # name, description (used for matching), instructions
  reference.md      # loaded only when needed (progressive disclosure)
  scripts/run.sh    # bundled helper the skill can call
```

**Use a skill when:** there's a *right way* to do a recurring kind of work and you want it applied consistently — TDD, debugging, code review, writing a plan, grilling a design. Skills carry process and judgment, not just a prompt.

Examples in this workflow: `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `superpowers:writing-plans`, `grill-me`, `handoff`.

> Creating your own: the `write-a-skill` / `writing-skills` skills scaffold one with proper structure and progressive disclosure.

---

## What is a Command?

A command is a **user-triggered prompt template** — a Markdown file under `.claude/commands/` (or provided by a plugin) that you invoke by typing `/name`. It expands into a prompt, optionally with arguments.

The defining trait: **commands are user-invoked and deterministic in *triggering*.** Nothing fires a command except you typing it. It's a keyboard shortcut for a chunk of instruction you'd otherwise retype.

```markdown
---
description: Open a PR with a filled template
---
Review the staged diff and open a pull request. Use the template in
.github/PULL_REQUEST_TEMPLATE.md. Title in imperative mood. $ARGUMENTS
```

```
/ship-pr fixes the rate-limit race condition
```

**Use a command when:** you repeatedly type the same instruction to start a known action, and you want it on a slash. Commands are about *convenience and consistency of invocation*, not about teaching Claude a procedure.

### Skill vs Command — the real difference

They blur because a skill can be invoked like a command and a command can contain procedural instructions. The clean split:

| | Skill | Command |
|--|-------|---------|
| Who triggers it | Claude (auto), or you | Only you |
| Primary purpose | Encode *how* to do something | Fire a known prompt fast |
| Contents | Instructions + scripts + references, progressive disclosure | A prompt template + arguments |
| Activates on its own? | Yes, when relevant | Never |
| Good for | Process, discipline, judgment | Shortcuts, ceremony, repeated kickoffs |

Heuristic: **if you'd want it to happen automatically when the situation arises, it's a skill. If it should only happen when you ask by name, it's a command.** "Always debug systematically" → skill. "Open a PR the way we like" → command (or a skill if there's real procedure to enforce, like `ship-pr`).

---

## What is a Subagent?

A subagent is a **delegated context window**. The main session (the orchestrator) spawns it with a task; it works in isolation with its own tools and its own context, and returns only a summary. It does not share the main conversation's history and cannot pollute it.

**Use a subagent when:** the work would flood the main context (broad codebase exploration, running a test suite, deep research), or when you want parallelism. Define reusable ones in `.claude/agents/` — see [Creating Agents by Repo](creating-agents.md). Scale them up into [agent teams or workflows](capabilities.md#subagents-vs-agent-teams-vs-workflows) when one isn't enough.

A subagent isn't an alternative to a skill or command — it's *where* they run. A subagent can itself invoke skills.

---

## What is an MCP?

An MCP (Model Context Protocol) server exposes a **set of tools** to Claude over a standard protocol — a database query tool, a Figma reader, a GitHub client, a project-context server. Claude calls them like built-in tools.

**Use an MCP when:** Claude needs to *reach an external system or authoritative data* that isn't in the repo — live library docs, design files, an issue tracker, internal metadata. MCP is about *capability and reach*, not process. Full treatment in [Setup → MCP Servers](setup.md#mcp-servers) and [Creating Your Own MCP](creating-mcp.md).

---

## Side-by-side

| | Skill | Command | Subagent | MCP |
|--|-------|---------|----------|-----|
| **Triggered by** | Claude (auto) or user | User only | Orchestrator | Claude (calls a tool) |
| **Answers** | *How* to do it well | *Start* this action | *Where* to do it | *What* it can reach |
| **Lives in** | `.claude/skills/` or plugin | `.claude/commands/` or plugin | `.claude/agents/` or built-in | external process + config |
| **Changes** | Behavior/process | Invocation convenience | Context isolation | Tool surface |
| **Costs** | Context when loaded | ~Nothing until typed | A separate context window | Tool-def tokens (deferred via ToolSearch) |

---

## Decision guide

```
Need Claude to reach an external system / live data?      → MCP
Want a recurring kind of work done the RIGHT way?         → Skill
Want a shortcut to fire a known prompt on demand?         → Command
Want to isolate or parallelize a chunk of work?           → Subagent
```

They compose. A typical heavy task: you type a **command** that kicks off a **skill**, which dispatches **subagents** to explore, and those subagents call an **MCP** for live docs. See [Prompting → Combined: Agent + Skill + MCP](prompting.md).

---

## When NOT to use each

- **Don't make a skill** for a one-off, or for something with no "right way" to encode — that's just a prompt. Skills you never auto-trigger are dead weight in the matcher.
- **Don't make a command** for something you want to happen automatically — a command that only helps if you remember to type it will be forgotten. Make it a skill (or a [hook](setup.md#hooks)) instead.
- **Don't spawn a subagent** for trivial work — the round-trip and the summarization lose fidelity and cost latency. Do small lookups inline.
- **Don't build an MCP** for data that already lives in the repo and is cheap to read, or for a one-time fetch — a `WebFetch` or a file read is simpler. Build an MCP when the access is *recurring* and *authoritative*.
- **Don't encode a hard rule as any of these** if it must hold *every single time* — the model can skip instructions. Deterministic rules belong in a [hook](setup.md#hooks). See [Memory & Rules](memory-and-rules.md).
