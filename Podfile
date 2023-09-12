use_frameworks!

MAC_TARGET_VERSION = '10.15'

def mac_pods
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
        config.build_settings['SWIFT_VERSION'] = '5.0'
        config.build_settings['CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER'] = 'NO'
        config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
        config.build_settings['DEAD_CODE_STRIPPING'] = 'YES'
        config.build_settings['CLANG_ENABLE_MODULE_VERIFIER'] = 'YES'
        config.build_settings['ENABLE_MODULE_VERIFIER'] = 'NO'
        config.build_settings['STRIP_INSTALLED_PRODUCT'] = 'YES'
        config.build_settings['STRIP_STYLE'] = 'all'
        config.build_settings['STRIP_SWIFT_SYMBOLS'] = 'YES'
        config.build_settings['COPY_PHASE_STRIP'] = 'NO'
        config.build_settings.delete('ARCHS')
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
