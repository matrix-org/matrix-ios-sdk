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

#ifdef MX_CALL_STACK_JINGLE

#import <AVFoundation/AVFoundation.h>

@interface MXJingleVideoView ()
{
    /**
     The view in which MXJingleVideoView is displayed.
     */
    UIView *containerView;

    /**
     The contraints to display it with a keep fill aspect ratio.
     */
    NSLayoutConstraint *topConstraint;
    NSLayoutConstraint *leftConstraint;
    NSLayoutConstraint *bottomConstraint;
    NSLayoutConstraint *rightConstraint;

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
        self.translatesAutoresizingMaskIntoConstraints = NO;

        [containerView addSubview:self];

        // Make sure self follow 'containerView' size
        topConstraint = [NSLayoutConstraint
                         constraintWithItem:self
                         attribute:NSLayoutAttributeTop
                         relatedBy:NSLayoutRelationEqual
                         toItem:containerView
                         attribute:NSLayoutAttributeTop
                         multiplier:1.0f
                         constant:0];
        leftConstraint = [NSLayoutConstraint
                          constraintWithItem:self
                          attribute:NSLayoutAttributeLeft
                          relatedBy:NSLayoutRelationEqual
                          toItem:containerView
                          attribute:NSLayoutAttributeLeft
                          multiplier:1.0f
                          constant:0];
        bottomConstraint =[NSLayoutConstraint
                           constraintWithItem:self
                           attribute:NSLayoutAttributeBottom
                           relatedBy:0
                           toItem:containerView
                           attribute:NSLayoutAttributeBottom
                           multiplier:1.0
                           constant:0];
        rightConstraint =[NSLayoutConstraint
                          constraintWithItem:self
                          attribute:NSLayoutAttributeRight
                          relatedBy:0
                          toItem:containerView
                          attribute:NSLayoutAttributeRight
                          multiplier:1.0
                          constant:0];

        [NSLayoutConstraint activateConstraints:@[topConstraint, leftConstraint, bottomConstraint, rightConstraint]];
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

    // Compute the frame size to keep the aspect ratio in containerView
    CGRect videoFrame = AVMakeRectWithAspectRatioInsideRect(videoSize, containerView.frame);

    // Apply constraint so that the video is still  centered in containerView
    topConstraint.constant = (containerView.frame.size.height - videoFrame.size.height) / 2;
    bottomConstraint.constant = -topConstraint.constant;
    leftConstraint.constant = (containerView.frame.size.width - videoFrame.size.width) / 2;
    rightConstraint.constant = -leftConstraint.constant;
}

@end

#endif  // MX_CALL_STACK_JINGLE
