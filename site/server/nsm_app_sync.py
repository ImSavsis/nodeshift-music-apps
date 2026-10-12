import hashlib
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request

REPO = "ImSavsis/nodeshift-music-apps"
ROOT = "/var/www/nsm-app/app"
PLATFORMS = {
    "ios": "NodeShiftMusic.ipa",
    "android": "NodeShiftMusic.apk",
    "win": "NodeShiftMusic-Setup.exe",
}
USER_AGENT = "nsm-app-sync/1"


def release_url(platform, name):
    return "https://github.com/%s/releases/download/%s-latest/%s" % (REPO, platform, name)


def request(url):
    return urllib.request.Request(url, headers={"User-Agent": USER_AGENT})


def fetch_json(url):
    try:
        with urllib.request.urlopen(request(url), timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def read_local(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def atomic_write(path, data):
    directory = os.path.dirname(path)
    handle, temp = tempfile.mkstemp(dir=directory, prefix=".tmp-")
    try:
        with os.fdopen(handle, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(temp, 0o644)
        os.replace(temp, path)
    except BaseException:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def download(url, expected_sha, expected_size, target):
    directory = os.path.dirname(target)
    handle, temp = tempfile.mkstemp(dir=directory, prefix=".dl-")
    digest = hashlib.sha256()
    size = 0
    try:
        with os.fdopen(handle, "wb") as out, urllib.request.urlopen(request(url), timeout=120) as response:
            while True:
                chunk = response.read(1 << 20)
                if not chunk:
                    break
                digest.update(chunk)
                size += len(chunk)
                out.write(chunk)
            out.flush()
            os.fsync(out.fileno())
        if size != expected_size or digest.hexdigest() != expected_sha:
            raise ValueError("checksum mismatch: size %d/%d sha %s" % (size, expected_size, digest.hexdigest()))
        os.chmod(temp, 0o644)
        os.replace(temp, target)
    except BaseException:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def sync(platform, canonical):
    manifest = fetch_json(release_url(platform, "update.json"))
    manifest_path = os.path.join(ROOT, "update", platform + ".json")
    if manifest is None:
        if not os.path.exists(manifest_path):
            os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
            placeholder = {"platform": platform, "available": False}
            atomic_write(manifest_path, (json.dumps(placeholder, indent=2) + chr(10)).encode("utf-8"))
        print("%s: no release yet" % platform)
        return
    for key in ("file", "size", "sha256", "version"):
        if key not in manifest:
            raise ValueError("%s: manifest missing %s" % (platform, key))
    binary_path = os.path.join(ROOT, "bin", platform, canonical)
    current = read_local(manifest_path)
    if (
        current
        and current.get("available") is not False
        and current.get("sha256") == manifest["sha256"]
        and current.get("build") == manifest.get("build")
        and os.path.exists(binary_path)
    ):
        print("%s: up to date (%s build %s)" % (platform, manifest["version"], manifest.get("build")))
        return
    os.makedirs(os.path.dirname(binary_path), exist_ok=True)
    os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
    download(release_url(platform, manifest["file"]), manifest["sha256"], int(manifest["size"]), binary_path)
    published = dict(manifest)
    published["file"] = canonical
    published["url"] = "/app/files/%s/download" % platform
    published["page"] = "/app/files/%s" % platform
    atomic_write(manifest_path, (json.dumps(published, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    print("%s: published %s build %s (%d bytes)" % (platform, manifest["version"], manifest.get("build"), manifest["size"]))


def main():
    failed = False
    for platform, canonical in PLATFORMS.items():
        try:
            sync(platform, canonical)
        except Exception as error:
            failed = True
            print("%s: error: %s" % (platform, error), file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
