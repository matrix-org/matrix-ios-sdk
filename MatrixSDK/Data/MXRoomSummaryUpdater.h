/*
 Copyright 2017 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import <Foundation/Foundation.h>

#import "MXRoomSummary.h"
#import "MXRoomNameStringsLocalizable.h"

/**
 `MXRoomSummaryUpdater` is the default implementation for the `MXRoomSummaryUpdating` protocol.
 
 There is one `MXRoomSummaryUpdater` instance per MXSession.
 */
@interface MXRoomSummaryUpdater : NSObject <MXRoomSummaryUpdating>

/**
 Get the room summary updater for the given session.
 
 @param mxSession the session to use.
 @return the updater for this session.
 */
+ (instancetype)roomSummaryUpdaterForSession:(MXSession*)mxSession;


#pragma mark - Configuration

/**
 The type of events allowed as last message.
 
 Default is nil. All messages types are accepted.
 */
@property (nonatomic) NSArray<NSString*> *eventsFilterForMessages;

/**
 If YES, ignore profile changes of room members as last message.
 
 Default is NO.
 */
@property (nonatomic) BOOL ignoreMemberProfileChanges;

/**
 If YES, ignore redacted events as last message.

 Default is NO.
 */
@property (nonatomic) BOOL ignoreRedactedEvent;

/**
 String localizations used when computing names for room with no name.

 Default is an instance of `MXRoomNameDefaultStringLocalizations`.
 */
@property id<MXRoomNameStringsLocalizable> roomNameStringLocalizations;

/**
 Indicate YES to handle room types with nil or empty value.
 If YES `defaultRoomType` will be used to define the default room type to use in this case.
 
 YES by default.
*/
@property (nonatomic) BOOL showNilOrEmptyRoomType;

/**
 Room type used when the room type of a room is not defined (null or empty).
 
 MXRoomTypeRoom by default.
*/
@property (nonatomic) MXRoomType defaultRoomType;

/**
 List of supported room type strings to show to the user. Other room types will be hidden (see MXRoomSummary.hiddenFromUser). It's not necessary to add empty or nil values, this case is handled by `showNilOrEmptyRoomType` property.
 
 Nil by default.
*/
@property (nonatomic) NSArray<NSString *> *showRoomTypeStrings;

@end
