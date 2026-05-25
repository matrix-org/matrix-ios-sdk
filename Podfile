source 'https://cdn.cocoapods.org/'

# Uncomment this line to define a global platform for your project

# Expose Objective-C frameworks to Swift
# Build and link dependencies as static frameworks
use_frameworks! :linkage => :static

abstract_target 'MatrixSDK' do
    
    pod 'AFNetworking', '~> 4.0.0'
    pod 'GZIP', '~> 1.3.0'

    pod 'SwiftyBeaver', '1.9.5'
    
    pod 'Realm', '10.27.0'
    pod 'libbase58', '~> 0.1.4'
    pod 'MatrixSDKCrypto', '0.11.1', :inhibit_warnings => true
    
    target 'MatrixSDK-iOS' do
        platform :ios, '13.0'
        
        target 'MatrixSDKTests-iOS' do
            inherit! :search_paths
            pod 'OHHTTPStubs', '~> 9.1.0'
        end
    end
    
    target 'MatrixSDK-macOS' do
        platform :osx, '10.15'

        target 'MatrixSDKTests-macOS' do
            inherit! :search_paths
            pod 'OHHTTPStubs', '~> 9.1.0'
        end
    end
end

# from here: https://juejin.cn/post/7621018086649430025
def patch_afnetworking_private_header(installer)
  # 扫描并移除 AFNetworking 对私有 IPv6 头文件的直接引用，兼容新版 Xcode 的模块校验。
  afnetworking_dir = File.join(installer.sandbox.pod_dir('AFNetworking'), 'AFNetworking')
  return unless Dir.exist?(afnetworking_dir)

  private_header_import = '#import <netinet6/in6.h>'
  Dir.glob(File.join(afnetworking_dir, '**', '*.{h,m}')).each do |file_path|
    #next unless mcs_file_exists(file_path)

    file_content = File.read(file_path)
    next unless file_content.include?(private_header_import)

    original_mode = File.stat(file_path).mode
    File.chmod(original_mode | 0o200, file_path)
    File.write(file_path, file_content.gsub(private_header_import, ''))
    File.chmod(original_mode, file_path)
    puts "patched AFNetworking private header import: #{File.basename(file_path)}"
  end
end

post_install do |installer|
  patch_afnetworking_private_header(installer)

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
