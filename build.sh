#!/bin/sh

set -e
set -x

pod update
xcodebuild -workspace MatrixSDK.xcworkspace/ -scheme MatrixSDK -sdk iphonesimulator analyze
xcodebuild -workspace MatrixSDK.xcworkspace/ -scheme MatrixSDK -sdk iphoneos analyze
