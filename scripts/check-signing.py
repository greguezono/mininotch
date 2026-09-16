"""Run with python3 scripts/check-signing.py on the local signing Mac."""
import pathlib
import plistlib
import shutil
import subprocess
import tempfile


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True)


def build(root):
    result = run("bash", "scripts/build-app.sh", cwd=root)
    assert result.returncode == 0, result.stdout + result.stderr
    app = root / "build/MiniNotch.app"
    result = run("codesign", "-d", "-r-", str(app))
    assert result.returncode == 0, result.stderr
    requirement = result.stdout.strip().removeprefix("designated => ")
    assert "certificate leaf" in requirement and "cdhash" not in requirement, requirement
    return app, requirement


source = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="MiniNotch signing check ") as folder:
    root = pathlib.Path(folder)
    for name in ["Package.swift", "Sources", "Tests", "Resources", "scripts"]:
        item = source / name
        if item.is_dir():
            shutil.copytree(item, root / name)
        else:
            shutil.copy2(item, root / name)
    app, requirement = build(root)
    before = (app / "Contents/MacOS/MiniNotch").read_bytes()
    plist = root / "Resources/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    info["CFBundleVersion"] = "2"
    plist.write_bytes(plistlib.dumps(info))
    app, updated_requirement = build(root)
    assert before != (app / "Contents/MacOS/MiniNotch").read_bytes()
    assert requirement == updated_requirement
    checked = run("codesign", "--verify", "--strict", "-R", "=" + requirement, str(app))
    assert checked.returncode == 0, checked.stderr
    assert run("codesign", "--force", "--sign", "-", str(app)).returncode == 0
    assert run("codesign", "--verify", "-R", "=" + requirement, str(app)).returncode != 0
    script = root / "scripts/build-app.sh"
    original = script.read_text()
    script.write_text(original.replace("6D27E24D6528BC12546692D5D62CC4578BBAEC95", "0" * 40))
    unavailable = run("bash", "scripts/build-app.sh", cwd=root)
    assert unavailable.returncode != 0 and "no identity found" in unavailable.stderr, unavailable.stderr
    script.write_text(original)
    (root / "Resources/MinimalNotch.icns").unlink()
    missing = run("bash", "scripts/build-app.sh", cwd=root)
    assert missing.returncode != 0 and "Missing input" in missing.stderr
    shutil.copy2(source / "Resources/MinimalNotch.icns", root / "Resources/MinimalNotch.icns")
    shutil.rmtree(root / "build")
    outside = root / "outside"
    outside.mkdir()
    (root / "build").symlink_to(outside, target_is_directory=True)
    unsafe = run("bash", "scripts/build-app.sh", cwd=root)
    assert unsafe.returncode != 0 and "Unsafe output" in unsafe.stderr
    assert not list(outside.iterdir())
print("PASS: stable identity across changed builds; ad-hoc replacement and unsafe inputs rejected")
