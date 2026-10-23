import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import readline from "node:readline";

const repositoryRoot = process.argv[2];
assert(repositoryRoot, "repository root argument is required");

const temporaryDirectory = fs.mkdtempSync("/tmp/li-mcp-selectors-");
const socketPath = path.join(temporaryDirectory, "bridge.sock");
const shimPath = path.join(repositoryRoot, "Scripts/lookinside-mcp-shim.mjs");

let receivedBridgeFrameResolve;
const receivedBridgeFrame = new Promise((resolve) => {
  receivedBridgeFrameResolve = resolve;
});

const expectedResult = {
  className: "UIButton",
  selectors: ["titleLabel", "setTitle:forState:"],
  totalCount: 2,
  truncated: false,
  includesArguments: true,
  classChain: ["UIButton", "UIControl", "UIView", "NSObject"],
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
  const selectorsTool = listResponse.result.tools.find((tool) => tool.name === "selectors_list");
  assert(selectorsTool, "tools/list must advertise selectors_list");
  assert.deepEqual(selectorsTool.inputSchema.required, ["targetIdentifier"]);
  assert.deepEqual(selectorsTool.inputSchema.anyOf, [
    { required: ["className"] },
    { required: ["objectIdentifier"] },
  ]);
  assert.equal(selectorsTool.inputSchema.properties.limit.maximum, 2000);

  const callResponsePromise = sendMCP({
    jsonrpc: "2.0",
    id: 2,
    method: "tools/call",
    params: {
      name: "selectors_list",
      arguments: {
        targetIdentifier: "42",
        objectIdentifier: "0x25",
        includeArguments: true,
        nameFilter: "title",
        limit: 50,
      },
    },
  });

  const bridgeFrame = await receivedBridgeFrame;
  assert.equal(bridgeFrame.kind, "request");
  assert.equal(bridgeFrame.method, "selectors.list");
  assert.deepEqual(bridgeFrame.params, {
    targetIdentifier: "42",
    objectIdentifier: "0x25",
    includeArguments: true,
    nameFilter: "title",
    limit: 50,
  });

  const callResponse = await callResponsePromise;
  assert.equal(callResponse.result.isError, undefined);
  assert.deepEqual(JSON.parse(callResponse.result.content[0].text), expectedResult);

  console.log("lookinside-mcp shim selectors_list tests passed");
} finally {
  for (const waiter of responseWaiters.values()) {
    waiter.reject(new Error(`shim exited before responding: ${shimStderr}`));
  }
  output.close();
  shim.kill("SIGTERM");
  await new Promise((resolve) => bridgeServer.close(resolve));
  fs.rmSync(temporaryDirectory, { recursive: true, force: true });
}
