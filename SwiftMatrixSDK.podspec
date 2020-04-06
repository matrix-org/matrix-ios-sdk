Pod::Spec.new do |s|

  s.name         = "SwiftMatrixSDK"
  s.version      = "0.15.2"
  s.summary      = "The iOS SDK to build apps compatible with Matrix (https://www.matrix.org)"

  s.description  = <<-DESC
				   Matrix is a new open standard for interoperable Instant Messaging and VoIP, providing pragmatic HTTP APIs and open source reference implementations for creating and running your own real-time communication infrastructure.

				   Our hope is to make VoIP/IM as universal and interoperable as email.
                   DESC

  s.homepage     = "https://www.matrix.org"

  s.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE" }

  s.author             = { "matrix.org" => "support@matrix.org" }
  s.social_media_url   = "http://twitter.com/matrixdotorg"

  s.swift_version = '5.0'

  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.10"

  s.source       = { :git => "https://github.com/matrix-org/matrix-ios-sdk.git", :tag => "v#{s.version}" }
  s.source_files = "MatrixSDK", "MatrixSDK/**/*.{h,m,swift}"

  s.requires_arc  = true

  s.dependency 'AFNetworking', '~> 4.0.0'
  s.dependency 'GZIP', '~> 1.2.2'
  
  # Requirements for e2e encryption
  s.dependency 'OLMKit', '~> 3.1.0'
  s.dependency 'Realm', '~> 4.4.0'
  s.dependency 'libbase58', '~> 0.1.4'

end
