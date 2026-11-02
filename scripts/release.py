"""Configure signing, build and package public Flutter releases."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)


def version():
    tag = os.environ["RELEASE_VERSION"]
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?", tag):
        raise ValueError("Expected vMAJOR.MINOR.PATCH[-prerelease]")
    return tag


def android_signing():
    import base64
    names = ["ANDROID_KEYSTORE_BASE64", "ANDROID_STORE_PASSWORD", "ANDROID_KEY_PASSWORD", "ANDROID_KEY_ALIAS"]
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise RuntimeError("Missing release signing secrets: " + ", ".join(missing))
    keystore = ROOT / "android/release.keystore"
    keystore.write_bytes(base64.b64decode(os.environ[names[0]], validate=True))
    def escape(value):
        return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")
    properties = {"storeFile": "release.keystore", "storePassword": os.environ[names[1]], "keyPassword": os.environ[names[2]], "keyAlias": os.environ[names[3]]}
    (ROOT / "android/key.properties").write_text("".join(f"{k}={escape(v)}\n" for k, v in properties.items()), encoding="utf-8")


def build(target):
    tag = version()
    args = ["flutter", "build", target, "--release", "--build-name=" + tag[1:], "--build-number=" + str(1000 + int(os.environ.get("GITHUB_RUN_NUMBER", "1"))), "--dart-define=AGENTTOWER_SERVER_URL=https://relay.example.com"]
    # Windows resolves Flutter through flutter.bat.
    args[0] = shutil.which("flutter") or "flutter"
    if target == "apk":
        android_signing()
    if target == "macos":
        run(args[0], "config", "--enable-macos-desktop", "--no-enable-macos-arm64-only")
    try:
        run(*args)
    finally:
        if target == "apk":
            for name in ("android/release.keystore", "android/key.properties"):
                (ROOT / name).unlink(missing_ok=True)


def package(target):
    tag = version()
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    label = {"apk": "android", "windows": "windows-amd64", "macos": "macos-universal"}[target]
    stage = ROOT / "build/release-package" / f"AgentTower-Client-{tag}-{label}"
    stage.mkdir(parents=True, exist_ok=True)
    for name in ("LICENSE", "THIRD_PARTY.md", "README.md", "README.en.md"):
        shutil.copy2(ROOT / name, stage / name)
    shutil.copytree(ROOT / "assets/brands", stage / "brand-notices", dirs_exist_ok=True)
    # Record the exact public source and package lock used for this build.
    shutil.copy2(ROOT / "pubspec.lock", stage / "pubspec.lock")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    (stage / "BUILD_INFO.json").write_text(json.dumps({"version": tag, "commit": commit, "target": label, "defaultServer": "https://relay.example.com", "androidApplicationId": "com.agenttower.agenttower.opensource", "macOSSigning": "ad-hoc; not notarized"}, indent=2) + "\n", encoding="utf-8")
    if target == "apk":
        shutil.copy2(ROOT / "build/app/outputs/flutter-apk/app-release.apk", output / f"AgentTower-Client-{tag}-android.apk")
        archive = output / f"AgentTower-Client-{tag}-android-notices.zip"
    elif target == "windows":
        source = ROOT / "build/windows/x64/runner/Release"
        if not (source / "agenttower.exe").is_file():
            raise RuntimeError("Windows release executable not found")
        shutil.copytree(source, stage, dirs_exist_ok=True)
        archive = output / f"AgentTower-Client-{tag}-{label}.zip"
    else:
        apps = list((ROOT / "build/macos/Build/Products/Release").glob("*.app"))
        if len(apps) != 1:
            raise RuntimeError("Expected exactly one macOS application")
        binary = apps[0] / "Contents/MacOS/AgentTower"
        run("lipo", "-verify_arch", "arm64", "x86_64", str(binary))
        run("codesign", "--verify", "--deep", "--strict", str(apps[0]))
        run("ditto", str(apps[0]), str(stage / apps[0].name))
        archive = output / f"AgentTower-Client-{tag}-{label}.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(stage), str(archive))
        return
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for path in sorted(stage.rglob("*")):
            if path.is_file():
                z.write(path, f"{stage.name}/{path.relative_to(stage).as_posix()}")


def checksums():
    paths = sorted((ROOT / "dist").glob("*"))
    assets = [p for p in paths if p.suffix in (".zip", ".apk")]
    if len(assets) != 4:
        raise RuntimeError(f"Expected APK and three ZIPs, found {len(assets)}")
    (ROOT / "dist/SHA256SUMS.txt").write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in assets), encoding="utf-8")


if __name__ == "__main__":
    {"build": build, "package": package, "checksums": lambda _: checksums()}[sys.argv[1]](sys.argv[2] if len(sys.argv) > 2 else "")
