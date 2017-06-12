/*
 Copyright 2017 Vector Creations Ltd
 
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

#import "MXSDKOptions.h"

#ifdef MX_CALL_STACK_JINGLE

@class AVAudioSession;

/**
 This class helps to provide better integration level with CallKit for WebRTC
 */
@interface MXJingleCallAudioSessionConfigurator : NSObject

/**
 Applies appropriate settings to AVAudioSession
 
 @param isVideoCall: true if need configuration for video call, false if for voice call
 */
+ (void)configureAudioSessionForVideoCall:(BOOL)isVideoCall;

/**
 Performs necessary for WebRTC actions after audio session was activated
 
 @param audioSession: Instance of activated audio session
 */
+ (void)audioSessionDidActivated:(AVAudioSession *)audioSession;

/**
 Performs necessary for WebRTC actions after audio session was deactivated
 
 @param audioSession: Instance of deactivated audio session
 */
+ (void)audioSessionDidDeactivated:(AVAudioSession *)audioSession;

@end

#endif // MX_CALL_STACK_JINGLE
