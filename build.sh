#!/bin/sh

set -e
set -x

pod update

xcodebuild -workspace MatrixSDK.xcworkspace/ -scheme MatrixSDK -sdk iphonesimulator  -destination 'name=iPhone 5s'

# Dirty patch to make the Jenkins iOS builder happy (this mac is too old to install xcode 8.3)
echo "3.0" > .swift-version

# Run CocoaPod lint in order to check pod submission
# Note: --allow-warnings should be moved once AFNetworking is fixed (https://github.com/AFNetworking/AFNetworking/issues/3968)
pod lib lint --allow-warnings
