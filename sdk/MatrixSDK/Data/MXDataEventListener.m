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

#import "MXDataEventListener.h"

#import "MXSession.h"
#import "MXRoomData.h"

@interface MXDataEventListener()
{
    // A global listener needs to listen to each MXRoomData new events
    // roomDataEventListeners is the list of all MXRoomData listener for this MXDataEventListener
    // The key is the room_id. The valuse, the registered MXEventListener of the MXRoomData
    NSMutableDictionary *roomDataEventListeners;
}
@end

@implementation MXDataEventListener

- (instancetype)initWithSender:(id)sender andEventTypes:(NSArray *)eventTypes andListenerBlock:(MXEventListenerBlock)listenerBlock
{
    self = [super initWithSender:sender andEventTypes:eventTypes andListenerBlock:listenerBlock];
    if (self)
    {
        roomDataEventListeners = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)addRoomDataToSpy:(MXRoomData*)roomData
{
    if (![roomDataEventListeners objectForKey:roomData.room_id])
    {
        roomDataEventListeners[roomData.room_id] =
        [roomData registerEventListenerForTypes:self.eventTypes block:^(MXRoomData *roomData, MXEvent *event, BOOL isLive) {
            self.listenerBlock(self.sender, event, isLive);
        }];
    }

}

- (void)removeSpiedRoomData:(MXRoomData*)roomData
{
    if ([roomDataEventListeners objectForKey:roomData.room_id])
    {
        [roomData unregisterListener:roomDataEventListeners[roomData.room_id]];
        [roomDataEventListeners removeObjectForKey:roomData.room_id];
    }
}

- (void)removeAllSpiedRoomDatas
{
    // Here sender is the MXData instance. @TODO: not nice
    MXSession *matrixData = (MXSession *)self.sender;
    
    for (NSString *room_id in roomDataEventListeners)
    {
        MXRoomData *roomData = [matrixData getRoomData:room_id];
        [roomData unregisterListener:roomDataEventListeners[roomData.room_id]];
        
    }
    [roomDataEventListeners removeAllObjects];
}

@end
