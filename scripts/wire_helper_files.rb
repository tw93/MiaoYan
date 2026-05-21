#!/usr/bin/env ruby
# Wires standalone helper files into the MiaoYan target.
#
# Three Swift files (Helpers/Diagnostics.swift, Helpers/UIDelay.swift,
# Business/AppEnvironment.swift) were landed in HEAD but are not yet in the
# Xcode project's compile phase, so they ship as dead code until this script
# runs. This script is idempotent: it skips any file already present in the
# MiaoYan target's source build phase.
#
# Usage:
#   gem install xcodeproj   # if not already installed
#   ruby scripts/wire_helper_files.rb
#
# Commit the resulting MiaoYan.xcodeproj/project.pbxproj diff afterwards.
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../MiaoYan.xcodeproj', __dir__)
PROJECT_ROOT = File.expand_path('..', __dir__)

# rel_path inside repo, group name (top-level group inside main_group)
FILES_TO_WIRE = [
  ['Helpers/Diagnostics.swift',     'Helpers'],
  ['Helpers/UIDelay.swift',         'Helpers'],
  ['Business/AppEnvironment.swift', 'Business'],
].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == 'MiaoYan' }
abort 'MiaoYan target not found' unless target

added = 0
skipped = 0

FILES_TO_WIRE.each do |rel_path, group_name|
  abs_path = File.join(PROJECT_ROOT, rel_path)
  abort "missing source file on disk: #{rel_path}" unless File.exist?(abs_path)

  # Idempotency: skip if any existing build file in MiaoYan's source phase
  # already points at this path.
  already_in_phase = target.source_build_phase.files.any? do |bf|
    bf.file_ref && bf.file_ref.path == rel_path
  end
  if already_in_phase
    puts "skip: #{rel_path} already in MiaoYan target"
    skipped += 1
    next
  end

  # Locate the group: source files live under main_group -> MiaoYan -> <group_name>.
  parent = project.main_group.children.find { |c|
    c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == 'MiaoYan'
  }
  abort "MiaoYan source group not found in main_group" unless parent
  group = parent.children.find { |c|
    c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == group_name
  }
  abort "group not found under MiaoYan: #{group_name}" unless group

  # Reuse an existing file reference if one already lives in the group,
  # otherwise create a new one.
  existing_ref = group.files.find { |f| f.path == rel_path || f.path == File.basename(rel_path) }
  ref = existing_ref || begin
    new_ref = group.new_reference(abs_path)
    new_ref.path = rel_path
    new_ref.source_tree = 'SOURCE_ROOT'
    new_ref
  end

  target.source_build_phase.add_file_reference(ref)
  puts "added: #{rel_path} (to MiaoYan target via group '#{group_name}')"
  added += 1
end

project.save
puts ''
puts "Done. #{added} file(s) added, #{skipped} skipped."
puts 'Next: commit MiaoYan.xcodeproj/project.pbxproj, then xcodebuild build to verify.'
