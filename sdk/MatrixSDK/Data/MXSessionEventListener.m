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

#import "MXSessionEventListener.h"

#import "MXSession.h"
#import "MXRoom.h"

@interface MXSessionEventListener()
{
    // A global listener needs to listen to each MXRoom new events
    // roomEventListeners is the list of all MXRoom listener for this MXSessionEventListener
    // The key is the room_id. The valuse, the registered MXEventListener of the MXRoom
    NSMutableDictionary *roomEventListeners;
}
@end

@implementation MXSessionEventListener

- (instancetype)initWithSender:(id)sender andEventTypes:(NSArray *)eventTypes andListenerBlock:(MXOnEvent)listenerBlock
{
    self = [super initWithSender:sender andEventTypes:eventTypes andListenerBlock:listenerBlock];
    if (self)
    {
        roomEventListeners = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)addRoomToSpy:(MXRoom*)room
{
    if (![roomEventListeners objectForKey:room.state.room_id])
    {
        roomEventListeners[room.state.room_id] =
        [room listenToEventsOfTypes:self.eventTypes onEvent:^(MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            self.listenerBlock(event, isLive, roomState);
        }];
    }

}

- (void)removeSpiedRoom:(MXRoom*)room
{
    if ([roomEventListeners objectForKey:room.state.room_id])
    {
        [room removeListener:roomEventListeners[room.state.room_id]];
        [roomEventListeners removeObjectForKey:room.state.room_id];
    }
}

- (void)removeAllSpiedRooms
{
    // Here sender is the MXSession instance. Cast it
    MXSession *mxSession = (MXSession *)self.sender;
    
    for (NSString *room_id in roomEventListeners)
    {
        MXRoom *room = [mxSession room:room_id];
        [room removeListener:roomEventListeners[room.state.room_id]];
        
    }
    [roomEventListeners removeAllObjects];
}

@end
