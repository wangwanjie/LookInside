#!/usr/bin/env node

import net from "node:net";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";

const DEFAULT_SOCKET = path.join(
  os.homedir(),
  "Library/Application Support/LookInside/Host/run/lookinside-host-mcp.sock",
);

function parseArgs(argv) {
  let socketPath = process.env.LOOKINSIDE_MCP_SOCKET || DEFAULT_SOCKET;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--socket" && argv[i + 1]) {
      socketPath = argv[i + 1].replace(/^~(?=\/|$)/, os.homedir());
      i += 1;
    }
  }
  return { socketPath };
}

const { socketPath } = parseArgs(process.argv.slice(2));

const bridgeMethods = {
  ping: "ping",
  targets_list: "targets.list",
  hierarchy_read: "hierarchy.read",
  hierarchy_reload: "hierarchy.reload",
  attributes_read: "attributes.read",
  details_read: "details.read",
  invoke_method: "invoke.method",
  attribute_modify: "attribute.modify",
};

const tools = [
  {
    name: "ping",
    description: "Check whether the LookInside host MCP bridge is reachable.",
    inputSchema: { type: "object", additionalProperties: false, properties: {} },
  },
  {
    name: "targets_list",
    description: "List live LookInside inspection targets currently attached in the Mac app.",
    inputSchema: { type: "object", additionalProperties: false, properties: {} },
  },
  {
    name: "hierarchy_read",
    description: "Read a target view hierarchy, optionally scoped to a root object and depth. Each node includes objectIdentifier, parentObjectIdentifier, childObjectIdentifiers, and optionally inlined children.",
    inputSchema: {
      type: "object",
      additionalProperties: false,
      required: ["targetIdentifier"],
      properties: {
        targetIdentifier: { type: "string" },
        rootObjectIdentifier: { type: "string" },
        depth: { type: "integer", minimum: 1 },
      },
    },
  },
  {
    name: "hierarchy_reload",
    description: "Reload the target hierarchy and wait until LookInside updates its desktop cache.",
    inputSchema: {
      type: "object",
      additionalProperties: false,
      required: ["targetIdentifier"],
      properties: {
        targetIdentifier: { type: "string" },
      },
    },
  },
  {
    name: "attributes_read",
    description: "Read cached attributes for one object in a live target hierarchy.",
    inputSchema: {
      type: "object",
      additionalProperties: false,
      required: ["targetIdentifier", "objectIdentifier"],
      properties: {
        targetIdentifier: { type: "string" },
        objectIdentifier: { type: "string" },
        includeUserCustom: { type: "boolean", default: true },
      },
    },
  },
  {
    name: "details_read",
    description: "Fetch detailed attributes for multiple object identifiers. Each detail entry includes objectIdentifier, parentObjectIdentifier, groups, and secureContent.",
    inputSchema: {
      type: "object",
      additionalProperties: false,
      required: ["targetIdentifier", "objectIdentifiers"],
      properties: {
        targetIdentifier: { type: "string" },
        objectIdentifiers: { type: "array", items: { type: "string" }, minItems: 1 },
        includeUserCustom: { type: "boolean", default: true },
      },
    },
  },
  {
    name: "invoke_method",
    description: "Invoke a zero-argument selector on a live object.",
    inputSchema: {
      type: "object",
      additionalProperties: false,
      required: ["targetIdentifier", "objectIdentifier", "selector"],
      properties: {
        targetIdentifier: { type: "string" },
        objectIdentifier: { type: "string" },
        selector: { type: "string" },
      },
    },
  },
  {
    name: "attribute_modify",
    description: "Modify a writable cached LookInside attribute on a live object.",
    inputSchema: {
      type: "object",
      additionalProperties: false,
      required: ["targetIdentifier", "objectIdentifier", "attributeIdentifier", "value"],
      properties: {
        targetIdentifier: { type: "string" },
        objectIdentifier: { type: "string" },
        attributeIdentifier: { type: "string" },
        value: {
          type: "object",
          required: ["kind"],
          additionalProperties: false,
          properties: {
            kind: { type: "string" },
            data: {},
          },
        },
      },
    },
  },
];

function write(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function rpcError(id, code, message) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

function callBridge(method, params) {
  return new Promise((resolve, reject) => {
    const id = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const socket = net.createConnection({ path: socketPath });
    let buffer = "";
    let settled = false;

    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      fn(value);
    };

    socket.setTimeout(30000, () => {
      finish(reject, new Error(`Timed out waiting for LookInside bridge at ${socketPath}`));
    });
    socket.on("error", (error) => finish(reject, error));
    socket.on("connect", () => {
      socket.write(`${JSON.stringify({ kind: "request", id, method, params: params || {} })}\n`);
    });
    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      let newlineIndex;
      while ((newlineIndex = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newlineIndex).trim();
        buffer = buffer.slice(newlineIndex + 1);
        if (!line) continue;
        let frame;
        try {
          frame = JSON.parse(line);
        } catch {
          continue;
        }
        if (frame.kind === "response" && frame.id === id) {
          finish(resolve, frame);
        }
      }
    });
  });
}

async function handle(request) {
  const { id, method, params } = request;
  switch (method) {
    case "initialize":
      return {
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: params?.protocolVersion || "2024-11-05",
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: "lookinside", version: "0.1.0" },
        },
      };
    case "tools/list":
      return { jsonrpc: "2.0", id, result: { tools } };
    case "tools/call": {
      const toolName = params?.name;
      const bridgeMethod = bridgeMethods[toolName];
      if (!bridgeMethod) {
        return rpcError(id, -32602, `Unknown LookInside tool: ${toolName}`);
      }
      const frame = await callBridge(bridgeMethod, params?.arguments || {});
      if (frame.error) {
        return {
          jsonrpc: "2.0",
          id,
          result: {
            isError: true,
            content: [{ type: "text", text: JSON.stringify(frame.error, null, 2) }],
          },
        };
      }
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify(frame.result ?? null, null, 2) }],
        },
      };
    }
    default:
      if (method?.startsWith("notifications/")) return null;
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", async (line) => {
  if (!line.trim()) return;
  let request;
  try {
    request = JSON.parse(line);
  } catch {
    write(rpcError(null, -32700, "Parse error"));
    return;
  }
  try {
    const response = await handle(request);
    if (response) write(response);
  } catch (error) {
    write(rpcError(request.id ?? null, -32000, error?.message || String(error)));
  }
});
