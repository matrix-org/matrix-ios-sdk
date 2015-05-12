# Uncomment this line to define a global platform for your project
# platform :ios, "6.0"

source 'https://github.com/CocoaPods/Specs.git'

target "MatrixSDK" do
    pod 'AFNetworking', '~> 2.5.2'
    pod 'Mantle', '~> 1.5'

    # There is no pod for OpenWebRTC-SDK. Use the master branch from github
    # As of 2015/05/06, it works
    pod 'OpenWebRTC', '~> 0.1'
    pod 'OpenWebRTC-SDK', :git => 'https://github.com/EricssonResearch/openwebrtc-ios-sdk.git', :branch => 'master'

end

target "MatrixSDKTests" do

end

# Temp hack while https://github.com/EricssonResearch/openwebrtc-examples/issues/79 is not fixed
post_install do |installer_representation|
    installer_representation.project.targets.each do |target|
        if target.name == 'Pods-MatrixSDK-OpenWebRTC-SDK'

            puts "  Temporary hack in #{target.name} pod:"
            puts "  Disable OpenWebRTC code as it does not build for iOS Simulator (https://github.com/EricssonResearch/openwebrtc-examples/issues/79):"
        
            target.source_build_phase.files.each do |build_file|
                puts "    - Removing code in #{build_file.file_ref}"
                
                # Need to have write permission on the file
                new_permissions = File.stat(build_file.file_ref.real_path).mode | 0222
                File.chmod(new_permissions, build_file.file_ref.real_path)
                
                File.open(build_file.file_ref.real_path, 'w').write("/* Removed OpenWebRTC-SDK pod code because it does not build for iOS Simulator. See: https://github.com/EricssonResearch/openwebrtc-examples/issues/79 */")
            end   
        end
    end
end

