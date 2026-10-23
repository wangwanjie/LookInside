import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";

const repositoryRoot = process.argv[2];
assert(repositoryRoot, "repository root argument is required");

const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "lookinside-mcp-shim-reload-"));
const socketPath = path.join(temporaryDirectory, "bridge.sock");
const shimPath = path.join(repositoryRoot, "Scripts/lookinside-mcp-shim.mjs");

let receivedBridgeFrameResolve;
const receivedBridgeFrame = new Promise((resolve) => {
  receivedBridgeFrameResolve = resolve;
});
let releaseBridgeResponse;
const bridgeResponseAllowed = new Promise((resolve) => {
  releaseBridgeResponse = resolve;
});

const bridgeServer = net.createServer((connection) => {
  let buffer = "";
  connection.on("data", (chunk) => {
    buffer += chunk.toString("utf8");
    const newlineIndex = buffer.indexOf("\n");
    if (newlineIndex < 0) return;

    const frame = JSON.parse(buffer.slice(0, newlineIndex));
    receivedBridgeFrameResolve(frame);
    bridgeResponseAllowed.then(() => {
      connection.write(`${JSON.stringify({
        kind: "response",
        id: frame.id,
        result: { reloaded: true },
      })}\n`);
    });
  });
});

await new Promise((resolve, reject) => {
  bridgeServer.once("error", reject);
  bridgeServer.listen(socketPath, resolve);
});

const shim = spawn(process.execPath, [shimPath, "--socket", socketPath], {
  stdio: ["pipe", "pipe", "pipe"],
});
let shimStderr = "";
shim.stderr.on("data", (chunk) => {
  shimStderr += chunk.toString("utf8");
});

const responseWaiters = new Map();
const output = readline.createInterface({ input: shim.stdout, crlfDelay: Infinity });
output.on("line", (line) => {
  const message = JSON.parse(line);
  const waiter = responseWaiters.get(message.id);
  if (waiter) {
    responseWaiters.delete(message.id);
    waiter.resolve(message);
  }
});

function sendMCP(request) {
  return new Promise((resolve, reject) => {
    responseWaiters.set(request.id, { resolve, reject });
    shim.stdin.write(`${JSON.stringify(request)}\n`);
  });
}

try {
  const listResponse = await sendMCP({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} });
  const reloadTool = listResponse.result.tools.find((tool) => tool.name === "hierarchy_reload");
  assert(reloadTool, "tools/list must advertise hierarchy_reload");
  assert.deepEqual(reloadTool.inputSchema.required, ["targetIdentifier"]);

  let callResolved = false;
  const callResponsePromise = sendMCP({
    jsonrpc: "2.0",
    id: 2,
    method: "tools/call",
    params: {
      name: "hierarchy_reload",
      arguments: { targetIdentifier: "42" },
    },
  }).then((response) => {
    callResolved = true;
    return response;
  });

  const bridgeFrame = await receivedBridgeFrame;
  assert.equal(bridgeFrame.kind, "request");
  assert.equal(bridgeFrame.method, "hierarchy.reload");
  assert.deepEqual(bridgeFrame.params, { targetIdentifier: "42" });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(callResolved, false, "MCP call must remain pending while the Bridge reload is pending");

  releaseBridgeResponse();
  const callResponse = await callResponsePromise;
  assert.equal(callResponse.result.isError, undefined);
  assert.deepEqual(JSON.parse(callResponse.result.content[0].text), { reloaded: true });

  console.log("lookinside-mcp shim hierarchy_reload tests passed");
} finally {
  for (const waiter of responseWaiters.values()) {
    waiter.reject(new Error(`shim exited before responding: ${shimStderr}`));
  }
  output.close();
  shim.kill("SIGTERM");
  await new Promise((resolve) => bridgeServer.close(resolve));
  fs.rmSync(temporaryDirectory, { recursive: true, force: true });
}
