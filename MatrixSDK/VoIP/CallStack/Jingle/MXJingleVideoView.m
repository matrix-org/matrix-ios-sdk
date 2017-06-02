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

#import "MXJingleVideoView.h"

#import <AVFoundation/AVFoundation.h>

@interface MXJingleVideoView ()
{
    /**
     The view in which MXJingleVideoView is displayed.
     */
    UIView *containerView;
    
    /**
     The original size of the rendered video.
     */
    CGSize videoSize;
}

@end

@implementation MXJingleVideoView

- (instancetype)initWithContainerView:(UIView *)theContainerView
{
    self = [super initWithFrame:theContainerView.frame];
    if (self)
    {
        containerView = theContainerView;
        
        videoSize = containerView.frame.size;
        
        // Use 'containerView' as the container of a RTCEAGLVideoView
        [containerView addSubview:self];
    }

    self.delegate = self;

    return self;
}

- (void)layoutSubviews
{
    [self videoView:self didChangeVideoSize:videoSize];

    [super layoutSubviews];
}

#pragma mark - RTCEAGLVideoViewDelegate
- (void)videoView:(RTCEAGLVideoView *)videoView didChangeVideoSize:(CGSize)size
{
    videoSize = size;
    
    CGSize containerFrameSize = containerView.frame.size;
    BOOL isLandscapeContainer = (containerFrameSize.height < containerFrameSize.width);
    
    BOOL isLandscapeVideo = (videoSize.height < videoSize.width);
    
    // Check whether the video source is in the same orientation than its container
    if (isLandscapeVideo == isLandscapeContainer)
    {
        CGFloat ratioX, ratioY;
        CGFloat scale;
        CGSize  scaledVideoSize = CGSizeMake(videoSize.width, videoSize.height);
        
        ratioX = containerFrameSize.width  / videoSize.width;
        ratioY = containerFrameSize.height / videoSize.height;
        
        scale = MAX(ratioX, ratioY);
        
        scaledVideoSize.width  *= scale;
        scaledVideoSize.height *= scale;
        
        // padding
        scaledVideoSize.width  = floorf(scaledVideoSize.width  / 2) * 2;
        scaledVideoSize.height = floorf(scaledVideoSize.height / 2) * 2;
        
        CGRect frame = self.frame;
        frame.size = scaledVideoSize;
        frame.origin = CGPointMake((containerFrameSize.width - scaledVideoSize.width) / 2, (containerFrameSize.height - scaledVideoSize.height) / 2);
        self.frame = frame;
    }
    else
    {
        CGRect containerFrame = containerView.frame;
        containerFrame.origin = CGPointZero;
        
        // Compute the frame size to keep the aspect ratio in containerView
        self.frame = AVMakeRectWithAspectRatioInsideRect(videoSize, containerFrame);
    }
}

@end
