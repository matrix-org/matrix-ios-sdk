/*
 Copyright 2015 OpenMarket Ltd

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

#import "MXKRoomInputToolbarViewWithHPGrowingText.h"

@interface MXKRoomInputToolbarViewWithHPGrowingText() {
    // The growing text view used as text composer
    HPGrowingTextView *growingTextView;
    
    // HPGrowingTextView triggers growingTextViewDidChange event when it recomposes itself
    // Save the last edited text to prevent unexpected typing events
    NSString* lastEditedText;
}

@end

@implementation MXKRoomInputToolbarViewWithHPGrowingText

- (instancetype) init {
    self = [super init];
    if (self) {
        // Customize here toolbar buttons
        
        // Remove default composer
        self.defaultMessageComposerTextView.delegate = nil;
        [self.defaultMessageComposerTextView removeFromSuperview];
        self.defaultMessageComposerTextView  = nil;
        
        // Add customized message composer based on HPGrowingTextView use
        CGRect frame = messageComposerContainer.frame;
        frame.origin.x = frame.origin.y = 0;
        growingTextView = [[HPGrowingTextView alloc] initWithFrame:frame];
        growingTextView.delegate = self;
        
        // set text input font
        growingTextView.font = [UIFont systemFontOfSize:14];
        
        // draw a rounded border around the textView
        growingTextView.layer.cornerRadius = 5;
        growingTextView.layer.borderWidth = 1;
        growingTextView.layer.borderColor = [UIColor lightGrayColor].CGColor;
        growingTextView.clipsToBounds = YES;
        growingTextView.backgroundColor = [UIColor whiteColor];
        // on IOS 8, the growing textview animation could trigger weird UI animations
        // indeed, the messages tableView can be refreshed while its height is updated (e.g. when setting a message)
        growingTextView.animateHeightChange = NO;
        
        // Add the text composer by setting its edge constraints compare to the container.
        [messageComposerContainer addSubview:growingTextView];
        [messageComposerContainer addConstraint:[NSLayoutConstraint constraintWithItem:messageComposerContainer
                                                                               attribute:NSLayoutAttributeBottom
                                                                               relatedBy:NSLayoutRelationEqual
                                                                                  toItem:growingTextView
                                                                               attribute:NSLayoutAttributeBottom
                                                                              multiplier:1.0f
                                                                                constant:0.0f]];
        [messageComposerContainer addConstraint:[NSLayoutConstraint constraintWithItem:messageComposerContainer
                                                                               attribute:NSLayoutAttributeTop
                                                                               relatedBy:NSLayoutRelationEqual
                                                                                  toItem:growingTextView
                                                                               attribute:NSLayoutAttributeTop
                                                                              multiplier:1.0f
                                                                                constant:0.0f]];
        [messageComposerContainer addConstraint:[NSLayoutConstraint constraintWithItem:messageComposerContainer
                                                                               attribute:NSLayoutAttributeLeading
                                                                               relatedBy:NSLayoutRelationEqual
                                                                                  toItem:growingTextView
                                                                               attribute:NSLayoutAttributeLeading
                                                                              multiplier:1.0f
                                                                                constant:0.0f]];
        [messageComposerContainer addConstraint:[NSLayoutConstraint constraintWithItem:messageComposerContainer
                                                                               attribute:NSLayoutAttributeTrailing
                                                                               relatedBy:NSLayoutRelationEqual
                                                                                  toItem:growingTextView
                                                                               attribute:NSLayoutAttributeTrailing
                                                                              multiplier:1.0f
                                                                                constant:0.0f]];
        [messageComposerContainer setNeedsUpdateConstraints];
        
        lastEditedText = nil;
    }
    
    return self;
}

- (void)dealloc {
    if (growingTextView) {
        growingTextView.delegate = nil;
        [growingTextView removeFromSuperview];
        growingTextView = nil;
    }
}

- (void)setMaxHeight:(CGFloat)maxHeight {
    growingTextView.maxHeight = maxHeight - (self.messageComposerContainerTopConstraint.constant + self.messageComposerContainerBottomConstraint.constant);
    [growingTextView refreshHeight];
}

- (NSString*)textMessage {
    return growingTextView.text;
}

- (void)setTextMessage:(NSString *)textMessage {
    growingTextView.text = textMessage;
    self.rightInputToolbarButton.enabled = textMessage.length;
}

- (void)dismissKeyboard {
    [growingTextView resignFirstResponder];
}

#pragma mark - HPGrowingTextView delegate

- (void)growingTextViewDidEndEditing:(HPGrowingTextView *)sender {
    
    if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:isTyping:)]) {
        [self.delegate roomInputToolbarView:self isTyping:NO];
    }
}

- (void)growingTextViewDidChange:(HPGrowingTextView *)sender {
    
    NSString *msg = growingTextView.text;
    
    // HPGrowingTextView triggers growingTextViewDidChange event when it recomposes itself.
    // Save the last edited text to prevent unexpected typing events
    if (![lastEditedText isEqualToString:msg]) {
        lastEditedText = msg;
        if (msg.length) {
            if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:isTyping:)]) {
                [self.delegate roomInputToolbarView:self isTyping:YES];
            }
            self.rightInputToolbarButton.enabled = YES;
        } else {
            if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:isTyping:)]) {
                [self.delegate roomInputToolbarView:self isTyping:NO];
            }
            self.rightInputToolbarButton.enabled = NO;
        }
    }
}

- (void)growingTextView:(HPGrowingTextView *)growingTextView willChangeHeight:(float)height {
    // Update growing text's superview (toolbar view)
    CGFloat updatedHeight = height + (self.messageComposerContainerTopConstraint.constant + self.messageComposerContainerBottomConstraint.constant);
    if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:heightDidChanged:)]) {
        [self.delegate roomInputToolbarView:self heightDidChanged:updatedHeight];
    }
}

@end
