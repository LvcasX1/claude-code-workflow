# Creating Your Own MCP

A custom MCP lets you expose any tool, data source, or internal system to Claude Code as a first-class tool it can call during tasks. The `@modelcontextprotocol/sdk` handles the protocol; you write the tools. (For when an MCP is the right choice versus a skill, command, or subagent, see [Skills vs Commands](skills-vs-commands.md#what-is-an-mcp).)

The example below builds a project context server: an MCP that exposes internal project metadata and a file search tool, giving Claude accurate information about the repository that it could not reliably infer from the code alone.

- [1. Initialize the project](#1-initialize-the-project)
- [2. Define the server](#2-define-the-server)
- [3. Build and register](#3-build-and-register)
- [4. Verify in a session](#4-verify-in-a-session)
- [Updating the MCP](#updating-the-mcp)

---

## 1. Initialize the project

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

---

## 2. Define the server

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

---

## 3. Build and register

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

For a project-scoped registration that every contributor picks up automatically, add the server to `.mcp.json` instead — see [Setup → Project-scoped MCP Configuration](setup.md#project-scoped-mcp-configuration-with-mcpjson).

---

## 4. Verify in a session

```bash
claude
> /mcp
```

Claude lists all connected MCP servers and their tools. If `project-context` appears with `get_project_info` and `find_files`, the server is running correctly.

Call the tools from a prompt to confirm they return the expected output:

```
use the project-context MCP to get the architecture overview, then find all .py files under src/
```

---

## Updating the MCP

Since the server is registered by command path, changes to the source take effect after rebuilding and starting a new Claude session — no re-registration required. If you rename the server or change tool signatures, re-run `claude mcp add` with the same name to update the registration.

For distribution, publish the package to npm and register it via `npx`:

```bash
claude mcp add project-context -- npx -y my-mcp-package
```
