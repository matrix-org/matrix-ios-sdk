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

#import "MXCoreDataRoom.h"

#import "MXCoreDataEvent.h"

@interface MXCoreDataRoom ()
{
    // This is the position from the end
    NSInteger paginationPosition;
}
@end

@implementation MXCoreDataRoom

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
	// Convert Mantle MXEvent object to MXCoreDataEvent
    MXCoreDataEvent *cdEvent = [self coreDataEventFromEvent:event];

    // For info, do not set the room, it is automatically done by the CoreDataGeneratedAccessors methods
    // Setting it automatically adds the message to the tail of self.messages and prevents insertObject
    // from working
    //cdEvent.room = self;

    if (MXEventDirectionForwards == direction)
    {
        [self addMessagesObject:cdEvent];
    }
    else
    {
        [self insertObject:cdEvent inMessagesAtIndex:0];
    }

    //NSAssert([self coreDataEventWithEventId:event.eventId], @"The event must be in the db (and be unique)");
}

- (void)replaceEvent:(MXEvent*)event
{
    MXCoreDataEvent *cdEvent = [self coreDataEventWithEventId:event.eventId];
    NSUInteger index = [self.messages indexOfObject:cdEvent];

    [self removeObjectFromMessagesAtIndex:index];
    [self.managedObjectContext deleteObject:cdEvent];
    [self.managedObjectContext save:nil];

    [self insertObject:[self coreDataEventFromEvent:event] inMessagesAtIndex:index];
}

- (MXEvent *)eventWithEventId:(NSString *)eventId
{
    MXEvent *event;
    MXCoreDataEvent *cdEvent = [self coreDataEventWithEventId:eventId];
    if (cdEvent)
    {
        event = [self eventFromCoreDataEvent:cdEvent];
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
    for (MXCoreDataEvent *cdEvent in paginatedMessagesEntities)
    {
        [paginatedMessages addObject:[self eventFromCoreDataEvent:cdEvent]];
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
    MXCoreDataEvent *cdEvent;

    if (types)
    {
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataEvent"
                                                  inManagedObjectContext:self.managedObjectContext];
        [fetchRequest setEntity:entity];

        // Use messageForRoom.roomId as filter to search among messages events not state events of the room
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"messageForRoom.roomId == %@ AND type IN %@", self.roomId, types];
        fetchRequest.predicate = predicate;
        fetchRequest.fetchBatchSize = 1;
        fetchRequest.fetchLimit = 1;

        // Sort by age
        fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"ageLocalTs" ascending:NO]];

        NSArray *fetchedObjects = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];
        if (fetchedObjects.count)
        {
            cdEvent = fetchedObjects[0];
        }
    }
    else
    {
        cdEvent = self.messages.lastObject;
    }

    MXEvent *event = [self eventFromCoreDataEvent:cdEvent];
    
    return event;
}

- (void)storeState:(NSArray*)stateEvents
{
    // Butcher mode: Remove everything before setting new state events
    // This can be optimised but the tables in the core data db must be redesigned before
    [self removeState:self.state];
    [self.managedObjectContext save:nil];

    // Convert Mantle MXEvent objects to MXCoreDataEvents
    for (MXEvent *event in stateEvents)
    {
        [self addStateObject:[self coreDataEventFromEvent:event]];
    }
}

- (NSArray*)stateEvents
{
    NSError *error;

    // Do not loop into self.state. It is 30% slower than making the following Core Data requests
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataEvent"
                                              inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];

    // Use stateForRoom.roomId as filter to search among state events not message events of the room
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"stateForRoom.roomId == %@", self.roomId];
    [fetchRequest setPredicate:predicate];
    [fetchRequest setFetchBatchSize:100];

    NSArray *fetchedObjects = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];

    // Convert back self.state MXCoreDataEvents to MXEvents
    NSMutableArray *stateEvents = [NSMutableArray array];
    for (MXCoreDataEvent *cdEvent in fetchedObjects)
    {
        [stateEvents addObject:[self eventFromCoreDataEvent:cdEvent]];
    }

    return stateEvents;
}


#pragma mark - Private methods
- (MXCoreDataEvent *)coreDataEventWithEventId:(NSString *)eventId
{
    NSError *error;

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataEvent"
                                              inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];

    // Use messageForRoom.roomId as filter to search among messages events not state events of the room
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"messageForRoom.roomId == %@ AND eventId == %@", self.roomId, eventId];
    [fetchRequest setPredicate:predicate];
    [fetchRequest setFetchBatchSize:1];
    [fetchRequest setFetchLimit:1];

    MXCoreDataEvent *cdEvent;
    NSArray *fetchedObjects = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];

    NSAssert(fetchedObjects.count <= 1, @"MXCoreData coreDataEventWithEventId: Event with id %@ is not unique (%tu) in the db", eventId, fetchedObjects.count);

    if (fetchedObjects.count)
    {
        cdEvent = fetchedObjects[0];
    }

    return cdEvent;
}


#pragma mark - MXEvent / MXCoreDataEvent conversion
// Do not use MTLManagedObjectSerializing, the Mantle/CoreData bridge, as it is far slower than the
// following code
// TODO: The next step is to directly store MXEvent object in CD.
- (MXEvent*)eventFromCoreDataEvent:(MXCoreDataEvent*)cdEvent
{
    // This method is 4x times quicker than MTLManagedObjectSerializing equivalent
    MXEvent *event = [[MXEvent alloc] init];

    event.roomId = cdEvent.roomId;
    event.eventId = cdEvent.eventId;
    event.userId = cdEvent.userId;
    event.sender = cdEvent.sender;
    event.type = cdEvent.type;
    event.stateKey = cdEvent.stateKey;
    event.ageLocalTs = [cdEvent.ageLocalTs unsignedLongLongValue];
    event.originServerTs = [cdEvent.originServerTs unsignedLongLongValue];
    event.content = cdEvent.content;
    event.prevContent = cdEvent.prevContent;
    event.redactedBecause = cdEvent.redactedBecause;
    event.redacts = cdEvent.redacts;

    return event;
}

- (MXCoreDataEvent*)coreDataEventFromEvent:(MXEvent*)event
{
    // This method is 8x times quicker than MTLManagedObjectSerializing equivalent
    MXCoreDataEvent *cdEvent = [NSEntityDescription
                                  insertNewObjectForEntityForName:@"MXCoreDataEvent"
                                  inManagedObjectContext:self.managedObjectContext];

    cdEvent.roomId = event.roomId;
    cdEvent.eventId = event.eventId;
    cdEvent.userId = event.userId;
    cdEvent.sender = event.sender;
    cdEvent.type = event.type;
    cdEvent.stateKey = event.stateKey;
    cdEvent.ageLocalTs = @(event.ageLocalTs);
    cdEvent.originServerTs = @(event.originServerTs);
    cdEvent.content = event.content;
    cdEvent.prevContent = event.prevContent;
    cdEvent.redactedBecause = event.redactedBecause;
    cdEvent.redacts = event.redacts;

    return cdEvent;
}

@end
