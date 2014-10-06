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

#import "MXData.h"
#import "MatrixSDK.h"

@interface MXData ()
{
    // The matrix session to make Matrix API requests
    MXSession *matrixSession;
    
    // Rooms data
    // The key is the room ID. The value, the MXRoomData instance.
    NSMutableDictionary *rooms;
    
    // Presence data
    // The key is the user ID. The value, the TBD instance.
    NSMutableDictionary *presence;
}
@end

@implementation MXData

- (id)initWithMatrixSession:(MXSession*)mSession;
{
    self = [super init];
    if (self)
    {
        matrixSession = mSession;
        rooms = [NSMutableDictionary dictionary];
        presence = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)start
{
    [matrixSession initialSync:1 success:^(NSDictionary *JSONData) {
         for (NSDictionary *room in JSONData[@"rooms"]) {
             
             if ([room objectForKey:@"messages"])
             {
                 [self handleRoomMessages:room[@"messages"]
                             isLiveEvents:NO direction:NO];
             }
             if ([room objectForKey:@"state"])
             {
                 //[self handleEvents:room[@"state"] isLiveEvents:NO isStateEvents:YES pagFrom:nil];
             }
         }
     }
     failure:^(NSError *error) {
         NSLog(@"%@", error);
     }];
}

- (void)stop
{
    // @TODO
}

- (MXRoomData *)getRoomData:(NSString *)room_id
{
    return [rooms objectForKey:room_id];
}

- (NSArray *)recents
{
    NSMutableArray *recents = [NSMutableArray arrayWithCapacity:rooms.count];
    for (MXRoomData *room in rooms) {
        [recents addObject:room.lastEvent];
    }
    
    // @TODO: Do time order
    
    return recents;
}

- (MXRoomData *)createRoomData:(NSString *)room_id
{
    MXRoomData *room = [[MXRoomData alloc] initWithRoomId:room_id];
    [rooms setObject:room forKey:room_id];
    return room;
}

- (void)handleRoomMessages:(NSDictionary*)messages
              isLiveEvents:(BOOL)isLiveEvents
                 direction:(BOOL)direction
{
    NSValueTransformer *transformer = [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXEvent.class];
    
    NSArray *events = [transformer transformedValue:messages[@"chunk"]];

    // Handles messages according to their time order
    if (direction)
    {
        // paginateBackMessages requests messages to be in reverse chronological order
        [self handleEvents:events isLiveEvents:isLiveEvents
             isStateEvents:NO pagFrom:messages[@"start"]];
        
        // Store how far back we've paginated
        //$rootScope.events.rooms[room_id].pagination.earliest_token = messages.end;
    }
    else {
        // InitialSync returns messages in chronological order
        for (NSInteger i = events.count - 1; i >= 0; i--)
        {
            MXEvent *event = events[i];
            [self handleEvent:event isLiveEvent:isLiveEvents
                 isStateEvent:NO pagFrom:messages[@"end"]];
        }
        
        // Store where to start pagination
        //$rootScope.events.rooms[room_id].pagination.earliest_token = messages.start;
    }
    
    //NSLog(@"%@", messageEvents);
}

- (void)handleEvents:(NSArray*)events
        isLiveEvents:(BOOL)isLiveEvents isStateEvents:(BOOL)isStateEvents
             pagFrom:(NSString*)pagFrom
{
    for (MXEvent *event in events) {
        [self handleEvent:event isLiveEvent:isLiveEvents
             isStateEvent:isStateEvents pagFrom:pagFrom];
    }
}

- (void)handleEvent:(MXEvent*)event
        isLiveEvent:(BOOL)isLiveEvent isStateEvent:(BOOL)isStateEvent
            pagFrom:(NSString*)pagFrom
{
    if (event.room_id)
    {
        MXRoomData *room = [self getRoomData:event.room_id];
        if (nil == room)
        {
            room = [self createRoomData:event.room_id];
        }
        
        [room handleEvent:event isLiveEvent:isLiveEvent isStateEvent:isStateEvent pagFrom:pagFrom];
    }
}

@end
