import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "tools" / "rambu-puck-agent" / "Package.swift"
PLIST = ROOT / "tools" / "rambu-puck-agent" / "Resources" / "RambuPuckController-Info.plist"
SCRIPT = ROOT / "tools" / "package_rambu_puck_controller.sh"
CONTROLLER_SOURCES = ROOT / "tools" / "rambu-puck-agent" / "Sources" / "RambuPuckController"


def test_info_plist_declares_menu_bar_microphone_app() -> None:
    values = plistlib.loads(PLIST.read_bytes())

    assert values["CFBundleIdentifier"] == "id.rambu.puck.controller"
    assert values["CFBundleExecutable"] == "RambuPuckController"
    assert values["LSUIElement"] is True
    assert "mikrofon" in values["NSMicrophoneUsageDescription"].lower()


def test_package_and_script_build_the_declared_app_bundle() -> None:
    package = PACKAGE.read_text()
    script = SCRIPT.read_text()

    assert '.executable(name: "RambuPuckController"' in package
    assert 'name: "RambuPuckControllerApp"' in package
    assert "swift build -c release" in script
    assert '--product RambuPuckController' in script
    assert 'build/Rambu Puck.app/Contents/MacOS' in script
    assert "RambuPuckController-Info.plist" in script


def test_controller_production_files_do_not_embed_credentials() -> None:
    text = "\n".join(path.read_text() for path in CONTROLLER_SOURCES.glob("*.swift"))

    assert "RAMBU_PUCK_TOKEN=" not in text
    assert "Bearer eyJ" not in text
    assert "accessToken: \"" not in text
