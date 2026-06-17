# Under the Hood — The Agent Loop

Everything in [Capabilities](capabilities.md) — workflows, subagents, plan mode, scheduled runs — sits on top of one small, surprisingly simple core: **the agent loop**. Understanding it changes how you prompt, because once you see that there is no hidden state machine, you stop expecting Claude to "remember" things that aren't in the message array, and you start managing context deliberately.

Much of what we know publicly about Claude Code's internals is mapped at **[Claude Code Unpacked (ccunpacked.dev)](https://ccunpacked.dev/)**, an interactive teardown of the source: the agent loop, the 50+ tools, multi-agent orchestration, and unreleased features, traced step by step.

- [How we know this](#how-we-know-this)
- [The core idea: it's just a message array](#the-core-idea-its-just-a-message-array)
- [The Agent Loop, step by step](#the-agent-loop-step-by-step)
- [The tool system](#the-tool-system)
- [The source tree](#the-source-tree)
- [Why this matters for how you work](#why-this-matters-for-how-you-work)

---

## How we know this

Two events made Claude Code's internals unusually well-documented for a closed-source tool:

1. **The source-map leak (March 31, 2026).** The npm package `@anthropic-ai/claude-code` v2.1.88 shipped with a ~59.8MB source map by mistake, which let people reconstruct the original TypeScript. (The npm distribution has since been deprecated in favor of the native installer.)
2. **System-prompt archaeology.** Projects like [Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts) track the full system prompt, the built-in tool descriptions, and the sub-agent prompts (Plan / Explore / Task) across versions.

Anthropic's own [agent SDK docs](https://code.claude.com/docs/en/agent-sdk/agent-loop) describe the same loop from the outside. The picture below combines all three.

---

## The core idea: it's just a message array

The single most important thing to internalize: **the only state is a message array.** No explicit state machine. No workflow graph. No hidden memory.

> The SDK runs the same execution loop that powers Claude Code: Claude evaluates your prompt, calls tools to take action, receives the results, and repeats until the task is complete. The entire loop is implemented in roughly **88 lines**.

At each step, Claude sees the *entire* conversation so far — system prompt, your turn, every prior tool call and its result — plus the full tool definitions, and produces the next message in a **single forward pass**. Which tool it picks, and with what arguments, is just the output of that pass. Nothing routes it; the model decides.

This has a direct consequence: **context is the program.** What's in the message array is what Claude "knows." Anything you want it to act on must be in that array (or retrievable via a tool). This is the whole reason subagents, workflows, `/compact`, and handoff documents exist — they are all strategies for controlling what occupies that finite array.

---

## The Agent Loop, step by step

ccunpacked.dev breaks the journey from keypress to rendered response into eleven stages:

```
1 Input  →  2 Message  →  3 History  →  4 System  →  5 API  →  6 Tokens
                                                                  │
                                                                  ▼
   11 Await  ←  10 Hooks  ←  9 Render  ←  8 Loop  ←  7 Tools?  ◄──┘
```

| # | Stage | What happens |
|---|-------|--------------|
| 1 | **Input** | You type a message (Ink's `TextInput` component) or pipe input through stdin in non-interactive mode. |
| 2 | **Message** | The raw input becomes a structured user message. |
| 3 | **History** | It's appended to the running conversation — the message array that *is* the state. |
| 4 | **System** | The system prompt, environment context, `CLAUDE.md`, and tool definitions are assembled. |
| 5 | **API** | The whole thing is sent to the model. |
| 6 | **Tokens** | The response streams back token by token. |
| 7 | **Tools?** | Did the model ask to call a tool? If yes → execute it, append the result to history, go back to **5**. If no → the turn is ending. |
| 8 | **Loop** | The execute-tool-and-resend cycle is the loop. It repeats until the model produces a turn with no tool calls. |
| 9 | **Render** | The final assistant text is rendered to the terminal as markdown. |
| 10 | **Hooks** | Lifecycle hooks fire (`PostToolUse`, `Stop`, etc.) — deterministic shell commands outside the model's context. |
| 11 | **Await** | Control returns to you for the next input. |

The loop (stages 5–8) is the engine. Everything else — plan mode, subagents, workflows — is a structured way of deciding *what goes into the array at stage 4 and how stage 7's tools behave*.

---

## The tool system

Claude Code ships 50+ built-in tools. ccunpacked groups them by what they do; the families that matter most day to day:

| Family | Tools |
|--------|-------|
| **File operations** | `FileRead`, `FileEdit`, `FileWrite`, `Glob`, `Grep`, `NotebookEdit` |
| **Execution** | `Bash`, `PowerShell`, `REPL` |
| **Search & fetch** | `WebFetch`, `WebSearch`, `ToolSearch`, `WebBrowser` (feature-gated) |
| **Agents & tasks** | `Agent`, `SendMessage`, `TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate`, … (11 total) |

A few things worth noting:

- **`Agent` and `SendMessage`** are the primitives behind subagents and agent teams — spawning helpers and routing messages between them.
- **The `Task*` family** is the shared to-do list that both you and agent teams read and write; it's how teammates self-claim work.
- **`ToolSearch`** is the entry point to the deferred-tool system ([see Capabilities](capabilities.md#toolsearch-and-deferred-tools)) — MCP tools aren't all loaded at once; their schemas are fetched on demand.
- **Tool selection is model-driven.** There is no rules engine deciding which tool runs. The model emits a tool call as part of its normal output, and the harness executes it.

---

## The source tree

The reconstructed source gives a rough sense of where the weight sits:

| Directory | Files (approx.) | Role |
|-----------|-----------------|------|
| `utils/` | 564 | Helpers and plumbing |
| `components/` | 389 | UI components |
| `commands/` | 189 | Slash commands |
| `tools/` | 184 | Built-in tool implementations |
| `services/` | 130 | Core services |
| `hooks/` | 104 | Lifecycle hook handling |
| `ink/` | 96 | Terminal UI (Ink) |
| `bridge/` | 31 | — |
| `constants/` | 21 | — |
| `skills/` | 20 | Skill loading |

The terminal UI is built on **Ink** (React for CLIs), which is why the interface re-renders like a web app and why streaming output feels live.

---

## Why this matters for how you work

The internals aren't trivia — they explain the workflow choices in the rest of this guide:

- **Context is finite and it *is* the state.** That's why you keep the main conversation lean, push exploration into [subagents](workflow.md#agent-dispatch), move big jobs into [workflows](capabilities.md#dynamic-workflows) so intermediate results never enter your array, and write [handoff docs](session-continuity.md) when a session gets long.
- **There's no hidden memory.** If you want a rule applied every time, it has to be in the array on every turn (`CLAUDE.md`, [memory](memory-and-rules.md)) or enforced outside the model ([hooks](setup.md#hooks)).
- **The model chooses tools.** Good tool descriptions and good [skills](skills-vs-commands.md) are how you bias those choices — you're shaping the inputs to a forward pass, not configuring a router.
- **Plan mode is a constraint on stage 7.** It simply withholds the editing tools until you approve, which is why it's safe to let Claude think freely in plan mode.

> Explore the full interactive teardown at **[ccunpacked.dev](https://ccunpacked.dev/)**. System-prompt and tool-description archive: [Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts). Official loop docs: [How the agent loop works](https://code.claude.com/docs/en/agent-sdk/agent-loop).
