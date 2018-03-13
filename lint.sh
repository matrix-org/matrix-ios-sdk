#!/bin/sh

set -e
set -x

pod update

# Force lib lint on last Swift version
echo "4.1" > .swift-version

# Run CocoaPod lint in order to check pod submission
# Note: --allow-warnings should be removed once we fix our warnings with CallKit stuff only available from iOS10
pod lib lint MatrixSDK.podspec --use-libraries --allow-warnings
pod lib lint SwiftMatrixSDK.podspec --allow-warnings
