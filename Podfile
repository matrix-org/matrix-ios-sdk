# Uncomment this line to define a global platform for your project
# platform :ios, "6.0"

source 'https://github.com/CocoaPods/Specs.git'

target "MatrixSDK" do
    pod 'AFNetworking', '~> 2.5.2'
    pod 'Mantle', '~> 1.5'

    # There is no pod for OpenWebRTC-SDK. It must be git-cloned locally
    # See: https://github.com/EricssonResearch/openwebrtc-ios-sdk#usage
    # As 2015/05/06, checkout the master branch of the `openwebrtc-ios-sdk` repo
    pod 'OpenWebRTC', '~> 0.1'
    pod 'OpenWebRTC-SDK', :path => '../openwebrtc-ios-sdk/OpenWebRTC-SDK.podspec'

end

target "MatrixSDKTests" do

end

