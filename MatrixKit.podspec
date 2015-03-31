Pod::Spec.new do |s|

  s.name         = "MatrixKit"
  s.version      = "0.0.1"
  s.summary      = "The Matrix reusable UI library for iOS based on MatrixSDK."

  s.description  = <<-DESC
					Matrix Kit provides basic reusable interfaces to ease building of apps compatible with Matrix (http://www.matrix.org).
                   DESC

  s.homepage     = "http://www.matrix.org"

  s.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE" }

  s.author             = { "matrix.org" => "support@matrix.org" }
  s.social_media_url   = "http://twitter.com/matrixdotorg"

  s.platform     = :ios, "7.0"

  s.source       = { :git => "https://github.com/matrix-org/matrix-ios-sdk.git", :tag => "v0.0.1" }
  s.source_files  = "MatrixKit", "MatrixKit/MatrixKit/**/*.{h,m}"
  s.resources	 = 'MatrixKit/MatrixKit/**/*.{xib}'
  
  s.requires_arc  = true

  #s.dependency 'MatrixSDK', '~> 0.3.1'
  s.dependency 'HPGrowingTextView', '~> 1.1'

end
