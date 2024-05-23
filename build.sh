#!/bin/sh

set -e
set -x

pod install

if [ $1 == 'xcframework' ]	# optionally supports additional arguments for CFBundleShortVersionString and CFBundleVersion
then
	# archive the framework for iOS, macOS, Catalyst and the Simulator
	xcodebuild archive -workspace MatrixSDK.xcworkspace -scheme MatrixSDK-iOS -destination "generic/platform=iOS" -archivePath build/MatrixSDK-iOS SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES IPHONEOS_DEPLOYMENT_TARGET=13.0 GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS=NO MARKETING_VERSION=$2 CURRENT_PROJECT_VERSION=$3
	xcodebuild archive -workspace MatrixSDK.xcworkspace -scheme MatrixSDK-iOS -destination "generic/platform=iOS Simulator" -archivePath build/MatrixSDK-iOSSimulator SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES IPHONEOS_DEPLOYMENT_TARGET=13.0 GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS=NO MARKETING_VERSION=$2 CURRENT_PROJECT_VERSION=$3
	xcodebuild archive -workspace MatrixSDK.xcworkspace -scheme MatrixSDK-macOS -destination "generic/platform=macOS" -archivePath build/MatrixSDK-macOS SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES MACOSX_DEPLOYMENT_TARGET=10.10 GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS=NO MARKETING_VERSION=$2 CURRENT_PROJECT_VERSION=$3
	xcodebuild archive -workspace MatrixSDK.xcworkspace -scheme MatrixSDK-iOS -destination "generic/platform=macOS,variant=Mac Catalyst" -archivePath ./build/MatrixSDK-MacCatalyst SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES IPHONEOS_DEPLOYMENT_TARGET=13.0 GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS=NO MARKETING_VERSION=$2 CURRENT_PROJECT_VERSION=$3

	cd build

	# clean xcframework artifacts
	if [ -d 'MatrixSDK.xcframework' ]; then rm -rf MatrixSDK.xcframework; fi
	if [ -f 'MatrixSDK.xcframework.zip' ]; then rm -rf MatrixSDK.xcframework.zip; fi

	# build and zip the xcframework
	xcodebuild -create-xcframework \
		-framework MatrixSDK-iOS.xcarchive/Products/Library/Frameworks/MatrixSDK.framework \
		-debug-symbols ${PWD}/MatrixSDK-iOS.xcarchive/dSYMs/MatrixSDK.framework.dSYM \
		-debug-symbols ${PWD}/MatrixSDK-iOS.xcarchive/BCSymbolMaps/*.bcsymbolmap \
		-framework MatrixSDK-iOSSimulator.xcarchive/Products/Library/Frameworks/MatrixSDK.framework \
		-debug-symbols ${PWD}/MatrixSDK-iOSSimulator.xcarchive/dSYMs/MatrixSDK.framework.dSYM \
		-framework MatrixSDK-macOS.xcarchive/Products/Library/Frameworks/MatrixSDK.framework \
		-framework MatrixSDK-MacCatalyst.xcarchive/Products/Library/Frameworks/MatrixSDK.framework \
		-output MatrixSDK.xcframework
	zip -ry MatrixSDK.xcframework.zip MatrixSDK.xcframework
else
	xcodebuild -workspace MatrixSDK.xcworkspace/ -scheme MatrixSDK -sdk iphonesimulator  -destination 'name=iPhone 5s'
fi