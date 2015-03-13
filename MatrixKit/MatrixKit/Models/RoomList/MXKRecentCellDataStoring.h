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

#import <Foundation/Foundation.h>
#import <MatrixSDK/MatrixSDK.h>

#import "MXKCellData.h"

@class MXKRecentListDataSource;

/**
 `MXKRoomCellDataStoring` defines a class must conform in order to store MXKRoom cell data
 managed by `MXKRecentListDataSource`.
 */
@protocol MXKRecentCellDataStoring <NSObject>

#pragma mark - Data displayed by a room recent cell

@property (nonatomic, readonly) NSString *roomId;
@property (nonatomic, readonly) NSString *lastEventDescription;
@property (nonatomic, readonly) uint64_t lastEventOriginServerTs;
@property (nonatomic, readonly) NSUInteger unreadCount;
@property (nonatomic, readonly) BOOL containsBingUnread;

#pragma mark - Public methods
/**
 Create a new `MXKCellData` object for a new bubble cell.

 @param recentListDataSource the `MXKRecentListDataSource` object that will use this instance.
 @return the newly created instance.
 */
- (instancetype)initWithLastEvent:(MXEvent*)event andRoomState:(MXRoomState*)roomState markAsUnread:(BOOL)isUnread andRecentListDataSource:(MXKRecentListDataSource*)recentListDataSource;

// Update the current last event description with the provided event, except if this description is empty (see unsupported/unexpected events).
// Return true when the provided event is considered as new last event
- (BOOL)updateWithLastEvent:(MXEvent*)event andRoomState:(MXRoomState*)roomState markAsUnread:(BOOL)isUnread;

- (void)resetUnreadCount;

@end
