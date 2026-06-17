# Creating Agents by Repo

An agent in this workflow is a specialized Claude invocation configured with a specific role, set of tools, and scope of authority. Rather than using a generic Claude session for every task, you create a purpose-built agent for each repository or domain. (For where agents sit relative to skills, commands, and MCP, see [Skills vs Commands](skills-vs-commands.md#what-is-a-subagent).)

Agents are defined as Markdown files with YAML frontmatter stored in `.claude/agents/`. Committing that directory makes the agents available to everyone who clones the repository — no manual registration required.

- [How to Create an Agent](#how-to-create-an-agent)
- [Example: Python LangChain Expert Agent](#example-python-langchain-expert-agent)
- [Model, effort, and isolation](#model-effort-and-isolation)

---

## How to Create an Agent

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

---

## Example: Python LangChain Expert Agent

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

## Model, effort, and isolation

A few frontmatter fields tune *how* the agent runs:

The `model` field sets the model; `effort` controls reasoning depth independently. `effort: max` on Opus enables extended thinking:

```yaml
---
name: architect
description: Designs system architecture and evaluates trade-offs for complex tasks
model: opus
effort: max
---
```

Subagents can run in isolated git worktrees so their changes do not affect the working tree until merged ([why this matters](capabilities.md#worktree-isolation)):

```yaml
---
name: refactor-agent
description: Performs large-scale refactors in an isolated branch
model: sonnet
isolation: worktree
---
```

For how the model is resolved across env vars, invocation parameters, and this field, see [The Workflow → Model selection per task](workflow.md#model-selection-per-task).
