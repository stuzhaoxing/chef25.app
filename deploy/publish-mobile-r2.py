#!/usr/bin/env python3
"""Publish an immutable mobile release and activate its private manifest."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from urllib.request import Request, urlopen

PREFIX = "downloads/mobile"
LOCK = f"{PREFIX}/.publish-lock"
LATEST = f"{PREFIX}/latest.json"
IMMUTABLE = "public, max-age=31536000, immutable"
MAX_RELEASE_BYTES = 2 * 1024**3
MAX_BUCKET_BYTES = 9_000_000_000  # Decimal GB; leave headroom below the shared 10 GB free tier.
MAX_BUCKET_OBJECTS = 10_000
PUBLIC_HEADERS = {
    "Accept-Encoding": "identity",
    "User-Agent": "Chef25-Mobile-Release-Verifier/1.0 (+https://www.chef25.com)",
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_origin(value):
    if not re.fullmatch(r"https://[a-z0-9]+(?:[.-][a-z0-9]+)+", value):
        raise ValueError(
            "CHEF25_DOWNLOAD_ORIGIN must be an HTTPS origin without a path"
        )
    return value


def error_code(error):
    return getattr(error, "response", {}).get("Error", {}).get("Code")


def validate(folder):
    files = list(folder.iterdir())
    if not files or any(not item.is_file() or item.is_symlink() for item in files):
        raise ValueError("Distribution must contain regular files only")
    if sum(item.stat().st_size for item in files) > MAX_RELEASE_BYTES:
        raise ValueError("Mobile distribution exceeds the 2 GiB release budget")
    manifest = json.loads((folder / "distribution.json").read_text())
    version = manifest.get("version")
    if not isinstance(version, str) or not re.fullmatch(
        r"\d+\.\d+\.\d+", version
    ):
        raise ValueError("Invalid mobile release version")
    if manifest.get("preview") is not True:
        raise ValueError("Only preview distributions are currently accepted")
    ios = manifest.get("ios", {})
    if ios.get("distribution") != "testflight" or not re.fullmatch(
        r"https://testflight\.apple\.com/join/[A-Za-z0-9]+",
        ios.get("url", ""),
    ):
        raise ValueError("A valid public TestFlight URL is required")
    android = manifest.get("android", {})
    url = android.get("url", "")
    expected_prefix = f"/downloads/mobile/v{version}/"
    if not url.startswith(expected_prefix) or "/" in url[len(expected_prefix) :]:
        raise ValueError("Invalid Android download URL")
    apk = folder / Path(url).name
    if not apk.is_file():
        raise ValueError("Android APK named by the manifest is missing")
    if sha256(apk) != android.get("sha256"):
        raise ValueError("Android APK SHA-256 mismatch")
    if apk.stat().st_size != android.get("size"):
        raise ValueError("Android APK size mismatch")
    if android.get("signing") != "apk-v2":
        raise ValueError("Android APK must be release-signed with APK v2")
    source = manifest.get("source", {})
    source_file = folder / Path(source.get("url", "")).name
    if not source_file.is_file() or sha256(source_file) != source.get("sha256"):
        raise ValueError("Matching source archive is missing or corrupt")
    expected_sums = {}
    for line in (folder / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([a-f0-9]{64})  ([^/]+)", line)
        if not match:
            raise ValueError("Invalid SHA256SUMS")
        expected_sums[match.group(2)] = match.group(1)
    actual = {
        item.name: sha256(item)
        for item in files
        if item.name != "SHA256SUMS"
    }
    if actual != expected_sums:
        raise ValueError("SHA256SUMS does not describe the distribution")
    return manifest


def version_tuple(version):
    if not isinstance(version, str) or not re.fullmatch(
        r"\d+\.\d+\.\d+", version
    ):
        raise ValueError("Invalid published version")
    return tuple(map(int, version.split(".")))


def content_type(file):
    if file.suffix == ".json":
        return "application/json"
    if file.name == "SHA256SUMS" or file.suffix == ".md":
        return "text/plain; charset=utf-8"
    if file.suffix == ".apk":
        return "application/vnd.android.package-archive"
    return "application/octet-stream"


def check_capacity(client, bucket, planned):
    # The bucket is shared with Desktop. Detect writers using multipart uploads
    # rather than undercounting storage that this publisher cannot enumerate.
    if client.list_multipart_uploads(Bucket=bucket, MaxUploads=1).get("Uploads"):
        raise ValueError("Incomplete multipart upload exists; resolve it before publishing")
    sizes = {}
    token = None
    while True:
        page = client.list_objects_v2(
            Bucket=bucket,
            MaxKeys=1000,
            **({"ContinuationToken": token} if token else {}),
        )
        for item in page.get("Contents", []):
            sizes[item["Key"]] = item["Size"]
        if len(sizes) > MAX_BUCKET_OBJECTS:
            raise ValueError("Bucket object-count limit exceeded")
        if not page.get("IsTruncated"):
            break
        next_token = page.get("NextContinuationToken")
        if not next_token or next_token == token:
            raise ValueError("Cannot safely enumerate bucket capacity")
        token = next_token
    projected = sum(sizes.values()) + sum(
        max(0, size - sizes.get(key, 0)) for key, size in planned.items()
    )
    if (
        projected > MAX_BUCKET_BYTES
        or len(set(sizes) | set(planned)) > MAX_BUCKET_OBJECTS
    ):
        raise ValueError(
            "Publication would exceed the shared 9 GB / 10000 object budget"
        )


def verify_public(origin, key, file):
    url = origin + "/" + key
    request = Request(url, headers=PUBLIC_HEADERS)
    with urlopen(request, timeout=180) as response:
        if response.status != 200 or response.geturl() != url:
            raise ValueError("Public download did not return the requested object")
        if response.headers.get("Content-Length") != str(file.stat().st_size):
            raise ValueError("Public download length mismatch")
        if key == LATEST and "no-store" not in response.headers.get(
            "Cache-Control", ""
        ).lower():
            raise ValueError("Mobile manifest must disable caching")
        digest = hashlib.sha256()
        for chunk in iter(lambda: response.read(1024 * 1024), b""):
            digest.update(chunk)
        if digest.hexdigest() != sha256(file):
            raise ValueError("Public download checksum mismatch")
    if file.suffix in {".apk", ".gz"}:
        range_request = Request(
            url, headers={**PUBLIC_HEADERS, "Range": "bytes=0-0"}
        )
        with urlopen(range_request, timeout=60) as response:
            if (
                response.status != 206
                or response.headers.get("Content-Range")
                != f"bytes 0-0/{file.stat().st_size}"
            ):
                raise ValueError("Public download does not support byte ranges")


def get_object(client, bucket, key):
    try:
        return client.get_object(Bucket=bucket, Key=key)
    except Exception as error:
        if error_code(error) in {"NoSuchKey", "404"}:
            return None
        raise


@contextmanager
def publication_lock(client, bucket):
    try:
        client.put_object(
            Bucket=bucket,
            Key=LOCK,
            Body=b"Chef25 mobile publication in progress\n",
            IfNoneMatch="*",
            CacheControl="no-store",
        )
    except Exception as error:
        if error_code(error) in {
            "PreconditionFailed",
            "412",
            "ConditionalRequestConflict",
            "409",
        }:
            raise ValueError("Another mobile publication holds the R2 lock") from None
        raise
    try:
        yield
    finally:
        client.delete_object(Bucket=bucket, Key=LOCK)


def put_immutable(client, bucket, key, file):
    digest = sha256(file)
    try:
        with file.open("rb") as body:
            client.put_object(
                Bucket=bucket,
                Key=key,
                Body=body,
                ContentLength=file.stat().st_size,
                ContentType=content_type(file),
                CacheControl=IMMUTABLE,
                Metadata={"sha256": digest},
                IfNoneMatch="*",
            )
    except Exception as error:
        if error_code(error) not in {"PreconditionFailed", "412"}:
            raise
        existing = get_object(client, bucket, key)
        if existing is None:
            raise ValueError("Conflicting object disappeared; retry") from None
        with existing["Body"] as body:
            same = hashlib.sha256(body.read()).hexdigest() == digest
        if existing["ContentLength"] != file.stat().st_size or not same:
            raise ValueError("Release versions are immutable; publish a new version")


def publish(client, bucket, folder, origin, activate, verifier=verify_public):
    manifest = validate(folder)
    version_prefix = f"{PREFIX}/v{manifest['version']}/"
    with publication_lock(client, bucket):
        if activate:
            current = get_object(client, bucket, LATEST)
            if current is not None:
                with current["Body"] as body:
                    current_version = json.loads(body.read()).get("version")
                if version_tuple(current_version) > version_tuple(manifest["version"]):
                    raise ValueError("Automatic mobile downgrades are not allowed")
        files = sorted(folder.iterdir(), key=lambda item: item.name)
        planned = {
            version_prefix + file.name: file.stat().st_size for file in files
        }
        if activate:
            planned[LATEST] = (folder / "distribution.json").stat().st_size
        check_capacity(client, bucket, planned)
        for file in files:
            key = version_prefix + file.name
            put_immutable(client, bucket, key, file)
            verifier(origin, key, file)
        if activate:
            data = (folder / "distribution.json").read_bytes()
            client.put_object(
                Bucket=bucket,
                Key=LATEST,
                Body=data,
                ContentType="application/json",
                CacheControl="no-store",
            )
            verifier(origin, LATEST, folder / "distribution.json")
    print(
        f"Verified mobile R2 release v{manifest['version']} "
        f"({'activated' if activate else 'uploaded only'})"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--activate", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    origin = download_origin(
        os.environ.get("CHEF25_DOWNLOAD_ORIGIN", "https://download.chef25.com")
    )
    manifest = validate(args.folder)
    if args.dry_run:
        print(f"Mobile distribution v{manifest['version']} is valid")
        return
    import boto3
    from botocore.config import Config

    account = os.environ["CLOUDFLARE_ACCOUNT_ID"]
    bucket = os.environ["CHEF25_R2_BUCKET"]
    if not re.fullmatch(r"[a-f0-9]{32}", account):
        raise ValueError("Invalid Cloudflare account ID")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]", bucket):
        raise ValueError("Invalid R2 bucket name")
    client = boto3.client(
        "s3",
        endpoint_url=f"https://{account}.r2.cloudflarestorage.com",
        region_name="auto",
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        config=Config(
            signature_version="s3v4",
            retries={"max_attempts": 5, "mode": "standard"},
            connect_timeout=30,
            read_timeout=180,
            request_checksum_calculation="when_required",
            response_checksum_validation="when_required",
        ),
    )
    publish(client, bucket, args.folder, origin, args.activate)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        message = str(error) if isinstance(error, ValueError) else type(error).__name__
        print("Mobile R2 publication failed: " + message, file=sys.stderr)
        sys.exit(1)
