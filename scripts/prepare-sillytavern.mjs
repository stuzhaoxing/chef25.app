import { execFileSync } from "node:child_process";
import {
  access,
  cp,
  mkdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const platform = process.argv[2];
if (!["android", "ios"].includes(platform))
  throw new Error("Usage: node scripts/prepare-sillytavern.mjs <android|ios>");

const lock = JSON.parse(
  await readFile(path.join(root, "runtime.lock.json"), "utf8"),
);
const source = path.join(root, ".build", "third-party", "SillyTavern");
const destination = path.join(root, `.build/sillytavern-${platform}`);
const tiktokenRoot = path.join(root, "runtime/js-tiktoken");
const tiktokenModules = path.join(tiktokenRoot, "node_modules");

await mkdir(path.dirname(source), { recursive: true });
try {
  await access(path.join(source, ".git"));
} catch {
  execFileSync("git", ["init", source], { stdio: "inherit" });
}

function git(...args) {
  execFileSync("git", ["-C", source, ...args], { stdio: "inherit" });
}

let hasOrigin = true;
try {
  git("remote", "get-url", "origin");
} catch {
  hasOrigin = false;
}
if (!hasOrigin)
  git(
    "remote",
    "add",
    "origin",
    `https://github.com/${lock.sillyTavern.repository}.git`,
  );
git("fetch", "--depth=1", "origin", lock.sillyTavern.commit);
git("checkout", "--force", "--detach", "FETCH_HEAD");

const packageJson = JSON.parse(
  await readFile(path.join(source, "package.json"), "utf8"),
);
if (packageJson.version !== lock.sillyTavern.version)
  throw new Error("SillyTavern version does not match runtime.lock.json");

const npmCache = path.join(root, ".build", "npm-cache");
execFileSync(
  "npm",
  ["ci", "--omit=dev", "--ignore-scripts", "--no-audit", "--no-fund"],
  {
    cwd: source,
    stdio: "inherit",
    env: { ...process.env, npm_config_cache: npmCache },
  },
);
execFileSync(
  "npm",
  ["ci", "--ignore-scripts", "--no-audit", "--no-fund"],
  {
    cwd: tiktokenRoot,
    stdio: "inherit",
    env: { ...process.env, npm_config_cache: npmCache },
  },
);

await rm(destination, { recursive: true, force: true });
await cp(source, destination, {
  recursive: true,
  // App Store bundles reject symlinks. npm's .bin directories only hold
  // command-line shims, so they are not needed by the embedded server.
  filter: (file) => ![".git", ".bin"].includes(path.basename(file)),
});

const runtimeDirectory = path.join(destination, ".chef25-runtime");
await mkdir(runtimeDirectory, { recursive: true });
const iosSource = path.join(root, "spike/ios-node-runtime");
await cp(
  path.join(iosSource, "WebAssemblyTiktokenBootstrap.cjs"),
  path.join(runtimeDirectory, "WebAssemblyTiktokenBootstrap.cjs"),
);
await cp(
  path.join(iosSource, "tiktoken-wasmless.cjs"),
  path.join(runtimeDirectory, "tiktoken-wasmless.cjs"),
);
await cp(
  path.join(tiktokenModules, "js-tiktoken"),
  path.join(destination, "node_modules", "js-tiktoken"),
  { recursive: true },
);
await cp(
  path.join(tiktokenModules, "base64-js"),
  path.join(destination, "node_modules", "base64-js"),
  { recursive: true },
);

await writeFile(
  path.join(destination, "node_modules", "tiktoken", "tiktoken.cjs"),
  "'use strict';\n\nmodule.exports = require('../../.chef25-runtime/tiktoken-wasmless.cjs');\n",
);

const jimpPng = path.join(
  destination,
  "node_modules/@jimp/wasm-png/dist/esm/index.js",
);
const jimpJpeg = path.join(
  destination,
  "node_modules/@jimp/wasm-jpeg/dist/esm/index.js",
);
try {
  await access(jimpPng);
  await writeFile(jimpPng, "import png from '@jimp/js-png';\n\nexport default png;\n");
} catch {}
try {
  await access(jimpJpeg);
  await writeFile(
    jimpJpeg,
    "import jpeg from '@jimp/js-jpeg';\n\nexport default jpeg;\n",
  );
} catch {}

await writeFile(
  path.join(runtimeDirectory, "build-info.json"),
  JSON.stringify(
    {
      node: lock.nodeVersion,
      nodeMobile: lock.nodeMobileVersion,
      sillyTavern: lock.sillyTavern.version,
      sillyTavernCommit: lock.sillyTavern.commit,
      platform,
    },
    null,
    2,
  ) + "\n",
);

await access(path.join(destination, "server.js"));
console.log(
  `Prepared SillyTavern ${lock.sillyTavern.version} for ${platform} at ${destination}`,
);
