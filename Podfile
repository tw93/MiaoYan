use_frameworks!

MAC_TARGET_VERSION = '11.5'

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
  xcode_base_version = `xcodebuild -version | grep 'Xcode' | awk '{print $2}' | cut -d . -f 1`
  installer.pods_project.targets.each do |project|
    project.build_configurations.each do |config|
        config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.5'
        config.build_settings['SWIFT_VERSION'] = '5.0'
        config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
        config.build_settings['DEAD_CODE_STRIPPING'] = 'YES'
        config.build_settings['ENABLE_MODULE_VERIFIER'] = 'NO'
        config.build_settings['STRIP_INSTALLED_PRODUCT'] = 'YES'
        # config.build_settings['STRIP_STYLE'] = 'all'
        config.build_settings['STRIP_SWIFT_SYMBOLS'] = 'YES'
        config.build_settings['COPY_PHASE_STRIP'] = 'NO'
        config.build_settings.delete('ARCHS')
        if config.base_configuration_reference && Integer(xcode_base_version) >= 15
                xcconfig_path = config.base_configuration_reference.real_path
                xcconfig = File.read(xcconfig_path)
                xcconfig_mod = xcconfig.gsub(/DT_TOOLCHAIN_DIR/, "TOOLCHAIN_DIR")
                File.open(xcconfig_path, "w") { |file| file << xcconfig_mod }
        end
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
