Pod::Spec.new do |s|

  s.name         = "MatrixSDK"
  s.version      = "0.27.17"
  s.summary      = "The iOS SDK to build apps compatible with Matrix (https://www.matrix.org)"

  s.description  = <<-DESC
				   Matrix is a new open standard for interoperable Instant Messaging and VoIP, providing pragmatic HTTP APIs and open source reference implementations for creating and running your own real-time communication infrastructure.

				   Our hope is to make VoIP/IM as universal and interoperable as email.
                   DESC

  s.homepage     = "https://www.matrix.org"

  s.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE" }

  s.author             = { "matrix.org" => "support@matrix.org" }
  s.social_media_url   = "http://twitter.com/matrixdotorg"

  s.source       = { :git => "https://github.com/matrix-org/matrix-ios-sdk.git", :tag => "v#{s.version}" }
  
  s.requires_arc  = true
  s.swift_versions = ['5.1', '5.2']
  
  s.ios.deployment_target = "13.0"
  s.osx.deployment_target = "10.15"
  
  s.default_subspec = 'Core'
  s.subspec 'Core' do |ss|
      ss.ios.deployment_target = "13.0"
      ss.osx.deployment_target = "10.15"
      
      ss.source_files = "MatrixSDK", "MatrixSDK/**/*.{h,m}", "MatrixSDK/**/*.{swift}"
      ss.osx.exclude_files = "MatrixSDK/VoIP/MXiOSAudioOutputRoute*.swift"
      ss.private_header_files = ['MatrixSDK/MatrixSDKSwiftHeader.h', "MatrixSDK/**/*_Private.h"]
      ss.resources = "MatrixSDK/**/*.{xcdatamodeld}"
      ss.frameworks = "CoreData"

      ss.dependency 'AFNetworking', '~> 4.0.0'
      ss.dependency 'GZIP', '~> 1.3.0'

      ss.dependency 'SwiftyBeaver', '1.9.5'

      # Requirements for e2e encryption
      ss.dependency 'Realm', '10.27.0'
      ss.dependency 'libbase58', '~> 0.1.4'
      ss.dependency 'MatrixSDKCrypto', '0.4.3', :configurations => ["DEBUG", "RELEASE"], :inhibit_warnings => true
  end

  s.subspec 'JingleCallStack' do |ss|
    ss.ios.deployment_target = "13.0"
    
    ss.source_files  = "MatrixSDKExtensions/VoIP/Jingle/**/*.{h,m}"
    
    ss.dependency 'MatrixSDK/Core'
    
    # The Google WebRTC stack
    # Note: it is disabled because its framework does not embed x86 build which
    # prevents us from submitting the MatrixSDK pod
    #ss.ios.dependency 'GoogleWebRTC', '~>1.1.21820'
    
    # Use WebRTC framework included in Jitsi Meet SDK
    # Use the lite version so we don't add a dependency on Giphy.
    ss.ios.dependency 'JitsiMeetSDKLite', '8.1.2-lite'
  end

end
