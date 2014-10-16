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

#import "MXDataEventListener.h"

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
    
    // The list of global events listeners (`MXDataEventListener`)
    NSMutableArray *globalEventListeners;
}
@end

@implementation MXData
@synthesize matrixSession, eventsFilterForMessages;

- (id)initWithMatrixSession:(MXSession*)mSession;
{
    self = [super init];
    if (self)
    {
        matrixSession = mSession;
        rooms = [NSMutableDictionary dictionary];
        presence = [NSMutableDictionary dictionary];
        
        streamingActive = NO;
        
        globalEventListeners = [NSMutableArray array];
        
        // Define default events to consider as messages
        eventsFilterForMessages = @[
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
             MXRoomData *roomData = [self getOrCreateRoomData:room[@"room_id"] withJSONData:JSONData];
             
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
        // And signal them with notifyListeners
        
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
            // Convert chunk array into an array of MXEvents
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
                    MXRoomData *roomData = [self getOrCreateRoomData:event.room_id withJSONData:nil];
                    [roomData handleLiveEvent:event];
                }
                break;
        }
    }
}

- (void)close
{
    streamingActive = NO;
    
    [self unregisterAllListeners];
    
    // @TODO: Cancel the pending eventsFromToken request
}

- (MXRoomData *)getRoomData:(NSString *)room_id
{
    return [rooms objectForKey:room_id];
}

- (MXRoomData *)getOrCreateRoomData:(NSString *)room_id withJSONData:JSONData
{
    MXRoomData *roomData = [self getRoomData:room_id];
    if (nil == roomData)
    {
        roomData = [self createRoomData:room_id withJSONData:JSONData];
    }
    return roomData;
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
    MXRoomData *roomData = [[MXRoomData alloc] initWithRoomId:room_id andMatrixData:self andJSONData:JSONData];
    
    // Register global listeners for this room
    for (MXDataEventListener *listener in globalEventListeners)
    {
        [listener addRoomDataToSpy:roomData];
    }
    
    [rooms setObject:roomData forKey:room_id];
    return roomData;
}


#pragma mark - Events listeners
- (id)registerEventListenerForTypes:(NSArray*)types block:(MXDataEventListenerBlock)listenerBlock
{
    MXDataEventListener *listener = [[MXDataEventListener alloc] initWithSender:self andEventTypes:types andListenerBlock:listenerBlock];
    
    // This listener must be listen to all existing rooms
    for (MXRoomData *roomData in rooms)
    {
        [listener addRoomDataToSpy:roomData];
    }
    
    [globalEventListeners addObject:listener];
    
    return listener;
}

- (void)unregisterListener:(id)listenerId
{
    // Clean the MXDataEventListener
    MXDataEventListener *listener = (MXDataEventListener *)listenerId;
    [listener removeAllSpiedRoomDatas];
    
    // Before removing it
    [globalEventListeners removeObject:listener];
}

- (void)unregisterAllListeners
{
    for (MXDataEventListener *listener in globalEventListeners)
    {
        [self unregisterListener:listener];
    }
}

- (void)notifyListeners:(MXEvent*)event isLiveEvent:(BOOL)isLiveEvent
{
    // Notify all listeners
    for (MXEventListener *listener in globalEventListeners)
    {
        [listener notify:event isLiveEvent:isLiveEvent];
    }
}

@end
