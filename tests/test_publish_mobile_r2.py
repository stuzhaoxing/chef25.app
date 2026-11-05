import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "mobile_publisher",
    Path(__file__).resolve().parents[1] / "deploy/publish-mobile-r2.py",
)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class S3Error(Exception):
    def __init__(self, code):
        self.response = {"Error": {"Code": code}}


class MemoryS3:
    def __init__(self):
        self.objects = {}
        self.writes = []
        self.multipart = {}

    def list_multipart_uploads(self, **kwargs):
        return self.multipart

    def list_objects_v2(self, **kwargs):
        return {
            "Contents": [
                {"Key": key, "Size": len(data)}
                for key, data in self.objects.items()
            ],
            "IsTruncated": False,
        }

    def put_object(self, **kwargs):
        key = kwargs["Key"]
        if kwargs.get("IfNoneMatch") == "*" and key in self.objects:
            raise S3Error("PreconditionFailed")
        body = kwargs["Body"]
        self.objects[key] = body.read() if hasattr(body, "read") else body
        self.writes.append(kwargs)

    def get_object(self, **kwargs):
        key = kwargs["Key"]
        if key not in self.objects:
            raise S3Error("NoSuchKey")
        data = self.objects[key]
        return {"Body": io.BytesIO(data), "ContentLength": len(data)}

    def delete_object(self, **kwargs):
        del self.objects[kwargs["Key"]]


class MobilePublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.client = MemoryS3()
        self.origin = "https://download.chef25.com"
        self.verified = []
        self.write_fixture()

    def write_fixture(self, version="0.1.0", apk=b"signed apk"):
        files = {
            f"Chef25_{version}_android-arm64.apk": apk,
            f"Chef25_{version}_source.tar.gz": b"source archive",
            "THIRD_PARTY_NOTICES.md": b"notices",
        }
        for name, data in files.items():
            (self.folder / name).write_bytes(data)
        android = files[f"Chef25_{version}_android-arm64.apk"]
        source = files[f"Chef25_{version}_source.tar.gz"]
        manifest = {
            "version": version,
            "preview": True,
            "ios": {
                "distribution": "testflight",
                "url": "https://testflight.apple.com/join/AbCd1234",
            },
            "android": {
                "url": f"/downloads/mobile/v{version}/Chef25_{version}_android-arm64.apk",
                "sha256": hashlib.sha256(android).hexdigest(),
                "size": len(android),
                "signing": "apk-v2",
            },
            "source": {
                "url": f"/downloads/mobile/v{version}/Chef25_{version}_source.tar.gz",
                "sha256": hashlib.sha256(source).hexdigest(),
            },
        }
        (self.folder / "distribution.json").write_text(
            json.dumps(manifest, indent=2) + "\n"
        )
        sums = []
        for path in sorted(self.folder.iterdir()):
            if path.name == "SHA256SUMS":
                continue
            sums.append(
                f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}"
            )
        (self.folder / "SHA256SUMS").write_text("\n".join(sums) + "\n")
        self.manifest = manifest

    def verify(self, origin, key, file):
        self.assertEqual(origin, self.origin)
        self.assertEqual(self.client.objects[key], file.read_bytes())
        self.verified.append(key)

    def publish(self, activate=True, verifier=None):
        return publisher.publish(
            self.client,
            "test-bucket",
            self.folder,
            self.origin,
            activate=activate,
            verifier=verifier or self.verify,
        )

    def test_uploads_and_verifies_all_files_before_activation(self):
        self.publish()

        keys = [item["Key"] for item in self.client.writes]
        self.assertEqual(keys[-1], "downloads/mobile/latest.json")
        self.assertEqual(
            len(self.verified),
            len(list(self.folder.iterdir())) + 1,
        )
        self.assertNotIn(publisher.LOCK, self.client.objects)
        self.assertIn("no-store", self.client.writes[-1]["CacheControl"])
        immutable_writes = [
            item
            for item in self.client.writes
            if item["Key"].startswith("downloads/mobile/v0.1.0/")
        ]
        self.assertTrue(immutable_writes)
        self.assertTrue(
            all(
                item["CacheControl"] == publisher.IMMUTABLE
                for item in immutable_writes
            )
        )
        self.assertTrue(
            all(item["IfNoneMatch"] == "*" for item in immutable_writes)
        )

    def test_capacity_failure_leaves_live_manifest_unchanged(self):
        self.client.objects["downloads/mobile/latest.json"] = (
            b'{"version":"0.0.1"}'
        )
        with patch.object(publisher, "MAX_BUCKET_BYTES", 10):
            with self.assertRaisesRegex(ValueError, "budget"):
                self.publish()
        self.assertEqual(
            self.client.objects,
            {"downloads/mobile/latest.json": b'{"version":"0.0.1"}'},
        )

    def test_multipart_upload_blocks_publication(self):
        self.client.multipart = {"Uploads": [{}]}
        with self.assertRaisesRegex(ValueError, "multipart"):
            self.publish()
        self.assertEqual(self.client.objects, {})

    def test_same_version_changed_bytes_are_not_overwritten(self):
        self.publish()
        previous = self.client.objects["downloads/mobile/latest.json"]
        self.write_fixture(apk=b"different signed apk")
        with self.assertRaisesRegex(ValueError, "immutable"):
            self.publish()
        self.assertEqual(
            self.client.objects["downloads/mobile/latest.json"], previous
        )

    def test_failed_public_verification_does_not_activate(self):
        def fail(*args):
            raise ValueError("Public download checksum mismatch")

        with self.assertRaisesRegex(ValueError, "checksum"):
            self.publish(verifier=fail)
        self.assertNotIn("downloads/mobile/latest.json", self.client.objects)

    def test_downgrade_is_rejected_before_upload(self):
        self.client.objects["downloads/mobile/latest.json"] = (
            b'{"version":"9.0.0"}'
        )
        with self.assertRaisesRegex(ValueError, "downgrades"):
            self.publish()
        self.assertEqual(len(self.client.writes), 1)  # Lock creation only.

    def test_corrupt_local_artifact_fails_before_r2(self):
        apk = self.folder / "Chef25_0.1.0_android-arm64.apk"
        apk.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "SHA-256|size"):
            self.publish()
        self.assertEqual(self.client.writes, [])

    def test_upload_only_leaves_manifest_unchanged(self):
        self.publish(activate=False)
        self.assertNotIn("downloads/mobile/latest.json", self.client.objects)
        self.assertTrue(self.verified)
        self.assertTrue(all("/v0.1.0/" in key for key in self.verified))

    def test_manifest_rejects_non_public_testflight_link(self):
        manifest = dict(self.manifest)
        manifest["ios"] = {
            "distribution": "testflight",
            "url": "https://example.com/join/AbCd1234",
        }
        (self.folder / "distribution.json").write_text(
            json.dumps(manifest, indent=2) + "\n"
        )
        with self.assertRaisesRegex(ValueError, "TestFlight"):
            self.publish()


if __name__ == "__main__":
    unittest.main()
