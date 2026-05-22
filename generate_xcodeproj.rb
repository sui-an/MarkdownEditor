#!/usr/bin/env ruby
require 'digest'
require 'fileutils'

PROJECT_DIR = File.expand_path(__dir__)
PROJECT_NAME = "MarkdownEditor"
XCODEPROJ = File.join(PROJECT_DIR, "#{PROJECT_NAME}.xcodeproj")
PBXPROJ = File.join(XCODEPROJ, "project.pbxproj")

# Generate a deterministic 24-char hex ID from a string
def make_id(seed)
  Digest::SHA256.hexdigest(seed)[0...24].upcase
end

# Collect source files
sources_dir = File.join(PROJECT_DIR, "Sources")
swift_files = Dir.glob(File.join(sources_dir, "**", "*.swift")).sort.map { |f| f.sub(PROJECT_DIR + "/", "") }

resources_dir = File.join(PROJECT_DIR, "Resources")
resource_files = Dir.glob(File.join(resources_dir, "**", "*")).sort.select { |f|
  File.file?(f) && !f.end_with?(".swift") && !f.include?("Assets.xcassets")
}.map { |f| f.sub(PROJECT_DIR + "/", "") }

info_plist_path = "Resources/Info.plist"
assets_path = "Resources/Assets.xcassets"
mermaid_path = "Resources/mermaid.min.js"

puts "Swift files: #{swift_files.length}"
swift_files.each { |f| puts "  #{f}" }
puts "Resource files: #{resource_files.length}"
resource_files.each { |f| puts "  #{f}" }

# Generate IDs
root_id = make_id("root")
sources_group_id = make_id("sources_group")
resources_group_id = make_id("resources_group")
products_group_id = make_id("products_group")
main_group_id = make_id("main_group")
project_id = make_id("project")
target_id = make_id("target")
product_ref_id = make_id("product_ref")
sources_phase_id = make_id("sources_phase")
resources_phase_id = make_id("resources_phase")
shell_script_phase_id = make_id("shell_script_phase")

# Configuration list IDs
project_config_list_id = make_id("project_config_list")
target_config_list_id = make_id("target_config_list")
debug_config_id = make_id("debug_config")
release_config_id = make_id("release_config")

# Build settings
build_settings_base_id = make_id("build_settings_base")
build_settings_debug_id = make_id("build_settings_debug")
build_settings_release_id = make_id("build_settings_release")

# File reference IDs (deterministic by path)
file_ref_ids = {}
build_file_ids = {}

# Group IDs for subdirectories
group_ids = {}
group_paths = {}

# Generate group structure for Sources
current_models_group = make_id("group_Models")
current_views_group = make_id("group_Views")
current_sidebar_group = make_id("group_Sidebar")
current_editor_group = make_id("group_Editor")
current_preview_group = make_id("group_Preview")
current_services_group = make_id("group_Services")

# Build file references
swift_files.each do |f|
  file_ref_ids[f] = make_id("ref_#{f}")
  build_file_ids[f] = make_id("build_#{f}")
end

resource_files.each do |f|
  file_ref_ids[f] = make_id("ref_#{f}")
  build_file_ids[f] = make_id("res_build_#{f}")
end

# Info.plist
file_ref_ids[info_plist_path] = make_id("ref_info_plist")
build_file_ids[info_plist_path] = make_id("build_info_plist")

# App icon / assets
file_ref_ids[assets_path] = make_id("ref_assets")
build_file_ids[assets_path] = make_id("build_assets")

# Mermaid
file_ref_ids[mermaid_path] = make_id("ref_mermaid")
build_file_ids[mermaid_path] = make_id("build_mermaid")

# Include mermaid and assets in resource files for build phase
all_resources = resource_files + [info_plist_path, assets_path, mermaid_path].reject { |f| resource_files.include?(f) }

# Generate pbxproj content
def quote(s); "\"#{s}\""; end
def line(indent, text); "#{"\t" * indent}#{text}"; end

