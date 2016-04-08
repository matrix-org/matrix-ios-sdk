Pod::Spec.new do |s|

  s.name         = "MatrixSDK"
  s.version      = "0.6.5"
  s.summary      = "The iOS SDK to build apps compatible with Matrix (http://www.matrix.org)"

  s.description  = <<-DESC
				   Matrix is a new open standard for interoperable Instant Messaging and VoIP, providing pragmatic HTTP APIs and open source reference implementations for creating and running your own real-time communication infrastructure. 

				   Our hope is to make VoIP/IM as universal and interoperable as email.
                   DESC

  s.homepage     = "http://www.matrix.org"

  s.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE" }

  s.author             = { "matrix.org" => "support@matrix.org" }
  s.social_media_url   = "http://twitter.com/matrixdotorg"

  s.platform     = :ios, "7.0"

  s.source       = { :git => "https://github.com/matrix-org/matrix-ios-sdk.git", :tag => "v0.6.5" }
  s.source_files = "MatrixSDK", "MatrixSDK/**/*.{h,m}"
  s.resources    = "MatrixSDK/Data/Store/MXCoreDataStore/*.xcdatamodeld"

  s.frameworks   = "CoreData"

  s.requires_arc  = true

  s.dependency 'AFNetworking', '~> 2.6.0'

end
