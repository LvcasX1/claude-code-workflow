# Agentic Development with Claude Code

Agentic development is the practice of delegating multi-step engineering work to an AI agent that plans, executes, and validates tasks autonomously — rather than answering one prompt at a time. Instead of asking Claude "write this function" and manually applying the result, you give it a goal and let it explore the codebase, reason about the approach, write the code, review it, and prepare a commit. The developer's role shifts from typist to reviewer.

This repository documents the full setup behind that workflow: the tools, the configuration, the skills layer that governs agent behavior, and the patterns that make it reliable in practice. It is grounded in the architectural patterns described in [claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice) — the separation of subagents, commands, skills, and workflows into distinct concerns, and the Research → Plan → Execute → Review → Ship loop as the foundation of every task.

```mermaid
graph TD
    A[Claude Code CLI] --> B[Superpowers Skills]
    A --> C[MCP Servers]
    A --> D[Agent Dispatch]

    B --> B1[Plan Mode]
    B --> B2[Brainstorming]
    B --> B3[TDD / Debugging]
    B --> B4[Code Review]

    C --> C1[Context7]
    C --> C2[Local Custom MCP]
    C --> C3[Remote MCPs]

    D --> D1[Parallel Subagents]
    D --> D2[Agent Teams]
```

---

## Quick Start

**Option A — guided setup (recommended):**

```bash
# 1. Install Claude Code
curl -fsSL https://claude.ai/install.sh | bash

# 2. Clone this repo and run the setup script
git clone https://github.com/LvcasX1/claude-code-workflow
cd  claude-code-workflow 
./setup.sh
```

The script installs plugins, walks you through MCP selection, collects API keys, and verifies everything works. Re-running it skips steps that are already done.

**Option B — manual minimal setup:**

```bash
# 1. Install Claude Code
curl -fsSL https://claude.ai/install.sh | bash

# 2. Install Superpowers
claude plugin install superpowers@claude-plugins-official

# 3. Start in your project
cd /path/to/your/project
claude
> /init
```

That is enough to get the structured workflow running. `/init` generates `CLAUDE.md` and from that point every task follows the Research → Plan → Execute → Review → Ship loop enforced by Superpowers skills.

The rest of this guide covers the full setup: MCP servers for live context, parallel agents, git flow, and creating your own MCP.

---

## Table of Contents

