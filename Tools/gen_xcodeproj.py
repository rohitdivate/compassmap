#!/usr/bin/env python3
"""Generate Tradewind.xcodeproj from the source tree.

The Xcode project is a build artifact here, not something anyone hand-edits. This
script walks the source directories, assigns deterministic object IDs, and writes a
plain (objectVersion 56) project.pbxproj plus a shared scheme.

Run it after adding or removing source files:

    python3 Tools/gen_xcodeproj.py

`project.yml` describes the same layout for XcodeGen, which is the fallback if this
generated project ever misbehaves.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import sys
from dataclasses import dataclass, field

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "Tradewind"
PROJECT_DIR = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj")

APP_BUNDLE_ID = "com.tradewind.app"
WIDGET_BUNDLE_ID = "com.tradewind.app.widgets"
TESTS_BUNDLE_ID = "com.tradewind.app.tests"
UITESTS_BUNDLE_ID = "com.tradewind.app.uitests"
# Empty means "whatever Xcode picks", which is right for CI and for a simulator build. Set it with
# `python3 Tools/setup_signing.py --team ABCDE12345` so a device build does not need a UI visit.
DEVELOPMENT_TEAM = ""
DEPLOYMENT_TARGET = "26.0"
MARKETING_VERSION = "1.0"
BUILD_VERSION = "1"


# --------------------------------------------------------------------------------------
# object identifiers
# --------------------------------------------------------------------------------------

_used_ids: dict[str, str] = {}


def oid(*parts: str) -> str:
    """Deterministic 24-hex-char identifier for a logical object."""
    key = "\x00".join(parts)
    if key in _used_ids:
        return _used_ids[key]
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest().upper()[:24]
    while digest in _used_ids.values():  # astronomically unlikely, but cheap to rule out
        digest = hashlib.sha1((digest + key).encode("utf-8")).hexdigest().upper()[:24]
    _used_ids[key] = digest
    return digest


# --------------------------------------------------------------------------------------
# file discovery
# --------------------------------------------------------------------------------------

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".h": "sourcecode.c.h",
    ".m": "sourcecode.c.objc",
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.entitlements",
    ".xcassets": "folder.assetcatalog",
    ".json": "text.json",
    ".md": "net.daringfireball.markdown",
    ".png": "image.png",
    ".strings": "text.plist.strings",
    ".xcconfig": "text.xcconfig",
}


def swift_sources(*dirs: str) -> list[str]:
    """Every .swift file under the given repo-relative directories, sorted."""
    found: list[str] = []
    for d in dirs:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(n for n in dirnames if not n.startswith(".") and not n.endswith(".xcassets"))
            for name in sorted(filenames):
                if name.endswith(".swift"):
                    rel = os.path.relpath(os.path.join(dirpath, name), ROOT)
                    found.append(rel)
    return sorted(found)


@dataclass
class Target:
    name: str
    product_type: str
    product_name: str
    product_ext: str
    bundle_id: str
    sources: list[str]
    resources: list[str] = field(default_factory=list)
    info_plist: str | None = None
    entitlements: str | None = None
    extra_settings: dict[str, str] = field(default_factory=dict)
    dependencies: list[str] = field(default_factory=list)
    embeds: list[str] = field(default_factory=list)

    @property
    def product_filename(self) -> str:
        return f"{self.product_name}.{self.product_ext}"


def build_targets() -> list[Target]:
    shared = swift_sources("Shared")
    app_only = swift_sources("Tradewind")
    widget_only = swift_sources("TradewindWidgets")
    tests_only = swift_sources("TradewindTests")

    assets = "Tradewind/Resources/Assets.xcassets"
    resources = [assets] if os.path.isdir(os.path.join(ROOT, assets)) else []

    # Fonts are added as individual files rather than a folder reference so they land at the
    # bundle root, which is where `UIAppFonts` looks for them by bare filename. The OFL licence
    # texts ship alongside, since the licence requires them to travel with the fonts.
    fonts_dir = os.path.join(ROOT, "Tradewind", "Resources", "Fonts")
    if os.path.isdir(fonts_dir):
        for name in sorted(os.listdir(fonts_dir)):
            if name.endswith((".ttf", ".otf", ".txt")):
                resources.append(f"Tradewind/Resources/Fonts/{name}")

    common = {
        "SWIFT_VERSION": "5.0",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "TARGETED_DEVICE_FAMILY": "1",
        "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        "SUPPORTS_MACCATALYST": "NO",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": BUILD_VERSION,
        "MARKETING_VERSION": MARKETING_VERSION,
        "GENERATE_INFOPLIST_FILE": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    }
    if DEVELOPMENT_TEAM:
        common["DEVELOPMENT_TEAM"] = DEVELOPMENT_TEAM

    app = Target(
        name="Tradewind",
        product_type="com.apple.product-type.application",
        product_name="Tradewind",
        product_ext="app",
        bundle_id=APP_BUNDLE_ID,
        sources=app_only + shared,
        resources=resources,
        info_plist="Tradewind/Info.plist",
        entitlements="Tradewind/Tradewind.entitlements",
        extra_settings={
            **common,
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "ENABLE_PREVIEWS": "YES",
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        },
        dependencies=["TradewindWidgets"],
        embeds=["TradewindWidgets"],
    )

    widgets = Target(
        name="TradewindWidgets",
        product_type="com.apple.product-type.app-extension",
        product_name="TradewindWidgets",
        product_ext="appex",
        bundle_id=WIDGET_BUNDLE_ID,
        sources=widget_only + shared,
        resources=resources,
        info_plist="TradewindWidgets/Info.plist",
        entitlements="TradewindWidgets/TradewindWidgets.entitlements",
        extra_settings={
            **common,
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME": "WidgetBackground",
            "SKIP_INSTALL": "YES",
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
        },
    )

    # The test bundle compiles the pure layers directly rather than linking the app, so
    # `xcodebuild test` needs no host application and no BUNDLE_LOADER wiring. Only
    # Foundation-only directories are eligible — anything touching SwiftUI, SwiftData or
    # CoreLocation stays out so the test bundle cannot be broken by UI code.
    pure_directories = ("Shared/Math/", "Shared/Snapshot/", "Shared/Metadata/")
    testable_shared = [p for p in shared if p.startswith(pure_directories)]
    tests = Target(
        name="TradewindTests",
        product_type="com.apple.product-type.bundle.unit-test",
        product_name="TradewindTests",
        product_ext="xctest",
        bundle_id=TESTS_BUNDLE_ID,
        sources=tests_only + testable_shared,
        info_plist=None,
        entitlements=None,
        extra_settings={
            **common,
            "GENERATE_INFOPLIST_FILE": "YES",
            "CODE_SIGNING_ALLOWED": "NO",
        },
    )

    # UI tests launch the real app in a simulator, which is the one thing the unit bundle above
    # cannot do — it has no host application on purpose. Two bugs reached a device because nothing
    # ever launched this app: a crash in init() and a Settings screen that could not be opened.
    #
    # TEST_TARGET_NAME is what makes this a *UI* test target rather than a unit one: it tells Xcode
    # which application to install and drive. Without it the bundle builds and tests nothing.
    ui_tests = Target(
        name="TradewindUITests",
        product_type="com.apple.product-type.bundle.ui-testing",
        product_name="TradewindUITests",
        product_ext="xctest",
        bundle_id=UITESTS_BUNDLE_ID,
        sources=swift_sources("TradewindUITests"),
        info_plist=None,
        entitlements=None,
        extra_settings={
            **common,
            "GENERATE_INFOPLIST_FILE": "YES",
            "TEST_TARGET_NAME": "Tradewind",
            "CODE_SIGNING_ALLOWED": "NO",
        },
        dependencies=["Tradewind"],
    )

    return [app, widgets, tests, ui_tests]


# --------------------------------------------------------------------------------------
# pbxproj emission
# --------------------------------------------------------------------------------------


class Writer:
    def __init__(self) -> None:
        self.lines: list[str] = []

    def w(self, indent: int, text: str) -> None:
        self.lines.append("\t" * indent + text)

    def text(self) -> str:
        return "\n".join(self.lines) + "\n"


def file_type_for(path: str) -> str:
    _, ext = os.path.splitext(path)
    return FILE_TYPES.get(ext, "text")


def collect_file_refs(targets: list[Target]) -> list[str]:
    paths: set[str] = set()
    for t in targets:
        paths.update(t.sources)
        paths.update(t.resources)
        if t.info_plist:
            paths.add(t.info_plist)
        if t.entitlements:
            paths.add(t.entitlements)
    return sorted(paths)


@dataclass
class GroupNode:
    name: str
    children: dict[str, "GroupNode"] = field(default_factory=dict)
    # Full repo-relative paths, not basenames: file reference IDs are derived from the full
    # path, so a group holding basenames would emit child IDs that match nothing and Xcode
    # would look for every source at the repository root.
    files: list[str] = field(default_factory=list)

    def insert(self, rel_path: str, full_path: str | None = None) -> None:
        full = full_path if full_path is not None else rel_path
        parts = rel_path.split("/")
        if len(parts) == 1:
            self.files.append(full)
            return
        head, rest = parts[0], "/".join(parts[1:])
        child = self.children.get(head)
        if child is None:
            child = GroupNode(head)
            self.children[head] = child
        child.insert(rest, full)


def group_tree(paths: list[str]) -> GroupNode:
    root = GroupNode("<root>")
    for p in paths:
        root.insert(p)
    return root


def group_oid(prefix: str, node_path: str) -> str:
    return oid("group", prefix, node_path)


def emit_groups(w: Writer, root: GroupNode, products: list[Target]) -> tuple[str, str]:
    """Write every PBXGroup. Returns (main_group_id, products_group_id)."""
    main_id = oid("group", "main")
    products_id = oid("group", "Products")

    def walk(node: GroupNode, node_path: str) -> list[tuple[str, str]]:
        """Emit descendants depth-first; returns (child_id, comment) for this node."""
        entries: list[tuple[str, str]] = []
        for key in sorted(node.children):
            child = node.children[key]
            child_path = f"{node_path}/{key}" if node_path else key
            grandchildren = walk(child, child_path)
            gid = group_oid("dir", child_path)
            w.w(2, f"{gid} /* {key} */ = {{")
            w.w(3, "isa = PBXGroup;")
            w.w(3, "children = (")
            for cid, comment in grandchildren:
                w.w(4, f"{cid} /* {comment} */,")
            w.w(3, ");")
            w.w(3, f"path = {quoted(key)};")
            w.w(3, "sourceTree = \"<group>\";")
            w.w(2, "};")
            entries.append((gid, key))
        for f in sorted(node.files):
            entries.append((oid("fileref", f), os.path.basename(f)))
        return entries

    w.w(1, "/* Begin PBXGroup section */")
    top_entries = walk(root, "")

    w.w(2, f"{products_id} /* Products */ = {{")
    w.w(3, "isa = PBXGroup;")
    w.w(3, "children = (")
    for t in products:
        w.w(4, f"{oid('product', t.name)} /* {t.product_filename} */,")
    w.w(3, ");")
    w.w(3, "name = Products;")
    w.w(3, "sourceTree = \"<group>\";")
    w.w(2, "};")

    w.w(2, f"{main_id} = {{")
    w.w(3, "isa = PBXGroup;")
    w.w(3, "children = (")
    for cid, comment in top_entries:
        w.w(4, f"{cid} /* {comment} */,")
    w.w(4, f"{products_id} /* Products */,")
    w.w(3, ");")
    w.w(3, "sourceTree = \"<group>\";")
    w.w(2, "};")
    w.w(1, "/* End PBXGroup section */")
    return main_id, products_id


def quoted(value: str) -> str:
    if value and all(c.isalnum() or c in "._/$" for c in value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


PROJECT_DEBUG = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_TESTABILITY": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": '"DEBUG=1 $(inherited)"',
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "MTL_FAST_MATH": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
}

PROJECT_RELEASE = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
}


def emit_settings(w: Writer, indent: int, settings: dict[str, str]) -> None:
    w.w(indent, "buildSettings = {")
    for key in sorted(settings):
        w.w(indent + 1, f"{key} = {settings[key]};")
    w.w(indent, "};")


def target_settings(t: Target, configuration: str) -> dict[str, str]:
    s = dict(t.extra_settings)
    s["PRODUCT_BUNDLE_IDENTIFIER"] = t.bundle_id
    s["PRODUCT_NAME"] = "\"$(TARGET_NAME)\""
    if t.info_plist:
        s["INFOPLIST_FILE"] = t.info_plist
    if t.entitlements:
        s["CODE_SIGN_ENTITLEMENTS"] = t.entitlements
    if configuration == "Debug":
        s.setdefault("SWIFT_OPTIMIZATION_LEVEL", "-Onone")
    return s


def generate() -> str:
    targets = build_targets()
    app = targets[0]
    by_name = {t.name: t for t in targets}
    all_paths = collect_file_refs(targets)
    tree = group_tree(all_paths)

    w = Writer()
    w.w(0, "// !$*UTF8*$!")
    w.w(0, "{")
    w.w(1, "archiveVersion = 1;")
    w.w(1, "classes = {")
    w.w(1, "};")
    w.w(1, "objectVersion = 56;")
    w.w(1, "objects = {")
    w.w(0, "")

    # ---- PBXBuildFile -----------------------------------------------------------------
    w.w(1, "/* Begin PBXBuildFile section */")
    for t in targets:
        for path in sorted(set(t.sources)):
            bid = oid("buildfile", t.name, path)
            w.w(
                2,
                f"{bid} /* {os.path.basename(path)} in Sources */ = {{isa = PBXBuildFile; "
                f"fileRef = {oid('fileref', path)} /* {os.path.basename(path)} */; }};",
            )
        for path in sorted(set(t.resources)):
            bid = oid("buildfile", t.name, path)
            w.w(
                2,
                f"{bid} /* {os.path.basename(path)} in Resources */ = {{isa = PBXBuildFile; "
                f"fileRef = {oid('fileref', path)} /* {os.path.basename(path)} */; }};",
            )
        for embedded in t.embeds:
            dep = by_name[embedded]
            bid = oid("embedfile", t.name, embedded)
            w.w(
                2,
                f"{bid} /* {dep.product_filename} in Embed Foundation Extensions */ = "
                f"{{isa = PBXBuildFile; fileRef = {oid('product', embedded)} /* {dep.product_filename} */; "
                "settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };",
            )
    w.w(1, "/* End PBXBuildFile section */")
    w.w(0, "")

    # ---- PBXContainerItemProxy --------------------------------------------------------
    proxies = [(t, dep) for t in targets for dep in t.dependencies]
    if proxies:
        w.w(1, "/* Begin PBXContainerItemProxy section */")
        for t, dep in proxies:
            w.w(2, f"{oid('proxy', t.name, dep)} /* PBXContainerItemProxy */ = {{")
            w.w(3, "isa = PBXContainerItemProxy;")
            w.w(3, f"containerPortal = {oid('project')} /* Project object */;")
            w.w(3, "proxyType = 1;")
            w.w(3, f"remoteGlobalIDString = {oid('target', dep)};")
            w.w(3, f"remoteInfo = {dep};")
            w.w(2, "};")
        w.w(1, "/* End PBXContainerItemProxy section */")
        w.w(0, "")

    # ---- PBXCopyFilesBuildPhase ------------------------------------------------------
    embedders = [t for t in targets if t.embeds]
    if embedders:
        w.w(1, "/* Begin PBXCopyFilesBuildPhase section */")
        for t in embedders:
            w.w(2, f"{oid('embedphase', t.name)} /* Embed Foundation Extensions */ = {{")
            w.w(3, "isa = PBXCopyFilesBuildPhase;")
            w.w(3, "buildActionMask = 2147483647;")
            w.w(3, "dstPath = \"\";")
            w.w(3, "dstSubfolderSpec = 13;")
            w.w(3, "files = (")
            for embedded in t.embeds:
                dep = by_name[embedded]
                w.w(4, f"{oid('embedfile', t.name, embedded)} /* {dep.product_filename} in Embed Foundation Extensions */,")
            w.w(3, ");")
            w.w(3, "name = \"Embed Foundation Extensions\";")
            w.w(3, "runOnlyForDeploymentPostprocessing = 0;")
            w.w(2, "};")
        w.w(1, "/* End PBXCopyFilesBuildPhase section */")
        w.w(0, "")

    # ---- PBXFileReference ------------------------------------------------------------
    w.w(1, "/* Begin PBXFileReference section */")
    for path in all_paths:
        name = os.path.basename(path)
        w.w(
            2,
            f"{oid('fileref', path)} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type_for(path)}; path = {quoted(name)}; sourceTree = \"<group>\"; }};",
        )
    for t in targets:
        explicit = {
            "app": "wrapper.application",
            "appex": "wrapper.app-extension",
            "xctest": "wrapper.cfbundle",
        }[t.product_ext]
        w.w(
            2,
            f"{oid('product', t.name)} /* {t.product_filename} */ = {{isa = PBXFileReference; "
            f"explicitFileType = {explicit}; includeInIndex = 0; path = {quoted(t.product_filename)}; "
            "sourceTree = BUILT_PRODUCTS_DIR; };",
        )
    w.w(1, "/* End PBXFileReference section */")
    w.w(0, "")

    # ---- PBXFrameworksBuildPhase -----------------------------------------------------
    w.w(1, "/* Begin PBXFrameworksBuildPhase section */")
    for t in targets:
        w.w(2, f"{oid('frameworks', t.name)} /* Frameworks */ = {{")
        w.w(3, "isa = PBXFrameworksBuildPhase;")
        w.w(3, "buildActionMask = 2147483647;")
        w.w(3, "files = (")
        w.w(3, ");")
        w.w(3, "runOnlyForDeploymentPostprocessing = 0;")
        w.w(2, "};")
    w.w(1, "/* End PBXFrameworksBuildPhase section */")
    w.w(0, "")

    # ---- PBXGroup --------------------------------------------------------------------
    main_id, products_id = emit_groups(w, tree, targets)
    w.w(0, "")

    # ---- PBXNativeTarget -------------------------------------------------------------
    w.w(1, "/* Begin PBXNativeTarget section */")
    for t in targets:
        w.w(2, f"{oid('target', t.name)} /* {t.name} */ = {{")
        w.w(3, "isa = PBXNativeTarget;")
        w.w(3, f"buildConfigurationList = {oid('configlist', t.name)} /* Build configuration list for PBXNativeTarget \"{t.name}\" */;")
        w.w(3, "buildPhases = (")
        w.w(4, f"{oid('sources', t.name)} /* Sources */,")
        w.w(4, f"{oid('frameworks', t.name)} /* Frameworks */,")
        w.w(4, f"{oid('resources', t.name)} /* Resources */,")
        if t.embeds:
            w.w(4, f"{oid('embedphase', t.name)} /* Embed Foundation Extensions */,")
        w.w(3, ");")
        w.w(3, "buildRules = (")
        w.w(3, ");")
        w.w(3, "dependencies = (")
        for dep in t.dependencies:
            w.w(4, f"{oid('dependency', t.name, dep)} /* PBXTargetDependency */,")
        w.w(3, ");")
        w.w(3, f"name = {t.name};")
        w.w(3, f"productName = {t.name};")
        w.w(3, f"productReference = {oid('product', t.name)} /* {t.product_filename} */;")
        w.w(3, f"productType = \"{t.product_type}\";")
        w.w(2, "};")
    w.w(1, "/* End PBXNativeTarget section */")
    w.w(0, "")

    # ---- PBXProject ------------------------------------------------------------------
    w.w(1, "/* Begin PBXProject section */")
    w.w(2, f"{oid('project')} /* Project object */ = {{")
    w.w(3, "isa = PBXProject;")
    w.w(3, "attributes = {")
    w.w(4, "BuildIndependentTargetsInParallel = 1;")
    w.w(4, "LastSwiftUpdateCheck = 1600;")
    w.w(4, "LastUpgradeCheck = 1600;")
    w.w(4, "TargetAttributes = {")
    for t in targets:
        w.w(5, f"{oid('target', t.name)} = {{")
        w.w(6, "CreatedOnToolsVersion = 16.0;")
        w.w(5, "};")
    w.w(4, "};")
    w.w(3, "};")
    w.w(3, f"buildConfigurationList = {oid('configlist', '__project__')} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;")
    w.w(3, "compatibilityVersion = \"Xcode 15.0\";")
    w.w(3, "developmentRegion = en;")
    w.w(3, "hasScannedForEncodings = 0;")
    w.w(3, "knownRegions = (")
    w.w(4, "en,")
    w.w(4, "Base,")
    w.w(3, ");")
    w.w(3, f"mainGroup = {main_id};")
    w.w(3, "minimizedProjectReferenceProxies = 1;")
    w.w(3, f"productRefGroup = {products_id} /* Products */;")
    w.w(3, "projectDirPath = \"\";")
    w.w(3, "projectRoot = \"\";")
    w.w(3, "targets = (")
    for t in targets:
        w.w(4, f"{oid('target', t.name)} /* {t.name} */,")
    w.w(3, ");")
    w.w(2, "};")
    w.w(1, "/* End PBXProject section */")
    w.w(0, "")

    # ---- PBXResourcesBuildPhase ------------------------------------------------------
    w.w(1, "/* Begin PBXResourcesBuildPhase section */")
    for t in targets:
        w.w(2, f"{oid('resources', t.name)} /* Resources */ = {{")
        w.w(3, "isa = PBXResourcesBuildPhase;")
        w.w(3, "buildActionMask = 2147483647;")
        w.w(3, "files = (")
        for path in sorted(set(t.resources)):
            w.w(4, f"{oid('buildfile', t.name, path)} /* {os.path.basename(path)} in Resources */,")
        w.w(3, ");")
        w.w(3, "runOnlyForDeploymentPostprocessing = 0;")
        w.w(2, "};")
    w.w(1, "/* End PBXResourcesBuildPhase section */")
    w.w(0, "")

    # ---- PBXSourcesBuildPhase --------------------------------------------------------
    w.w(1, "/* Begin PBXSourcesBuildPhase section */")
    for t in targets:
        w.w(2, f"{oid('sources', t.name)} /* Sources */ = {{")
        w.w(3, "isa = PBXSourcesBuildPhase;")
        w.w(3, "buildActionMask = 2147483647;")
        w.w(3, "files = (")
        for path in sorted(set(t.sources)):
            w.w(4, f"{oid('buildfile', t.name, path)} /* {os.path.basename(path)} in Sources */,")
        w.w(3, ");")
        w.w(3, "runOnlyForDeploymentPostprocessing = 0;")
        w.w(2, "};")
    w.w(1, "/* End PBXSourcesBuildPhase section */")
    w.w(0, "")

    # ---- PBXTargetDependency ---------------------------------------------------------
    if proxies:
        w.w(1, "/* Begin PBXTargetDependency section */")
        for t, dep in proxies:
            w.w(2, f"{oid('dependency', t.name, dep)} /* PBXTargetDependency */ = {{")
            w.w(3, "isa = PBXTargetDependency;")
            w.w(3, f"target = {oid('target', dep)} /* {dep} */;")
            w.w(3, f"targetProxy = {oid('proxy', t.name, dep)} /* PBXContainerItemProxy */;")
            w.w(2, "};")
        w.w(1, "/* End PBXTargetDependency section */")
        w.w(0, "")

    # ---- XCBuildConfiguration --------------------------------------------------------
    w.w(1, "/* Begin XCBuildConfiguration section */")
    for config, settings in (("Debug", PROJECT_DEBUG), ("Release", PROJECT_RELEASE)):
        w.w(2, f"{oid('buildconfig', '__project__', config)} /* {config} */ = {{")
        w.w(3, "isa = XCBuildConfiguration;")
        emit_settings(w, 3, settings)
        w.w(3, f"name = {config};")
        w.w(2, "};")
    for t in targets:
        for config in ("Debug", "Release"):
            w.w(2, f"{oid('buildconfig', t.name, config)} /* {config} */ = {{")
            w.w(3, "isa = XCBuildConfiguration;")
            emit_settings(w, 3, target_settings(t, config))
            w.w(3, f"name = {config};")
            w.w(2, "};")
    w.w(1, "/* End XCBuildConfiguration section */")
    w.w(0, "")

    # ---- XCConfigurationList ---------------------------------------------------------
    w.w(1, "/* Begin XCConfigurationList section */")
    for owner, label in [("__project__", f'PBXProject "{PROJECT_NAME}"')] + [
        (t.name, f'PBXNativeTarget "{t.name}"') for t in targets
    ]:
        w.w(2, f"{oid('configlist', owner)} /* Build configuration list for {label} */ = {{")
        w.w(3, "isa = XCConfigurationList;")
        w.w(3, "buildConfigurations = (")
        for config in ("Debug", "Release"):
            w.w(4, f"{oid('buildconfig', owner, config)} /* {config} */,")
        w.w(3, ");")
        w.w(3, "defaultConfigurationIsVisible = 0;")
        w.w(3, "defaultConfigurationName = Release;")
        w.w(2, "};")
    w.w(1, "/* End XCConfigurationList section */")
    w.w(0, "")

    w.w(1, "};")
    w.w(1, f"rootObject = {oid('project')} /* Project object */;")
    w.w(0, "}")

    _ = app  # kept for readability of build_targets ordering
    return w.text()


def validate(pbxproj: str, expected_paths: list[str]) -> None:
    """Checks the two integrity properties the pbxproj format does not check itself.

    Nothing validates a pbxproj. An ID referenced by a group or a build phase that matches no
    emitted object is silently ignored, and every affected file then resolves relative to the
    project root instead of its folder — which Xcode reports, minutes later and a long way from
    the cause, as "Build input files cannot be found". Both properties are cheap to assert here.
    """
    import re

    def section(name: str) -> str:
        start = pbxproj.find(f"/* Begin {name} section */")
        end = pbxproj.find(f"/* End {name} section */")
        return pbxproj[start:end] if start >= 0 and end > start else ""

    defined = set(re.findall(r"^\t\t([0-9A-F]{24}) ", pbxproj, flags=re.MULTILINE))
    referenced = set(re.findall(r"\b([0-9A-F]{24})\b", pbxproj))

    # 1. Nothing points at an object that was never emitted.
    dangling = referenced - defined
    if dangling:
        raise SystemExit(
            f"generated project references {len(dangling)} undefined object(s): "
            + ", ".join(sorted(dangling)[:8])
        )

    # 2. Every file reference lives in some group, so its path resolves through that group's
    #    folder rather than through the project root.
    groups = section("PBXGroup")
    orphans = [
        path for path in expected_paths if oid("fileref", path) not in groups
    ]
    if orphans:
        raise SystemExit(
            f"{len(orphans)} file reference(s) are not in any group, so their paths would "
            f"resolve at the project root: {orphans[:5]}"
        )



def testable_references(names: list[str]) -> str:
    """One <TestableReference> per test bundle.

    The scheme used to hardcode a single one. A UI test target that is not listed here builds and
    then never runs under `xcodebuild test`, which is a silent pass — the worst possible outcome for
    the tests whose whole job is catching what CI otherwise cannot see.
    """
    blocks = []
    for name in names:
        blocks.append(
            f"""         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{oid('target', name)}"
               BuildableName = "{name}.xctest"
               BlueprintName = "{name}"
               ReferencedContainer = "container:Tradewind.xcodeproj">
            </BuildableReference>
         </TestableReference>"""
        )
    return "\n".join(blocks)


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_id}"
               BuildableName = "Tradewind.app"
               BlueprintName = "Tradewind"
               ReferencedContainer = "container:Tradewind.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
{testables}
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_id}"
            BuildableName = "Tradewind.app"
            BlueprintName = "Tradewind"
            ReferencedContainer = "container:Tradewind.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_id}"
            BuildableName = "Tradewind.app"
            BlueprintName = "Tradewind"
            ReferencedContainer = "container:Tradewind.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

WORKSPACE_DATA = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""


def main() -> int:
    pbxproj = generate()
    validate(pbxproj, collect_file_refs(build_targets()))

    if os.path.isdir(PROJECT_DIR):
        shutil.rmtree(PROJECT_DIR)
    os.makedirs(os.path.join(PROJECT_DIR, "project.xcworkspace", "xcshareddata"), exist_ok=True)
    os.makedirs(os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes"), exist_ok=True)

    with open(os.path.join(PROJECT_DIR, "project.pbxproj"), "w", encoding="utf-8") as fh:
        fh.write(pbxproj)
    with open(
        os.path.join(PROJECT_DIR, "project.xcworkspace", "contents.xcworkspacedata"), "w", encoding="utf-8"
    ) as fh:
        fh.write(WORKSPACE_DATA)
    with open(
        os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes", f"{PROJECT_NAME}.xcscheme"), "w", encoding="utf-8"
    ) as fh:
        fh.write(
            SCHEME_TEMPLATE.format(
                app_id=oid("target", "Tradewind"),
                testables=testable_references(["TradewindTests", "TradewindUITests"]),
            )
        )

    targets = build_targets()
    print(f"wrote {os.path.relpath(PROJECT_DIR, ROOT)}")
    for t in targets:
        print(f"  {t.name:<18} {len(t.sources):>3} swift, {len(t.resources)} resource(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
