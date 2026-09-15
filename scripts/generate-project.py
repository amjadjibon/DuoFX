#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project after adding source files."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
objects = {}


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def add(name, body):
    key = uid(name)
    objects[key] = body
    return key


def array(items):
    return "(" + ", ".join(items) + ",)" if items else "()"


sources, resources = [], []
folder_files = {}


def reference_in_folder(path, reference):
    folder_files.setdefault(path.parent.relative_to(root).as_posix(), []).append(reference)


for path in sorted((root / "DuoFX").rglob("*")) + [root / "NOTICE", root / "Licenses/LidAngleSensor.txt"]:
    if path.suffix not in (".swift", ".metal", ".png", ".txt", ".icns", ".plist", ".wav") and path.name != "NOTICE":
        continue
    rel = path.relative_to(root).as_posix()
    kind = {".swift": "sourcecode.swift", ".metal": "text", ".png": "image.png",
            ".icns": "image.icns", ".plist": "text.plist.xml", ".wav": "audio.wav"}.get(path.suffix, "text")
    ref = add(rel, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {json.dumps(rel)}; sourceTree = SOURCE_ROOT;')
    reference_in_folder(path, ref)
    if path.name == "Info.plist":
        continue
    build = add(rel + ":build", f"isa = PBXBuildFile; fileRef = {ref};")
    (sources if path.suffix == ".swift" else resources).append(build)

for name in ("README.md", "DESIGN.md", "Package.swift", "Signing.xcconfig"):
    file_type = 'lastKnownFileType = text.xcconfig;' if name.endswith(".xcconfig") else ''
    ref = add(name, f'isa = PBXFileReference; {file_type} path = {json.dumps(name)}; sourceTree = SOURCE_ROOT;')
    reference_in_folder(root / name, ref)


def folder_group(folder):
    children = list(folder_files.get(folder, []))
    direct_folders = sorted({Path(other).parts[len(Path(folder).parts)]
                             for other in folder_files
                             if Path(folder) in Path(other).parents})
    for child in direct_folders:
        children.append(folder_group((Path(folder) / child).as_posix()))
    return add("folder:" + folder, f'isa = PBXGroup; children = {array(children)}; name = {json.dumps(Path(folder).name)}; sourceTree = "<group>";')


product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = DuoFX.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f'isa = PBXGroup; children = {array([product])}; name = Products; sourceTree = "<group>";')
top_folders = sorted({Path(folder).parts[0] for folder in folder_files if folder != "."})
main_children = [folder_group(folder) for folder in top_folders] + folder_files.get(".", []) + [products]
main = add("main", f'isa = PBXGroup; children = {array(main_children)}; sourceTree = "<group>";')
source_phase = add("sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(sources)}; runOnlyForDeploymentPostprocessing = 0;")
resource_phase = add("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resources)}; runOnlyForDeploymentPostprocessing = 0;")
framework_phase = add("frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
project_configs, target_configs = [], []
for name in ("Debug", "Release"):
    project_configs.append(add("project:" + name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; ARCHS = arm64; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; }};'))
    optimization = "-Onone" if name == "Debug" else "-O"
    target_configs.append(add("target:" + name, f'''isa = XCBuildConfiguration; name = {name}; baseConfigurationReference = {uid("Signing.xcconfig")}; buildSettings = {{
        PRODUCT_NAME = DuoFX; PRODUCT_BUNDLE_IDENTIFIER = com.duofx.DuoFX;
        INFOPLIST_FILE = DuoFX/Info.plist; GENERATE_INFOPLIST_FILE = NO;
        ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES;
        SWIFT_OPTIMIZATION_LEVEL = "{optimization}";
        SWIFT_EMIT_LOC_STRINGS = NO;
        SWIFT_STRICT_CONCURRENCY = complete;
        LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
    }};'''))
project_list = add("project-list", f'isa = XCConfigurationList; buildConfigurations = {array(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target_list = add("target-list", f'isa = XCConfigurationList; buildConfigurations = {array(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add("target", f'isa = PBXNativeTarget; buildConfigurationList = {target_list}; buildPhases = {array([source_phase, framework_phase, resource_phase])}; buildRules = (); dependencies = (); name = DuoFX; productName = DuoFX; productReference = {product}; productType = "com.apple.product-type.application";')
project = add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([target])};')
folder = root / "DuoFX.xcodeproj"
folder.mkdir(exist_ok=True)
(folder / "project.pbxproj").write_text("// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" + "\n".join(f"{key} = {{ {value} }};" for key, value in objects.items()) + f"\n}}; rootObject = {project}; }}\n")
scheme_dir = folder / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="DuoFX.app" BlueprintName="DuoFX" ReferencedContainer="container:DuoFX.xcodeproj"/>'
(scheme_dir / "DuoFX.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
