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
target = project.new_target(:application, 'MiaoYanMobile', :ios, '18.0')

project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][target.uuid] = {
  'CreatedOnToolsVersion' => '26.0',
  'SystemCapabilities' => {
    'com.apple.iCloud' => { 'enabled' => 1 },
  },
}

target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']          = 'com.tw93.miaoyan'
  s['PRODUCT_NAME']                       = '$(TARGET_NAME)'
  s['SWIFT_VERSION']                      = '6.0'
  s['IPHONEOS_DEPLOYMENT_TARGET']         = '18.0'
  s['CURRENT_PROJECT_VERSION']            = '4.0.0'
  s['MARKETING_VERSION']                  = '4.0.0'
  s['INFOPLIST_FILE']                     = 'MiaoYanMobile/Resources/Info.plist'
  s['INFOPLIST_KEY_CFBundleDisplayName']  = 'MiaoYan'
  s['INFOPLIST_KEY_LSApplicationCategoryType'] = 'public.app-category.productivity'
  s['TARGETED_DEVICE_FAMILY']             = '1,2'
  s['ENABLE_PREVIEWS']                    = 'YES'
  s['SWIFT_STRICT_CONCURRENCY']           = 'complete'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'app'
  s['CODE_SIGN_ENTITLEMENTS']             = 'MiaoYanMobile.entitlements'
  s['CODE_SIGN_STYLE']                    = 'Automatic'
  s['DEVELOPMENT_TEAM']                   = '5EH69Y5X38'
  s['MACOSX_DEPLOYMENT_TARGET']           = '11.0'
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
  ['MiaoYanMobile/Views/NoteEditorView.swift',  views_group],
  ['MiaoYanMobile/Views/NoteDetailView.swift',  views_group],
  ['MiaoYanMobile/Views/NewNoteView.swift',     views_group],
  ['MiaoYanMobile/Views/NoteReaderView.swift',  views_group],
  ['MiaoYanMobile/Views/SearchView.swift',      views_group],
  ['MiaoYanMobile/Services/CloudSyncManager.swift',    services_group],
  ['MiaoYanMobile/Services/FileReader.swift',         services_group],
  ['MiaoYanMobile/Services/MobileHtmlRenderer.swift', services_group],
  ['MiaoYanMobile/Services/RecentNotesCache.swift',   services_group],
]

source_files.each do |rel_path, group|
  ref = add_file(group, PROJECT_ROOT, rel_path)
  target.source_build_phase.add_file_reference(ref)
end

# --- Resource files ---
resource_files = [
  'Resources/app.icon',
  'MiaoYanMobile/Resources/mobile-reader.css',
  'MiaoYanMobile/Resources/MobileAssets.xcassets',
  'MiaoYanMobile/Resources/Localizable.xcstrings',
  'MiaoYanMobile/Resources/InfoPlist.xcstrings',
  'MiaoYanMobile/Resources/PrivacyInfo.xcprivacy',
]

resource_files.each do |rel_path|
  ref = add_file(resources_group, PROJECT_ROOT, rel_path)
  target.resources_build_phase.add_file_reference(ref)
end

add_file(resources_group, PROJECT_ROOT, 'MiaoYanMobile/Resources/Info.plist')
add_file(resources_group, PROJECT_ROOT, 'MiaoYanMobile.entitlements')
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
