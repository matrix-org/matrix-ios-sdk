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

@implementation MXJingleVideoView

- (instancetype)initWithContainerView:(UIView *)containerView
{
    self = [super initWithFrame:containerView.frame];
    if (self)
    {
        // Use 'containerView' as the container of a RTCEAGLVideoView
        self.translatesAutoresizingMaskIntoConstraints = NO;

        [containerView addSubview:self];

        // Make sure self follow 'containerView' size
        NSLayoutConstraint *top = [NSLayoutConstraint
                                   constraintWithItem:self
                                   attribute:NSLayoutAttributeTop
                                   relatedBy:NSLayoutRelationEqual
                                   toItem:containerView
                                   attribute:NSLayoutAttributeTop
                                   multiplier:1.0f
                                   constant:0];
        NSLayoutConstraint *left = [NSLayoutConstraint
                                    constraintWithItem:self
                                    attribute:NSLayoutAttributeLeft
                                    relatedBy:NSLayoutRelationEqual
                                    toItem:containerView
                                    attribute:NSLayoutAttributeLeft
                                    multiplier:1.0f
                                    constant:0];
        NSLayoutConstraint *bottom =[NSLayoutConstraint
                                     constraintWithItem:self
                                     attribute:NSLayoutAttributeBottom
                                     relatedBy:0
                                     toItem:containerView
                                     attribute:NSLayoutAttributeBottom
                                     multiplier:1.0
                                     constant:0];
        NSLayoutConstraint *right =[NSLayoutConstraint
                                    constraintWithItem:self
                                    attribute:NSLayoutAttributeRight
                                    relatedBy:0
                                    toItem:containerView
                                    attribute:NSLayoutAttributeRight
                                    multiplier:1.0
                                    constant:0];


        [NSLayoutConstraint activateConstraints:@[top, left, bottom, right]];
    }

    self.delegate = self;
    
    return self;
}


#pragma mark - RTCEAGLVideoViewDelegate
- (void)videoView:(RTCEAGLVideoView *)videoView didChangeVideoSize:(CGSize)size
{
    // @TODO: Manage aspect ratio
    NSLog(@"### didChangeVideoSize: %@", NSStringFromCGSize(size));
}

@end

#endif  // MX_CALL_STACK_JINGLE
