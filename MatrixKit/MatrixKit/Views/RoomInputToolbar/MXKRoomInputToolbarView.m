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

#import "MXKRoomInputToolbarView.h"

#import <MediaPlayer/MediaPlayer.h>
#import <MobileCoreServices/MobileCoreServices.h>

@interface MXKRoomInputToolbarView() {
    /**
     Alert used to list options.
     */
    MXKAlert *currentAlert;
    
    /**
     Current media picker
     */
    UIImagePickerController *mediaPicker;
    
    /**
     Temporary movie player used to retrieve video thumbnail
     */
    MPMoviePlayerController *tmpVideoPlayer;
}

@property (nonatomic) IBOutlet UIView *messageComposerContainer;

@end

@implementation MXKRoomInputToolbarView
@synthesize messageComposerContainer;

- (instancetype)init {
    NSArray *nibViews = [[NSBundle bundleForClass:[MXKRoomInputToolbarView class]] loadNibNamed:NSStringFromClass([MXKRoomInputToolbarView class])
                                                                                          owner:nil
                                                                                        options:nil];
    self = nibViews.firstObject;
    if (self) {
        [self setTranslatesAutoresizingMaskIntoConstraints: NO];
        
        // Reset default container background color
        self.messageComposerContainer.backgroundColor = [UIColor clearColor];
        // Set default message composer background color
        self.defaultMessageComposerTextView.backgroundColor = [UIColor whiteColor];
        // Set default toolbar background color
        self.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
        
        // Disable send button
        self.rightInputToolbarButton.enabled = NO;
        
        // Add an accessory view to the text view in order to retrieve keyboard view.
        _inputAccessoryView = [[UIView alloc] initWithFrame:CGRectZero];
        self.defaultMessageComposerTextView.inputAccessoryView = _inputAccessoryView;
    }
    
    return self;
}

- (void)dealloc {
    if (currentAlert) {
        [currentAlert dismiss:NO];
        currentAlert = nil;
    }
    
    if (mediaPicker) {
        [self dismissMediaPicker];
        mediaPicker = nil;
    }
}

- (IBAction)onTouchUpInside:(UIButton*)button {
    if (button == self.leftInputToolbarButton) {
        // Option button has been pressed
        if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:presentMXKAlert:)]) {
            // List available options
            __weak typeof(self) weakSelf = self;
            currentAlert = [[MXKAlert alloc] initWithTitle:@"Select an action:" message:nil style:MXKAlertStyleActionSheet];
            
            // Check whether media attachment is supported
            if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:presentMediaPicker:)]) {
                [currentAlert addActionWithTitle:@"Attach Media from Library" style:MXKAlertActionStyleDefault handler:^(MXKAlert *alert) {
                    __strong __typeof(weakSelf)strongSelf = weakSelf;
                    strongSelf->currentAlert = nil;
                    
                    // Open media gallery
                    strongSelf->mediaPicker = [[UIImagePickerController alloc] init];
                    strongSelf->mediaPicker.delegate = strongSelf;
                    strongSelf->mediaPicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                    strongSelf->mediaPicker.allowsEditing = NO;
                    strongSelf->mediaPicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, nil];
                    [strongSelf.delegate roomInputToolbarView:strongSelf presentMediaPicker:strongSelf->mediaPicker];
                }];
                
                [currentAlert addActionWithTitle:@"Take Photo/Video" style:MXKAlertActionStyleDefault handler:^(MXKAlert *alert) {
                    __strong __typeof(weakSelf)strongSelf = weakSelf;
                    strongSelf->currentAlert = nil;
                    
                    // Open Camera
                    strongSelf->mediaPicker = [[UIImagePickerController alloc] init];
                    strongSelf->mediaPicker.delegate = strongSelf;
                    strongSelf->mediaPicker.sourceType = UIImagePickerControllerSourceTypeCamera;
                    strongSelf->mediaPicker.allowsEditing = NO;
                    strongSelf->mediaPicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, nil];
                    [strongSelf.delegate roomInputToolbarView:strongSelf presentMediaPicker:strongSelf->mediaPicker];
                }];
            } else {
                NSLog(@"[MXKRoomInputToolbarView] Attach media is not supported");
            }
            
            // Check whether user invitation is supported
            if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:inviteMatrixUser:)]) {
                [currentAlert addActionWithTitle:@"Invite matrix User" style:MXKAlertActionStyleDefault handler:^(MXKAlert *alert) {
                    __strong __typeof(weakSelf)strongSelf = weakSelf;
                    
                    // Ask for userId to invite
                    strongSelf->currentAlert = [[MXKAlert alloc] initWithTitle:@"User ID:" message:nil style:MXKAlertStyleAlert];
                    strongSelf->currentAlert.cancelButtonIndex = [strongSelf->currentAlert addActionWithTitle:@"Cancel" style:MXKAlertActionStyleDefault handler:^(MXKAlert *alert) {
                        __strong __typeof(weakSelf)strongSelf = weakSelf;
                        strongSelf->currentAlert = nil;
                    }];
                    
                    [strongSelf->currentAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                        textField.secureTextEntry = NO;
                        textField.placeholder = @"ex: @bob:homeserver";
                    }];
                    [strongSelf->currentAlert addActionWithTitle:@"Invite" style:MXKAlertActionStyleDefault handler:^(MXKAlert *alert) {
                        UITextField *textField = [alert textFieldAtIndex:0];
                        NSString *userId = textField.text;
                        
                        __strong __typeof(weakSelf)strongSelf = weakSelf;
                        strongSelf->currentAlert = nil;
                        
                        if (userId.length) {
                            [strongSelf.delegate roomInputToolbarView:strongSelf inviteMatrixUser:userId];
                        }
                    }];
                    
                    [strongSelf.delegate roomInputToolbarView:strongSelf presentMXKAlert:strongSelf->currentAlert];
                }];
            } else {
                NSLog(@"[MXKRoomInputToolbarView] Invitation is not supported");
            }
            
            currentAlert.cancelButtonIndex = [currentAlert addActionWithTitle:@"Cancel" style:MXKAlertActionStyleDefault handler:^(MXKAlert *alert) {
                __strong __typeof(weakSelf)strongSelf = weakSelf;
                strongSelf->currentAlert = nil;
            }];
            
            currentAlert.sourceView = button;
            
            [self.delegate roomInputToolbarView:self presentMXKAlert:currentAlert];
        } else {
            NSLog(@"[MXKRoomInputToolbarView] Option display is not supported");
        }
    } else if (button == self.rightInputToolbarButton) {
        // Send button has been pressed
        if (self.textMessage.length && [self.delegate respondsToSelector:@selector(roomInputToolbarView:sendTextMessage:)]) {
            [self.delegate roomInputToolbarView:self sendTextMessage:self.textMessage];
        }
        
        // Reset message
        self.textMessage = nil;
    }
}

