/*
 Copyright 2016 OpenMarket Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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
#import "MXEventTimeline.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Prefix used to build fake invite event.
 */
FOUNDATION_EXPORT NSString *const kMXRoomInviteStateEventIdPrefix;

@interface MXRoomEventTimeline: NSObject <MXEventTimeline>

/**
 Create a timeline instance for a room.

 If the timeline is live, the events will be stored to the MXSession instance store.
 Else, they will be only stored in memory and released on [MXEventTimeline destroy].

 @param room the room associated to the timeline
 @param initialEventId the initial event for the timeline. A nil value will create a live timeline.
 @return a MXEventTimeline instance.
 */
- (instancetype)initWithRoom:(MXRoom*)room andInitialEventId:(nullable NSString*)initialEventId;

/**
 Create a timeline instance for a room and force it to use the given MXStore to store events.

 @param room the room associated to the timeline
 @param initialEventId the initial event for the timeline. A nil value will create a live timeline.
 @param store the store to use to store timeline events.
 @return a MXEventTimeline instance.
 */
- (instancetype)initWithRoom:(MXRoom*)room initialEventId:(nullable NSString*)initialEventId andStore:(id<MXStore>)store;

@end

NS_ASSUME_NONNULL_END
