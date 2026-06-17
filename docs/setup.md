# Setup

Everything needed to go from a clean machine to a fully configured agentic workflow: the CLI, the skills layer, the token-compression plugin, the grilling skills, MCP servers for live context, and the status line.

For a one-command guided install, run [`setup.sh`](../setup.sh) from the repo root. This document is the manual reference behind what that script does.

- [Claude Code CLI](#claude-code-cli)
- [Superpowers Skills](#superpowers-skills)
- [mattpocock/skills](#mattpocockskills)
- [Caveman](#caveman)
- [MCP Servers](#mcp-servers)
- [CCStatusLine](#ccstatusline)
- [Hooks](#hooks)

---

## Claude Code CLI

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

## Superpowers Skills

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

> For the conceptual difference between a skill, a command, a subagent, and an MCP — and when to reach for each — see [Skills vs Commands](skills-vs-commands.md). For how Superpowers planning compares to native plan mode, see [Planning](planning.md).

---

## mattpocock/skills

[mattpocock/skills](https://github.com/mattpocock/skills) is a second skill collection focused on the *thinking* phases of development — interrogating a plan before code is written, breaking specs into issues, and handing work off cleanly. It complements Superpowers rather than replacing it: Superpowers governs the execution discipline (TDD, verification, code review), while these skills sharpen the plan that execution runs against.

Install with the `skills` CLI (it prompts you to pick which skills to add):

```bash
npx skills@latest add mattpocock/skills
```

Select `/setup-matt-pocock-skills` during installation, then run it once inside a session. It asks which issue tracker you use (GitHub, Linear, or local files), your triage label conventions, and where documentation should live — wiring the rest of the collection to your project.

The skills used in this workflow:

| Skill | Type | Use |
|-------|------|-----|
| `grill-me` | user-invoked | Relentlessly interview you about a plan or design until every branch of the decision tree is resolved. Run it **after** producing a plan, before writing code. |
| `grill-with-docs` | user-invoked | Same grilling, but cross-checked against your project's existing domain model and documented decisions (CONTEXT.md, ADRs), and it updates that documentation inline as decisions crystallise. |
| `handoff` | user-invoked | Compact the current conversation into a handoff document another agent (or a future session) can pick up. See [Session Continuity](session-continuity.md). |
| `improve-codebase-architecture` | user-invoked | Find deepening/refactoring opportunities informed by the domain language in CONTEXT.md. |

The central idea behind `grill-me` is that *no one knows exactly what they want* until they are forced to defend each decision. Plan mode and Superpowers both produce a plan; grilling stress-tests it. See [Planning](planning.md#grilling-the-plan) for exactly where this slots into the loop.

---

## Caveman

Caveman is a token compression plugin that instructs Claude to respond in a stripped-down, high-density syntax — dropping articles, filler words, and pleasantries while preserving full technical accuracy. Real-world savings range from 22% to 87% per prompt. Code blocks, commit messages, and PR descriptions bypass the filter and remain in normal prose.

Install via the Claude Code plugin manager:

```bash
claude plugin install caveman@caveman
```

Toggle and tune it in-session:

```
/caveman lite|full|ultra      # set intensity
stop caveman                  # back to normal prose
```

Repo: [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)

---

## MCP Servers

An MCP (Model Context Protocol) server is a process that runs alongside Claude Code and exposes a set of callable tools over a standard protocol. Claude treats MCP tools the same way it treats built-in tools like `Read` or `Bash`: it decides when to call them, passes arguments, and incorporates the result into its reasoning. The difference is that MCP tools are domain-specific — you define exactly what they return and how.

From Claude's perspective, calling an MCP tool is no different from reading a file. From the developer's perspective, it means Claude gets precise, structured, on-demand information instead of having to discover it by reading code.

### MCP vs codebase reading

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

### MCPs used in this workflow

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

### Figma

Gives Claude access to Figma files, components, and layout data. Requires a Figma personal access token.

```bash
claude mcp add --scope user figma -- npx -y @figma/mcp-server --figma-api-key ${FIGMA_API_KEY}
```

Add `FIGMA_API_KEY=your_figma_personal_access_token` to your environment or `.env.example`.

### Coda

Bridges Claude to Coda documents for reading and writing pages, tables, and rows. Requires a Coda API token.

```bash
claude mcp add --scope user coda -- npx -y coda-mcp --api-key ${CODA_API_KEY}
```

Add `CODA_API_KEY=your_coda_api_token` to your environment or `.env.example`.

### Local Custom MCP

A local MCP gives Claude access to project-specific context, internal tools, or domain knowledge that no public server provides. The setup section of this repo includes an example implementation with `get_project_info` and `find_files` tools — see [Creating Your Own MCP](creating-mcp.md) for the full TypeScript implementation.

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

### Remote MCPs

Remote MCPs connect Claude to cloud services (GitHub, Slack, Jira, etc.) via HTTP or SSE transport. The registration pattern is the same; the transport layer differs:

```bash
claude mcp add --transport sse my-remote-mcp https://my-mcp-host.example.com/sse
```

List all registered MCPs and their status:

```bash
claude mcp list
```

### Project-scoped MCP Configuration with `.mcp.json`

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

### MCP scopes: repo-specific, monorepo, and global

Every MCP server is registered at one of **three scopes**. The scope decides *which projects the server loads in* and *whether it's shared with your team* — and getting it right is how you keep a server from loading where it isn't wanted.

| Scope | Loads in | Shared with team | Stored in | Add with |
|-------|----------|------------------|-----------|----------|
| **`local`** (default) | Current project only | No (private to you) | `~/.claude.json`, keyed by project path | `claude mcp add <name> -- <cmd>` |
| **`project`** | Current project only | Yes, via version control | `.mcp.json` in project root | `claude mcp add --scope project <name> -- <cmd>` |
| **`user`** | **All** your projects | No (private to you) | `~/.claude.json` | `claude mcp add --scope user <name> -- <cmd>` |

> Naming note: in older versions `local` was called `project` and `user` was called `global`. The flags above are current.

Map that to what you actually want:

- **Repo-specific, just for you** → `local` (the default). A local server added while inside `/path/to/api` is stored under *that path* in `~/.claude.json`, so it never appears in your other projects.
- **Repo-specific, shared with the team** → `project`. Writes a `.mcp.json` you commit; everyone who clones the repo gets it (after approving — see below).
- **Global, every project** → `user`. Best for personal utilities you use everywhere (a scratch DB, a notes server). Use sparingly: a user-scoped server loads in *every* session, so a heavy one is the most common cause of "MCPs eating context everywhere."

```bash
# Repo-specific, private to you (default)
claude mcp add db -- npx -y @bytebase/dbhub --dsn "$LOCAL_DSN"

# Repo-specific, shared with the team (writes .mcp.json)
claude mcp add --scope project github -- npx -y @modelcontextprotocol/server-github

# Global, available in all your projects
claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key "$CONTEXT7_API_KEY"
```

**Precedence when the same name exists in more than one scope:** `local` → `project` → `user` (highest first). Claude connects to the server *once*, using the highest-precedence definition; fields are **not** merged across scopes. This lets a repo override a global server by defining a `local` or `project` server with the same name.

#### Monorepos

Two facts drive monorepo setups:

1. **`.mcp.json` is read from the project root** — the directory you start `claude` in.
2. **`local`-scoped servers are keyed by project path** in `~/.claude.json`.

That gives you clean per-package isolation without extra config:

- **Shared across the whole monorepo** → a single `.mcp.json` at the monorepo root (start `claude` from the root), or `user` scope.
- **Specific to one package** → either commit a `.mcp.json` inside that package directory and launch `claude` from there, **or** `cd` into the package and add the server at `local` scope — it's automatically bound to that package's path and won't load when you work in a sibling package.

```bash
# Package-specific server, isolated to packages/api by path
cd packages/api
claude mcp add api-fixtures -- node ./scripts/fixtures-mcp.js
# Working in packages/web later? api-fixtures is not registered there.
```

For a server that's shared at the root but unwanted in a particular package, disable it per-package with `disabledMcpjsonServers` (next section) rather than removing it globally.

### Managing MCP servers

```bash
claude mcp list                     # all servers + connection status
claude mcp get <name>               # details for one server
claude mcp remove <name>            # unregister a server entirely
claude mcp reset-project-choices    # forget approvals/rejections for .mcp.json servers
```

Inside a session, `/mcp` shows connected servers, their tools, and handles OAuth sign-in.

**Approval of project servers.** For security, Claude Code prompts before using `project`-scoped servers from a `.mcp.json` (so cloning a repo can't silently run someone's server). Until approved they show as `⏸ Pending approval` in `claude mcp list` and **their tools don't load**. Approve them interactively, or pre-approve in `settings.json` (below). Reset your choices with `claude mcp reset-project-choices`.

### Keeping MCPs out of startup context

The concern — "servers loading at startup and eating context" — is mostly handled for you, with a few levers when it isn't.

**Tool Search (on by default) is the main defense.** With it enabled, only tool *names* and short server instructions load at session start; the full tool definitions are deferred and fetched on demand via the `ToolSearch` tool (see [Capabilities → ToolSearch](capabilities.md#toolsearch-and-deferred-tools)). Adding more servers therefore has minimal startup cost — only the tools Claude actually uses enter context. Control it with the `ENABLE_TOOL_SEARCH` environment variable:

| Value | Behavior |
|-------|----------|
| (default) | Defer all MCP tool definitions; discover on demand |
| `auto` | Load schemas upfront if they fit within ~10% of the context window, defer the rest |
| `auto:N` | Same, with a custom percentage `N` |
| `false` | Disable — load all tool schemas upfront (the old behavior; most context-hungry) |

Leave it on. The opposite knob, **`alwaysLoad: true`** on a server's config, *forces* all that server's tools into startup context **and** blocks startup until the server connects — use it only for a couple of tools needed on literally every turn.

**To stop specific servers from loading at all**, control them in `settings.json` (`.claude/settings.json` for one repo, `~/.claude/settings.json` globally):

```json
{
  "enableAllProjectMcpServers": false,
  "enabledMcpjsonServers": ["github"],
  "disabledMcpjsonServers": ["filesystem", "heavy-analytics"]
}
```

| Key | Type | Effect |
|-----|------|--------|
| `enableAllProjectMcpServers` | boolean | Auto-approve *all* `.mcp.json` servers (skip the prompt) |
| `enabledMcpjsonServers` | string[] | Approve only these named `.mcp.json` servers |
| `disabledMcpjsonServers` | string[] | Reject these named `.mcp.json` servers — they won't connect or load |

So, the practical recipe for "load a few, deactivate the rest":

- **A server you never want anywhere** → `claude mcp remove <name>`.
- **A `.mcp.json` server unwanted in this repo (or this monorepo package)** → add its name to `disabledMcpjsonServers` in that scope's `settings.json`. It stays in the committed `.mcp.json` for teammates but won't load for you.
- **Approve only a subset of a repo's servers** → set `enabledMcpjsonServers` to the few you want and leave the rest unapproved.
- **A global (`user`) server that's only occasionally useful** → demote it to `local`/`project` scope so it stops loading in every project, and re-add it where needed.

Finally, MCP **output** (not startup) is capped separately: Claude warns past 10,000 tokens of tool output and truncates at a 25,000-token default. Raise it per session with `MAX_MCP_OUTPUT_TOKENS` if a server returns large payloads you actually need.

> Full reference: [Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp) · [Settings](https://code.claude.com/docs/en/settings).

---

## CCStatusLine

CCStatusLine is a status line integration that surfaces Claude Code session state directly in your terminal prompt. It shows the active model, current and remaining context window, and git state — removing the need to switch windows to check what Claude is doing mid-session.

Repo: [sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline)

Install via npm or bun:

```bash
npm install -g ccstatusline
# or
bunx ccstatusline
```

Then point Claude Code to it by running `/statusline` in a session. Claude Code will guide the configuration interactively.

The config used in this workflow is at [`config/ccstatusline.json`](../config/ccstatusline.json). Copy it to `~/.config/ccstatusline/settings.json` to use it directly.

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

## Hooks

Hooks are shell commands that Claude Code executes automatically at specific points in the session lifecycle — before or after a tool call, when Claude goes idle, when a subagent finishes, or when a task changes state. They run in the background, outside Claude's context, and can block, modify, or log tool activity without consuming tokens.

Hooks are the only reliable way to enforce a rule *every single time* — Claude follows instructions in `CLAUDE.md` most of the time, but a hook runs deterministically because the harness executes it, not the model. See [Memory & Rules](memory-and-rules.md) for when to encode a rule as memory, as a `CLAUDE.md` instruction, or as a hook.

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
