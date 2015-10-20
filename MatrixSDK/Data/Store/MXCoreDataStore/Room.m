/*
 Copyright 2015 OpenMarket Ltd

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

#import "Room.h"

#import "MXEventEntity+CoreDataProperties.h"

@interface Room ()
{
    // This is the position from the end
    NSInteger paginationPosition;
}
@end

@implementation Room

- (instancetype)init
{
    self = [super init];
    if (self)
    {
    }
    return self;
}

- (void)storeEvent:(MXEvent *)event direction:(MXEventDirection)direction
{
	// Convert Mantle MXEvent objectsto MXEventEntitie
    MXEventEntity *eventEntity = [self eventEntityFromEvent:event];

    // For info, do not set the room, it is automatically done by the CoreDataGeneratedAccessors methods
    // Setting it automatically adds the message to the tail of self.messages and prevents insertObject
    // from working
    //eventEntity.room = self;

    if (MXEventDirectionForwards == direction)
    {
        [self addMessagesObject:eventEntity];
    }
    else
    {
        [self insertObject:eventEntity inMessagesAtIndex:0];
    }

    //NSAssert([self eventEntityWithEventId:event.eventId], @"The event must be in the db (and be unique)");
}

- (void)replaceEvent:(MXEvent*)event
{
    MXEventEntity *eventEntity = [self eventEntityWithEventId:event.eventId];
    NSUInteger index = [self.messages indexOfObject:eventEntity];

    [self removeObjectFromMessagesAtIndex:index];
    [self.managedObjectContext deleteObject:eventEntity];
    [self.managedObjectContext save:nil];

    [self insertObject:[self eventEntityFromEvent:event] inMessagesAtIndex:index];
}

- (MXEvent *)eventWithEventId:(NSString *)eventId
{
    MXEvent *event;
    MXEventEntity *eventEntity = [self eventEntityWithEventId:eventId];
    if (eventEntity)
    {
        event = [self eventFromEventEntity:eventEntity];
    }
    return event;
}

- (void)resetPagination
{
    paginationPosition = self.messages.count;
}

- (NSArray *)paginate:(NSUInteger)numMessages
{
    NSArray *paginatedMessagesEntities;

    if (0 < paginationPosition)
    {
        if (numMessages < paginationPosition)
        {
            // Return a slice of messages
            paginatedMessagesEntities = [self.messages.array subarrayWithRange:NSMakeRange(paginationPosition - numMessages, numMessages)];
            paginationPosition -= numMessages;
        }
        else
        {
            // Return the last slice of messages
            paginatedMessagesEntities = [self.messages.array subarrayWithRange:NSMakeRange(0, paginationPosition)];
            paginationPosition = 0;
        }
    }

    NSMutableArray *paginatedMessages = [NSMutableArray arrayWithCapacity:paginatedMessagesEntities.count];
    for (MXEventEntity *eventEntity in paginatedMessagesEntities)
    {
        [paginatedMessages addObject:[self eventFromEventEntity:eventEntity]];
    }

    return paginatedMessages;
}

- (NSUInteger)remainingMessagesForPagination
{
    return paginationPosition;
}

- (MXEvent*)lastMessageWithTypeIn:(NSArray*)types
{
    NSError *error;
    MXEventEntity *eventEntity;

    if (types)
    {
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXEventEntity"
                                                  inManagedObjectContext:self.managedObjectContext];
        [fetchRequest setEntity:entity];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"messageForRoom.roomId == %@ AND type IN %@", self.roomId, types];
        [fetchRequest setPredicate:predicate];
        [fetchRequest setFetchLimit:1];

        NSArray *fetchedObjects = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];
        if (fetchedObjects.count)
        {
            eventEntity = fetchedObjects[0];
        }
    }
    else
    {
        eventEntity = self.messages.lastObject;
    }

    MXEvent *event = [self eventFromEventEntity:eventEntity];
    
    return event;
}

- (void)storeState:(NSArray*)stateEvents
{
    // Butcher mode: Remove everything before setting new state events
    // This can be optimised but the tables in the core data db must be redesigned before
    [self removeState:self.state];
    [self.managedObjectContext save:nil];

    // Convert Mantle MXEvent objects to MXEventEntities
    for (MXEvent *event in stateEvents)
    {
        [self addStateObject:[self eventEntityFromEvent:event]];
    }
}

- (NSArray*)stateEvents
{
    // Convert back self.state MXEventEntities to MXEvents
    NSMutableArray *stateEvents = [NSMutableArray arrayWithCapacity:self.state.count];
    for (MXEventEntity *eventEntity in self.state)
    {
        [stateEvents addObject:[self eventFromEventEntity:eventEntity]];
    }

    return stateEvents;
}


#pragma mark - Private methods
- (MXEventEntity *)eventEntityWithEventId:(NSString *)eventId
{
    NSError *error;

    // TODO: how to efficiently search into only self.messages excluding events in self.state?
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXEventEntity"
                                              inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];

    // Use messageForRoom.roomId as filter to search among messages events not state events of the room
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"messageForRoom.roomId == %@ AND eventId == %@", self.roomId, eventId];
    [fetchRequest setPredicate:predicate];
    [fetchRequest setFetchLimit:1];

    MXEventEntity *eventEntity;
    NSArray *fetchedObjects = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];

    // TODO: the same: how to efficiently search into only self.messages excluding events in self.state?
    NSMutableArray *fetchedObjects2 = [NSMutableArray array];
    for (MXEventEntity *fetchedObject in fetchedObjects)
    {
        if (NSNotFound != [self.messages indexOfObject:fetchedObject])
        {
            [fetchedObjects2 addObject:fetchedObject];
        }
    }

    NSAssert(fetchedObjects2.count <= 1, @"MXCoreData eventEntityWithEventId: Event with id %@ is not unique (%tu) in the db", eventId, fetchedObjects2.count);

    if (fetchedObjects2.count)
    {
        eventEntity = fetchedObjects2[0];
    }

    return eventEntity;
}


#pragma mark - MXEvent / MXEventEntity conversion
// Do not use MTLManagedObjectSerializing, the Mantle/CoreData bridge, as it is far slower than the
// following code
// TODO: The next step is to directly store MXEvent object in CD.
- (MXEvent*)eventFromEventEntity:(MXEventEntity*)eventEntity
{
    // This method is 4x times quicker than MTLManagedObjectSerializing equivalent
    MXEvent *event = [[MXEvent alloc] init];

    event.roomId = eventEntity.roomId;
    event.eventId = eventEntity.eventId;
    event.userId = eventEntity.userId;
    event.sender = eventEntity.sender;
    event.type = eventEntity.type;
    event.stateKey = eventEntity.stateKey;
    event.ageLocalTs = [eventEntity.ageLocalTs unsignedLongLongValue];
    event.originServerTs = [eventEntity.originServerTs unsignedLongLongValue];
    event.content = eventEntity.content;
    event.prevContent = eventEntity.prevContent;
    event.redactedBecause = eventEntity.redactedBecause;
    event.redacts = eventEntity.redacts;

    return event;
}

- (MXEventEntity*)eventEntityFromEvent:(MXEvent*)event
{
    // This method is 8x times quicker than MTLManagedObjectSerializing equivalent
    MXEventEntity *eventEntity = [NSEntityDescription
                                  insertNewObjectForEntityForName:@"MXEventEntity"
                                  inManagedObjectContext:self.managedObjectContext];

    eventEntity.roomId = event.roomId;
    eventEntity.eventId = event.eventId;
    eventEntity.userId = event.userId;
    eventEntity.sender = event.sender;
    eventEntity.type = event.type;
    eventEntity.stateKey = event.stateKey;
    eventEntity.ageLocalTs = @(event.ageLocalTs);
    eventEntity.originServerTs = @(event.originServerTs);
    eventEntity.content = event.content;
    eventEntity.prevContent = event.prevContent;
    eventEntity.redactedBecause = event.redactedBecause;
    eventEntity.redacts = event.redacts;

    return eventEntity;
}

@end
