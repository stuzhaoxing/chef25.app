import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  copyFile,
  mkdir,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const output = path.join(root, "artifacts/mobile-distribution");
const versionConfig = JSON.parse(
  await readFile(path.join(root, "mobile-version.json"), "utf8"),
);
const runtime = JSON.parse(
  await readFile(path.join(root, "runtime.lock.json"), "utf8"),
);
const sourceApk = process.env.MOBILE_APK;
const testflightPublicUrl = process.env.TESTFLIGHT_PUBLIC_URL;
const buildNumber = process.env.MOBILE_BUILD_NUMBER;

if (!sourceApk) throw new Error("MOBILE_APK is required");
if (!/^\d+\.\d+\.\d+$/.test(versionConfig.version))
  throw new Error("Invalid mobile version");
if (!buildNumber || !/^\d+$/.test(buildNumber))
  throw new Error("MOBILE_BUILD_NUMBER must be a positive integer");
if (
  !testflightPublicUrl ||
  !/^https:\/\/testflight\.apple\.com\/join\/[A-Za-z0-9]+$/.test(
    testflightPublicUrl,
  )
)
  throw new Error("TESTFLIGHT_PUBLIC_URL must be a public TestFlight join URL");

await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });

const digest = async (file) =>
  createHash("sha256")
    .update(await readFile(file))
    .digest("hex");

const apkName = `Chef25_${versionConfig.version}_android-arm64.apk`;
const apk = path.join(output, apkName);
await copyFile(sourceApk, apk);
const apkSha256 = await digest(apk);
const suppliedSha256 = process.env.MOBILE_APK_SHA256;
if (suppliedSha256 && suppliedSha256 !== apkSha256)
  throw new Error("Android APK SHA-256 changed after verification");

const sourceName = `Chef25_${versionConfig.version}_source.tar.gz`;
execFileSync(
  "git",
  [
    "archive",
    "--format=tar.gz",
    `--output=${path.join(output, sourceName)}`,
    "HEAD",
  ],
  { cwd: root, stdio: "inherit" },
);
await copyFile(
  path.join(root, "THIRD_PARTY_NOTICES.md"),
  path.join(output, "THIRD_PARTY_NOTICES.md"),
);

const commit = execFileSync("git", ["rev-parse", "HEAD"], {
  cwd: root,
  encoding: "utf8",
}).trim();
if (!/^[a-f0-9]{40}$/.test(commit)) throw new Error("Invalid build commit");

const distribution = {
  version: versionConfig.version,
  preview: true,
  commit,
  buildNumber: Number(buildNumber),
  ios: {
    distribution: "testflight",
    url: testflightPublicUrl,
    buildNumber: Number(buildNumber),
  },
  android: {
    url: `/downloads/mobile/v${versionConfig.version}/${apkName}`,
    sha256: apkSha256,
    size: (await stat(apk)).size,
    signing: "apk-v2",
    minSdk: versionConfig.androidMinSdk,
    abi: "arm64-v8a",
  },
  runtime: {
    node: runtime.nodeVersion,
    nodeMobile: runtime.nodeMobileVersion,
    sillyTavern: runtime.sillyTavern.version,
  },
  source: {
    url: `/downloads/mobile/v${versionConfig.version}/${sourceName}`,
    sha256: await digest(path.join(output, sourceName)),
    size: (await stat(path.join(output, sourceName))).size,
  },
};

await writeFile(
  path.join(output, "distribution.json"),
  JSON.stringify(distribution, null, 2) + "\n",
);
const sums = [];
for (const name of (await readdir(output)).sort()) {
  if (name === "SHA256SUMS") continue;
  sums.push(`${await digest(path.join(output, name))}  ${name}`);
}
await writeFile(path.join(output, "SHA256SUMS"), sums.join("\n") + "\n");

console.log(`Created mobile distribution v${versionConfig.version}`);
