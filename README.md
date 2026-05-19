# skills-by-yigitkonur-secondary

the b-side. the "we're not at 100M subs but the content still slaps" channel.

basically the main pack (https://github.com/yigitkonur/skills-by-yigitkonur) graduated some skills out because they're niche, project-shaped, or just don't fit the everyday vibe — but you still want them when you want them. that's what lives here.

think mrbeast2 energy. less popular sibling. still posts. still goes hard.

## what's in here

skills you reach for sometimes, not every day. mostly framework guides, mcp variants, language-specific build skills, niche cli wrappers.

## install one

```bash
npx -y skills add -y -g yigitkonur/skills-by-yigitkonur-secondary/skills/<skill-name>
```

or pin to a specific project (no `-g`) when you only need it in one codebase:

```bash
cd /path/to/your/project
npx -y skills add -y yigitkonur/skills-by-yigitkonur-secondary/skills/<skill-name>
```

## install the whole b-side

```bash
npx -y skills add -y -g yigitkonur/skills-by-yigitkonur-secondary
```

honestly don't. it's a lot. cherry-pick.

## the skills

| skill | what it does |
|---|---|
| [audit-agentic-cli](skills/audit-agentic-cli/) | audit a cli for agent-readiness — stable json, exit codes, repair loops |
| [audit-agentic-mcp](skills/audit-agentic-mcp/) | same vibe but for mcp servers — agent-readiness audit + redesign |
| [audit-skill-by-derailment](skills/audit-skill-by-derailment/) | stress-test an existing SKILL.md by running a fresh subagent on a real task |
| [build-chrome-extension](skills/build-chrome-extension/) | chrome mv3 — manifest, service_worker, content_scripts, popup, side_panel |
| [build-clean-mcp-architecture](skills/build-clean-mcp-architecture/) | clean architecture layer rules for typescript mcp servers |
| [build-effect-ts-v3](skills/build-effect-ts-v3/) | effect-ts v3 — typed errors, services, layers, Schema, Stream |
| [build-kernel-ts-sdk](skills/build-kernel-ts-sdk/) | kernel ts sdk — browsers, apps, profiles, managed auth, playwright/cdp |
| [build-langchain-ts-app](skills/build-langchain-ts-app/) | langchain.js — agents, tool-calling, rag retrievers, langgraph |
| [build-macos-app](skills/build-macos-app/) | swiftui/appkit — hig, liquid glass, snapshots, swiftlint, convex+clerk |
| [build-mcp-server-sdk-v1](skills/build-mcp-server-sdk-v1/) | mcp servers on @modelcontextprotocol/sdk v1.x |
| [build-mcp-server-sdk-v2](skills/build-mcp-server-sdk-v2/) | mcp servers on @modelcontextprotocol/server v2 |
| [build-mcp-use-agent](skills/build-mcp-use-agent/) | typescript mcp-use MCPAgent — `run`, `stream`, `streamEvents` |
| [build-mcp-use-client](skills/build-mcp-use-client/) | typescript mcp-use clients — MCPClient, MCPSession, react helpers |
| [build-mcp-use-server](skills/build-mcp-use-server/) | typescript mcp-use servers — tools, schemas, sessions, transports, widgets |
| [build-raycast-script-command](skills/build-raycast-script-command/) | raycast script commands in python/bash with @raycast metadata header |
| [build-tinacms-nextjs](skills/build-tinacms-nextjs/) | tinacms-backed next.js — schemas, useTina visual editing, mdx |
| [convert-mcp-sdk-v1-to-v2](skills/convert-mcp-sdk-v1-to-v2/) | port v1 mcp servers to the v2 split-package sdk |
| [run-codex-review-loop](skills/run-codex-review-loop/) | per-branch codex review fix loops (deprecation shim → run-codex-2) |
| [run-linear-cli](skills/run-linear-cli/) | drive the linear-cli for issue lifecycle, bulk creation, git/pr loops |

## why move them out of the main pack

context window economy. every installed skill bumps your trigger surface and your token bill. the main pack is the everyday loadout. this pack is the toolbox in the garage — get it when the job calls for it.

## license

mit. same as the main pack.
