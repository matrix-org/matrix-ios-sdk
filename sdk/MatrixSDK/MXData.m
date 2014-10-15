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

#define SERVER_TIMEOUT_MS 30000
#define CLIENT_TIMEOUT_MS 40000
#define ERR_TIMEOUT_MS    5000

@interface MXData ()
{
    // Rooms data
    // The key is the room ID. The value, the MXRoomData instance.
    NSMutableDictionary *rooms;
    
    // Presence data
    // The key is the user ID. The value, the TBD instance.
    NSMutableDictionary *presence;

    // Indicates if we are streaming
    BOOL streamingActive;
}
@end

@implementation MXData
@synthesize matrixSession, eventTypesToUseAsMessages;

- (id)initWithMatrixSession:(MXSession*)mSession;
{
    self = [super init];
    if (self)
    {
        matrixSession = mSession;
        rooms = [NSMutableDictionary dictionary];
        presence = [NSMutableDictionary dictionary];
        
        streamingActive = NO;
        
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
                 roomData = [self createRoomData:room[@"room_id"] withJSONData:room];
             }
             
             if ([room objectForKey:@"messages"])
             {
                 MXPaginationResponse *roomMessages =
                 [MTLJSONAdapter modelOfClass:[MXPaginationResponse class]
                           fromJSONDictionary:[room objectForKey:@"messages"]
                                        error:nil];;
                 
                 [roomData handleMessages:roomMessages
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
        
        // Start listening to live events
        [self streamEventsFromToken:JSONData[@"end"]];
     }
     failure:^(NSError *error) {
         failure(error);
     }];
}

- (void)streamEventsFromToken:(NSString*)token
{
    streamingActive = YES;
    
    [matrixSession eventsFromToken:token serverTimeout:SERVER_TIMEOUT_MS clientTimeout:CLIENT_TIMEOUT_MS success:^(NSDictionary *JSONData) {
        
        if (streamingActive)
        {
            // Convert chunk array into an array of MXEvent
            NSValueTransformer *transformer = [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXEvent.class];
            NSArray *events = [transformer transformedValue:JSONData[@"chunk"]];
            
            // And handle them
            [self handleLiveEvents:events];
            
            // Go streaming from the returned token
            
            [self streamEventsFromToken:JSONData[@"end"]];
        }
        
    } failure:^(NSError *error) {
        
       if (streamingActive)
       {
           // Relaunch the request later
           dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, ERR_TIMEOUT_MS * NSEC_PER_MSEC);
           dispatch_after(delayTime, dispatch_get_main_queue(), ^(void) {
               
               [self streamEventsFromToken:token];
           });
       }
    }];
}

- (void)handleLiveEvents:(NSArray*)events
{
    for (MXEvent *event in events)
    {
        switch (event.eventType)
        {
            case MXEventTypePresence:
                // @TODO
                break;
                
            default:
                if (event.room_id)
                {
                    // Make room data digest the event
                    MXRoomData *roomData = [self getRoomData:event.room_id];
                    [roomData handleLiveEvent:event];
                }
                break;
        }
    }
}

- (void)close
{
    streamingActive = NO;
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
        if (room.lastMessage)
        {
            [recents addObject:room.lastMessage];
        }
        else
        {
            NSLog(@"WARNING: Ignore corrupted room (%@): no last message", room.room_id);
        }
    }
    
    // Order them by ts
    [recents sortUsingComparator:^NSComparisonResult(MXEvent *obj1, MXEvent *obj2) {
        return obj2.ts - obj1.ts;
    }];
    
    return recents;
}

- (MXRoomData *)createRoomData:(NSString *)room_id withJSONData:(NSDictionary*)JSONData
{
    MXRoomData *room = [[MXRoomData alloc] initWithRoomId:room_id andMatrixData:self andJSONData:JSONData];
    [rooms setObject:room forKey:room_id];
    return room;
}

@end
