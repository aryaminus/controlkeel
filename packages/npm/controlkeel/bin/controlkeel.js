#!/usr/bin/env node

const { spawn } = require("node:child_process");
const { ensureBinary } = require("../lib/install");

async function main() {
  const binaryPath = await ensureBinary({ forceDownload: false });
  const child = spawn(binaryPath, process.argv.slice(2), { stdio: "inherit" });

  child.on("exit", (code, signal) => {
    if (signal) {
      process.kill(process.pid, signal);
      return;
    }

    process.exit(code ?? 0);
  });
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
