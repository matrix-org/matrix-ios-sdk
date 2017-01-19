# Uncomment this line to define a global platform for your project
# platform :ios, "6.0"

source 'https://github.com/CocoaPods/Specs.git'

target "MatrixSDK" do
pod 'AFNetworking', '~> 3.1.0'

pod 'OLMKit'
#pod 'OLMKit', :path => '../olm/OLMKit.podspec'

# This fork of OLMKit changes the way the OLMKitVersionString is exposed.
# This change is necessary to work around a compiler error that occurs when
# both MatrixSDK and OLMKit pods are included in a project with use_frameworks! enabled.
#pod 'OLMKit', :git => 'https://github.com/aapierce0/OLMKit.git', :branch => 'OLMKit-xcode-framework-compatibility'

pod 'Realm', '~> 2.1.1'

end

target "MatrixSDKTests" do

end

