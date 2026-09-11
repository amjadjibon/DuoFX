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


sources, resources, references = [], [], []
for path in sorted((root / "DuoFX").rglob("*")) + [root / "NOTICE", root / "Licenses/LidAngleSensor.txt"]:
    if path.suffix not in (".swift", ".metal", ".png", ".txt") and path.name != "NOTICE":
        continue
    rel = path.relative_to(root).as_posix()
    kind = {".swift": "sourcecode.swift", ".metal": "text", ".png": "image.png"}.get(path.suffix, "text")
    ref = add(rel, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {json.dumps(rel)}; sourceTree = SOURCE_ROOT;')
    build = add(rel + ":build", f"isa = PBXBuildFile; fileRef = {ref};")
    references.append(ref)
    (sources if path.suffix == ".swift" else resources).append(build)

product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = DuoFX.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f'isa = PBXGroup; children = {array([product])}; name = Products; sourceTree = "<group>";')
main = add("main", f'isa = PBXGroup; children = {array(references + [products])}; sourceTree = "<group>";')
source_phase = add("sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(sources)}; runOnlyForDeploymentPostprocessing = 0;")
resource_phase = add("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resources)}; runOnlyForDeploymentPostprocessing = 0;")
framework_phase = add("frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
project_configs, target_configs = [], []
for name in ("Debug", "Release"):
    project_configs.append(add("project:" + name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; ARCHS = arm64; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; }};'))
    optimization = "-Onone" if name == "Debug" else "-O"
    target_configs.append(add("target:" + name, f'''isa = XCBuildConfiguration; name = {name}; buildSettings = {{
        PRODUCT_NAME = DuoFX; PRODUCT_BUNDLE_IDENTIFIER = com.duofx.DuoFX;
        INFOPLIST_FILE = DuoFX/Info.plist; GENERATE_INFOPLIST_FILE = NO;
        CODE_SIGN_STYLE = Automatic; CODE_SIGN_IDENTITY = "-";
        ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES;
        SWIFT_OPTIMIZATION_LEVEL = "{optimization}";
        SWIFT_EMIT_LOC_STRINGS = NO;
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
