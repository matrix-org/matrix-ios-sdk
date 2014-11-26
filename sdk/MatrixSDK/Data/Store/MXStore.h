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

#import "MXJSONModels.h"
#import "MXEventListener.h"

@protocol MXStore

#pragma mark - Room data

/**
 Store room events received from the home server.
 
 @param roomId the id of the room.
 @param events the array of events to store. Each event comes as a JSON NSDictionary.
 @param direction the origin of the event. Live or past events.
 */
- (void)storeEventsForRoom:(NSString*)roomId events:(NSArray*)events direction:(MXEventDirection)direction;

/**
 Store/retrieve the current pagination token of a room.
 */
- (void)storePaginationTokenOfRoom:(NSString*)roomId andToken:(NSString*)token;
- (NSString*)paginationTokenOfRoom:(NSString*)roomId;

/**
 Store/retrieve the flag indicating that the SDK has reached the end of pagination
 in its pagination requests to the home server.
 */
- (void)storeHasReachedHomeServerPaginationEndForRoom:(NSString*)roomId andValue:(BOOL)value;
- (BOOL)hasReachedHomeServerPaginationEndForRoom:(NSString*)roomId;

/**
 Reset pagination mechanism in a room.

 @param roomId the id of the room.
 */
- (void)resetPaginationOfRoom:(NSString*)roomId;

/**
 Get more messages in the room from the current pagination point.

 @param roomId the id of the room.
 @param numMessages the number or messages to get.
 @return an array of events. Each event must come as a JSON NSDictionary like they
         have been stored with `storeEventsForRoom`.
 */
- (NSArray*)paginateRoom:(NSString*)roomId numMessages:(NSUInteger)numMessages;

@property (nonatomic) NSString *eventStreamToken;

// @TODO
//- (void)recents;

@end