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

#import "MXSession.h"
#import "MatrixSDK.h"

#import "MXSessionEventListener.h"

#define SERVER_TIMEOUT_MS 30000
#define CLIENT_TIMEOUT_MS 40000
#define ERR_TIMEOUT_MS    5000

@interface MXSession ()
{
    // Rooms data
    // The key is the room ID. The value, the MXRoom instance.
    NSMutableDictionary *rooms;
    
    // Users data
    // The key is the user ID. The value, the MXUser instance.
    NSMutableDictionary *users;

    // Indicates if we are streaming
    BOOL streamingActive;
    
    // The list of global events listeners (`MXSessionEventListener`)
    NSMutableArray *globalEventListeners;
}
@end

@implementation MXSession
@synthesize matrixRestClient, eventsFilterForMessages;

- (id)initWithMatrixRestClient:(MXRestClient*)mRestClient;
{
    self = [super init];
    if (self)
    {
        matrixRestClient = mRestClient;
        rooms = [NSMutableDictionary dictionary];
        users = [NSMutableDictionary dictionary];
        
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
    [matrixRestClient initialSyncWithLimit:1 success:^(NSDictionary *JSONData) {
         for (NSDictionary *roomDict in JSONData[@"rooms"])
         {
             MXRoom *room = [self getOrCreateRoom:roomDict[@"room_id"] withJSONData:roomDict];
             
             if ([roomDict objectForKey:@"messages"])
             {
                 MXPaginationResponse *roomMessages = [MXPaginationResponse modelFromJSON:[roomDict objectForKey:@"messages"]];
                 
                 [room handleMessages:roomMessages
                             isLiveEvents:NO direction:NO];
             }
             if ([roomDict objectForKey:@"state"])
             {
                 [room handleStateEvents:roomDict[@"state"]];
             }
        }
        
        // Manage presence
        for (NSDictionary *presenceDict in JSONData[@"presence"])
        {
            MXEvent *presenceEvent = [MXEvent modelFromJSON:presenceDict];
            [self handlePresenceEvent:presenceEvent isLiveEvent:NO];
        }
        
        // We have data, the SDK user can start using it
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
    
    [matrixRestClient eventsFromToken:token serverTimeout:SERVER_TIMEOUT_MS clientTimeout:CLIENT_TIMEOUT_MS success:^(NSDictionary *JSONData) {
        
        if (streamingActive)
        {
            // Convert chunk array into an array of MXEvents
            NSArray *events = [MXEvent modelsFromJSON:JSONData[@"chunk"]];
            
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
            {
                [self handlePresenceEvent:event isLiveEvent:YES];
                break;
            }
                
            default:
                if (event.roomId)
                {
                    // Make room data digest the event
                    MXRoom *room = [self getOrCreateRoom:event.roomId withJSONData:nil];
                    [room handleLiveEvent:event];
                }
                break;
        }
    }
}

- (void) handlePresenceEvent:(MXEvent *)event isLiveEvent:(BOOL)isLiveEvent
{
    // Update MXUser with presence data
    NSString *userId = event.userId;
    if (userId)
    {
        MXUser *user = [self getOrCreateUser:userId];
        [user updateWithPresenceEvent:event];
    }
    
    [self notifyListeners:event isLiveEvent:isLiveEvent];
}

- (void)close
{
    streamingActive = NO;
    
    [self unregisterAllListeners];
    
    // @TODO: Cancel the pending eventsFromToken request
}


#pragma mark - the user's rooms
- (MXRoom *)room:(NSString *)room_id
{
    return [rooms objectForKey:room_id];
}

- (NSArray *)rooms
{
    return [rooms allValues];
}

- (MXRoom *)getOrCreateRoom:(NSString *)room_id withJSONData:JSONData
{
    MXRoom *room = [self room:room_id];
    if (nil == room)
    {
        room = [self createRoom:room_id withJSONData:JSONData];
    }
    return room;
}

- (MXRoom *)createRoom:(NSString *)room_id withJSONData:(NSDictionary*)JSONData
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:room_id andMatrixSession:self andJSONData:JSONData];
    
    // Register global listeners for this room
    for (MXSessionEventListener *listener in globalEventListeners)
    {
        [listener addRoomToSpy:room];
    }
    
    [rooms setObject:room forKey:room_id];
    return room;
}


#pragma mark - Matrix users
- (MXUser *)user:(NSString *)userId
{
    return [users objectForKey:userId];
}

- (NSArray *)users
{
    return [users allValues];
}

- (MXUser *)getOrCreateUser:(NSString *)userId
{
    MXUser *user = [self user:userId];
    
    if (nil == user)
    {
        user = [[MXUser alloc] initWithUserId:userId];
        [users setObject:user forKey:userId];
    }
    return user;
}

#pragma mark - User's recents
- (NSArray *)recents
{
    NSMutableArray *recents = [NSMutableArray arrayWithCapacity:rooms.count];
    for (MXRoom *room in rooms.allValues)
    {
        if (room.lastMessage)
        {
            [recents addObject:room.lastMessage];
        }
        else
        {
            NSLog(@"WARNING: Ignore corrupted room (%@): no last message", room.state.room_id);
        }
    }
    
    // Order them by origin_server_ts
    [recents sortUsingComparator:^NSComparisonResult(MXEvent *obj1, MXEvent *obj2) {
        NSComparisonResult result = NSOrderedAscending;
        if (obj2.originServerTs > obj1.originServerTs) {
            result = NSOrderedDescending;
        } else if (obj2.originServerTs == obj1.originServerTs) {
            result = NSOrderedSame;
        }
        return result;
    }];
    
    return recents;
}


#pragma mark - Global events listeners
- (id)registerEventListenerForTypes:(NSArray*)types block:(MXSessionEventListenerBlock)listenerBlock
{
    MXSessionEventListener *listener = [[MXSessionEventListener alloc] initWithSender:self andEventTypes:types andListenerBlock:listenerBlock];
    
    // This listener must be listen to all existing rooms
    for (MXRoom *room in rooms.allValues)
    {
        [listener addRoomToSpy:room];
    }
    
    [globalEventListeners addObject:listener];
    
    return listener;
}

- (void)unregisterListener:(id)listenerId
{
    // Clean the MXSessionEventListener
    MXSessionEventListener *listener = (MXSessionEventListener *)listenerId;
    [listener removeAllSpiedRooms];
    
    // Before removing it
    [globalEventListeners removeObject:listener];
}

- (void)unregisterAllListeners
{
    for (MXSessionEventListener *listener in globalEventListeners)
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
