import { execFile } from "node:child_process"
import type { Plugin } from "@opencode-ai/plugin"

const BASE_URL = (
  process.env.PORTAINER_URL ?? "http://umbrel:9000"
).replace(/\/+$/, "")
const KEYCHAIN_SERVICE =
  process.env.PORTAINER_KEYCHAIN_SERVICE ?? "portainer-t3-mcp"
const KEYCHAIN_ACCOUNT =
  process.env.PORTAINER_KEYCHAIN_ACCOUNT ?? process.env.USER ?? "opencode"
const FRESH_TTL_MS =
  Number(process.env.PORTAINER_SNAPSHOT_TTL_SECONDS ?? "300") * 1000
const FAILED_TTL_MS = 60_000
const HTTP_TIMEOUT_MS = 10_000

const ENDPOINT_TYPES: Record<number, string> = {
  1: "docker",
  2: "docker-agent",
  3: "azure",
  4: "edge-agent",
  5: "kubernetes",
  6: "kubernetes-agent",
  7: "kaas",
}
const ENDPOINT_STATUS: Record<number, string> = { 1: "up", 2: "down" }
const STACK_TYPES: Record<number, string> = { 1: "swarm", 2: "standalone" }
const STACK_STATUS: Record<number, string> = { 1: "active", 2: "inactive" }

type Entry = { text: string; fetchedAt: number; failed: boolean }

let cache: Entry | null = null
let inflight: Promise<void> | null = null

const FALLBACK_HINT =
  "Run ./scripts/configure-portainer-key in a terminal, then restart opencode."

function fmtDate(unixSeconds: number | null | undefined): string {
  if (!unixSeconds) return "-"
  return new Date(unixSeconds * 1000).toISOString().slice(0, 10)
}

async function readApiKeyFromKeychain(): Promise<string> {
  return await new Promise((resolve) => {
    execFile(
      "/usr/bin/security",
      [
        "find-generic-password",
        "-s",
        KEYCHAIN_SERVICE,
        "-a",
        KEYCHAIN_ACCOUNT,
        "-w",
      ],
      { timeout: 5_000 },
      (error, stdout) => {
        if (error) resolve("")
        else resolve(stdout.trim())
      },
    )
  })
}

async function apiGet(path: string, apiKey: string): Promise<any> {
  const res = await fetch(`${BASE_URL}/api/${path}`, {
    headers: { "X-API-Key": apiKey },
    signal: AbortSignal.timeout(HTTP_TIMEOUT_MS),
  })
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`)
  return await res.json()
}

function renderSnapshot(
  version: string,
  endpoints: any[],
  stacks: any[],
): string {
  const lines: string[] = []
  lines.push(`<portainer-snapshot instance="${BASE_URL}" version="${version}">`)
  lines.push("Live Portainer state, auto-loaded for this session:")
  lines.push("")
  lines.push(`Environments (endpoints): ${endpoints.length}`)
  for (const e of endpoints) {
    lines.push(
      `- id=${e.Id} name="${e.Name}" type=${ENDPOINT_TYPES[e.Type] ?? e.Type} ` +
        `status=${ENDPOINT_STATUS[e.Status] ?? e.Status} url=${e.URL || "-"}`,
    )
  }
  lines.push("")
  lines.push(`Stacks: ${stacks.length}`)
  for (const s of stacks) {
    lines.push(
      `- id=${s.Id} name="${s.Name}" type=${STACK_TYPES[s.Type] ?? s.Type} ` +
        `endpointId=${s.EndpointId} status=${STACK_STATUS[s.Status] ?? s.Status} ` +
        `created=${fmtDate(s.CreationDate)} updated=${fmtDate(s.UpdateDate)}`,
    )
  }
  lines.push("")
  lines.push(
    "For deeper inspection (containers, services, stack files, logs), use the " +
      "portainer-read_* / portainer-write_* MCP tools; read tools are pre-approved.",
  )
  lines.push("</portainer-snapshot>")
  return lines.join("\n")
}

function renderFailure(reason: string): string {
  return [
    `<portainer-snapshot instance="${BASE_URL}" state="unavailable">`,
    `Could not load live Portainer state (${reason}).`,
    `MCP tools (portainer-read_*) may still work. If the API key is missing: ${FALLBACK_HINT}`,
    "</portainer-snapshot>",
  ].join("\n")
}

async function fetchAndCache(): Promise<void> {
  const apiKey = await readApiKeyFromKeychain()
  if (!apiKey) {
    cache = { text: renderFailure("no API key in macOS Keychain"), fetchedAt: Date.now(), failed: true }
    return
  }
  try {
    const [status, endpoints, stacks] = await Promise.all([
      apiGet("status", apiKey),
      apiGet("endpoints", apiKey),
      apiGet("stacks", apiKey),
    ])
    cache = {
      text: renderSnapshot(
        String(status?.Version ?? "unknown"),
        Array.isArray(endpoints) ? endpoints : [],
        Array.isArray(stacks) ? stacks : [],
      ),
      fetchedAt: Date.now(),
      failed: false,
    }
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err)
    cache = { text: renderFailure(reason), fetchedAt: Date.now(), failed: true }
  }
}

async function ensureSnapshot(): Promise<string> {
  const now = Date.now()
  const ttl = cache?.failed ? FAILED_TTL_MS : FRESH_TTL_MS
  if (cache && now - cache.fetchedAt < ttl) return cache.text
  if (!inflight) {
    inflight = fetchAndCache().finally(() => {
      inflight = null
    })
  }
  if (!cache) await inflight.catch(() => {})
  return cache?.text ?? renderFailure("snapshot fetch failed")
}

const plugin = (async () => {
  void ensureSnapshot().catch(() => {})

  return {
    "experimental.chat.system.transform": async (
      _input,
      output,
    ): Promise<void> => {
      const text = await ensureSnapshot()
      output.system.push(text)
    },
  }
}) satisfies Plugin

export default plugin
