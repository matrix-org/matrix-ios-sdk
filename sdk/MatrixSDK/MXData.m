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
@synthesize eventTypesToUseAsMessages;

- (id)initWithMatrixSession:(MXSession*)mSession;
{
    self = [super init];
    if (self)
    {
        matrixSession = mSession;
        rooms = [NSMutableDictionary dictionary];
        presence = [NSMutableDictionary dictionary];
        
        // Define default events to consider as messages
        eventTypesToUseAsMessages = @[
                                      kMXEventTypeStringRoomName,
                                      kMXEventTypeStringRoomTopic,
                                      kMXEventTypeStringRoomMember,
                                      kMXEventTypeStringRoomMessage
                                      ];
    }
    return self;
}

- (void)start:(void (^)())initialSyncDone
      failure:(void (^)(NSError *error))failure
{
    [matrixSession initialSync:1 success:^(NSDictionary *JSONData) {
         for (NSDictionary *room in JSONData[@"rooms"])
         {
             MXRoomData *roomData = [self getRoomData:room[@"room_id"]];
             if (nil == roomData)
             {
                 roomData = [self createRoomData:room[@"room_id"]];
             }
             
             if ([room objectForKey:@"messages"])
             {
                 [roomData handleMessages:room[@"messages"]
                             isLiveEvents:NO direction:NO];
             }
             if ([room objectForKey:@"state"])
             {
                 [roomData handleStateEvents:room[@"state"]];
             }
        }
        
        // @TODO: Manage presence
        
        // We have data, the MXData client can start using it
        initialSyncDone();
        
        // @TODO: Start listening to live events
     }
     failure:^(NSError *error) {
         failure(error);
     }];
}

- (void)close
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
    for (MXRoomData *room in rooms.allValues)
    {
        [recents addObject:room.lastMessage];
    }
    
    // Order them by ts
    [recents sortUsingComparator:^NSComparisonResult(MXEvent *obj1, MXEvent *obj2) {
        return obj2.ts - obj1.ts;
    }];
    
    return recents;
}

- (MXRoomData *)createRoomData:(NSString *)room_id
{
    MXRoomData *room = [[MXRoomData alloc] initWithRoomId:room_id andEventTypesToUseAsMessages:eventTypesToUseAsMessages];
    [rooms setObject:room forKey:room_id];
    return room;
}

@end
