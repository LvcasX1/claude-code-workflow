# Prompting

Effective prompting in this workflow is less about crafting clever prompts and more about invoking the right skill and pointing Claude at the right context. The pattern is consistent: **skill first (sets the process), MCP second (sets the knowledge), task last (the goal).**

- [Activating the Repo Agent](#activating-the-repo-agent)
- [Skill Invocation](#skill-invocation)
- [MCP Context Reference](#mcp-context-reference)
- [Combined: Agent + Skill + MCP](#combined-agent--skill--mcp)

---

## Activating the Repo Agent

If the repository has a `CLAUDE.md`, Claude Code picks it up automatically when you start a session in that directory. No additional prompt is needed:

```bash
cd /path/to/langchain-service
claude
```

Claude starts with the project context and constraints defined there. Every task in that session is governed by the role, constraints, and workflow rules in `CLAUDE.md`.

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

This forces Claude to re-read and reaffirm the agent identity at session start, which prevents context drift in long sessions or when behavior is overridden mid-task.

---

## Skill Invocation

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

Skill invocation is project-agnostic. The skill sets the process; the codebase and `CLAUDE.md` provide the context. (You often don't need to name the skill at all — Superpowers auto-activates the relevant one. Naming it forces the choice. See [Skills vs Commands](skills-vs-commands.md).)

---

## MCP Context Reference

Reference MCP context inline to give Claude accurate, version-specific documentation:

```
using context7, implement a LangGraph StateGraph with a conditional edge that routes
between a retriever node and a generation node based on document relevance score,
using RunnableWithMessageHistory for conversation memory
```

---

## Combined: Agent + Skill + MCP

The full pattern — agent role from `CLAUDE.md`, skill to set the process, MCP for accurate context, then the task:

```
/superpowers:test-driven-development
using context7 for the langchain and chroma documentation, implement a retrieval chain using
create_history_aware_retriever and create_retrieval_chain wrapped in RunnableWithMessageHistory
with a Chroma retriever — follow the LCEL interface defined in CLAUDE.md
```

Skill first (sets the process), MCP second (sets the knowledge), task last (the actual goal). Claude loads the skill, confirms its agent role, queries Context7 for live documentation, and executes within the constraints defined in `CLAUDE.md`.
