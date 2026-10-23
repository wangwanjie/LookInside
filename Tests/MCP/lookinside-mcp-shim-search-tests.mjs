import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import readline from "node:readline";

const repositoryRoot = process.argv[2];
assert(repositoryRoot, "repository root argument is required");

// Unix-domain socket paths are capped at roughly 100 bytes on macOS. Keep this
// independent of a possibly deeply nested TMPDIR supplied by an outer test.
const temporaryDirectory = fs.mkdtempSync("/tmp/li-mcp-search-");
const socketPath = path.join(temporaryDirectory, "bridge.sock");
const shimPath = path.join(repositoryRoot, "Scripts/lookinside-mcp-shim.mjs");

let receivedBridgeFrameResolve;
const receivedBridgeFrame = new Promise((resolve) => {
  receivedBridgeFrameResolve = resolve;
});

const expectedResult = {
  matches: [
    {
      objectIdentifier: "0x2afe",
      className: "UIButton",
      title: "UIButton",
      subtitle: null,
      frame: { x: 10, y: 20, width: 100, height: 44 },
      isHidden: false,
      alpha: 1,
      depth: 2,
      ancestorObjectIdentifiers: ["0x1000", "0x2000"],
      pathDescription: "UIWindow > UIView > UIButton",
      matchedFields: ["className"],
      secureContent: false,
    },
  ],
  totalMatchCount: 1,
  truncated: false,
  searchedNodeCount: 32,
  searchedFields: ["className"],
};

const bridgeServer = net.createServer((connection) => {
  let buffer = "";
  connection.on("data", (chunk) => {
    buffer += chunk.toString("utf8");
    const newlineIndex = buffer.indexOf("\n");
    if (newlineIndex < 0) return;

    const frame = JSON.parse(buffer.slice(0, newlineIndex));
    receivedBridgeFrameResolve(frame);
    connection.write(`${JSON.stringify({
      kind: "response",
      id: frame.id,
      result: expectedResult,
    })}\n`);
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
  const searchTool = listResponse.result.tools.find((tool) => tool.name === "hierarchy_find");
  assert(searchTool, "tools/list must advertise hierarchy_find");
  assert.deepEqual(searchTool.inputSchema.required, ["targetIdentifier", "className"]);
  assert.equal(searchTool.inputSchema.properties.className.minLength, 1);

  const callResponsePromise = sendMCP({
    jsonrpc: "2.0",
    id: 2,
    method: "tools/call",
    params: {
      name: "hierarchy_find",
      arguments: {
        targetIdentifier: "42",
        className: "UIButton",
        rootObjectIdentifier: "0x1000",
        includeHidden: false,
        limit: 10,
      },
    },
  });

  const bridgeFrame = await receivedBridgeFrame;
  assert.equal(bridgeFrame.kind, "request");
  assert.equal(bridgeFrame.method, "hierarchy.find");
  assert.deepEqual(bridgeFrame.params, {
    targetIdentifier: "42",
    rootObjectIdentifier: "0x1000",
    includeHidden: false,
    limit: 10,
    query: "UIButton",
    matchFields: ["className"],
  });

  const callResponse = await callResponsePromise;
  assert.equal(callResponse.result.isError, undefined);
  assert.deepEqual(JSON.parse(callResponse.result.content[0].text), expectedResult);

  console.log("lookinside-mcp shim hierarchy_find tests passed");
} finally {
  for (const waiter of responseWaiters.values()) {
    waiter.reject(new Error(`shim exited before responding: ${shimStderr}`));
  }
  output.close();
  shim.kill("SIGTERM");
  await new Promise((resolve) => bridgeServer.close(resolve));
  fs.rmSync(temporaryDirectory, { recursive: true, force: true });
}
