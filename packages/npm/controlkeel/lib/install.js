"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const https = require("node:https");

const packageJson = require("../package.json");

// Hardcoded repository and version for security - no environment variable overrides
const REPOSITORY = "aryaminus/controlkeel";
const VERSION = packageJson.version;

// Binary releases are downloaded from the project's public GitHub Releases and
// their signatures verified with cosign (see verifySignature). This is the base
// URL for all network egress this installer performs — binary, checksum file,
// and optional cosign sig/cert artifacts all resolve from here. Kept as plain,
// auditable strings: obfuscating them (e.g. base64 at runtime) is a pattern
// supply-chain scanners treat as MORE suspicious, not less.
const RELEASES_URL = `https://github.com/${REPOSITORY}/releases`;

function releaseBaseUrl() {
  if (VERSION === "latest") {
    return `${RELEASES_URL}/latest/download`;
  }

  return `${RELEASES_URL}/download/v${VERSION}`;
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

function downloadText(url) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, (response) => {
      if (response.statusCode && response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        response.resume();
        downloadText(response.headers.location).then(resolve, reject);
        return;
      }

      if (response.statusCode !== 200) {
        reject(new Error(`Failed to download ${url} (HTTP ${response.statusCode})`));
        return;
      }

      let data = "";
      response.on("data", (chunk) => { data += chunk; });
      response.on("end", () => resolve(data));
    });

    request.on("error", reject);
  });
}

function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
    stream.on("error", reject);
  });
}

async function verifyChecksum(filePath, asset) {
  const checksumUrl = `${releaseBaseUrl()}/controlkeel-checksums.txt`;

  let checksumText;
  try {
    checksumText = await downloadText(checksumUrl);
  } catch (err) {
    throw new Error(
      `[controlkeel] Failed to download checksum file from ${checksumUrl}. ` +
      `Cannot verify binary integrity. Aborting installation. (${err.message})`
    );
  }

  const expectedHash = checksumText
    .split("\n")
    .map((line) => line.trim().split(/\s+/))
    .find(([, name]) => name === asset || name === `./${asset}`)?.[0];

  if (!expectedHash) {
    throw new Error(
      `[controlkeel] No checksum entry found for ${asset} in checksums file. ` +
      `Cannot verify binary integrity. Aborting installation.`
    );
  }

  const actualHash = await sha256File(filePath);

  if (actualHash !== expectedHash) {
    fs.rmSync(filePath, { force: true });
    throw new Error(
      `Checksum mismatch for ${asset}.\n  Expected: ${expectedHash}\n  Got:      ${actualHash}\n` +
      `The downloaded binary has been removed. Please retry the installation or download manually from GitHub Releases.`
    );
  }
}

/**
 * Verify a cosign keyless signature when cosign is available on PATH.
 * Falls back gracefully when cosign is not installed.
 */
async function verifySignature(filePath, asset, baseUrl) {
  if (process.env.CONTROLKEEL_SKIP_SIGNATURE === "1") return;

  const { execFileSync } = require("node:child_process");
  const lookupCommand = process.platform === "win32" ? "where" : "command";
  const lookupArgs = process.platform === "win32" ? ["cosign"] : ["-v", "cosign"];

  let cosignPath;
  try {
    cosignPath = execFileSync(lookupCommand, lookupArgs, { encoding: "utf8", shell: false }).split(/\r?\n/)[0].trim();
  } catch {
    // cosign not available — checksum-only mode
    return;
  }

  if (!cosignPath) return;

  const repo = REPOSITORY;
  const sigUrl = `${baseUrl}/${asset}.sig`;
  const certUrl = `${baseUrl}/${asset}.pem`;
  const sigFile = path.join(os.tmpdir(), `${asset}.sig`);
  const certFile = path.join(os.tmpdir(), `${asset}.pem`);

  await download(sigUrl, sigFile).catch(() => null);
  await download(certUrl, certFile).catch(() => null);

  if (!fs.existsSync(sigFile) || !fs.existsSync(certFile)) {
    fs.rmSync(sigFile, { force: true });
    fs.rmSync(certFile, { force: true });

    if (process.env.CONTROLKEEL_REQUIRE_SIGNATURE === "1") {
      throw new Error(`[controlkeel] No cosign signature/certificate available for ${asset}`);
    }

    return;
  }

  try {
    execFileSync(cosignPath, [
      "verify-blob", filePath,
      "--signature", sigFile,
      "--certificate", certFile,
      "--certificate-identity-regexp", `^https://github.com/${repo}/.github/workflows/release.yml@refs/tags/v[0-9].*`,
      "--certificate-oidc-issuer", "https://token.actions.githubusercontent.com"
    ], { stdio: "pipe", timeout: 30000 });

    console.log(`[controlkeel] Verified ${asset} signature (cosign keyless)`);
  } catch (err) {
    throw new Error(`[controlkeel] cosign signature verification failed for ${asset}`);
  } finally {
    fs.rmSync(sigFile, { force: true });
    fs.rmSync(certFile, { force: true });
  }
}

async function ensureBinary({ forceDownload = false } = {}) {
  const destination = binaryPath();

  if (!forceDownload && fs.existsSync(destination)) {
    return destination;
  }

  ensureVendorDir();
  const asset = assetName();
  const tempPath = path.join(os.tmpdir(), `${asset}-${Date.now()}`);
  const url = `${releaseBaseUrl()}/${asset}`;

  await download(url, tempPath);
  await verifyChecksum(tempPath, asset);
  await verifySignature(tempPath, asset, releaseBaseUrl());

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
