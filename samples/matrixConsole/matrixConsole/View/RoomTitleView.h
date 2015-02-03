/*
 Copyright 2014 OpenMarket Ltd
 
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

@class MXRoom;

@interface RoomTitleView : UIView<UIGestureRecognizerDelegate> {
}

@property (weak, nonatomic) IBOutlet UITextField *displayNameTextField;
@property (weak, nonatomic) IBOutlet UITextField *topicTextField;

@property (strong, nonatomic) MXRoom *mxRoom;
@property (nonatomic) BOOL editable;
@property (nonatomic) BOOL hiddenTopic;
@property (nonatomic) BOOL isEditing;

- (void)dismissKeyboard;

// force to refresh the title display
- (void)refreshDisplay;

// return YES if the animation has been stopped
- (BOOL)stopTopicAnimation;

@end