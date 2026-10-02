#!/usr/bin/env python3
"""Smoke-check release guards and the build/package path with fake macOS tools."""

import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


source_root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="haken-release-smoke-") as temporary:
    root = Path(temporary) / "project"
    scripts = root / "Scripts"
    resources = root / "AppResources"
    fake_bin = Path(temporary) / "bin"
    mock_root = Path(temporary) / "mock"
    for directory in (scripts, resources, fake_bin, mock_root):
        directory.mkdir(parents=True, exist_ok=True)
    for name in ("build-direct-release.sh", "package-direct-release.sh"):
        shutil.copy2(source_root / "Scripts" / name, scripts / name)
    shutil.copy2(source_root / "AppResources/Info.plist", resources / "Info.plist")
    shutil.copy2(source_root / "AppResources/AppIcon.svg", resources / "AppIcon.svg")
    shutil.copytree(source_root / "AppResources/AppIcon.iconset", resources / "AppIcon.iconset")
    shutil.copytree(source_root / ".agents/skills/haken-control", root / ".agents/skills/haken-control")

    tools = {
        "swift": '''#!/usr/bin/env python3
import os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write("swift " + " ".join(args) + "\\n")
triple = args[args.index("--triple") + 1]
directory = pathlib.Path(os.environ["MOCK_ROOT"]) / triple
directory.mkdir(parents=True, exist_ok=True)
if "--show-bin-path" in args:
    print(directory)
else:
    product = args[args.index("--product") + 1]
    path = directory / ("Haken" if product == "Haken" else "haken-cli")
    path.write_text("mock executable")
    path.chmod(0o755)
''',
        "lipo": '''#!/usr/bin/env python3
import os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write("lipo " + " ".join(args) + "\\n")
if "-archs" in args:
    print("arm64 x86_64")
else:
    path = pathlib.Path(args[args.index("-output") + 1])
    path.write_text("mock universal executable")
    path.chmod(0o755)
''',
        "iconutil": '''#!/usr/bin/env python3
import pathlib, sys
pathlib.Path(sys.argv[sys.argv.index("-o") + 1]).write_bytes(b"mock icns")
''',
        "plutil": "#!/bin/sh\nexit 0\n",
        "codesign": '''#!/usr/bin/env python3
import os, sys
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write("codesign " + " ".join(sys.argv[1:]) + "\\n")
if "--display" in sys.argv:
    print("Authority=Developer ID Application: Smoke Test (ABCDE12345)", file=sys.stderr)
    sys.stderr.write("verbose certificate diagnostic\\n" * 30000)
''',
        "hdiutil": '''#!/usr/bin/env python3
import os, pathlib, shutil, sys
args = sys.argv[1:]
if args[0] == "create":
    source = pathlib.Path(args[args.index("-srcfolder") + 1])
    image = pathlib.Path(args[-1])
    image.touch()
    pathlib.Path(os.environ["MOCK_ROOT"], "volume-source").write_text(str(source))
elif args[0] == "attach":
    mount = pathlib.Path(args[args.index("-mountpoint") + 1])
    source = pathlib.Path(pathlib.Path(os.environ["MOCK_ROOT"], "volume-source").read_text())
    shutil.copytree(source, mount, dirs_exist_ok=True, symlinks=True)
elif args[0] == "detach":
    mount = pathlib.Path(args[1])
    for child in mount.iterdir():
        shutil.rmtree(child) if child.is_dir() and not child.is_symlink() else child.unlink()
''',
    }
    for name, contents in tools.items():
        path = fake_bin / name
        path.write_text(contents)
        path.chmod(0o755)

    base_env = os.environ | {
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "MOCK_ROOT": str(mock_root),
        "MOCK_LOG": str(mock_root / "calls.log"),
        "BUILD_NUMBER": "1",
        "MARKETING_VERSION": "1.2.3",
        "SIGNING_IDENTITY": "Developer ID Application: Smoke Test (ABCDE12345)",
    }
    script = scripts / "build-direct-release.sh"
    for key, value, expected in (
        ("BUILD_NUMBER", "0", "BUILD_NUMBER must be a positive integer"),
        ("MARKETING_VERSION", "v1.2.3", "MARKETING_VERSION must use numeric dot notation"),
        ("SIGNING_IDENTITY", "Apple Development: Smoke Test", "SIGNING_IDENTITY must be a Developer ID Application identity"),
    ):
        result = subprocess.run(["/bin/bash", str(script)], cwd=root, env=base_env | {key: value}, text=True, capture_output=True)
        assert result.returncode == 64, (key, result.returncode, result.stderr)
        assert expected in result.stderr, (key, result.stderr)
    assert not (root / "build").exists(), "invalid inputs must not create output"

    result = subprocess.run(["/bin/bash", str(script)], cwd=root, env=base_env, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr[-2000:]
    app = root / "build/release/Haken.app"
    image = root / "build/release/Haken-macos-universal.dmg"
    assert (app / "Contents/Helpers/haken").is_file()
    assert (app / "Contents/MacOS/Haken").is_file()
    assert (app / "Contents/Resources/AppIcon.icns").is_file()
    assert (app / "Contents/Resources/AppIcon.svg").is_file()
    assert (app / "Contents/Resources/AppIcon.iconset/Contents.json").is_file()
    assert (app / "Contents/Resources/Skills/haken-control/SKILL.md").is_file()
    assert (app / "Contents/Resources/Skills/haken-control/agents/openai.yaml").is_file()
    assert plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIconFile"] == "AppIcon"
    assert image.is_file()
    calls = (mock_root / "calls.log").read_text().splitlines()
    cli_sign = next(i for i, call in enumerate(calls) if "--identifier com.haken.app.haken" in call)
    app_sign = next(i for i, call in enumerate(calls) if "--identifier com.haken.app " in call)
    assert cli_sign < app_sign, "the nested CLI must be signed before the app"
    universal_builds = [call for call in calls if call.startswith("lipo -create")]
    assert len(universal_builds) == 2
    assert all("arm64-apple-macosx15.0" in call and "x86_64-apple-macosx15.0" in call for call in universal_builds)
    assert sum("--show-bin-path" in call for call in calls if call.startswith("swift ")) == 2
    assert sum("lipo -archs" in call for call in calls) == 2
    assert any("Contents/Helpers/haken" in call and "--verify" in call for call in calls)
    assert any("Contents/MacOS/Haken" in call and "--verify" in call for call in calls)

print("Direct release input and mocked build/package smoke checks passed.")
