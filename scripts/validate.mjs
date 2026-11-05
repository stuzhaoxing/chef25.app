import { readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const readJson = async (name) =>
  JSON.parse(await readFile(path.join(root, name), "utf8"));

const [version, lock, packageJson] = await Promise.all([
  readJson("mobile-version.json"),
  readJson("runtime.lock.json"),
  readJson("package.json"),
]);

if (version.version !== packageJson.version)
  throw new Error("package.json and mobile-version.json versions differ");
if (!/^\d+\.\d+\.\d+$/.test(version.version))
  throw new Error("Mobile version must be stable semver");
if (version.androidMinSdk !== 24)
  throw new Error("Android minSdk must remain 24 unless runtime support is revalidated");
if (!/^\d+\.\d+$/.test(version.iosDeploymentTarget))
  throw new Error("Invalid iOS deployment target");
if (lock.nodeMobileVersion !== `${lock.nodeVersion}-0`)
  throw new Error("Node Mobile and upstream Node versions differ");
if (!/^[a-f0-9]{40}$/.test(lock.nodeMobile.commit))
  throw new Error("Node Mobile commit must be pinned");
if (!/^[a-f0-9]{40}$/.test(lock.sillyTavern.commit))
  throw new Error("SillyTavern commit must be pinned");
for (const [platform, artifact] of Object.entries(
  lock.nodeMobile.platforms,
)) {
  if (!artifact.url.startsWith("https://github.com/"))
    throw new Error(`${platform} runtime must use the pinned GitHub release`);
  if (!/^[a-f0-9]{64}$/.test(artifact.sha256))
    throw new Error(`${platform} runtime needs a SHA-256`);
}

console.log(
  `Mobile ${version.version}; Node ${lock.nodeVersion}; SillyTavern ${lock.sillyTavern.version}`,
);
