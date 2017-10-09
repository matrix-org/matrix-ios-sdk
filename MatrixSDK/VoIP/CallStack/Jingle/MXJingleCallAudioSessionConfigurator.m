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

#if defined MX_CALL_STACK_JINGLE && TARGET_OS_IPHONE

@import AVFoundation;

#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/utsname.h>

// Preferred hardware sample rate (unit is in Hertz). The client sample rate
// will be set to this value as well to avoid resampling the the audio unit's
// format converter. Note that, some devices, e.g. BT headsets, only supports
// 8000Hz as native sample rate.
static const double kRTCAudioSessionHighPerformanceSampleRate = 48000.0;

// A lower sample rate will be used for devices with only one core
// (e.g. iPhone 4). The goal is to reduce the CPU load of the application.
static const double kRTCAudioSessionLowComplexitySampleRate = 16000.0;

// Use a hardware I/O buffer size (unit is in seconds) that matches the 10ms
// size used by WebRTC. The exact actual size will differ between devices.
// Example: using 48kHz on iPhone 6 results in a native buffer size of
// ~10.6667ms or 512 audio frames per buffer. The FineAudioBuffer instance will
// take care of any buffering required to convert between native buffers and
// buffers used by WebRTC. It is beneficial for the performance if the native
// size is as close to 10ms as possible since it results in "clean" callback
// sequence without bursts of callbacks back to back.
static const double kRTCAudioSessionHighPerformanceIOBufferDuration = 0.01;

// Use a larger buffer size on devices with only one core (e.g. iPhone 4).
// It will result in a lower CPU consumption at the cost of a larger latency.
// The size of 60ms is based on instrumentation that shows a significant
// reduction in CPU load compared with 10ms on low-end devices.
// TODO(henrika): monitor this size and determine if it should be modified.
static const double kRTCAudioSessionLowComplexityIOBufferDuration = 0.06;

// Try to use mono to save resources. Also avoids channel format conversion
// in the I/O audio unit. Initial tests have shown that it is possible to use
// mono natively for built-in microphones and for BT headsets but not for
// wired headsets. Wired headsets only support stereo as native channel format
// but it is a low cost operation to do a format conversion to mono in the
// audio unit. Hence, we will not hit a RTC_CHECK in
// VerifyAudioParametersForActiveAudioSession() for a mismatch between the
// preferred number of channels and the actual number of channels.
static const int kRTCAudioSessionPreferredNumberOfChannels = 1;

@implementation MXJingleCallAudioSessionConfigurator

- (void)configureAudioSessionForVideoCall:(BOOL)isVideoCall
{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:AVAudioSessionCategoryOptionAllowBluetooth
                        error:nil];
    
    // AVAudioSessionModeVideoChat is optimized for video calls on modern devices. Instead of using the speaker from the bottom
    // of the phone as it is for AVAudioSessionModeVoiceChat, it uses the speaker located near with buil-in receiver.
    // This really increases audio quality
    NSString *mode = isVideoCall ? AVAudioSessionModeVideoChat : AVAudioSessionModeVoiceChat;
    [audioSession setMode:mode error:nil];
    
    // Sometimes category options don't stick after setting mode.
    if (audioSession.categoryOptions != AVAudioSessionCategoryOptionAllowBluetooth)
    {
        [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                      withOptions:AVAudioSessionCategoryOptionAllowBluetooth
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
}

- (void)audioSessionDidActivate:(AVAudioSession *)audioSession
{
    // Finish audio session configuration. These properties can be set only after activation
    [audioSession setPreferredInputNumberOfChannels:kRTCAudioSessionPreferredNumberOfChannels error:nil];
    [audioSession setPreferredOutputNumberOfChannels:kRTCAudioSessionPreferredNumberOfChannels error:nil];
    
    // Guys from Google have their own mind on priority of task devoted to make RTCAudioSession public to use.
    // https://bugs.chromium.org/p/webrtc/issues/detail?id=7351
    //
    // They had already implemented neccesary methods to make it possible for WebRTC to work with CallKit. They will be available in v.60.
    // https://bugs.chromium.org/p/webrtc/issues/detail?id=7446
    //
    // We use a bit of Obj-C runtime power and call neccesary methods on our own.
    // It's safe since all necessary checks are performed.
    // In the future when RTCAudioSession will become public we will switch to use methods directly.
    //
    // The reason of this runtime magic is that OS activates audio session earlier than it does WebRTC, it's worth mention that
    // activation of audio session is expensive operation and it's better to avoid doing job twice
    
    Class cls = objc_getClass("RTCAudioSession");
    Class metaCls = objc_getMetaClass("RTCAudioSession");
    
    SEL selSharedInstance = NSSelectorFromString(@"sharedInstance");
    SEL selIncrementActivationCount = NSSelectorFromString(@"incrementActivationCount");
    SEL selSetIsActive = NSSelectorFromString(@"setIsActive:");
    
    if (cls &&
        metaCls &&
        class_respondsToSelector(metaCls, selSharedInstance) &&
        class_respondsToSelector(cls, selIncrementActivationCount) &&
        class_respondsToSelector(cls, selSetIsActive))
    {
        id rtcAudioSession = ((id (*)(id, SEL))objc_msgSend)(cls, selSharedInstance);
        ((void (*)(id, SEL))objc_msgSend)(rtcAudioSession, selIncrementActivationCount);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(rtcAudioSession, selSetIsActive, YES);
    }
}

- (void)audioSessionDidDeactivate:(AVAudioSession *)audioSession
{
    Class cls = objc_getClass("RTCAudioSession");
    Class metaCls = objc_getMetaClass("RTCAudioSession");
    
    SEL selSharedInstance = NSSelectorFromString(@"sharedInstance");
    SEL selDecrementActivationCount = NSSelectorFromString(@"decrementActivationCount");
    SEL selSetIsActive = NSSelectorFromString(@"setIsActive:");
    
    if (cls &&
        metaCls &&
        class_respondsToSelector(metaCls, selSharedInstance) &&
        class_respondsToSelector(cls, selDecrementActivationCount) &&
        class_respondsToSelector(cls, selSetIsActive))
    {
        id rtcAudioSession = ((id (*)(id, SEL))objc_msgSend)(cls, selSharedInstance);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(rtcAudioSession, selSetIsActive, NO);
        ((void (*)(id, SEL))objc_msgSend)(rtcAudioSession, selDecrementActivationCount);
    }
}

@end

#endif // MX_CALL_STACK_JINGLE && TARGET_OS_IPHONE