pbxproj = <<~HEADER
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {
HEADER

# PBXBuildFile section
pbxproj += "\n/* Begin PBXBuildFile section */\n"
swift_files.each do |f|
  pbxproj += "\t\t#{build_file_ids[f]} /* #{File.basename(f)} in Sources */ = {isa = PBXBuildFile; fileRef = #{file_ref_ids[f]} /* #{File.basename(f)} */; };\n"
end
all_resources.uniq.each do |f|
  next if f.include?("Assets.xcassets")  # handled differently
  pbxproj += "\t\t#{build_file_ids[f]} /* #{File.basename(f)} in Resources */ = {isa = PBXBuildFile; fileRef = #{file_ref_ids[f]} /* #{File.basename(f)} */; };\n"
end
# Assets.xcassets is special
if file_ref_ids[assets_path]
  pbxproj += "\t\t#{build_file_ids[assets_path]} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = #{file_ref_ids[assets_path]} /* Assets.xcassets */; };\n"
end
pbxproj += "/* End PBXBuildFile section */\n"

# PBXFileReference section
pbxproj += "\n/* Begin PBXFileReference section */\n"
pbxproj += "\t\t#{product_ref_id} /* #{PROJECT_NAME}.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = #{PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; };\n"

swift_files.each do |f|
  pbxproj += "\t\t#{file_ref_ids[f]} /* #{File.basename(f)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{File.basename(f)}; sourceTree = \"<group>\"; };\n"
end

all_resources.uniq.each do |f|
  ext = File.extname(f)
  type = case ext
  when ".plist" then "text.plist.xml"
  when ".css" then "text.css"
  when ".js" then "sourcecode.javascript"
  when ".json" then "text.json"
  else "file"
  end
  if f.include?("Assets.xcassets")
    pbxproj += "\t\t#{file_ref_ids[f]} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };\n"
  else
    pbxproj += "\t\t#{file_ref_ids[f]} /* #{File.basename(f)} */ = {isa = PBXFileReference; lastKnownFileType = #{type}; path = #{File.basename(f)}; sourceTree = \"<group>\"; };\n"
  end
end
pbxproj += "/* End PBXFileReference section */\n"

# PBXGroup section
pbxproj += "\n/* Begin PBXGroup section */\n"

# Group tree
pbxproj += "\t\t#{main_group_id} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
pbxproj += "\t\t\t\t#{sources_group_id} /* Sources */,\n"
pbxproj += "\t\t\t\t#{resources_group_id} /* Resources */,\n"
pbxproj += "\t\t\t\t#{products_group_id} /* Products */,\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

# Sources group with sub-groups
pbxproj += "\t\t#{sources_group_id} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
pbxproj += "\t\t\t\t#{file_ref_ids["Sources/MarkdownEditorApp.swift"]} /* MarkdownEditorApp.swift */,\n"

# Models group
pbxproj += "\t\t\t\t#{current_models_group} /* Models */,\n"
# Views group
pbxproj += "\t\t\t\t#{current_views_group} /* Views */,\n"
# Services group
pbxproj += "\t\t\t\t#{current_services_group} /* Services */,\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tpath = Sources;\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

# Models group
model_files = swift_files.select { |f| f.include?("/Models/") }
pbxproj += "\t\t#{current_models_group} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
model_files.each do |f|
  pbxproj += "\t\t\t\t#{file_ref_ids[f]} /* #{File.basename(f)} */,\n"
end
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tpath = Models;\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

# Views group
pbxproj += "\t\t#{current_views_group} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
# ContentView is directly in Views
content_view_file = swift_files.find { |f| f == "Sources/Views/ContentView.swift" }
pbxproj += "\t\t\t\t#{file_ref_ids[content_view_file]} /* ContentView.swift */,\n" if content_view_file
pbxproj += "\t\t\t\t#{current_sidebar_group} /* Sidebar */,\n"
pbxproj += "\t\t\t\t#{current_editor_group} /* Editor */,\n"
pbxproj += "\t\t\t\t#{current_preview_group} /* Preview */,\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tpath = Views;\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

# Sidebar group
sidebar_files = swift_files.select { |f| f.include?("/Sidebar/") }
pbxproj += "\t\t#{current_sidebar_group} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
sidebar_files.each do |f|
  pbxproj += "\t\t\t\t#{file_ref_ids[f]} /* #{File.basename(f)} */,\n"
end
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tpath = Sidebar;\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

# Editor group
editor_files = swift_files.select { |f| f.include?("/Editor/") }
pbxproj += "\t\t#{current_editor_group} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
editor_files.each do |f|
  pbxproj += "\t\t\t\t#{file_ref_ids[f]} /* #{File.basename(f)} */,\n"
end
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tpath = Editor;\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

# Preview group
preview_files = swift_files.select { |f| f.include?("/Preview/") }
pbxproj += "\t\t#{current_preview_group} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
preview_files.each do |f|
  pbxproj += "\t\t\t\t#{file_ref_ids[f]} /* #{File.basename(f)} */,\n"
end
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tpath = Preview;\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

# Services group
service_files = swift_files.select { |f| f.include?("/Services/") }
pbxproj += "\t\t#{current_services_group} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
service_files.each do |f|
  pbxproj += "\t\t\t\t#{file_ref_ids[f]} /* #{File.basename(f)} */,\n"
end
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tpath = Services;\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

# Resources group
pbxproj += "\t\t#{resources_group_id} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
all_resources.uniq.each do |f|
  pbxproj += "\t\t\t\t#{file_ref_ids[f]} /* #{File.basename(f)} */,\n"
end
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tpath = Resources;\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

# Products group
pbxproj += "\t\t#{products_group_id} = {\n"
pbxproj += "\t\t\tisa = PBXGroup;\n"
pbxproj += "\t\t\tchildren = (\n"
pbxproj += "\t\t\t\t#{product_ref_id} /* #{PROJECT_NAME}.app */,\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tname = Products;\n"
pbxproj += "\t\t\tsourceTree = \"<group>\";\n"
pbxproj += "\t\t};\n"

pbxproj += "/* End PBXGroup section */\n"

# PBXNativeTarget section
pbxproj += "\n/* Begin PBXNativeTarget section */\n"
pbxproj += "\t\t#{target_id} /* #{PROJECT_NAME} */ = {\n"
pbxproj += "\t\t\tisa = PBXNativeTarget;\n"
pbxproj += "\t\t\tbuildConfigurationList = #{target_config_list_id} /* Build configuration list for PBXNativeTarget \"#{PROJECT_NAME}\" */;\n"
pbxproj += "\t\tbuildPhases = (\n"
pbxproj += "\t\t\t\t#{sources_phase_id} /* Sources */,\n"
pbxproj += "\t\t\t\t#{resources_phase_id} /* Resources */,\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\tbuildRules = (\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\tdependencies = (\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\tname = #{PROJECT_NAME};\n"
pbxproj += "\t\tproductName = #{PROJECT_NAME};\n"
pbxproj += "\t\tproductReference = #{product_ref_id} /* #{PROJECT_NAME}.app */;\n"
pbxproj += "\t\tproductType = \"com.apple.product-type.application\";\n"
pbxproj += "\t\t};\n"
pbxproj += "/* End PBXNativeTarget section */\n"

# PBXProject section
pbxproj += "\n/* Begin PBXProject section */\n"
pbxproj += "\t\t#{project_id} /* Project object */ = {\n"
pbxproj += "\t\t\tisa = PBXProject;\n"
pbxproj += "\t\t\tattributes = {\n"
pbxproj += "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
pbxproj += "\t\t\t\tLastSwiftUpdateCheck = 1540;\n"
pbxproj += "\t\t\t\tLastUpgradeCheck = 1540;\n"
pbxproj += "\t\t\t};\n"
pbxproj += "\t\t\tbuildConfigurationList = #{project_config_list_id} /* Build configuration list for PBXProject \"#{PROJECT_NAME}\" */;\n"
pbxproj += "\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n"
pbxproj += "\t\t\tdevelopmentRegion = en;\n"
pbxproj += "\t\t\thasScannedForEncodings = 0;\n"
pbxproj += "\t\t\tknownRegions = (\n"
pbxproj += "\t\t\t\ten,\n"
pbxproj += "\t\t\t\tBase,\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tmainGroup = #{main_group_id};\n"
pbxproj += "\t\t\tproductRefGroup = #{products_group_id};\n"
pbxproj += "\t\t\tprojectDirPath = \"\";\n"
pbxproj += "\t\t\tprojectRoot = \"\";\n"
pbxproj += "\t\t\ttargets = (\n"
pbxproj += "\t\t\t\t#{target_id} /* #{PROJECT_NAME} */,\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t};\n"
pbxproj += "/* End PBXProject section */\n"

# PBXSourcesBuildPhase section
pbxproj += "\n/* Begin PBXSourcesBuildPhase section */\n"
pbxproj += "\t\t#{sources_phase_id} /* Sources */ = {\n"
pbxproj += "\t\t\tisa = PBXSourcesBuildPhase;\n"
pbxproj += "\t\t\tbuildActionMask = 2147483647;\n"
pbxproj += "\t\t\tfiles = (\n"
swift_files.each do |f|
  pbxproj += "\t\t\t\t#{build_file_ids[f]} /* #{File.basename(f)} in Sources */,\n"
end
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
pbxproj += "\t\t};\n"
pbxproj += "/* End PBXSourcesBuildPhase section */\n"

# PBXResourcesBuildPhase section
pbxproj += "\n/* Begin PBXResourcesBuildPhase section */\n"
pbxproj += "\t\t#{resources_phase_id} /* Resources */ = {\n"
pbxproj += "\t\t\tisa = PBXResourcesBuildPhase;\n"
pbxproj += "\t\t\tbuildActionMask = 2147483647;\n"
pbxproj += "\t\t\tfiles = (\n"
all_resources.uniq.each do |f|
  pbxproj += "\t\t\t\t#{build_file_ids[f]} /* #{File.basename(f)} in Resources */,\n"
end
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
pbxproj += "\t\t};\n"
pbxproj += "/* End PBXResourcesBuildPhase section */\n"

# XCConfigurationList for project
pbxproj += "\n/* Begin XCConfigurationList section */\n"
pbxproj += "\t\t#{project_config_list_id} /* Build configuration list for PBXProject \"#{PROJECT_NAME}\" */ = {\n"
pbxproj += "\t\t\tisa = XCConfigurationList;\n"
pbxproj += "\t\t\tbuildConfigurations = (\n"
pbxproj += "\t\t\t\t#{debug_config_id} /* Debug */,\n"
pbxproj += "\t\t\t\t#{release_config_id} /* Release */,\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tdefaultConfigurationIsVisible = 0;\n"
pbxproj += "\t\t\tdefaultConfigurationName = Release;\n"
pbxproj += "\t\t};\n"

pbxproj += "\t\t#{target_config_list_id} /* Build configuration list for PBXNativeTarget \"#{PROJECT_NAME}\" */ = {\n"
pbxproj += "\t\t\tisa = XCConfigurationList;\n"
pbxproj += "\t\t\tbuildConfigurations = (\n"
pbxproj += "\t\t\t\t#{build_settings_debug_id} /* Debug */,\n"
pbxproj += "\t\t\t\t#{build_settings_release_id} /* Release */,\n"
pbxproj += "\t\t\t);\n"
pbxproj += "\t\t\tdefaultConfigurationIsVisible = 0;\n"
pbxproj += "\t\t\tdefaultConfigurationName = Release;\n"
pbxproj += "\t\t};\n"
pbxproj += "/* End XCConfigurationList section */\n"

# XCBuildConfiguration section
pbxproj += "\n/* Begin XCBuildConfiguration section */\n"

# Project-level Debug
pbxproj += "\t\t#{debug_config_id} /* Debug */ = {\n"
pbxproj += "\t\t\tisa = XCBuildConfiguration;\n"
pbxproj += "\t\t\tbuildSettings = {\n"
pbxproj += "\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;\n"
pbxproj += "\t\t\t\tCLANG_ANALYZER_NONNULL = YES;\n"
pbxproj += "\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";\n"
pbxproj += "\t\t\t\tCLANG_ENABLE_MODULES = YES;\n"
pbxproj += "\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;\n"
pbxproj += "\t\t\t\tCOPY_PHASE_STRIP = NO;\n"
pbxproj += "\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;\n"
pbxproj += "\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;\n"
pbxproj += "\t\t\t\tENABLE_TESTABILITY = YES;\n"
pbxproj += "\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;\n"
pbxproj += "\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;\n"
pbxproj += "\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (\n"
pbxproj += "\t\t\t\t\t\"DEBUG=1\",\n"
pbxproj += "\t\t\t\t\t\"$(inherited)\",\n"
pbxproj += "\t\t\t\t);\n"
pbxproj += "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n"
pbxproj += "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;\n"
pbxproj += "\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;\n"
pbxproj += "\t\t\t\tONLY_ACTIVE_ARCH = YES;\n"
pbxproj += "\t\t\t\tSDKROOT = macosx;\n"
pbxproj += "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n"
pbxproj += "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n"
pbxproj += "\t\t\t};\n"
pbxproj += "\t\t\tname = Debug;\n"
pbxproj += "\t\t};\n"

# Project-level Release
pbxproj += "\t\t#{release_config_id} /* Release */ = {\n"
pbxproj += "\t\t\tisa = XCBuildConfiguration;\n"
pbxproj += "\t\t\tbuildSettings = {\n"
pbxproj += "\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;\n"
pbxproj += "\t\t\t\tCLANG_ANALYZER_NONNULL = YES;\n"
pbxproj += "\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";\n"
pbxproj += "\t\t\t\tCLANG_ENABLE_MODULES = YES;\n"
pbxproj += "\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;\n"
pbxproj += "\t\t\t\tCOPY_PHASE_STRIP = NO;\n"
pbxproj += "\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n"
pbxproj += "\t\t\t\tENABLE_NS_ASSERTIONS = NO;\n"
pbxproj += "\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;\n"
pbxproj += "\t\t\t\tGCC_OPTIMIZATION_LEVEL = s;\n"
pbxproj += "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n"
pbxproj += "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;\n"
pbxproj += "\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;\n"
pbxproj += "\t\t\t\tSDKROOT = macosx;\n"
pbxproj += "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n"
pbxproj += "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";\n"
pbxproj += "\t\t\t};\n"
pbxproj += "\t\t\tname = Release;\n"
pbxproj += "\t\t};\n"

# Target-level Debug
pbxproj += "\t\t#{build_settings_debug_id} /* Debug */ = {\n"
pbxproj += "\t\t\tisa = XCBuildConfiguration;\n"
pbxproj += "\t\t\tbuildSettings = {\n"
pbxproj += "\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n"
pbxproj += "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
pbxproj += "\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;\n"
pbxproj += "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
pbxproj += "\t\t\t\tENABLE_HARDENED_RUNTIME = YES;\n"
pbxproj += "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
pbxproj += "\t\t\t\tINFOPLIST_FILE = Resources/Info.plist;\n"
pbxproj += "\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = \"MarkdownEditor\";\n"
pbxproj += "\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.productivity\";\n"
pbxproj += "\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = \"\";\n"
pbxproj += "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
pbxproj += "\t\t\t\t\t\"$(inherited)\",\n"
pbxproj += "\t\t\t\t\t\"@executable_path/../Frameworks\",\n"
pbxproj += "\t\t\t\t);\n"
pbxproj += "\t\t\t\tMARKETING_VERSION = 1.0;\n"
pbxproj += "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.markdowneditor.app;\n"
pbxproj += "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
pbxproj += "\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n"
pbxproj += "\t\t\t\tSWIFT_VERSION = 5.0;\n"
pbxproj += "\t\t\t};\n"
pbxproj += "\t\t\tname = Debug;\n"
pbxproj += "\t\t};\n"

# Target-level Release
pbxproj += "\t\t#{build_settings_release_id} /* Release */ = {\n"
pbxproj += "\t\t\tisa = XCBuildConfiguration;\n"
pbxproj += "\t\t\tbuildSettings = {\n"
pbxproj += "\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n"
pbxproj += "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
pbxproj += "\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;\n"
pbxproj += "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
pbxproj += "\t\t\t\tENABLE_HARDENED_RUNTIME = YES;\n"
pbxproj += "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
pbxproj += "\t\t\t\tINFOPLIST_FILE = Resources/Info.plist;\n"
pbxproj += "\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = \"MarkdownEditor\";\n"
pbxproj += "\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.productivity\";\n"
pbxproj += "\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = \"\";\n"
pbxproj += "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
pbxproj += "\t\t\t\t\t\"$(inherited)\",\n"
pbxproj += "\t\t\t\t\t\"@executable_path/../Frameworks\",\n"
pbxproj += "\t\t\t\t);\n"
pbxproj += "\t\t\t\tMARKETING_VERSION = 1.0;\n"
pbxproj += "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.markdowneditor.app;\n"
pbxproj += "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
pbxproj += "\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n"
pbxproj += "\t\t\t\tSWIFT_VERSION = 5.0;\n"
pbxproj += "\t\t\t};\n"
pbxproj += "\t\t\tname = Release;\n"
pbxproj += "\t\t};\n"

pbxproj += "/* End XCBuildConfiguration section */\n"

# Root object
pbxproj += "\n/* Begin PBXRootObject section */\n"
pbxproj += "\t\t#{root_id} /* Root object */ = {\n"
pbxproj += "\t\t\tisa = PBXRootObject;\n"
pbxproj += "\t\t\trootObject = #{project_id} /* Project object */;\n"
pbxproj += "\t\t};\n"
pbxproj += "/* End PBXRootObject section */\n"

# Close
pbxproj += <<~FOOTER
	};
	rootObject = #{root_id} /* Root object */;
}
FOOTER

# Write the pbxproj
FileUtils.mkdir_p(XCODEPROJ)
File.write(PBXPROJ, pbxproj)
puts "Generated #{PBXPROJ}"
puts "Total size: #{pbxproj.bytesize} bytes"
