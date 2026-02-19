/**
 * Bandeira JavaScript/TypeScript SDK.
 *
 * Polls the Bandeira server, caches flags locally, and evaluates strategies
 * in-process — so isEnabled() calls are pure in-memory lookups.
 */

// ── Types ─────────────────────────────────────────────────────────────────

export interface BandeiraConfig {
  /** Base URL of the Bandeira server (e.g. "http://localhost:8080"). */
  url: string;
  /** Client API token (created in the Bandeira admin UI). */
  token: string;
  /** Poll interval in milliseconds. Defaults to 15000 (15 seconds). */
  pollInterval?: number;
  /** Custom fetch function (for testing or non-browser environments). */
  fetchFn?: typeof fetch;
}

export interface BandeiraContext {
  /** Used by userWithId strategy and as default stickiness. */
  userId?: string;
  /** Alternative stickiness key. */
  sessionId?: string;
  /** Used by remoteAddress strategy. */
  remoteAddress?: string;
  /** Arbitrary key-value pairs for constraint evaluation. */
  properties?: Record<string, string>;
}

interface Flag {
  name: string;
  enabled: boolean;
  strategies: Strategy[];
}

interface Strategy {
  name: string;
  parameters: Record<string, unknown>;
  constraints: Constraint[];
}

interface Constraint {
  context_name: string;
  operator: string;
  values: string[];
  inverted: boolean;
  case_insensitive: boolean;
}

interface ApiResponse {
  flags: Flag[];
}

// ── Client ────────────────────────────────────────────────────────────────

export class BandeiraClient {
  private flags: Map<string, Flag> = new Map();
  private timer: ReturnType<typeof setInterval> | null = null;
  private readonly config: Required<
    Pick<BandeiraConfig, "url" | "token" | "pollInterval">
  > & { fetchFn: typeof fetch };

  constructor(config: BandeiraConfig) {
    if (!config.url) throw new Error("bandeira: url is required");
    if (!config.token) throw new Error("bandeira: token is required");

    this.config = {
      url: config.url.replace(/\/+$/, ""),
      token: config.token,
      pollInterval: config.pollInterval ?? 15_000,
      fetchFn: config.fetchFn ?? globalThis.fetch.bind(globalThis),
    };
  }

  /** Start polling. Must be called before isEnabled(). */
  async start(): Promise<void> {
    await this.fetch();
    this.timer = setInterval(() => {
      this.fetch().catch(() => {});
    }, this.config.pollInterval);
  }

