use_frameworks!

MAC_TARGET_VERSION = '10.11'
IOS_TARGET_VERSION = '10'

def mac_pods
    pod 'MASShortcut', :git => 'https://github.com/shpakovski/MASShortcut.git', :branch => 'master'
    pod 'Sparkle', '~> 1.22.0'
end

def ios_pods
    pod 'NightNight', :git => 'https://github.com/draveness/NightNight.git', :branch => 'master'
    pod 'DKImagePickerController', '4.1.4'
    pod 'SSZipArchive', :git => 'https://github.com/ZipArchive/ZipArchive.git', :branch => 'master'
    pod 'DropDown', '2.3.13'
end

def common_pods
    pod 'Highlightr', :git => 'https://github.com/raspu/Highlightr.git', :branch => 'master'
    pod 'libcmark_gfm', :git => 'https://github.com/KristopherGBaker/libcmark_gfm.git', :branch => 'master'
    pod 'SSZipArchive', :git => 'https://github.com/ZipArchive/ZipArchive.git', :branch => 'master'
end

def framework_pods
    pod 'SwiftLint', '~> 0.47.0'
end

target 'MiaoYanCore macOS' do
    platform :osx, MAC_TARGET_VERSION
    pod 'MASShortcut', :git => 'https://github.com/shpakovski/MASShortcut.git', :branch => 'master'
    framework_pods
end

target 'MiaoYan' do
    platform :osx, MAC_TARGET_VERSION
    mac_pods
    common_pods
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    if target.name == 'cmark-gfm-swift-macOS'
      source_files = target.source_build_phase.files
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
