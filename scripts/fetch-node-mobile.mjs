import { createHash } from "node:crypto";
import {
  access,
  copyFile,
  mkdir,
  readFile,
  rm,
  stat,
} from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";

const root = path.resolve(import.meta.dirname, "..");
const platform = process.argv[2];
if (!["android", "ios"].includes(platform))
  throw new Error("Usage: node scripts/fetch-node-mobile.mjs <android|ios>");

const lock = JSON.parse(
  await readFile(path.join(root, "runtime.lock.json"), "utf8"),
);
const key = platform === "android" ? "android-arm64" : "ios-arm64";
const artifact = lock.nodeMobile.platforms[key];
if (!artifact) throw new Error(`Missing runtime lock for ${key}`);

const cache = path.join(root, ".build", "downloads");
const archive = path.join(cache, path.basename(new URL(artifact.url).pathname));
const destination = path.join(root, ".build", "nodejs-mobile", platform);
await mkdir(cache, { recursive: true });

async function valid(file) {
  try {
    if ((await stat(file)).size === 0) return false;
    const digest = createHash("sha256")
      .update(await readFile(file))
      .digest("hex");
    return digest === artifact.sha256;
  } catch {
    return false;
  }
}

if (!(await valid(archive))) {
  await rm(archive, { force: true });
  const response = await fetch(artifact.url, { redirect: "follow" });
  if (!response.ok)
    throw new Error(`Runtime download failed with HTTP ${response.status}`);
  const { writeFile } = await import("node:fs/promises");
  await writeFile(archive, Buffer.from(await response.arrayBuffer()));
}
if (!(await valid(archive)))
  throw new Error("Node Mobile runtime SHA-256 mismatch");

await rm(destination, { recursive: true, force: true });
await mkdir(destination, { recursive: true });
const unzip = spawnSync("unzip", ["-q", archive, "-d", destination], {
  stdio: "inherit",
});
if (unzip.status !== 0) throw new Error("Cannot extract Node Mobile runtime");

if (platform === "android") {
  const source = path.join(destination, "bin", "arm64-v8a", "libnode.so");
  await access(source);
  const target = path.join(
    root,
    "spike/android-node-runtime/libnode/arm64-v8a/libnode.so",
  );
  await mkdir(path.dirname(target), { recursive: true });
  await copyFile(source, target);
} else {
  await access(path.join(destination, "NodeMobile.xcframework", "Info.plist"));
}

console.log(
  `Prepared Node.js Mobile ${lock.nodeMobileVersion} (${artifact.sha256}) for ${platform}`,
);
