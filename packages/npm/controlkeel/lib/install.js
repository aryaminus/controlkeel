"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const https = require("node:https");

const REPOSITORY = process.env.CONTROLKEEL_GITHUB_REPO || "aryaminus/controlkeel";
const VERSION = process.env.CONTROLKEEL_VERSION || "latest";

function releaseBaseUrl() {
  if (VERSION === "latest") {
    return `https://github.com/${REPOSITORY}/releases/latest/download`;
  }

  return `https://github.com/${REPOSITORY}/releases/download/v${VERSION}`;
}

function assetName(platform = process.platform, arch = process.arch) {
  if (platform === "linux" && arch === "x64") {
    return "controlkeel-linux-x86_64";
  }

  if (platform === "linux" && arch === "arm64") {
    return "controlkeel-linux-arm64";
  }

  if (platform === "darwin" && arch === "x64") {
    return "controlkeel-macos-x86_64";
  }

  if (platform === "darwin" && arch === "arm64") {
    return "controlkeel-macos-arm64";
  }

  if (platform === "win32" && arch === "x64") {
    return "controlkeel-windows-x86_64.exe";
  }

  throw new Error(`Unsupported platform for ControlKeel: ${platform}/${arch}`);
}

function binaryFilename(platform = process.platform) {
  return platform === "win32" ? "controlkeel.exe" : "controlkeel";
}

function binaryPath() {
  return path.join(__dirname, "..", "vendor", binaryFilename());
}

function ensureVendorDir() {
  fs.mkdirSync(path.dirname(binaryPath()), { recursive: true });
}

function download(url, destination) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, (response) => {
      if (response.statusCode && response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        response.resume();
        download(response.headers.location, destination).then(resolve, reject);
        return;
      }

      if (response.statusCode !== 200) {
        reject(new Error(`Failed to download ${url} (HTTP ${response.statusCode})`));
        return;
      }

      const file = fs.createWriteStream(destination);
      response.pipe(file);

      file.on("finish", () => {
        file.close(() => resolve(destination));
      });

      file.on("error", (error) => {
        fs.rmSync(destination, { force: true });
        reject(error);
      });
    });

    request.on("error", reject);
  });
}

async function ensureBinary({ forceDownload = false } = {}) {
  const destination = binaryPath();

  if (!forceDownload && fs.existsSync(destination)) {
    return destination;
  }

  ensureVendorDir();
  const tempPath = path.join(os.tmpdir(), `${assetName()}-${Date.now()}`);
  const url = `${releaseBaseUrl()}/${assetName()}`;

  await download(url, tempPath);
  fs.copyFileSync(tempPath, destination);
  fs.rmSync(tempPath, { force: true });

  if (process.platform !== "win32") {
    fs.chmodSync(destination, 0o755);
  }

  return destination;
}

module.exports = {
  assetName,
  binaryPath,
  ensureBinary
};
