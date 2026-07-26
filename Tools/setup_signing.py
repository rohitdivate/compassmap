#!/usr/bin/env python3
"""Point Tradewind at your own Apple Developer identifiers, in one command.

`com.tradewind.app` is a placeholder and is not yours, so a fresh clone will not sign. This rewrites
every identifier in the repository — entitlements, Info.plist, AppGroup.swift, project.yml and the
project generator — and regenerates `Tradewind.xcodeproj`, so the only thing left to do in Xcode is
press Run.

    # Paid Apple Developer Program membership: everything works.
    python3 Tools/setup_signing.py --prefix com.yourname --team ABCDE12345

    # Free Apple ID (a "Personal Team"): App Groups and iCloud are not available to it, so the
    # entitlements that request them are removed. See --free below for what that costs.
    python3 Tools/setup_signing.py --prefix com.yourname --team ABCDE12345 --free

Find your team ID at https://developer.apple.com/account under Membership details, or in Xcode:
Settings → Accounts → your Apple ID → Manage Certificates has it in the window title. If you have no
team ID at all, sign in to Xcode with your Apple ID once and it will create a Personal Team.

Re-running is safe, and `--reset` puts the placeholders back.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

PLACEHOLDER = "com.tradewind"

FREE_APP_ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<!-- A free Personal Team cannot use App Groups, iCloud or push, so this file is deliberately
\t     empty. The app runs; the widgets and Live Activity cannot read its data. -->
</dict>
</plist>
"""

FREE_WIDGET_ENTITLEMENTS = FREE_APP_ENTITLEMENTS

PAID_APP_ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>group.{prefix}.app</string>
\t</array>
\t<key>com.apple.developer.icloud-container-identifiers</key>
\t<array>
\t\t<string>iCloud.{prefix}.app</string>
\t</array>
\t<key>com.apple.developer.icloud-services</key>
\t<array>
\t\t<string>CloudKit</string>
\t</array>
\t<key>com.apple.developer.ubiquity-kvstore-identifier</key>
\t<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
\t<key>aps-environment</key>
\t<string>development</string>
</dict>
</plist>
"""

PAID_WIDGET_ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>group.{prefix}.app</string>
\t</array>
</dict>
</plist>
"""


def current_prefix() -> str:
    """Whatever prefix the repository is currently set to, so re-running is idempotent."""
    text = (ROOT / "Tools" / "gen_xcodeproj.py").read_text(encoding="utf-8")
    match = re.search(r'^APP_BUNDLE_ID = "(.+)\.app"$', text, re.MULTILINE)
    if match is None:
        sys.exit("could not read APP_BUNDLE_ID out of Tools/gen_xcodeproj.py")
    return match.group(1)


def configured_team() -> str:
    """The team ID currently baked into the generator, if any."""
    text = (ROOT / "Tools" / "gen_xcodeproj.py").read_text(encoding="utf-8")
    match = re.search(r'^DEVELOPMENT_TEAM = "(.*)"$', text, re.MULTILINE)
    return match.group(1) if match else ""


def team_in_project() -> str:
    """The team ID Xcode wrote into the project, if someone picked one in Signing & Capabilities.

    Regenerating the project rewrites `project.pbxproj` wholesale, so a team chosen in Xcode's UI
    would silently vanish. Reading it back means running this script never undoes that choice.
    """
    path = ROOT / "Tradewind.xcodeproj" / "project.pbxproj"
    if not path.exists():
        return ""
    found = set(re.findall(r"DEVELOPMENT_TEAM = ([A-Z0-9]{10});", path.read_text(encoding="utf-8")))
    return found.pop() if len(found) == 1 else ""


PLACEHOLDER_PREFIXES = {"com.yourname", "com.example", "com.yourcompany", "com.mycompany", "com.test"}


def validate_prefix(prefix: str) -> None:
    """Catch the two mistakes that produce a confusing Xcode error rather than a clear one."""
    if prefix.lower() in PLACEHOLDER_PREFIXES:
        sys.exit(
            f"--prefix {prefix} is the placeholder from the documentation, not an identifier.\n"
            "Use something of your own, e.g. --prefix com.rohitdivate. It does not have to be a\n"
            "domain you own — only one nobody else has already registered with Apple."
        )
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+", prefix):
        sys.exit(
            f"--prefix {prefix} is not a reverse-DNS identifier. Apple requires at least one dot and\n"
            "only letters, digits and hyphens — 'tradewind' will not provision, 'com.rohitdivate' will."
        )


def swap(path: pathlib.Path, old: str, new: str, *, expected: int) -> None:
    text = path.read_text(encoding="utf-8")
    found = text.count(old)
    if found != expected:
        sys.exit(f"{path.relative_to(ROOT)}: expected {expected} occurrences of {old!r}, found {found}")
    path.write_text(text.replace(old, new), encoding="utf-8")
    print(f"  {path.relative_to(ROOT)}  ({found})")


