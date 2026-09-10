import { describe, expect, it, vi } from "vitest";

const spawnCalls: Array<Record<string, unknown>> = [];

vi.mock("@modelcontextprotocol/sdk/client/stdio.js", () => ({
  StdioClientTransport: class {
    constructor(params: Record<string, unknown>) {
      spawnCalls.push(params);
    }
    async start(): Promise<void> {}
    async close(): Promise<void> {}
  },
}));

vi.mock("@modelcontextprotocol/sdk/client/index.js", () => ({
  Client: class {
    async connect(): Promise<void> {}
    async close(): Promise<void> {}
  },
}));

import { McpSession } from "./mcp-transport.js";

describe("MCP stdio spawn options", () => {
  it("spawns the process in the server's configured working directory", async () => {
    const session = new McpSession({ name: "test" });
    await session.connectStdio({
      command: process.execPath,
      cwd: "/Users/luke/dev/rakazo-setup/rakazo",
      allowedCommands: [process.execPath],
    });
    expect(spawnCalls).toHaveLength(1);
    expect(spawnCalls[0]).toMatchObject({
      command: process.execPath,
      cwd: "/Users/luke/dev/rakazo-setup/rakazo",
      stderr: "pipe",
    });
    await session.close();
  });

  it("omits cwd from the spawn options when the server has none", async () => {
    const session = new McpSession({ name: "test" });
    await session.connectStdio({
      command: process.execPath,
      allowedCommands: [process.execPath],
    });
    expect(spawnCalls).toHaveLength(2);
    expect(spawnCalls[1]?.cwd).toBeUndefined();
    await session.close();
  });
});
