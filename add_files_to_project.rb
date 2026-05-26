#!/usr/bin/env ruby
# Add new Swift files to Xcode project

project_file = 'MarkdownEditor.xcodeproj/project.pbxproj'

# New files to add
new_files = [
  'Sources/Services/SessionRestoreService.swift',
  'Sources/Models/SearchState.swift',
  'Sources/Models/ViewRefs.swift',
  'Sources/Views/SearchPanelView.swift',
  'Sources/Services/HeadingParser.swift',
  'Sources/Views/OutlinePanelView.swift'
]

# Read project file
content = File.read(project_file)

# Generate random UUIDs
def generate_uuid
  sprintf('%0X8X%0X8X%0X8X%0X8X%0X8X%0X8X%0X8X%0X8X',
    rand(0...0xFFFFFFFF),
    rand(0...0xFFFFFFFF),
    rand(0...0xFFFFFFFF),
    rand(0...0xFFFFFFFF),
    rand(0...0xFFFFFFFF),
    rand(0...0xFFFFFFFF),
    rand(0...0xFFFFFFFF),
    rand(0...0xFFFFFFFF),
    rand(0...0xFFFFFFFF)
  )
end

uuids = {}
new_files.each { |path| uuids[path] = generate_uuid }

# Add to PBXBuildFile section
pbx_build_files = new_files.map do |path|
  file_name = File.basename(path)
  "		#{uuids[path][0..7]}#{uuids[path][8..15].upcase} /* #{file_name} in Sources */ = {isa = PBXBuildFile; fileRef = #{uuids[path]} /* #{file_name} */; };"
end

# Find PBXBuildFile section
pbx_build_files_match = content.match(/(.*Begin PBXBuildFile section.*?\/\* ImageHandler\.swift in Sources \*\/ = \{isa = PBXBuildFile;.*?\n)/s)

if pbx_build_files_match
  insert_point = pbx_build_files_match.end(1)
  content = content[0, insert_point] + "\n" + pbx_build_files.join("\n") + content[insert_point..-1]
else
  puts "Warning: Could not find PBXBuildFile section, trying alternative method"
  # Fallback: append to end of file
  content += "\n" + pbx_build_files.join("\n")
end

# Add to PBXFileReference section
pbx_file_refs = new_files.map do |path|
  file_name = File.basename(path)
  "		#{uuids[path]} /* #{file_name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{file_name}; sourceTree = \"<group>\"; };"
end

pbx_file_refs_match = content.match(/(.*Begin PBXFileReference section.*?path = FileTreeItem.swift.*?\n)/s)

if pbx_file_refs_match
  insert_point = pbx_file_refs_match.end(1)
  content = content[0, insert_point] + "\n" + pbx_file_refs.join("\n") + content[insert_point..-1]
else
  puts "Warning: Could not find PBXFileReference section"
end

# Add to PBXSourcesBuildPhase section
# Find Sources build phase
sources_phase_match = content.match(/(.*Begin PBXSourcesBuildPhase.*?\/\* FileTreeItem.swift \*\/,.*?\n)/s)

if sources_phase_match
  insert_point = sources_phase_match.end(1)
  build_file_ids = new_files.map { |path| uuids[path][0..7] + uuids[path][8..15].upcase }
  new_sources = "\n" + build_file_ids.map { |id| "		#{id} /* #{File.basename(new_files.find { |f| f.end_with?('.swift') })} in Sources */," }.join("\n")
  content = content[0, insert_point] + new_sources + content[insert_point..-1]
else
  puts "Warning: Could not find PBXSourcesBuildPhase section"
end

# Write back
File.write(project_file, content)

puts "Added #{new_files.length} files to Xcode project:"
new_files.each { |f| puts "  - #{f}" }
