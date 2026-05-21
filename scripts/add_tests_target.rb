#!/usr/bin/env ruby
# Adds the MiaoYanTests unit test target to MiaoYan.xcodeproj.
#
# Idempotent: re-runs are no-ops once the target exists. Run once after pulling
# new test source files, or commit the resulting pbxproj diff.
#
# Usage:
#   gem install xcodeproj   # if not already installed
#   ruby scripts/add_tests_target.rb
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../MiaoYan.xcodeproj', __dir__)
PROJECT_ROOT = File.expand_path('..', __dir__)
TESTS_DIR    = 'MiaoYanTests'

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == 'MiaoYanTests' }
  puts "Target MiaoYanTests already exists, skipping."
  exit 0
end

host_target = project.targets.find { |t| t.name == 'MiaoYan' }
abort "MiaoYan host target not found" unless host_target

# --- Create unit test target ---
test_target = project.new_target(:unit_test_bundle, 'MiaoYanTests', :osx, '11.5')

project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][test_target.uuid] = {
  'CreatedOnToolsVersion' => '16.0',
  'TestTargetID'          => host_target.uuid,
}

test_target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']    = 'com.tw93.miaoyan.tests'
  s['PRODUCT_NAME']                 = '$(TARGET_NAME)'
  s['SWIFT_VERSION']                = '6.0'
  s['MACOSX_DEPLOYMENT_TARGET']     = '11.5'
  s['INFOPLIST_FILE']               = 'MiaoYanTests/Info.plist'
  s['BUNDLE_LOADER']                = '$(TEST_HOST)'
  s['TEST_HOST']                    = '$(BUILT_PRODUCTS_DIR)/MiaoYan.app/Contents/MacOS/MiaoYan'
  s['LD_RUNPATH_SEARCH_PATHS']      = ['$(inherited)', '@executable_path/../Frameworks', '@loader_path/../Frameworks']
  s['CODE_SIGN_STYLE']              = 'Automatic'
  s['DEVELOPMENT_TEAM']             = '5EH69Y5X38'
  s['ENABLE_TESTING_SEARCH_PATHS']  = 'YES'
end

# --- File references ---
main_group  = project.main_group
tests_group = main_group.new_group('MiaoYanTests', TESTS_DIR)

def add_file(group, project_root, rel_path)
  ref = group.new_reference(File.join(project_root, rel_path))
  ref.path = rel_path
  ref.source_tree = 'SOURCE_ROOT'
  ref
end

test_sources = Dir.glob(File.join(PROJECT_ROOT, TESTS_DIR, '*.swift')).map { |abs|
  File.join(TESTS_DIR, File.basename(abs))
}.sort

test_sources.each do |rel_path|
  ref = add_file(tests_group, PROJECT_ROOT, rel_path)
  test_target.source_build_phase.add_file_reference(ref)
end

# Info.plist is referenced via INFOPLIST_FILE; only add as a file reference, not in any build phase.
add_file(tests_group, PROJECT_ROOT, File.join(TESTS_DIR, 'Info.plist'))

# --- Host target dependency ---
test_target.add_dependency(host_target)

# --- Wire the unit test target into the MiaoYan scheme so `xcodebuild test`
# against the existing `MiaoYan` scheme picks it up without users having to
# also wire a separate scheme. ---
shared_data_dir = File.join(PROJECT_PATH, 'xcshareddata', 'xcschemes')
scheme_path = File.join(shared_data_dir, 'MiaoYan.xcscheme')

if File.exist?(scheme_path)
  scheme = Xcodeproj::XCScheme.new(scheme_path)
  test_action = scheme.test_action
  already_wired = test_action.testables.any? { |t|
    t.buildable_references.any? { |br| br.target_name == 'MiaoYanTests' }
  }
  unless already_wired
    testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
    test_action.add_testable(testable)
    scheme.save_as(PROJECT_PATH, 'MiaoYan')
    puts "Wired MiaoYanTests into MiaoYan.xcscheme."
  end
else
  puts "WARNING: MiaoYan.xcscheme not found at #{scheme_path}. Skipping scheme wiring; create a Tests scheme manually."
end

project.save
puts "Done. MiaoYanTests target added with #{test_sources.size} source file(s)."
puts "Run: xcodebuild test -project MiaoYan.xcodeproj -scheme MiaoYan -destination 'platform=macOS'"