1. [Setup](#setup)
   - [Claude Code CLI](#claude-code-cli)
   - [Superpowers Skills](#superpowers-skills)
   - [Caveman](#caveman)
   - [MCP Servers](#mcp-servers)
2. [Workflow Approach](#workflow-approach)
   - [Repo Init](#repo-init)
   - [Building Knowledge](#building-knowledge)
   - [Skills and Plan Mode](#skills-and-plan-mode)
   - [Agent Dispatch](#agent-dispatch)
   - [CCStatusLine](#ccstatusline)
3. [Creating Agents by Repo](#creating-agents-by-repo)
4. [Prompting](#prompting)
5. [Code Review](#code-review)
6. [Git Flow](#git-flow)
7. [Example Projects](#example-projects)
8. [Creating Your Own MCP](#creating-your-own-mcp)
9. [Credits](#credits)

---

## Setup

### Claude Code CLI

Claude Code is Anthropic's official CLI for running Claude as an interactive coding agent.

The recommended installation method is the native installer, which auto-updates in the background and requires no external dependencies.

**macOS, Linux, WSL:**

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://claude.ai/install.ps1 | iex
```

**Homebrew (macOS):**

```bash
brew install --cask claude-code
```

> The npm package (`npm install -g @anthropic-ai/claude-code`) is deprecated. Use the native installer above. If you have an existing npm installation, migrate with:
>
> ```bash
> curl -fsSL https://claude.ai/install.sh | bash
> npm uninstall -g @anthropic-ai/claude-code
> ```

Verify the installation:

```bash
claude --version
claude doctor
```

Start a session by running `claude` inside any project directory. Authentication is handled on first launch via a browser prompt — you need a Pro, Max, Team, or Enterprise account.

For full configuration options see the [Claude Code documentation](https://code.claude.com/docs/en/getting-started).

Claude Code stores persistent configuration in `~/.claude/settings.json`. This is where you set environment variables, default models, permission modes, and feature flags that apply across all sessions:

```json
{
  "model": "claude-sonnet-4-6",
  "env": {
    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-haiku-4-5-20251001",
    "DISABLE_AUTOUPDATER": "0"
  }
}
```

Project-specific settings go in `.claude/settings.json` at the repository root and override user-level settings for that project. Commit this file to version control to share configuration across the team.

---

### Superpowers Skills

Superpowers is a skills plugin system for Claude Code. It installs a set of behavioral rules — called skills — that intercept Claude's responses and enforce structured workflows. When you invoke a skill (via `/skill-name` in the prompt), Claude loads the skill's instructions and follows them exactly before doing anything else.

This is what makes the workflow reproducible. Without skills, Claude improvises. With skills, it follows the same disciplined process every time: brainstorm before building, write a plan before touching code, verify before claiming completion.

Install Superpowers via the Claude Code plugin manager:

```bash
claude plugin install superpowers@claude-plugins-official
```

Verify that skills are available:

```bash
claude /find-skills
```

Superpowers repo: [obra/superpowers](https://github.com/obra/superpowers)

---

### Caveman

Caveman is a token compression plugin that instructs Claude to respond in a stripped-down, high-density syntax — dropping articles, filler words, and pleasantries while preserving full technical accuracy. Real-world savings range from 22% to 87% per prompt. Code blocks, commit messages, and PR descriptions bypass the filter and remain in normal prose.

Install via the Claude Code plugin manager:

```bash
claude plugin install caveman@caveman
```

Repo: [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)

---

### MCP Servers

An MCP (Model Context Protocol) server is a process that runs alongside Claude Code and exposes a set of callable tools over a standard protocol. Claude treats MCP tools the same way it treats built-in tools like `Read` or `Bash`: it decides when to call them, passes arguments, and incorporates the result into its reasoning. The difference is that MCP tools are domain-specific — you define exactly what they return and how.

From Claude's perspective, calling an MCP tool is no different from reading a file. From the developer's perspective, it means Claude gets precise, structured, on-demand information instead of having to discover it by reading code.

#### MCP vs codebase reading

When Claude starts a task without an MCP, it discovers context by reading files: directory listings, source files, configuration, tests. This works, but it is expensive. For every file read, Claude consumes tokens on content that may be irrelevant to the task at hand.

A project MCP inverts this: instead of Claude reading broadly and filtering, it queries a server that returns exactly the fact it needs — an architecture summary, an owner, a list of relevant files — in one call.

The difference compounds on larger codebases and multi-step tasks:

| Task | Without MCP (codebase read) | With project MCP |
|------|-----------------------------|------------------|
| Identify the entry point for the payments module | Read 8–15 files to trace imports and find the handler | 1 tool call: `get_project_info({ section: "architecture" })` |
| List all chain definitions in the project | Recursive directory walk + filter | 1 tool call: `find_files({ directory: "src/chains", extension: ".py" })` |
| Find the on-call contact before escalating a bug | Search `CODEOWNERS`, `README`, Slack docs | 1 tool call: `get_project_info({ section: "team" })` |
| Understand the dependency constraints before adding a package | Read `pyproject.toml`, `requirements.txt`, inline comments | 1 tool call: `get_project_info({ section: "dependencies" })` |

Approximate token impact on a 50k-line Python monorepo:

| Scenario | Tokens consumed (input) | Latency |
|----------|------------------------|---------|
| Claude reads codebase to orient before a feature task | 18,000 – 40,000 | 25 – 60 s |
| Claude calls project MCP for the same orientation | 400 – 800 | 1 – 3 s |
| Claude reads files to find all chain definitions | 6,000 – 12,000 | 10 – 20 s |
| Claude calls `find_files` via MCP | 200 – 400 | < 1 s |

These are illustrative estimates based on typical file sizes and tool call overhead. Actual numbers vary by codebase structure, model, and task complexity. The key property is that MCP queries scale with the answer, not with the size of the codebase.

The secondary benefit is accuracy. When Claude reads source files to extract facts like ownership or architectural intent, it infers — and inference can be wrong. An MCP tool returns the authoritative value defined by the team, not Claude's interpretation of a comment in a file that may be out of date.

#### MCPs used in this workflow

| MCP | Repo | Description |
|-----|------|-------------|
| [Context7](https://github.com/upstash/context7) | upstash/context7 | Fetches live, version-accurate documentation for any public library or framework. Claude calls it instead of relying on training data that may reflect an older API version. Requires an API key from [context7.com](https://context7.com). |
| [Figma](https://github.com/figma/mcp-server-guide) | figma/mcp-server-guide | Gives Claude direct access to Figma design files, component structures, and layout information, enabling implementation from design without manual handoff. |
| [Coda](https://github.com/orellazri/coda-mcp) | orellazri/coda-mcp | Bridges Claude to Coda documents, allowing it to read and write pages, tables, and rows — useful for syncing implementation state with project documentation. |

Context7 example using the same section-focused query pattern as the project MCP:

```
use context7 to get the LangChain LCEL interface documentation, focusing on the pipe operator and chain composition
```

Context7 exposes two tools internally: `resolve-library-id` to identify the library and `get-library-docs` to fetch the relevant section. Claude calls them in sequence and proceeds with accurate, version-matched API references — one tool call instead of Claude inferring from stale training data.

| Step | Without Context7 | With Context7 |
|------|-----------------|---------------|
| Get current LCEL chain composition API | Claude uses training data (may be stale) or you paste docs manually | 1 tool call, live docs fetched at query time |
| Resolve correct method signatures for the installed version | Guess from training data or read source in `site-packages` | Context7 matches docs to the library version in use |
| Implement without hallucinating deprecated methods | Not guaranteed | Accurate: docs reflect the actual current API |

#### Figma

Gives Claude access to Figma files, components, and layout data. Requires a Figma personal access token.

```bash
claude mcp add --scope user figma -- npx -y @figma/mcp-server --figma-api-key ${FIGMA_API_KEY}
```

Add `FIGMA_API_KEY=your_figma_personal_access_token` to your environment or `.env.example`.

#### Coda

Bridges Claude to Coda documents for reading and writing pages, tables, and rows. Requires a Coda API token.

```bash
claude mcp add --scope user coda -- npx -y coda-mcp --api-key ${CODA_API_KEY}
```

Add `CODA_API_KEY=your_coda_api_token` to your environment or `.env.example`.

#### Local Custom MCP

A local MCP gives Claude access to project-specific context, internal tools, or domain knowledge that no public server provides. The setup section of this repo includes an example implementation with `get_project_info` and `find_files` tools — see [Creating Your Own MCP](#creating-your-own-mcp) for the full TypeScript implementation.

Register a local MCP by pointing Claude at the compiled server entry point:

```bash
claude mcp add my-local-mcp -- node /path/to/my-mcp/dist/index.js
```

Or add it to your Claude config directly:

```json
{
  "mcpServers": {
    "my-local-mcp": {
      "command": "node",
      "args": ["/path/to/my-mcp/dist/index.js"]
    }
  }
}
```

#### Remote MCPs

Remote MCPs connect Claude to cloud services (GitHub, Slack, Jira, etc.) via HTTP or SSE transport. The registration pattern is the same; the transport layer differs:

```bash
claude mcp add --transport sse my-remote-mcp https://my-mcp-host.example.com/sse
```

List all registered MCPs and their status:

```bash
claude mcp list
```

#### Project-scoped MCP Configuration with `.mcp.json`

The `claude mcp add` command registers MCPs globally in your user config. For project-specific MCPs that should be available to every developer who clones the repository — without requiring manual registration — use a `.mcp.json` file at the repository root.

Claude Code detects `.mcp.json` automatically when starting a session in that directory and makes all servers defined in it available for that session. This is the recommended approach for local MCPs tied to a specific project.

Create `.mcp.json` at the root of the repository:

```json
{
  "mcpServers": {
    "project-context": {
      "command": "node",
      "args": ["./mcp/dist/index.js"],
      "description": "Project-specific context and internal API documentation"
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp", "--api-key", "${CONTEXT7_API_KEY}"],
      "description": "Live library documentation"
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
      },
      "description": "GitHub issues, PRs, and repository access"
    }
  }
}
```

Key points about `.mcp.json`:

- **Scope**: applies only to sessions started in the directory containing the file. Global MCPs registered via `claude mcp add` remain active alongside it.
- **Environment variables**: use `${VAR_NAME}` syntax to reference shell environment variables. Secrets are never hardcoded in the file.
- **Version control**: commit `.mcp.json` to the repository so all contributors get the same MCP setup. Add a `.env.example` listing required environment variables so developers know what to set locally.
- **Local MCP paths**: use relative paths (e.g., `./mcp/index.js`) so the config works on any machine after cloning.

A matching `.env.example` for the config above:

```bash
# .env.example
GITHUB_TOKEN=your_github_personal_access_token_here
CONTEXT7_API_KEY=your_context7_api_key_here
```

---

## Workflow Approach

```mermaid
flowchart LR
    A[Repo Init] --> B[Build Knowledge]
    B --> C[Activate Skills]
    C --> D[Dispatch Agents]
    D --> E[Prompt + Execute]
    E --> F[Review]
    F --> G[Commit]
```

### Repo Init

Every new repository starts with `/init`. This command instructs Claude to explore the codebase — directory structure, dependencies, existing conventions — and generate a `CLAUDE.md` file at the root.

```
/init
```

`CLAUDE.md` is the project's standing instructions for Claude. It tells the agent what the project does, which patterns to follow, which files not to touch, and any project-specific constraints. Claude reads this file at the start of every session.

A minimal `CLAUDE.md` looks like this:

```markdown
# Project Context

This is a TypeScript REST API built with Express and Prisma.

## Conventions
- Use async/await, not callbacks
- All database access goes through the repository layer in src/repositories/
- Run `npm test` before committing

## Do Not Modify
- src/migrations/ — managed by the DBA team
```

---

### Building Knowledge

For projects with internal APIs, proprietary domain models, or documentation that Claude has no training data for, a local MCP fills that gap. Instead of pasting long context into every prompt, you register a server that Claude can query on demand.

The local MCP in this repo exposes project-specific context as structured tools. Claude calls the MCP during planning and execution phases to retrieve accurate information rather than inferring from incomplete context.

Register and verify the local MCP before starting work on a new repository:

```bash
claude mcp add project-context -- node ./mcp/dist/index.js
claude mcp list
```

---

### Skills and Plan Mode

Skills are the core mechanism that makes this workflow structured rather than ad-hoc. When Superpowers is installed, Claude checks at the start of every task whether a skill applies. If one does, it loads the skill's instructions and follows them before taking any other action.

The most visible example is plan mode. When a task requires implementation — writing code, creating files, making changes — Claude enters plan mode before touching anything. It explores the codebase, asks clarifying questions one at a time, proposes approaches, and presents a full plan for approval. Only after the user approves does Claude begin implementation.

Here is what plan mode looks like in practice. The task list appears in the terminal as Claude works through the structured workflow:

```
7 tasks (1 done, 1 in progress, 5 open)
  ✔ Explore project context
  ◼ Ask clarifying questions
  ◻ Propose 2-3 structural approaches
  ◻ Present design sections and get approval
  ◻ Write design doc
  ◻ Spec self-review and user approval
  ◻ Transition to writing-plans
```

Each step has a specific purpose:

| Step | What happens |
|------|-------------|
| Explore project context | Claude reads relevant files, checks git history, identifies existing patterns |
| Ask clarifying questions | One question at a time — Claude does not make assumptions about intent |
| Propose 2-3 approaches | Each approach includes trade-offs and a recommendation |
| Present design sections | The plan is shown section by section; the user approves each part |
| Write design doc | The approved spec is written to `docs/superpowers/specs/` |
| Spec self-review | Claude checks for placeholders, contradictions, and ambiguity before handing off |
| Transition to writing-plans | A separate skill generates the step-by-step implementation plan |

This structure prevents the most common failure mode of AI-assisted development: Claude doing a lot of work in the wrong direction before the developer notices.

---

### Agent Dispatch

Claude Code has two distinct mechanisms for parallel work. Choosing the right one determines how agents communicate, how results flow back, and what the token cost looks like.

#### Parallel subagents

Subagents run within a single session. The orchestrator spawns them, they work in isolated context windows, and they return a summary to the main conversation when done. They cannot message each other — all coordination goes through the orchestrator.

```mermaid
flowchart TD
    O[Orchestrator\nmain model] --> A1[Explore Agent\nHaiku — codebase structure]
    O --> A2[Explore Agent\nHaiku — existing patterns]
    O --> A3[Plan Agent\ninherits — design approaches]

    A1 -->|summary only| S[Synthesize results]
    A2 -->|summary only| S
    A3 -->|summary only| S

    S --> I[Implementation]
```

Up to 10 subagents run simultaneously in a single session. Each operates in its own context window — exploration results and intermediate output never pollute the main conversation. The orchestrator receives only the final summary from each subagent.

The `superpowers:dispatching-parallel-agents` skill governs when subagents are dispatched. It prevents unnecessary parallelism (which wastes tokens) and enforces sequential execution when agents share state or file dependencies.

Use subagents for:

- Parallel codebase exploration before implementation
- Isolated verification tasks (type checking, linting, tests)
- Targeted research that would flood the main context

#### Agent teams

Agent teams are separate, fully independent Claude Code sessions that coordinate through a shared task list and a messaging mailbox. Unlike subagents, teammates can send messages directly to each other without routing through the lead.

```mermaid
flowchart TD
    L[Team Lead] -->|assigns tasks| TL[Task List]
    L -->|spawns| T1[Teammate: security]
    L -->|spawns| T2[Teammate: performance]
    L -->|spawns| T3[Teammate: test coverage]

    T1 <-->|direct messaging| T2
    T2 <-->|direct messaging| T3
    T1 <-->|direct messaging| T3

    T1 -->|claims & completes| TL
    T2 -->|claims & completes| TL
    T3 -->|claims & completes| TL

    TL -->|all done| L
```

Agent teams are experimental and disabled by default. Enable them in `settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Spawn a team from a prompt to the lead:

```
Create an agent team to review PR #142. Spawn three reviewers:
- One focused on security implications
- One checking performance impact
- One validating test coverage
Have them review in parallel and report findings.
```

Teammates self-claim tasks from the shared list as they finish their current work. Task claiming uses file locking to prevent race conditions when multiple teammates try to claim the same task simultaneously. When a task that others depend on is completed, blocked tasks unblock automatically.

| | Parallel subagents | Agent teams |
|--|-------------------|-------------|
| Communication | Orchestrator only | Direct teammate-to-teammate messaging |
| Coordination | Orchestrator assigns | Shared task list, self-claiming |
| Context | Summarized back to main | Each teammate is a full independent session |
| Token cost | Lower | Higher — scales linearly with teammate count |
| Best for | Focused isolated tasks | Complex work requiring debate and collaboration |
| Status | Stable | Experimental |

The strongest use cases for agent teams are tasks where teammates benefit from challenging each other: parallel PR review with different lenses, debugging with competing hypotheses, or cross-layer changes where frontend, backend, and test work can be owned independently.

Start with 3–5 teammates. Beyond that, coordination overhead and token cost increase faster than throughput. Keep teammates from editing the same files — two teammates writing to the same file leads to overwrites.

#### Model selection per task

Claude Code routes each subagent or teammate to a model based on the nature of the task. The model is resolved in this order:

1. The `CLAUDE_CODE_SUBAGENT_MODEL` environment variable — set in `~/.claude/settings.json` under `env` for a persistent global default, or exported in the shell for a session-scoped override
2. The per-invocation `model` parameter passed by the orchestrator
3. The `model` field in the subagent's definition file
4. The main conversation's model (`inherit`, the default)

Built-in subagents follow this allocation:

| Subagent | Model | Reason |
|----------|-------|--------|
| Explore | Haiku | Read-only file search — low latency, high throughput |
| Plan | Inherits | Research during plan mode — needs orchestrator-level reasoning |
| General-purpose | Inherits | Multi-step tasks requiring exploration and modification |
| Claude Code Guide | Haiku | Feature questions — simple lookups |
| statusline-setup | Sonnet | Lightweight configuration with reliable instruction following |

**File reads and directory listings run on Haiku.** The Explore agent handles these with read-only tools and minimal context. **MCP tool calls are inherited by all subagents** by default — you can scope a specific MCP to a single subagent to keep its tool descriptions out of the main context window entirely.

Custom subagents set their model and behavior in a frontmatter definition stored in `.claude/agents/`:

```yaml
---
name: api-reviewer
description: Reviews API surface for breaking changes and security issues
tools: Read, Grep, Glob
model: sonnet
---

You are an API reviewer. Analyze the public interface for breaking changes,
missing validation, and security issues. Return a structured report.
```

The `effort` field controls reasoning depth independently of the model. `effort: max` on Opus 4.6 enables extended thinking:

```yaml
---
name: architect
description: Designs system architecture and evaluates trade-offs for complex tasks
model: opus
effort: max
---
```

Subagents can run in isolated git worktrees so their changes do not affect the working tree until merged:

```yaml
---
name: refactor-agent
description: Performs large-scale refactors in an isolated branch
model: sonnet
isolation: worktree
---
```

---

### CCStatusLine

CCStatusLine is a status line integration that surfaces Claude Code session state directly in your terminal prompt. It shows the active model, current and remaining context window, and git state — removing the need to switch windows to check what Claude is doing mid-session.

Repo: [sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline)

Install via npm or bun:

```bash
npm install -g ccstatusline
# or
bunx ccstatusline
```

Then point Claude Code to it by running `/statusline` in a session. Claude Code will guide the configuration interactively.

The config used in this workflow is at [`config/ccstatusline.json`](config/ccstatusline.json). Copy it to `~/.config/ccstatusline/settings.json` to use it directly.

```json
{
  "version": 3,
  "lines": [[
    { "type": "git-root-dir",      "color": "brightWhite" },
    { "type": "separator" },
    { "type": "git-branch",        "color": "brightYellow" },
    { "type": "separator" },
    { "type": "git-insertions",    "color": "brightGreen" },
    { "type": "custom-text",       "customText": " " },
    { "type": "git-deletions",     "color": "hex:f7768e" },
    { "type": "separator" },
    { "type": "custom-text",       "customText": "Current Ctx: " },
    { "type": "context-length",    "color": "brightCyan",  "rawValue": true },
    { "type": "separator" },
    { "type": "custom-text",       "customText": "Remaining Ctx: " },
    { "type": "context-percentage","color": "brightGreen", "rawValue": true, "metadata": { "inverse": "true" } },
    { "type": "separator" },
    { "type": "model",             "color": "cyan",        "rawValue": true }
  ]],
  "flexMode": "full-minus-40",
  "compactThreshold": 60,
  "colorLevel": 3
}
```

What each segment shows:

| Segment | Description |
|---------|-------------|
| `git-root-dir` | Repository name — confirms which project Claude is working in |
| `git-branch` | Current branch |
| `git-insertions` / `git-deletions` | Lines added and removed since the last commit — a live diff summary |
| `context-length` | Raw token count of the current context window |
| `context-percentage` (inverse) | Remaining context as a percentage — counts down as the session grows |
| `model` | The active Claude model for the session |

`flexMode: "full-minus-40"` keeps the status line 40 characters shorter than the terminal width, leaving room for the shell prompt. `compactThreshold: 60` collapses to a shorter format on narrow terminals.

---

### Hooks

Hooks are shell commands that Claude Code executes automatically at specific points in the session lifecycle — before or after a tool call, when Claude goes idle, when a subagent finishes, or when a task changes state. They run in the background, outside Claude's context, and can block, modify, or log tool activity without consuming tokens.

Common uses in this workflow:

| Hook event | Use |
|------------|-----|
| `PreToolUse` (Edit, Write) | Run linter before every file write to catch issues before they land |
| `PostToolUse` (Bash) | Log command output to a file for audit trails |
| `Stop` | Send a desktop notification when Claude finishes a long task |
| `TeammateIdle` | Quality gate — block a teammate from going idle until a test passes |
| `TaskCompleted` | Prevent task completion until a required check has run |

Hooks are configured in `settings.json` under the `hooks` key:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "ruff check ${file} --fix"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "notify-send 'Claude Code' 'Session complete'"
          }
        ]
      }
    ]
  }
}
```

A hook that exits with code `2` sends its stdout back to Claude as feedback and blocks the triggering action. Any other non-zero exit blocks the action silently. Exit `0` allows it to proceed.

Full hook reference: [Claude Code hooks documentation](https://code.claude.com/docs/en/hooks)

---

## Creating Agents by Repo

An agent in this workflow is a specialized Claude invocation configured with a specific role, set of tools, and scope of authority. Rather than using a generic Claude session for every task, you create a purpose-built agent for each repository or domain.

Agents are defined as Markdown files with YAML frontmatter stored in `.claude/agents/`. Committing that directory makes the agents available to everyone who clones the repository — no manual registration required.

### How to Create an Agent

The fastest way is the `/agents` command inside a Claude Code session:

```
> /agents
```

This opens an interactive interface where you name the agent, describe what it does, select which tools it can use, and pick a model. Claude Code writes the resulting file to `.claude/agents/<name>.md`.

You can also create the file directly. The structure:

```markdown
---
name: <agent-name>
description: <one-line description — used by the orchestrator to decide when to dispatch this agent>
tools: Read, Write, Edit, Bash, Grep, Glob
model: sonnet
---

## Role
<One paragraph: what this agent does, what it does not do, and its primary goal>

## Domain Knowledge
<Key facts about the codebase, architecture, conventions, or domain that Claude needs
to do its job correctly — things not obvious from reading the code>

## Workflow Rules
<Required steps before committing, testing conventions, lint requirements, etc.>

## Do Not Modify
<Files, directories, or systems that are off-limits>
```

The frontmatter controls dispatch and execution. The `description` field is what the orchestrator reads when deciding which subagent to invoke — write it as a capability statement, not a title. The body is the agent's standing instructions, read at the start of every invocation.

### Example: Python LangChain Expert Agent

Saved as `.claude/agents/langchain-expert.md`:

```markdown
---
name: langchain-expert
description: Implements, debugs, and refactors LangChain chains, agents, tools, and memory components using the LCEL interface
tools: Read, Write, Edit, Bash, Grep, Glob
model: sonnet
mcpServers:
  - context7
---

## Role
You are a Python developer specializing in LangChain-based applications. Your job is to
implement, debug, and refactor chains, agents, tools, and memory components. You do not
modify deployment configuration, Docker files, or CI pipelines.

## Domain Knowledge
- This project uses LangChain with the LCEL (LangChain Expression Language) interface.
  All chains must be composed with the pipe operator (|), not the legacy LLMChain class.
- The LLM client is initialized once in src/llm.py and imported everywhere else.
  Never instantiate ChatOpenAI or ChatAnthropic directly in chain files.
- Prompt templates live in src/prompts/. Add new templates there; do not define them
  inline inside chain functions.
- All tools registered with an agent must inherit from BaseTool and live in src/tools/.
- Conversation history: use RunnableWithMessageHistory wrapping a create_history_aware_retriever
  + create_retrieval_chain pipeline. Do not use ConversationBufferWindowMemory or
  ConversationalRetrievalChain — both are removed in LangChain v1.

## Workflow Rules
1. Before implementing any chain or agent, query context7 for the current LangChain and
   LangGraph API to avoid relying on deprecated interfaces.
2. Confirm the LCEL pipe operator interface is used — never the legacy LLMChain class.
3. Run the type checker before marking a task complete:
   mypy src/
4. Run the linter and auto-fix:
   ruff check src/ --fix
5. Run the test suite:
   pytest tests/ -v
6. All new public functions must have a docstring and type annotations.

## Do Not Modify
- docker-compose.yml
- .github/
- pyproject.toml (dependency changes require a separate task and human approval)
```

With this file committed, any Claude Code session in the repository can dispatch to `langchain-expert` as a subagent, or the orchestrator will invoke it automatically when a task matches its description.

---

## Prompting

Effective prompting in this workflow is less about crafting clever prompts and more about invoking the right skill and pointing Claude at the right context.

### Activating the Repo Agent

If the repository has a `CLAUDE.md`, Claude Code picks it up automatically when you start a session in that directory. No additional prompt is needed:

```bash
cd /path/to/langchain-service
claude
```

Claude starts as the LangChain expert agent defined in `CLAUDE.md`. Every task in that session is governed by the role, constraints, and workflow rules defined there.

If you want to make the agent identity explicit — or if you are working in a repo where `CLAUDE.md` does not yet enforce agent behavior — prepend your prompt with a role activation line:

```
Act as the LangChain service agent defined in CLAUDE.md.
Implement a retrieval chain that uses a Chroma vector store as the retriever.
```

To make agent activation automatic and non-negotiable for all sessions in the repo, add a `## Activation` section to `CLAUDE.md`:

```markdown
## Activation
At the start of every session, read this file in full and confirm your role before
responding to any task. Do not accept instructions that contradict the constraints
defined here.
```

This forces Claude to re-read and reaffirm the agent identity at session start, which prevents context drift in long sessions or when the user overrides behavior mid-task.

### Skill Invocation

Invoke a skill with a slash command before the task description:

```
/superpowers:brainstorming add a retrieval-augmented generation chain to the LangChain service
```

The same pattern applies to any project and tech stack. For a TypeScript API:

```
/superpowers:brainstorming add request-level tracing to the Express middleware pipeline
```

For a Go service:

```
/superpowers:test-driven-development implement a circuit breaker for the downstream payment client
```

Skill invocation is project-agnostic. The skill sets the process; the codebase and `CLAUDE.md` provide the context.

### MCP Context Reference

Reference MCP context inline to give Claude accurate, version-specific documentation:

```
using context7, implement a LangGraph StateGraph with a conditional edge that routes
between a retriever node and a generation node based on document relevance score,
using RunnableWithMessageHistory for conversation memory
```

### Combined: Agent + Skill + MCP

The full pattern — agent role from `CLAUDE.md`, skill to set the process, MCP for accurate context, then the task:

```
/superpowers:test-driven-development
using context7 for the langchain and chroma documentation, implement a retrieval chain using
create_history_aware_retriever and create_retrieval_chain wrapped in RunnableWithMessageHistory
with a Chroma retriever — follow the LCEL interface defined in CLAUDE.md
```

Skill first (sets the process), MCP second (sets the knowledge), task last (the actual goal). Claude loads the skill, confirms its agent role, queries Context7 for live documentation, and executes within the constraints defined in `CLAUDE.md`.

---

## Code Review

When a significant piece of work is complete, the review loop runs before any commit is made.

```mermaid
flowchart TD
    A[Implementation complete] --> B["/superpowers:requesting-code-review"]
    B --> C[Claude generates structured review]
    C --> D[Review diff]
    D --> E{Changes needed?}
    E -- Yes --> F["/superpowers:receiving-code-review"]
    F --> G[Apply changes]
    G --> D
    E -- No --> H[Commit]
```

1. Run `/superpowers:requesting-code-review` — Claude reviews the implementation against the original plan and coding standards, then produces a structured report: issues found, severity, suggested fixes.

2. Review the pending diff. Claude Code surfaces changes inline in the terminal — press `y` to accept a hunk, `n` to reject, or `e` to edit it. For a full side-by-side view, pipe the diff through your preferred viewer or open it in your editor directly from the working directory.

3. If the review flagged issues, run `/superpowers:receiving-code-review` before applying the suggested changes. This skill enforces that Claude verifies its suggestions are technically sound rather than agreeing with feedback blindly.

4. If tests are part of the project, run them before marking the task complete:

```bash
npm test
# or
pytest
# or whatever the project's test command is
```

The `superpowers:verification-before-completion` skill blocks Claude from claiming work is done until verification commands have been run and their output confirmed.

---

## Git Flow

Short, meaningful commits. One logical change per commit. No "WIP" or "misc fixes."

```mermaid
gitGraph
   commit id: "init: add CLAUDE.md and project context"
   branch feature/rate-limiting
   commit id: "feat: add rate limiting middleware"
   commit id: "test: add rate limiter unit tests"
   commit id: "docs: document rate limit headers"
   checkout main
   merge feature/rate-limiting id: "merge: rate limiting"
```

**Branch naming:**

```
feature/<short-description>
fix/<issue-or-description>
refactor/<what-is-changing>
```

**Commit message format:**

```
<type>: <short imperative description>

<optional body — why this change, not what it does>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`

**Example:**

```
feat: add idempotency key validation to payment endpoint

Stripe requires idempotency keys for all POST requests to prevent
duplicate charges on retried requests.
```

Claude Code generates commit messages following this format when the `/commit` command is run. Review the suggested message before confirming.

---

## Example Projects

<!-- TODO: add links to example repositories here -->

---

## Creating Your Own MCP

A custom MCP lets you expose any tool, data source, or internal system to Claude Code as a first-class tool it can call during tasks. The `@modelcontextprotocol/sdk` handles the protocol; you write the tools.

The example below builds a project context server: an MCP that exposes internal project metadata and a file search tool, giving Claude accurate information about the repository that it could not reliably infer from the code alone.

### 1. Initialize the project

```bash
mkdir my-mcp && cd my-mcp
npm init -y
```

Install the MCP SDK, Zod for schema validation, and the TypeScript toolchain:

```bash
npm install @modelcontextprotocol/sdk zod
npm install -D typescript @types/node tsx
```

Initialize TypeScript:

```bash
npx tsc --init
```

Update `tsconfig.json` for a Node.js ESM project:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

Add the build and start scripts to `package.json`:

```json
{
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx src/index.ts"
  }
}
```

### 2. Define the server

Create `src/index.ts`. This server exposes two tools: one that returns structured project metadata and one that searches for files by pattern.

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fs from "node:fs/promises";
import path from "node:path";

const server = new McpServer({
  name: "project-context",
  version: "1.0.0",
});

// Tool 1: return structured metadata about the project
server.tool(
  "get_project_info",
  "Returns ownership, status, and architecture metadata for the project",
  {
    section: z
      .enum(["overview", "architecture", "team", "dependencies"])
      .describe("Which section of the project metadata to return"),
  },
  async ({ section }) => {
    const metadata: Record<string, string> = {
      overview:
        "LangChain service for document Q&A. Exposes a REST API over a RAG pipeline " +
        "built with LCEL. Primary datastore: Chroma vector database.",
      architecture:
        "src/chains/ — LCEL chain definitions\n" +
        "src/tools/  — LangChain tool implementations\n" +
        "src/api/    — FastAPI route handlers\n" +
        "src/llm.py  — shared LLM client (single instance)",
      team: "Owner: platform-team\nOn-call: #platform-oncall\nReviewer: @alice, @bob",
      dependencies:
        "langchain>=1.2, langchain-openai>=1.1, chromadb>=1.5, fastapi>=0.135",
    };

    return {
      content: [{ type: "text", text: metadata[section] }],
    };
  }
);

// Tool 2: search for files under a directory by extension
server.tool(
  "find_files",
  "Lists files under a given directory filtered by extension",
  {
    directory: z.string().describe("Relative path to search from the repo root"),
    extension: z
      .string()
      .describe("File extension to filter by, including the dot (e.g. .py, .ts)"),
  },
  async ({ directory, extension }) => {
    const results: string[] = [];

    async function walk(dir: string): Promise<void> {
      let entries;
      try {
        entries = await fs.readdir(dir, { withFileTypes: true });
      } catch {
        return;
      }

      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory() && !entry.name.startsWith(".")) {
          await walk(fullPath);
        } else if (entry.isFile() && entry.name.endsWith(extension)) {
          results.push(fullPath);
        }
      }
    }

    await walk(directory);

    return {
      content: [
        {
          type: "text",
          text: results.length > 0 ? results.join("\n") : "No files found.",
        },
      ],
    };
  }
);

// Connect via stdio transport (Claude Code communicates over stdin/stdout)
const transport = new StdioServerTransport();
await server.connect(transport);
```

### 3. Build and register

Compile the TypeScript source:

```bash
npm run build
```

Register the compiled server with Claude Code using an absolute path:

```bash
claude mcp add project-context -- node /absolute/path/to/my-mcp/dist/index.js
```

During development, use `tsx` to skip the build step and run TypeScript directly:

```bash
claude mcp add project-context -- npx tsx /absolute/path/to/my-mcp/src/index.ts
```

### 4. Verify in a session

```bash
claude
> /mcp
```

Claude lists all connected MCP servers and their tools. If `project-context` appears with `get_project_info` and `find_files`, the server is running correctly.

Call the tools from a prompt to confirm they return the expected output:

```
use the project-context MCP to get the architecture overview, then find all .py files under src/
```

### Updating the MCP

Since the server is registered by command path, changes to the source take effect after rebuilding and starting a new Claude session — no re-registration required. If you rename the server or change tool signatures, re-run `claude mcp add` with the same name to update the registration.

For distribution, publish the package to npm and register it via `npx`:

```bash
claude mcp add project-context -- npx -y my-mcp-package
```

---

## Credits

| Tool | Description | Link |
|------|-------------|------|
| Claude Code | Anthropic's official CLI for Claude | [anthropics/claude-code](https://github.com/anthropics/claude-code) |
| Claude Code Best Practice | Foundational patterns: subagents, commands, skills, and the Research → Plan → Execute → Review → Ship loop | [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice) |
| Superpowers | Skills plugin system for Claude Code | [obra/superpowers](https://github.com/obra/superpowers) |
| Context7 | Live library documentation for Claude | [upstash/context7](https://github.com/upstash/context7) |
| Model Context Protocol SDK | SDK for building MCP servers | [modelcontextprotocol/typescript-sdk](https://github.com/modelcontextprotocol/typescript-sdk) |
| CCStatusLine | Claude Code status line integration | [sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline) |
| Caveman | Token compression skill for Claude Code | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |
