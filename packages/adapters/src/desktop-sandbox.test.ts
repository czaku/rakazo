import { realpath, rm, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { buildChildEnv, DesktopSandboxProvider } from "./desktop-sandbox.js";

const roots: string[] = [];

const ctx = {
  operationId: "operation",
  traceId: "trace",
  spaceId: "workspace",
  userId: "user",
  signal: new AbortController().signal,
};

async function fixture(botId: string) {
  const root = await realpath(await mkdtemp(path.join(tmpdir(), "rakazo-desktop-sandbox-")));
  roots.push(root);
  const desktop = new DesktopSandboxProvider({ root });
  const computer = await desktop.provision({ botId, homePath: "/unused" }, ctx);
  return { root, desktop, computer };
}

async function collect(
  desktop: DesktopSandboxProvider,
  computer: Awaited<ReturnType<typeof fixture>>["computer"],
  request: Parameters<DesktopSandboxProvider["execute"]>[1],
  timeoutMs = 30_000,
) {
  const events: { type: string; data?: string; code?: number }[] = [];
  for await (const event of desktop.execute(computer, { timeoutMs, ...request }, ctx)) {
    events.push(event);
  }
  return events;
}

const nodeBin = process.execPath;

describe("desktop sandbox child env", () => {
  afterEach(async () => {
    await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
  });

  it("forwards allowlisted host env vars (PATH/HOME/USER) but never API secrets", () => {
    const savedEncryption = process.env.ENCRYPTION_KEY;
    const savedDatabase = process.env.DATABASE_URL;
    const savedToken = process.env.SCREEN_PROXY_SECRET;
    process.env.ENCRYPTION_KEY = "super-secret-encryption-key";
    process.env.DATABASE_URL = "postgres://user:pass@host/db";
    process.env.SCREEN_PROXY_SECRET = "screen-secret";
    try {
      const env = buildChildEnv();
      expect(env.PATH).toBe(process.env.PATH);
      if (process.env.HOME !== undefined) expect(env.HOME).toBe(process.env.HOME);
      expect(env.ENCRYPTION_KEY).toBeUndefined();
      expect(env.DATABASE_URL).toBeUndefined();
      expect(env.SCREEN_PROXY_SECRET).toBeUndefined();
      expect(env.BETTER_AUTH_SECRET).toBeUndefined();
      expect(env.SANDBOX_SUPERVISOR_TOKEN).toBeUndefined();
      expect(env.SMTP_URL).toBeUndefined();
    } finally {
      if (savedEncryption === undefined) delete process.env.ENCRYPTION_KEY;
      else process.env.ENCRYPTION_KEY = savedEncryption;
      if (savedDatabase === undefined) delete process.env.DATABASE_URL;
      else process.env.DATABASE_URL = savedDatabase;
      if (savedToken === undefined) delete process.env.SCREEN_PROXY_SECRET;
      else process.env.SCREEN_PROXY_SECRET = savedToken;
    }
  });

  it("forwards every LC_* host var by prefix and still hides ENCRYPTION_KEY", () => {
    const savedArbitrary = process.env.LC_FOO_BAR;
    const savedLcAddress = process.env.LC_ADDRESS;
    const savedEncryption = process.env.ENCRYPTION_KEY;
    process.env.LC_FOO_BAR = "arbitrary-locale-test";
    process.env.LC_ADDRESS = "en_US.UTF-8";
    process.env.ENCRYPTION_KEY = "must-not-leak";
    try {
      const env = buildChildEnv();
      expect(env.LC_FOO_BAR).toBe("arbitrary-locale-test");
      expect(env.LC_ADDRESS).toBe("en_US.UTF-8");
      expect(env.ENCRYPTION_KEY).toBeUndefined();
    } finally {
      if (savedArbitrary === undefined) delete process.env.LC_FOO_BAR;
      else process.env.LC_FOO_BAR = savedArbitrary;
      if (savedLcAddress === undefined) delete process.env.LC_ADDRESS;
      else process.env.LC_ADDRESS = savedLcAddress;
      if (savedEncryption === undefined) delete process.env.ENCRYPTION_KEY;
      else process.env.ENCRYPTION_KEY = savedEncryption;
    }
  });

  it("does not leak ENCRYPTION_KEY to spawned children", async () => {
    const savedEncryption = process.env.ENCRYPTION_KEY;
    process.env.ENCRYPTION_KEY = "super-secret-encryption-key";
    try {
      const { desktop, computer } = await fixture("bot-env-leak");
      const events = await collect(desktop, computer, {
        argv: [
          nodeBin,
          "-e",
          `process.stdout.write('ENC=' + (process.env.ENCRYPTION_KEY || '') + '\\n');`,
        ],
      });
      const stdout = events
        .filter((event): event is { type: "stdout"; data: string } => event.type === "stdout")
        .map((event) => event.data)
        .join("");
      expect(stdout).toContain("ENC=");
      expect(stdout).not.toContain("super-secret-encryption-key");
    } finally {
      if (savedEncryption === undefined) delete process.env.ENCRYPTION_KEY;
      else process.env.ENCRYPTION_KEY = savedEncryption;
    }
  });

  it("honours request.env and overlays it on the allowlist", async () => {
    const { desktop, computer } = await fixture("bot-request-env");
    const events = await collect(desktop, computer, {
      argv: [
        nodeBin,
        "-e",
        `process.stdout.write('FOO=' + (process.env.RKZ_TEST_FOO || '') + '\\n');`,
      ],
      env: { RKZ_TEST_FOO: "visible-from-request" },
    });
    const stdout = events
      .filter((event): event is { type: "stdout"; data: string } => event.type === "stdout")
      .map((event) => event.data)
      .join("");
    expect(stdout).toBe("FOO=visible-from-request\n");
  });

  it("caps stdout at 2 MB with a truncation marker when a child writes 10 MB", async () => {
    const { desktop, computer } = await fixture("bot-stdout-cap");
    const events = await collect(
      desktop,
      computer,
      {
        argv: [
          nodeBin,
          "-e",
          `process.stdout.write('a'.repeat(10_000_000));`,
        ],
      },
      60_000,
    );
    const stdout = events
      .filter((event): event is { type: "stdout"; data: string } => event.type === "stdout")
      .map((event) => event.data)
      .join("");
    expect(Buffer.byteLength(stdout, "utf8")).toBeLessThanOrEqual(2_000_000 + 64);
    expect(stdout).toContain("[output truncated: exceeded 2 MB]");
  });
});
