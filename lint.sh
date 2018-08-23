#!/bin/sh

set -e
set -x

pod update

# Force lib lint on last Swift version
echo "4.1" > .swift-version

# Run CocoaPod lint in order to check pod submission
bundle exec fastlane lint_pods
