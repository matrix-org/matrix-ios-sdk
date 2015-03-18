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

#import <UIKit/UIKit.h>

#import "MXKAlert.h"

@class MXKRoomInputToolbarView;
@protocol MXKRoomInputToolbarViewDelegate <NSObject>

@optional

/**
 Tells the delegate that the user is typing or has finished typing.
 
 @param toolbarView the room input toolbar view
 @param typing YES if the user is typing inside the message composer.
 */
- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView isTyping:(BOOL)typing;

/**
 Tells the delegate that toolbar height has been updated.
 
 @param toolbarView the room input toolbar view
 @param height the updted height of toolbar view.
 */
- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView heightDidChanged:(CGFloat)height;

/**
 Tells the delegate that the user wants send a text message.
 
 @param toolbarView the room input toolbar view
 @param textMessage
 */
- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView sendTextMessage:(NSString*)textMessage;

/**
 Tells the delegate that the user wants send an image.
 
 @param toolbarView the room input toolbar view
 @param image
 */
- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView sendImage:(UIImage*)image;

/**
 Tells the delegate that the user wants send a video.
 
 @param toolbarView the room input toolbar view
 @param videoURL
 @param videoThumbnail
 */
- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView sendVideo:(NSURL*)videoURL withThumbnail:(UIImage*)videoThumbnail;

/**
 Tells the delegate that the user wants invite a matrix user.
 
 @param toolbarView the room input toolbar view
 @param mxUserId matrix user id
 */
- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView inviteMatrixUser:(NSString*)mxUserId;

/**
 Tells the delegate that a MXKAlert must be presented.
 
 @param toolbarView the room input toolbar view
 @param alert to present
 */
- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView presentMXKAlert:(MXKAlert*)alert;

/**
 Tells the delegate that a media picker must be presented.
 
 @param toolbarView the room input toolbar view
 @param media picker to present
 */
- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView presentMediaPicker:(UIImagePickerController*)mediaPicker;

/**
 Tells the delegate that a media picker must be dismissed.
 
 @param toolbarView the room input toolbar view
 @param media picker to dismiss
 */
- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView dismissMediaPicker:(UIImagePickerController*)mediaPicker;

@end

/**
 `MXKRoomInputToolbarView` instance is a view used to handle all kinds of available inputs
 for a room (message composer, attachments selection...).
 
 By default the right button of the toolbar offers the following options: attach media, invite new members.
 By default the left button is used to send the content of the message composer.
 */
@interface MXKRoomInputToolbarView : UIView <UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate> {
    /**
     The message composer container view. Your own message composer may be added inside this container (after removing the default composer: `defaultMessageComposerTextView`).
     */
    UIView *messageComposerContainer;
}

/**
 The delegate notified when inputs are ready.
 */
@property (nonatomic) id<MXKRoomInputToolbarViewDelegate> delegate;

/**
  A custom button displayed on the left of the toolbar view.
 */
@property (weak, nonatomic) IBOutlet UIButton *leftInputToolbarButton;

/**
 A custom button displayed on the right of the toolbar view.
 */
@property (weak, nonatomic) IBOutlet UIButton *rightInputToolbarButton;

/**
 Default message composer defined in `messageComposerContainer`. You must remove it before adding your own message composer.
 */
@property (weak, nonatomic) IBOutlet UITextView *defaultMessageComposerTextView;

/**
 Layout constraint between the top of the message composer container and the top of its superview.
 The first view is the container, the second is the superview.
 */
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *messageComposerContainerTopConstraint;

/**
 Layout constraint between the bottom of the message composer container and the bottom of its superview.
 The first view is the superview, the second is the container.
 */
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *messageComposerContainerBottomConstraint;

/**
 `onTouchUpInside` action is registered on `Touch Up Inside` event for both buttons (left and right input toolbar buttons).
 Override this method to customize user interaction handling
 
 @param button the event sender
 */
- (IBAction)onTouchUpInside:(UIButton*)button;

/**
 The maximum height of the toolbar.
 A value <= 0 means no limit.
 */
@property CGFloat maxHeight;

/**
 The current text message in message composer.
 */
@property NSString *textMessage;

/**
 Force dismiss keyboard
 */
- (void)dismissKeyboard;

@end
