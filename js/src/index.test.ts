import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { BandeiraClient } from "./index.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load shared test fixtures.
const fixtures = JSON.parse(
  readFileSync(resolve(__dirname, "../../testdata/flags.json"), "utf-8")
);

function createClient(): BandeiraClient {
  const client = new BandeiraClient({
    url: "http://localhost:9999",
    token: "test-token",
  });
  client.loadFlags(fixtures);
  return client;
}

describe("BandeiraClient", () => {
  describe("basic toggles", () => {
    it("enabled flag with no strategies returns true", () => {
      const c = createClient();
      assert.equal(c.isEnabled("simple-on"), true);
    });

    it("disabled flag returns false", () => {
      const c = createClient();
      assert.equal(c.isEnabled("simple-off"), false);
    });

    it("unknown flag returns false", () => {
      const c = createClient();
      assert.equal(c.isEnabled("nonexistent"), false);
    });
  });

  describe("default strategy", () => {
    it("returns true", () => {
      const c = createClient();
      assert.equal(c.isEnabled("default-strategy"), true);
    });
  });

  describe("userWithId", () => {
    it("matches a listed user", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("user-targeting", { userId: "user-42" }),
        true
      );
    });

    it("rejects an unlisted user", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("user-targeting", { userId: "user-99" }),
        false
      );
    });

    it("rejects when no context provided", () => {
      const c = createClient();
      assert.equal(c.isEnabled("user-targeting"), false);
    });

    it("handles newline-separated user IDs", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("user-targeting-newlines", { userId: "user-42" }),
        true
      );
      assert.equal(
        c.isEnabled("user-targeting-newlines", { userId: "user-99" }),
        false
      );
    });
  });

  describe("gradualRollout", () => {
    it("100% rollout is always on", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("rollout-100", { userId: "anyone" }),
        true
      );
    });

    it("0% rollout is always off", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("rollout-0", { userId: "anyone" }),
        false
      );
    });

    it("no userId means no stickiness → false", () => {
      const c = createClient();
      assert.equal(c.isEnabled("rollout-50"), false);
    });

    it("session stickiness uses sessionId", () => {
      const c = createClient();
      // Just verify it doesn't crash and returns a boolean.
      const result = c.isEnabled("rollout-session-stickiness", {
        sessionId: "sess-123",
      });
      assert.equal(typeof result, "boolean");
    });
  });

  describe("remoteAddress", () => {
    it("exact match", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("ip-allowlist", { remoteAddress: "10.0.0.1" }),
        true
      );
    });

    it("prefix match", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("ip-allowlist", { remoteAddress: "192.168.1.100" }),
        true
      );
    });

    it("no match", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("ip-allowlist", { remoteAddress: "172.16.0.1" }),
        false
      );
    });

    it("legacy IPs key works", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("ip-allowlist-legacy", {
          remoteAddress: "10.0.0.1",
        }),
        true
      );
    });
  });

  describe("constraints", () => {
    it("IN operator matches", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-in", {
          properties: { companyId: "2" },
        }),
        true
      );
    });

    it("IN operator rejects", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-in", {
          properties: { companyId: "99" },
        }),
        false
      );
    });

    it("NOT_IN operator matches", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-not-in", {
          properties: { plan: "enterprise" },
        }),
        true
      );
    });

    it("NOT_IN operator rejects", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-not-in", {
          properties: { plan: "free" },
        }),
        false
      );
    });

    it("inverted constraint", () => {
      const c = createClient();
      // "free" is IN ["free"] → inverted → false
      assert.equal(
        c.isEnabled("constraint-inverted", {
          properties: { plan: "free" },
        }),
        false
      );
      // "enterprise" is NOT IN ["free"] → inverted → true
      assert.equal(
        c.isEnabled("constraint-inverted", {
          properties: { plan: "enterprise" },
        }),
        true
      );
    });

    it("case-insensitive constraint", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-case-insensitive", {
          properties: { country: "brazil" },
        }),
        true
      );
      assert.equal(
        c.isEnabled("constraint-case-insensitive", {
          properties: { country: "PORTUGAL" },
        }),
        true
      );
      assert.equal(
        c.isEnabled("constraint-case-insensitive", {
          properties: { country: "spain" },
        }),
        false
      );
    });

    it("STR_CONTAINS", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-str-contains", {
          properties: { email: "user@acme.com" },
        }),
        true
      );
      assert.equal(
        c.isEnabled("constraint-str-contains", {
          properties: { email: "user@other.com" },
        }),
        false
      );
    });

    it("STR_STARTS_WITH", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-str-starts-with", {
          properties: { email: "admin@acme.com" },
        }),
        true
      );
      assert.equal(
        c.isEnabled("constraint-str-starts-with", {
          properties: { email: "user@acme.com" },
        }),
        false
      );
    });

    it("STR_ENDS_WITH", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-str-ends-with", {
          properties: { email: "user@acme.com" },
        }),
        true
      );
      assert.equal(
        c.isEnabled("constraint-str-ends-with", {
          properties: { email: "user@acme.io" },
        }),
        false
      );
    });

    it("NUM_GTE", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-num-gte", {
          properties: { age: "21" },
        }),
        true
      );
      assert.equal(
        c.isEnabled("constraint-num-gte", {
          properties: { age: "18" },
        }),
        true
      );
      assert.equal(
        c.isEnabled("constraint-num-gte", {
          properties: { age: "16" },
        }),
        false
      );
    });

    it("DATE_AFTER", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constraint-date-after", {
          properties: { signupDate: "2026-06-15T00:00:00Z" },
        }),
        true
      );
      assert.equal(
        c.isEnabled("constraint-date-after", {
          properties: { signupDate: "2025-06-15T00:00:00Z" },
        }),
        false
      );
    });
  });

  describe("multi-strategy (OR logic)", () => {
    it("VIP user matches first strategy", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("multi-strategy", { userId: "vip-1" }),
        true
      );
    });
  });

  describe("constrained rollout", () => {
    it("passes when constraint matches", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constrained-rollout", {
          userId: "any-user",
          properties: { companyId: "acme" },
        }),
        true
      );
    });

    it("fails when constraint does not match", () => {
      const c = createClient();
      assert.equal(
        c.isEnabled("constrained-rollout", {
          userId: "any-user",
          properties: { companyId: "other" },
        }),
        false
      );
    });
  });

  describe("allFlags", () => {
    it("returns all flags with their enabled state", () => {
      const c = createClient();
      const flags = c.allFlags();
      assert.equal(flags["simple-on"], true);
      assert.equal(flags["simple-off"], false);
    });
  });

  describe("constructor validation", () => {
    it("throws on missing url", () => {
      assert.throws(
        () => new BandeiraClient({ url: "", token: "test" }),
        /url is required/
      );
    });

    it("throws on missing token", () => {
      assert.throws(
        () => new BandeiraClient({ url: "http://localhost", token: "" }),
        /token is required/
      );
    });
  });
});
