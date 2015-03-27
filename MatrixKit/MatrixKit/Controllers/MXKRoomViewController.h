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

#import "MXKViewController.h"
#import "MXKRoomDataSource.h"
#import "MXKRoomInputToolbarView.h"

extern NSString *const kCmdChangeDisplayName;
extern NSString *const kCmdEmote;
extern NSString *const kCmdJoinRoom;
extern NSString *const kCmdKickUser;
extern NSString *const kCmdBanUser;
extern NSString *const kCmdUnbanUser;
extern NSString *const kCmdSetUserPowerLevel;
extern NSString *const kCmdResetUserPowerLevel;

/**
 This view controller displays messages of a room.
 */
@interface MXKRoomViewController : MXKViewController <MXKDataSourceDelegate, MXKRoomInputToolbarViewDelegate, UITableViewDelegate>

/**
 The current data source associated to the view controller.
 */
@property (nonatomic, readonly) MXKRoomDataSource *dataSource;

/**
 The current input toolbar view defined into the view controller.
 */
@property (nonatomic, readonly) MXKRoomInputToolbarView* inputToolbarView;

/**
 Display a room.
 
 @param roomDataSource the data source .
 */
- (void)displayRoom:(MXKRoomDataSource*)roomDataSource;

/**
 Register the MXKRoomInputToolbarView class used to instantiate the input toolbar view
 which will handle message composer and attachments selection for the room.
 
 @param roomInputToolbarViewClass a MXKRoomInputToolbarView-inherited class.
 */
- (void)setRoomInputToolbarViewClass:(Class)roomInputToolbarViewClass;

/**
 Detect and process potential IRC command in provided string.
 
 @param string to analyse
 @return YES if IRC style command has been detected and interpreted.
 */
- (BOOL)isIRCStyleCommand:(NSString*)string;

@end