  /** Stop polling and release resources. */
  close(): void {
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  /**
   * Returns true if the flag is enabled.
   * Without context, only the enabled/disabled state is checked.
   */
  isEnabled(name: string, ctx?: BandeiraContext): boolean {
    const flag = this.flags.get(name);
    if (!flag || !flag.enabled) return false;

    if (flag.strategies.length === 0) return true;

    const evalCtx = ctx ?? {};

    // OR logic — if ANY strategy returns true, flag is ON.
    for (const s of flag.strategies) {
      if (evaluateStrategy(s, evalCtx)) return true;
    }

    return false;
  }

  /** Returns a snapshot of all known flags and their enabled state. */
  allFlags(): Record<string, boolean> {
    const result: Record<string, boolean> = {};
    for (const [k, v] of this.flags) {
      result[k] = v.enabled;
    }
    return result;
  }

  /** Directly load flags from an API response (useful for testing). */
  loadFlags(response: ApiResponse): void {
    const m = new Map<string, Flag>();
    for (const f of response.flags) {
      m.set(f.name, f);
    }
    this.flags = m;
  }

  private async fetch(): Promise<void> {
    const url = `${this.config.url}/api/v1/flags`;
    const resp = await this.config.fetchFn(url, {
      headers: { Authorization: `Bearer ${this.config.token}` },
    });

    if (!resp.ok) {
      const body = await resp.text();
      throw new Error(
        `bandeira: unexpected status ${resp.status}: ${body}`
      );
    }

    const data: ApiResponse = await resp.json();
    const m = new Map<string, Flag>();
    for (const f of data.flags) {
      m.set(f.name, f);
    }
    this.flags = m;
  }
}

// ── Strategy evaluation ───────────────────────────────────────────────────

function evaluateStrategy(s: Strategy, ctx: BandeiraContext): boolean {
  // AND logic — all constraints must pass.
  for (const con of s.constraints) {
    if (!evaluateConstraint(con, ctx)) return false;
  }

  switch (s.name) {
    case "default":
      return true;
    case "userWithId":
      return evalUserWithId(s, ctx);
    case "gradualRollout":
      return evalGradualRollout(s, ctx);
    case "remoteAddress":
      return evalRemoteAddress(s, ctx);
    default:
      return true;
  }
}

function evalUserWithId(s: Strategy, ctx: BandeiraContext): boolean {
  const raw = s.parameters["userIds"];
  if (typeof raw !== "string") return false;

  const ids = splitMulti(raw);
  return ids.includes(ctx.userId ?? "");
}

function evalGradualRollout(s: Strategy, ctx: BandeiraContext): boolean {
  const rolloutRaw = s.parameters["rollout"];
  let rollout: number;

  if (typeof rolloutRaw === "number") {
    rollout = rolloutRaw;
  } else if (typeof rolloutRaw === "string") {
    rollout = parseInt(rolloutRaw, 10);
    if (isNaN(rollout)) return false;
  } else {
    return false;
  }

  if (rollout >= 100) return true;
  if (rollout <= 0) return false;

  const stickiness =
    typeof s.parameters["stickiness"] === "string"
      ? (s.parameters["stickiness"] as string)
      : "userId";

  let stickinessValue = "";
  switch (stickiness) {
    case "userId":
      stickinessValue = ctx.userId ?? "";
      break;
    case "sessionId":
      stickinessValue = ctx.sessionId ?? "";
      break;
    default:
      stickinessValue = ctx.properties?.[stickiness] ?? "";
      break;
  }

  if (stickinessValue === "") return false;

  const groupId =
    typeof s.parameters["groupId"] === "string"
      ? (s.parameters["groupId"] as string)
      : "";

  const normalized = normalizedHash(stickinessValue + groupId);
  return normalized < rollout;
}

function evalRemoteAddress(s: Strategy, ctx: BandeiraContext): boolean {
  let raw = s.parameters["ips"];
  if (raw === undefined) raw = s.parameters["IPs"];
  if (typeof raw !== "string") return false;

  const addr = ctx.remoteAddress ?? "";
  for (const entry of splitMulti(raw)) {
    if (entry === addr) return true;
    if (entry.endsWith(".") && addr.startsWith(entry)) return true;
  }
  return false;
}

// ── Constraint evaluation ─────────────────────────────────────────────────

function evaluateConstraint(
  con: Constraint,
  ctx: BandeiraContext
): boolean {
  const ctxValue = getContextValue(con.context_name, ctx);
  const result = evalOperator(
    con.operator,
    ctxValue,
    con.values,
    con.case_insensitive
  );
  return con.inverted ? !result : result;
}

function getContextValue(name: string, ctx: BandeiraContext): string {
  switch (name) {
    case "userId":
      return ctx.userId ?? "";
    case "sessionId":
      return ctx.sessionId ?? "";
    case "remoteAddress":
      return ctx.remoteAddress ?? "";
    default:
      return ctx.properties?.[name] ?? "";
  }
}

function evalOperator(
  op: string,
  ctxValue: string,
  values: string[],
  caseInsensitive: boolean
): boolean {
  const cv = caseInsensitive ? ctxValue.toLowerCase() : ctxValue;

  const normalize = (v: string) =>
    caseInsensitive ? v.toLowerCase() : v;

  switch (op) {
    case "IN":
      return values.some((v) => cv === normalize(v));

    case "NOT_IN":
      return values.every((v) => cv !== normalize(v));

    case "STR_CONTAINS":
      return values.some((v) => cv.includes(normalize(v)));

    case "STR_STARTS_WITH":
      return values.some((v) => cv.startsWith(normalize(v)));

    case "STR_ENDS_WITH":
      return values.some((v) => cv.endsWith(normalize(v)));

    case "NUM_EQ":
    case "NUM_GT":
    case "NUM_GTE":
    case "NUM_LT":
    case "NUM_LTE": {
      const num = parseFloat(cv);
      if (isNaN(num)) return false;
      return values.some((v) => {
        const target = parseFloat(v);
        if (isNaN(target)) return false;
        switch (op) {
          case "NUM_EQ":
            return num === target;
          case "NUM_GT":
            return num > target;
          case "NUM_GTE":
            return num >= target;
          case "NUM_LT":
            return num < target;
          case "NUM_LTE":
            return num <= target;
          default:
            return false;
        }
      });
    }

    case "DATE_AFTER":
    case "DATE_BEFORE": {
      const t = new Date(cv).getTime();
      if (isNaN(t)) return false;
      return values.some((v) => {
        const target = new Date(v).getTime();
        if (isNaN(target)) return false;
        return op === "DATE_AFTER" ? t > target : t < target;
      });
    }

    default:
      return false;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

function splitMulti(s: string): string[] {
  return s
    .replace(/\r\n/g, ",")
    .replace(/\n/g, ",")
    .split(",")
    .map((p) => p.trim())
    .filter((p) => p !== "");
}

/**
 * FNV-1a 32-bit hash, mod 100, matching the Go SDK implementation.
 */
function normalizedHash(s: string): number {
  let hash = 0x811c9dc5; // FNV offset basis
  for (let i = 0; i < s.length; i++) {
    hash ^= s.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193); // FNV prime
  }
  return ((hash >>> 0) % 100);
}
