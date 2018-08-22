Pod::Spec.new do |s|

  s.name         = "MatrixSDK"
  s.version      = "0.11.1"
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
  
  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.10"
  
  s.default_subspec = 'Core'
  s.subspec 'Core' do |ss|
      ss.ios.deployment_target = "8.0"
      ss.osx.deployment_target = "10.10"
      
      ss.source_files = "MatrixSDK", "MatrixSDK/**/*.{h,m}"
      
      ss.dependency 'AFNetworking', '~> 3.2.0'
      ss.dependency 'GZIP', '~> 1.2.1'

      # Requirements for e2e encryption
      ss.dependency 'OLMKit', '~> 2.3.0'
      ss.dependency 'Realm', '~> 3.7.4'
  end

  s.subspec 'JingleCallStack' do |ss|
    ss.ios.deployment_target = "9.0"
    
    ss.source_files  = "MatrixSDKExtensions/VoIP/Jingle/**/*.{h,m}"
    
    ss.dependency 'MatrixSDK/Core'
    
    # The Google WebRTC stack
    # Note: it is disabled because its framework does not embed x86 build which
    # prevents us from submitting the MatrixSDK pod
    #ss.ios.dependency 'GoogleWebRTC', '~>1.1.21820'
    
    # Use WebRTC build at https://github.com/Anakros/WebRTC instead
    ss.ios.dependency 'WebRTC', '63.11.20455'
  end
  

  # This podspec has been disabled because we cannot lint SwiftSupport subspec with static libraries.
  # pod lint returns:
  #
  # - ERROR | [iOS] [MatrixSDK/SwiftSupport] unknown: Encountered an unknown error (The following Swift pods cannot yet be integrated as static libraries:
  #
  # Please add "MatrixSDKExtensions/MXAnalyticsDelegate/GoogleAnalytics/**/*.{h,m}" files directly to your project and add 'GoogleAnalytics' pod to your podfile.

  # s.subspec 'GoogleAnalytics' do |ss|
  #   ss.ios.deployment_target = "8.0"
    
  #   ss.source_files  = "MatrixSDKExtensions/MXAnalyticsDelegate/GoogleAnalytics/**/*.{h,m}"
    
  #   ss.dependency 'MatrixSDK/Core'
    
  #   ss.ios.dependency 'GoogleAnalytics' 
  # end

  s.subspec 'SwiftSupport' do |ss|    
    ss.source_files = "MatrixSDK", "MatrixSDK/**/*.{swift}"
   
    ss.dependency 'MatrixSDK/Core'      
  end

end
