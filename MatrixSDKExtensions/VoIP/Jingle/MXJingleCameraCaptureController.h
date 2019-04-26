/*
 Copyright 2019 New Vector Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

@import AVFoundation;

@class RTCCameraVideoCapturer;

/**
 `MXJingleCameraCaptureController` controls the WebRTC camera capture.
 
 Based on `ARDCaptureController` from iOS WebRTC sample app.
 @see https://github.com/WebKit/webkit/blob/master/Source/ThirdParty/libwebrtc/Source/webrtc/examples/objc/AppRTCMobile/ARDCaptureController.h
 */
NS_EXTENSION_UNAVAILABLE_IOS("Camera not available in app extensions.")
@interface MXJingleCameraCaptureController : NSObject

/**
 Change camera position.
 */
@property (nonatomic) AVCaptureDevicePosition cameraPosition;


/**
 Initialize with a camera video capturer.

 @param capturer WebRTC camera video capturer.
 @return A `MXJingleCameraCaptureController` instance.
 */
- (instancetype)initWithCapturer:(RTCCameraVideoCapturer *)capturer;

- (instancetype)init NS_UNAVAILABLE;

/**
 Start camera capture.
 */
- (void)startCapture;

/**
 Stop camera capture.
 */
- (void)stopCapture;

@end
