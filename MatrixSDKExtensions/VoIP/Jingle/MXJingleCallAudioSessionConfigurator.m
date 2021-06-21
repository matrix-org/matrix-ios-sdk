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
 
 Some parts of the code were taken from WebRTC iOS SDK because there is no public API
 to configure AVAudioSession for calls. We need these functionality because of CallKit support.
 See: https://chromium.googlesource.com/external/webrtc/+/master/webrtc/sdk/objc/Framework/Classes/Audio/RTCAudioSessionConfiguration.m
 */

#import "MXJingleCallAudioSessionConfigurator.h"

@import AVFoundation;
@import WebRTC;

#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/utsname.h>

@implementation MXJingleCallAudioSessionConfigurator

- (void)configureAudioSessionForVideoCall:(BOOL)isVideoCall
{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    AVAudioSessionCategoryOptions desiredOptions = AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:desiredOptions
                        error:nil];
    
    // AVAudioSessionModeVideoChat is optimized for video calls on modern devices. Instead of using the speaker from the bottom
    // of the phone as it is for AVAudioSessionModeVoiceChat, it uses the speaker located near with buil-in receiver.
    // This really increases audio quality
    NSString *mode = isVideoCall ? AVAudioSessionModeVideoChat : AVAudioSessionModeVoiceChat;
    [audioSession setMode:mode error:nil];
    
    // Sometimes category options don't stick after setting mode.
    if (audioSession.categoryOptions != desiredOptions)
    {
        [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                      withOptions:desiredOptions
                            error:nil];
    }
    
    double sampleRate;
    double ioBufferDuration;
    
    // Set the session's sample rate or the hardware sample rate.
    // It is essential that we use the same sample rate as stream format
    // to ensure that the I/O unit does not have to do sample rate conversion.
    // Set the preferred audio I/O buffer duration, in seconds.
    NSUInteger processorCount = [NSProcessInfo processInfo].processorCount;
    
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *machineName = [NSString stringWithCString:systemInfo.machine
                                               encoding:NSUTF8StringEncoding];
    BOOL isIphone4S = [machineName isEqualToString:@"iPhone4,1"];
    
    // Use best sample rate and buffer duration if the CPU has more than one
    // core.
    if (processorCount > 1 && !isIphone4S)
    {
        sampleRate = kRTCAudioSessionHighPerformanceSampleRate;
        ioBufferDuration = kRTCAudioSessionHighPerformanceIOBufferDuration;
    }
    else
    {
        sampleRate = kRTCAudioSessionLowComplexitySampleRate;
        ioBufferDuration = kRTCAudioSessionLowComplexityIOBufferDuration;
    }
    
    [audioSession setPreferredSampleRate:sampleRate error:nil];
    [audioSession setPreferredIOBufferDuration:ioBufferDuration error:nil];
    
    // Initialize audio manually, activate audio only when needed
    RTCAudioSession.sharedInstance.useManualAudio = YES;
}

- (void)audioSessionDidActivate:(AVAudioSession *)audioSession
{
    // Finish audio session configuration. These properties can be set only after activation
    [audioSession setPreferredInputNumberOfChannels:kRTCAudioSessionPreferredNumberOfChannels error:nil];
    [audioSession setPreferredOutputNumberOfChannels:kRTCAudioSessionPreferredNumberOfChannels error:nil];
    
    [RTCAudioSession.sharedInstance audioSessionDidActivate:audioSession];
    RTCAudioSession.sharedInstance.isAudioEnabled = YES;
}

- (void)audioSessionDidDeactivate:(AVAudioSession *)audioSession
{
    [RTCAudioSession.sharedInstance audioSessionDidDeactivate:audioSession];
    RTCAudioSession.sharedInstance.isAudioEnabled = NO;
}

- (void)configureAudioSessionAfterCallEnds
{
    RTCAudioSession.sharedInstance.isAudioEnabled = NO;
    // Reset useManualAudio property to default value
    RTCAudioSession.sharedInstance.useManualAudio = NO;
}

@end
