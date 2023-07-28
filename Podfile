use_frameworks!

MAC_TARGET_VERSION = '10.15'

def mac_pods
    pod 'MASShortcut'
    pod 'Sparkle'
    pod 'AppCenter'
    pod 'Alamofire'
    pod 'SwiftyJSON'
    pod 'Highlightr'
    pod 'libcmark_gfm'
    pod 'SSZipArchive'
    pod 'SwiftLint'
    pod 'MASShortcut'
end


target 'MiaoYan' do
    platform :osx, MAC_TARGET_VERSION
    mac_pods
end

post_install do |installer|
  installer.pods_project.targets.each do |project|
    
    project.build_configurations.each do |config|
        config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.15'
    end
    
    if project.name == 'cmark-gfm-swift-macOS'
      source_files = project.source_build_phase.files
      dummy = source_files.find do |file|
        file.file_ref.name == 'scanners.re'
      end
      source_files.delete dummy

      dummyM = source_files.find do |file|
        file.file_ref.name == 'module.modulemap'
      end
      source_files.delete dummyM
      puts "Deleting source file #{dummy.inspect} from target #{target.inspect}."
    end
  end
end

install! 'cocoapods', :deterministic_uuids => false

# ignore all warnings from all pods
inhibit_all_warnings!