def set_team(team: str) -> None:
    path = ROOT / "Tools" / "gen_xcodeproj.py"
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'^DEVELOPMENT_TEAM = ".*"$', f'DEVELOPMENT_TEAM = "{team}"', text, flags=re.MULTILINE
    )
    if count != 1:
        sys.exit("could not find DEVELOPMENT_TEAM in Tools/gen_xcodeproj.py")
    path.write_text(updated, encoding="utf-8")
    print(f"  Tools/gen_xcodeproj.py  DEVELOPMENT_TEAM = {team or '(none)'}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rewrite Tradewind's bundle identifiers and signing team.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--prefix",
        help="a reverse-DNS prefix of your own — com.<yourname> is fine, and it does not have to be "
        "a domain you own. The app becomes <prefix>.app. Must contain a dot, and the documentation's "
        "own examples are rejected so they cannot be pasted in by accident.",
    )
    parser.add_argument("--team", default=None, help="10-character Apple Developer team ID")
    parser.add_argument(
        "--free",
        action="store_true",
        help="strip the App Group, iCloud and push entitlements, which a free Personal Team cannot "
        "provision. The app runs on your device; widgets and the Live Activity will show no data, "
        "because an App Group is the only way an extension can read the app's spots.",
    )
    parser.add_argument(
        "--paid",
        action="store_true",
        help="restore the App Group and iCloud entitlements after a --free run",
    )
    parser.add_argument("--reset", action="store_true", help="put the com.tradewind placeholders back")
    args = parser.parse_args()

    if args.reset:
        args.prefix, args.team, args.paid = PLACEHOLDER, "", True

    if not any([args.prefix, args.team is not None, args.free, args.paid]):
        parser.error("nothing to do — pass --prefix, --team, --free, --paid or --reset")

    old = current_prefix()
    new = args.prefix or old
    if args.prefix:
        validate_prefix(args.prefix)

    # Xcode writes the team you pick in Signing & Capabilities straight into project.pbxproj, and
    # regenerating the project would throw it away. Adopt it instead, so this script never costs you
    # a choice you already made in the UI.
    if args.team is None and not configured_team():
        adopted = team_in_project()
        if adopted:
            print(f"adopting the team already set in Xcode: {adopted}")
            args.team = adopted

    if new != old:
        print(f"identifiers: {old}.app -> {new}.app")
        swap(ROOT / "Tools" / "gen_xcodeproj.py", f'"{old}.app', f'"{new}.app', expected=3)
        swap(ROOT / "Shared" / "Snapshot" / "AppGroup.swift", f"{old}.app", f"{new}.app", expected=2)
        swap(ROOT / "Tradewind" / "Info.plist", f"{old}.app.spot", f"{new}.app.spot", expected=1)
        swap(ROOT / "project.yml", old, new, expected=4)

    if args.free or args.paid:
        app = ROOT / "Tradewind" / "Tradewind.entitlements"
        widget = ROOT / "TradewindWidgets" / "TradewindWidgets.entitlements"
        if args.free:
            print("entitlements: App Group, iCloud and push removed (free Personal Team)")
            app.write_text(FREE_APP_ENTITLEMENTS, encoding="utf-8")
            widget.write_text(FREE_WIDGET_ENTITLEMENTS, encoding="utf-8")
        else:
            print("entitlements: App Group and iCloud restored")
            app.write_text(PAID_APP_ENTITLEMENTS.format(prefix=new), encoding="utf-8")
            widget.write_text(PAID_WIDGET_ENTITLEMENTS.format(prefix=new), encoding="utf-8")
    elif new != old:
        # Identifiers moved but the capability set did not, so only the strings need rewriting.
        for path, count in (
            (ROOT / "Tradewind" / "Tradewind.entitlements", 2),
            (ROOT / "TradewindWidgets" / "TradewindWidgets.entitlements", 1),
        ):
            if PLACEHOLDER in path.read_text(encoding="utf-8") or old in path.read_text(encoding="utf-8"):
                swap(path, f"{old}.app", f"{new}.app", expected=count)

    if args.team is not None:
        set_team(args.team)

    print("regenerating Tradewind.xcodeproj")
    subprocess.run([sys.executable, str(ROOT / "Tools" / "gen_xcodeproj.py")], check=True)

    print()
    print("Done. Open Tradewind.xcodeproj, pick your iPhone, and press Run.")
    if args.free:
        print(
            "Signed with a free Apple ID: the app expires after 7 days and needs re-running, and\n"
            "the widgets will be empty. Settings will say \"widgets unavailable\", which is true."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
