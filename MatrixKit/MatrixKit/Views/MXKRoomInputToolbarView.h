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

/**
 `MXKRoomInputToolbarView` instance is a view used to handle all kinds of available inputs
 for a room (message composer, attachments selection...).
 */
@interface MXKRoomInputToolbarView : UIView

/**
  A custom button displayed on the left of the toolbar view.
 */
@property (weak, nonatomic) IBOutlet UIButton *leftInputToolbarButton;

/**
 A custom button displayed on the right of the toolbar view.
 */
@property (weak, nonatomic) IBOutlet UIButton *rightInputToolbarButton;

/**
 `onTouchUpInside` action is registered on `Touch Up Inside` event for both buttons (left and right input toolbar buttons).
 Override this method to customize user interaction handling
 
 @param button the event sender
 */
- (IBAction)onTouchUpInside:(UIButton*)button;

@end
