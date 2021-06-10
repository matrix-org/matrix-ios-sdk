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

#import "MXJingleCameraCaptureController.h"

#import "MXLog.h"
#import <WebRTC/RTCCameraVideoCapturer.h>

static const Float64 kFramerateLimit = 30.0;
static const int kDefaultResolutionWidth = 1280;
static const int kDefaultResolutionHeight = 720;

@interface MXJingleCameraCaptureController()

@property (nonatomic, strong) RTCCameraVideoCapturer *capturer;

@end

@implementation MXJingleCameraCaptureController

- (instancetype)initWithCapturer:(RTCCameraVideoCapturer *)capturer
{
    if (self = [super init])
    {
        _capturer = capturer;
        _cameraPosition = AVCaptureDevicePositionFront;
    }
    
    return self;
}

- (void)startCapture
{
    AVCaptureDevice *device = [self findDeviceForPosition:self.cameraPosition];
    AVCaptureDeviceFormat *format = [self selectFormatForDevice:device];
    
    if (format == nil)
    {
        MXLogDebug(@"[MXJingleCameraCaptureController] No valid formats for device %@", device);
        return;
    }
    
    NSInteger fps = [self selectFpsForFormat:format];
    
    MXLogDebug(@"[MXJingleCameraCaptureController] start capture with device: %@\nfps: %ld\nformat: %@", device.localizedName, (long)fps, format);
    
    [_capturer startCaptureWithDevice:device format:format fps:fps];
}

- (void)stopCapture
{
    [_capturer stopCapture];
}

- (void)setCameraPosition:(AVCaptureDevicePosition)cameraPosition
{
    if (cameraPosition != _cameraPosition)
    {
        _cameraPosition = cameraPosition;
        [self startCapture];
    }
}


#pragma mark - Private

- (AVCaptureDevice *)findDeviceForPosition:(AVCaptureDevicePosition)position
{
    NSArray<AVCaptureDevice *> *captureDevices = [RTCCameraVideoCapturer captureDevices];
    for (AVCaptureDevice *device in captureDevices)
    {
        if (device.position == position)
        {
            return device;
        }
    }
    return captureDevices.firstObject;
}

- (AVCaptureDeviceFormat *)selectFormatForDevice:(AVCaptureDevice *)device
{
    return [self selectFormatForDevice:device
                       withTargetWidth:kDefaultResolutionWidth
                       andTargetHeight:kDefaultResolutionHeight];
}

- (AVCaptureDeviceFormat *)selectFormatForDevice:(AVCaptureDevice *)device withTargetWidth:(int)targetWidth andTargetHeight:(int)targetHeight
{
    NSArray<AVCaptureDeviceFormat *> *formats = [RTCCameraVideoCapturer supportedFormatsForDevice:device];
    AVCaptureDeviceFormat *selectedFormat = nil;
    int currentDiff = INT_MAX;
    
    for (AVCaptureDeviceFormat *format in formats)
    {
        CMVideoDimensions dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        FourCharCode pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription);
        int diff = abs(targetWidth - dimension.width) + abs(targetHeight - dimension.height);
        if (diff < currentDiff)
        {
            selectedFormat = format;
            currentDiff = diff;
        }
        else if (diff == currentDiff && pixelFormat == [_capturer preferredOutputPixelFormat])
        {
            selectedFormat = format;
        }
    }
    
    return selectedFormat;
}

- (NSInteger)selectFpsForFormat:(AVCaptureDeviceFormat *)format
{
    Float64 maxSupportedFramerate = 0;
    for (AVFrameRateRange *fpsRange in format.videoSupportedFrameRateRanges)
    {
        maxSupportedFramerate = fmax(maxSupportedFramerate, fpsRange.maxFrameRate);
    }
    return fmin(maxSupportedFramerate, kFramerateLimit);
}

@end
