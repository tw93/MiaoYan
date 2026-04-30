#!/usr/bin/env ruby
# Adds the MiaoYanMobile iOS target to MiaoYan.xcodeproj
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../MiaoYan.xcodeproj', __dir__)
PROJECT_ROOT = File.expand_path('..', __dir__)

project = Xcodeproj::Project.open(PROJECT_PATH)

# Guard: don't add twice
if project.targets.any? { |t| t.name == 'MiaoYanMobile' }
  puts "Target MiaoYanMobile already exists, skipping."
  exit 0
end

# --- Create iOS application target ---
target = project.new_target(:application, 'MiaoYanMobile', :ios, '16.0')

target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']          = 'com.tw93.miaoyan.mobile'
  s['PRODUCT_NAME']                       = '$(TARGET_NAME)'
  s['SWIFT_VERSION']                      = '6.0'
  s['IPHONEOS_DEPLOYMENT_TARGET']         = '16.0'
  s['INFOPLIST_FILE']                     = 'MiaoYanMobile/Resources/Info.plist'
  s['TARGETED_DEVICE_FAMILY']             = '1,2'
  s['ENABLE_PREVIEWS']                    = 'YES'
  s['SWIFT_STRICT_CONCURRENCY']           = 'complete'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['CODE_SIGN_STYLE']                    = 'Automatic'
  s['DEVELOPMENT_TEAM']                   = ''
  s.delete('COMBINE_HIDPI_IMAGES')
end

# --- Source groups (group paths are directories, file paths relative to PROJECT_ROOT) ---
main_group     = project.main_group
mobile_group   = main_group.new_group('MiaoYanMobile', 'MiaoYanMobile')
app_group      = mobile_group.new_group('App', 'MiaoYanMobile/App')
views_group    = mobile_group.new_group('Views', 'MiaoYanMobile/Views')
services_group = mobile_group.new_group('Services', 'MiaoYanMobile/Services')
resources_group = mobile_group.new_group('Resources', 'MiaoYanMobile/Resources')

# Helper: add a file to a group, with path relative to PROJECT_ROOT, source_tree SOURCE_ROOT
def add_file(group, project_root, rel_path)
  ref = group.new_reference(File.join(project_root, rel_path))
  ref.path = rel_path
  ref.source_tree = 'SOURCE_ROOT'
  ref
end

# --- Swift source files ---
source_files = [
  ['MiaoYanMobile/App/MiaoYanMobileApp.swift', app_group],
  ['MiaoYanMobile/App/AppState.swift',          app_group],
  ['MiaoYanMobile/Views/FolderListView.swift',  views_group],
  ['MiaoYanMobile/Views/NotesListView.swift',   views_group],
  ['MiaoYanMobile/Views/NoteReaderView.swift',  views_group],
  ['MiaoYanMobile/Views/SearchView.swift',      views_group],
  ['MiaoYanMobile/Services/FileReader.swift',         services_group],
  ['MiaoYanMobile/Services/MobileHtmlRenderer.swift', services_group],
]

source_files.each do |rel_path, group|
  ref = add_file(group, PROJECT_ROOT, rel_path)
  target.source_build_phase.add_file_reference(ref)
end

# --- Resource files ---
css_ref = add_file(resources_group, PROJECT_ROOT, 'MiaoYanMobile/Resources/mobile-reader.css')
target.resources_build_phase.add_file_reference(css_ref)

plist_ref = add_file(resources_group, PROJECT_ROOT, 'MiaoYanMobile/Resources/Info.plist')
# Info.plist is referenced via INFOPLIST_FILE build setting, not added to resources phase

# --- CMarkGFM Swift Package dependency ---
cmark_pkg = project.root_object.package_references.find { |r|
  r.repositoryURL.to_s.include?('swift-cmark-gfm')
}

if cmark_pkg
  product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product_dep.package = cmark_pkg
  product_dep.product_name = 'CMarkGFM'
  target.package_product_dependencies << product_dep

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product_dep
  target.frameworks_build_phase.files << build_file
  puts "Linked CMarkGFM to MiaoYanMobile."
else
  puts "WARNING: swift-cmark-gfm package not found. Link CMarkGFM manually."
end

project.save
puts "Done. MiaoYanMobile target added to #{PROJECT_PATH}"
