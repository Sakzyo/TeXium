#!/usr/bin/env python3
"""Generate the small, dependency-free Xcode application project deterministically."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
def ident(value): return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def quote(value): return json.dumps(str(value))
objects = {}
def put(key, body): objects[ident(key)] = body; return ident(key)
def refs(items): return "(" + ", ".join(items) + ")"

sources = sorted((ROOT / "Sources/TeXium").rglob("*.swift"))
file_refs = []
build_refs = []
for file in sources:
    path = str(file.relative_to(ROOT))
    reference = put("file:" + path, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(path)}; sourceTree = SOURCE_ROOT;")
    file_refs.append(reference)
    build_refs.append(put("build:" + path, f"isa = PBXBuildFile; fileRef = {reference};"))
icon = put("icon", 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Sources/TeXium/Resources/TeXium.icns; sourceTree = SOURCE_ROOT;')
icon_build = put("icon-build", f"isa = PBXBuildFile; fileRef = {icon};")
product = put("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TeXium.app; sourceTree = BUILT_PRODUCTS_DIR;')
products_group = put("products", f"isa = PBXGroup; children = ({product}); name = Products; sourceTree = \"<group>\";")
source_group = put("sources", f"isa = PBXGroup; children = {refs(file_refs + [icon])}; name = TeXium; sourceTree = \"<group>\";")
group = put("group", f"isa = PBXGroup; children = ({source_group}, {products_group}); sourceTree = \"<group>\";")
package = put("package", 'isa = XCLocalSwiftPackageReference; relativePath = .;')
dependency = put("core", f"isa = XCSwiftPackageProductDependency; package = {package}; productName = TeXiumCore;")
core_build = put("core-build", f"isa = PBXBuildFile; productRef = {dependency};")
source_phase = put("source-phase", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(build_refs)}; runOnlyForDeploymentPostprocessing = 0;")
framework_phase = put("framework-phase", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({core_build}); runOnlyForDeploymentPostprocessing = 0;")
resource_phase = put("resource-phase", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({icon_build}); runOnlyForDeploymentPostprocessing = 0;")
project_configs = []
target_configs = []
for configuration in ["Debug", "Release"]:
    release = configuration == "Release"
    project_configs.append(put("project:" + configuration, f'''isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{
        MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0;
        CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; GCC_C_LANGUAGE_STANDARD = gnu17;
        SWIFT_OPTIMIZATION_LEVEL = {quote('-O' if release else '-Onone')};
        SWIFT_COMPILATION_MODE = {quote('wholemodule' if release else 'singlefile')};
        DEBUG_INFORMATION_FORMAT = {quote('dwarf-with-dsym' if release else 'dwarf')};
        ONLY_ACTIVE_ARCH = {'NO' if release else 'YES'};
        ENABLE_TESTABILITY = {'NO' if release else 'YES'};
        SWIFT_ACTIVE_COMPILATION_CONDITIONS = {quote('$(inherited)' if release else 'DEBUG $(inherited)')};
    }};'''))
    target_configs.append(put("target:" + configuration, f'''isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{
        PRODUCT_NAME = TeXium; TEXIUM_APP_BUNDLE_IDENTIFIER = app.texium.mac; PRODUCT_BUNDLE_IDENTIFIER = "$(TEXIUM_APP_BUNDLE_IDENTIFIER)"; INFOPLIST_FILE = Sources/TeXium/Resources/Info.plist;
        GENERATE_INFOPLIST_FILE = NO; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-";
        ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = NO;
        COMBINE_HIDPI_IMAGES = YES; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");
        CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0.0;
    }};'''))
project_config = put("project-configs", f"isa = XCConfigurationList; buildConfigurations = {refs(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
target_config = put("target-configs", f"isa = XCConfigurationList; buildConfigurations = {refs(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
target = put("target", f'''isa = PBXNativeTarget; buildConfigurationList = {target_config}; buildPhases = ({source_phase}, {framework_phase}, {resource_phase}); buildRules = (); dependencies = (); name = TeXiumDesktop; packageProductDependencies = ({dependency}); productName = TeXium; productReference = {product}; productType = "com.apple.product-type.application";''')
ui_file = put("ui-file", 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/TeXiumUITests/TeXiumUITests.swift; sourceTree = SOURCE_ROOT;')
ui_build = put("ui-build", f'isa = PBXBuildFile; fileRef = {ui_file};')
ui_product = put("ui-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TeXiumUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
ui_sources = put("ui-sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ui_build}); runOnlyForDeploymentPostprocessing = 0;')
ui_configs = []
for configuration in ['Debug', 'Release']:
    ui_configs.append(put('ui:' + configuration, f'''isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{ PRODUCT_NAME = TeXiumUITests; PRODUCT_BUNDLE_IDENTIFIER = app.texium.ui-tests; GENERATE_INFOPLIST_FILE = YES; TEST_TARGET_NAME = TeXiumDesktop; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; SWIFT_VERSION = 5.0; MACOSX_DEPLOYMENT_TARGET = 14.0; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks"); }};'''))
ui_config = put('ui-configs', f'isa = XCConfigurationList; buildConfigurations = {refs(ui_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
ui_dependency = put('ui-dependency', f'isa = PBXTargetDependency; target = {target};')
ui_target = put('ui-target', f'isa = PBXNativeTarget; buildConfigurationList = {ui_config}; buildPhases = ({ui_sources}); buildRules = (); dependencies = ({ui_dependency}); name = TeXiumUITests; productName = TeXiumUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
objects[group] = objects[group].replace(f'({source_group}, {products_group})', f'({source_group}, {ui_file}, {products_group})')
objects[products_group] = objects[products_group].replace(f'({product})', f'({product}, {ui_product})')
project = put("project", f'''isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; packageReferences = ({package}); productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = ({target}, {ui_target});''')
content = '// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'
content += '\n'.join(f'  {key} = {{ {value} }};' for key, value in objects.items())
content += f'\n }};\n rootObject = {project};\n}}\n'
(ROOT / 'TeXium.xcodeproj/project.pbxproj').write_text(content)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="TeXium.app" BlueprintName="TeXiumDesktop" ReferencedContainer="container:TeXium.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="TeXiumUITests.xctest" BlueprintName="TeXiumUITests" ReferencedContainer="container:TeXium.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="TeXium.app" BlueprintName="TeXiumDesktop" ReferencedContainer="container:TeXium.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="TeXium.app" BlueprintName="TeXiumDesktop" ReferencedContainer="container:TeXium.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(ROOT / 'TeXium.xcodeproj/xcshareddata/xcschemes/TeXium.xcscheme').write_text(scheme)
print('Generated TeXium.xcodeproj with', len(sources), 'app source files and the local TeXiumCore package.')
