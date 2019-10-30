/*
 Copyright 2016 OpenMarket Ltd

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
#import <Foundation/Foundation.h>

#if __has_include(<WebRTC/WebRTC.h>)
#import <WebRTC/RTCEAGLVideoView.h>

NS_ASSUME_NONNULL_BEGIN

/**
 `MXJingleVideoView` is responsible for rendering RTCEAGLVideoView into
 a UIView container by keeping the aspect ratio of the video.

 @see https://developers.google.com/talk/libjingle/developer_guide
 */
NS_EXTENSION_UNAVAILABLE_IOS("Rendering not available in app extensions.")
@interface MXJingleVideoView : RTCEAGLVideoView <RTCVideoViewDelegate>

- (instancetype)initWithContainerView:(UIView *)containerView NS_DESIGNATED_INITIALIZER;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif
