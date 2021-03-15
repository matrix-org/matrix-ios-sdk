/*
 Copyright 2015 OpenMarket Ltd
 Copyright 2020 The Matrix.org Foundation C.I.C

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

#import "MXJSONModels.h"
#import "MXTaggedEvents.h"
#import "MXEvent.h"
#import "MXVirtualRoomInfo.h"

@class MXSession;
@class MXRoom;

/**
 `MXRoomAccountData` represents private data that the user has defined for a room.
 */
@interface MXRoomAccountData : NSObject <NSCoding>

/**
 The tags the user defined for this room.
 The key is the tag name. The value, the associated MXRoomTag object.
 */
@property (nonatomic, readonly) NSDictionary <NSString*, MXRoomTag*> *tags;

/**
 The event identifier which marks the last event read by the user.
 */
@property (nonatomic) NSString *readMarkerEventId;

/**
 The events the user has marked in this room.
 */
@property (nonatomic, readonly) MXTaggedEvents *taggedEvents;

/**
 Virtual room info for the room.
 */
@property (nonatomic, readonly) MXVirtualRoomInfo *virtualRoomInfo;

/**
 Process an event that modifies room account data (like m.tag event).

 @param event an event
 */
- (void)handleEvent:(MXEvent*)event;

/**
 Provide the information on a tagged event.
 
 @param eventId The event Id.
 @param tag the wanted tag.
 
 @return a MXTaggedEventInfo instance if the event has been tagged by the user, else null.
 */
- (MXTaggedEventInfo*)getTaggedEventInfo:(NSString*)eventId withTag:(NSString*)tag;

/**
 Provide the list of the events ids of the tag in the room.
 
 @param tag the wanted tag.
 @return the list of the identifiers of the events.
 */
- (NSArray<NSString *> *)getTaggedEventsIds:(NSString*)tag;

@end

/**
 The `MXRoomAccountDataUpdating` allows delegation of the update of room account data.
 */
@protocol MXRoomAccountDataUpdating <NSObject>


- (void)session:(MXSession*)session updateRoomAccountDataOf:(MXRoom*)room withStateEvents:(NSArray<MXEvent*>*)stateEvents completion:(void(^)(BOOL updated))completion;

/**
 Called to update the room account data on received state events.

 @param room the room of whom account data should be updated.
 @param stateEvents state events that may change the room account data.
 @param completion Block will be called at the end of the process. With a flag whether the room account data has been updated.
 */
- (void)updateAccountDataForRoom:(MXRoom *)room
                 withStateEvents:(NSArray<MXEvent*> *)stateEvents
                      completion:(void(^)(BOOL updated))completion;

/**
 Called to update the room account data if required in need of virtual rooms.

 @param room the room of whom account data should be updated.
 @param nativeRoomId native room id for the virtual room.
 @param completion Block will be called at the end of the process. With a flag whether the room account data has been updated.
 */
- (void)updateAccountDataIfRequiredForRoom:(MXRoom *)room
                          withNativeRoomId:(NSString *)nativeRoomId
                                completion:(void(^)(BOOL updated, NSError *error))completion;

@end
