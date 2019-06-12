/*
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

#import "MXAggregatedEditsUpdater.h"

#import "MXEventRelations.h"
#import "MXEventReplace.h"
#import "MXEventEditsListener.h"

@interface MXAggregatedEditsUpdater ()

@property (nonatomic) NSString *myUserId;
@property (nonatomic, weak) id<MXStore> matrixStore;
@property (nonatomic) NSMutableArray<MXEventEditsListener*> *listeners;

@end

@implementation MXAggregatedEditsUpdater

- (instancetype)initWithMyUser:(NSString*)userId
              aggregationStore:(id<MXAggregationsStore>)store
                   matrixStore:(id<MXStore>)matrixStore
{
    self = [super init];
    if (self)
    {
        self.myUserId = userId;
        self.matrixStore = matrixStore;

        self.listeners = [NSMutableArray array];
    }
    return self;
}


#pragma mark - Data update listener

- (id)listenToEditsUpdateInRoom:(NSString *)roomId block:(void (^)(MXEvent* replaceEvent))block
{
    MXEventEditsListener *listener = [MXEventEditsListener new];
    listener.roomId = roomId;
    listener.notificationBlock = block;
    
    [self.listeners addObject:listener];
    
    return listener;
}

- (void)removeListener:(id)listener
{
    [self.listeners removeObject:listener];
}

#pragma mark - Data update

- (void)handleReplace:(MXEvent *)replaceEvent
{
    NSString *roomId = replaceEvent.roomId;
    MXEvent *event = [self.matrixStore eventWithEventId:replaceEvent.relatesTo.eventId inRoom:roomId];
    
    if (![event.unsignedData.relations.replace.eventId isEqualToString:replaceEvent.eventId])
    {
        MXEvent *editedEvent = [event editedEventFromReplacementEvent:replaceEvent];
        
        if (editedEvent)
        {
            [self.matrixStore replaceEvent:editedEvent inRoom:roomId];
            [self notifyEventEditsListenersOfRoom:roomId replaceEvent:replaceEvent];
        }
    }
}

//- (void)handleRedaction:(MXEvent *)event
//{
//}

#pragma mark - Private

- (void)notifyEventEditsListenersOfRoom:(NSString*)roomId replaceEvent:(MXEvent*)replaceEvent
{
    for (MXEventEditsListener *listener in self.listeners)
    {
        if ([listener.roomId isEqualToString:roomId])
        {
            listener.notificationBlock(replaceEvent);
        }
    }
}

@end
