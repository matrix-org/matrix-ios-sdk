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
    pod 'MatrixSDKCrypto', '0.4.3', :inhibit_warnings => true
    
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

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