- (NSString*)textMessage {
    return _defaultMessageComposerTextView.text;
}

- (void)setTextMessage:(NSString *)textMessage {
    
    _defaultMessageComposerTextView.text = textMessage;
    self.rightInputToolbarButton.enabled = textMessage.length;
}

- (void)setPlaceholder:(NSString *)inPlaceholder {

    _placeholder = inPlaceholder;
}

- (void)dismissKeyboard {
    
    if (_defaultMessageComposerTextView) {
        [_defaultMessageComposerTextView resignFirstResponder];
    }
}

#pragma mark - UITextViewDelegate

- (void)textViewDidEndEditing:(UITextView *)textView {
    
    if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:isTyping:)]) {
        [self.delegate roomInputToolbarView:self isTyping:NO];
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    
    NSString *msg = textView.text;
    
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

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    
    // Hanlde here `Done` key pressed
    if([text isEqualToString:@"\n"]) {
        [textView resignFirstResponder];
        return NO;
    }
    
    return YES;
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage *selectedImage = [info objectForKey:UIImagePickerControllerOriginalImage];
        if (selectedImage) {
            if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:sendImage:)]) {
                [self.delegate roomInputToolbarView:self sendImage:selectedImage];
            } else {
                NSLog(@"[MXKRoomInputToolbarView] Attach image is not supported");
            }
        }
    } else if ([mediaType isEqualToString:(NSString *)kUTTypeMovie]) {
        NSURL* selectedVideo = [info objectForKey:UIImagePickerControllerMediaURL];
        // Check the selected video, and ignore multiple calls (observed when user pressed several time Choose button)
        if (selectedVideo && !tmpVideoPlayer) {
            // Create video thumbnail
            tmpVideoPlayer = [[MPMoviePlayerController alloc] initWithContentURL:selectedVideo];
            if (tmpVideoPlayer) {
                [tmpVideoPlayer setShouldAutoplay:NO];
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(moviePlayerThumbnailImageRequestDidFinishNotification:)
                                                             name:MPMoviePlayerThumbnailImageRequestDidFinishNotification
                                                           object:nil];
                [tmpVideoPlayer requestThumbnailImagesAtTimes:@[@1.0f] timeOption:MPMovieTimeOptionNearestKeyFrame];
                // We will finalize video attachment when thumbnail will be available (see movie player callback)
                return;
            }
        }
    }
    
    [self dismissMediaPicker];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissMediaPicker];
}

#pragma mark - Media Picker handling

- (void)dismissMediaPicker {
    mediaPicker.delegate = nil;
    
    if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:dismissMediaPicker:)]) {
        [self.delegate roomInputToolbarView:self dismissMediaPicker:mediaPicker];
    }
}

- (void)moviePlayerThumbnailImageRequestDidFinishNotification:(NSNotification *)notification {
    // Finalize video attachment
    UIImage* videoThumbnail = [[notification userInfo] objectForKey:MPMoviePlayerThumbnailImageKey];
    NSURL* selectedVideo = [tmpVideoPlayer contentURL];
    [tmpVideoPlayer stop];
    tmpVideoPlayer = nil;
    
    if ([self.delegate respondsToSelector:@selector(roomInputToolbarView:sendVideo:withThumbnail:)]) {
        [self.delegate roomInputToolbarView:self sendVideo:selectedVideo withThumbnail:videoThumbnail];
    } else {
        NSLog(@"[MXKRoomInputToolbarView] Attach video is not supported");
    }
}

@end
