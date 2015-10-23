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
    // The pagination references
    MXEvent *paginationStartEvent;
    NSUInteger paginationOffset;
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

    [self replaceObjectInMessagesAtIndex:index withObject:[self coreDataEventFromEvent:event]];
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
    // Reset the pagination starting point
    paginationStartEvent = [self lastMessageWithTypeIn:nil];
    paginationOffset = 0;
}

- (NSFetchRequest*)nextPaginationFetchRequest
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataEvent"
                                              inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];

    // Search for messages older than the pagination start point event
    NSString *ageLocalTs = [NSString stringWithFormat:@"%tu", paginationStartEvent.ageLocalTs];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"ageLocalTs <= %@ AND messageForRoom.roomId == %@", ageLocalTs, self.roomId];

    return fetchRequest;
}

- (NSArray *)paginate:(NSUInteger)numMessages
{
    NSError *error;
    
    NSFetchRequest* fetchRequest = [self nextPaginationFetchRequest ];
    fetchRequest.fetchBatchSize = numMessages;
    fetchRequest.fetchLimit = numMessages;
    fetchRequest.fetchOffset = paginationOffset;

    // Sort by age. We want the most recents within the [past, paginationStartEvent-paginationOffset] window
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"ageLocalTs" ascending:NO]];

    NSArray *paginatedMessagesEntities = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];

    // Reorder them by time
    NSMutableArray *paginatedMessages = [NSMutableArray arrayWithCapacity:paginatedMessagesEntities.count];
    for (NSInteger i = paginatedMessagesEntities.count - 1; 0 <= i; i--)
    {
        MXCoreDataEvent *cdEvent = paginatedMessagesEntities[i];
        [paginatedMessages addObject:[self eventFromCoreDataEvent:cdEvent]];
    }

    // Move the pagination cursor
    paginationOffset += paginatedMessagesEntities.count;

    return paginatedMessages;
}

- (NSUInteger)remainingMessagesForPagination
{
    NSFetchRequest *fetchRequest = [self nextPaginationFetchRequest];
    return [self.managedObjectContext countForFetchRequest:fetchRequest error:nil] - paginationOffset;
}

- (MXEvent*)lastMessageWithTypeIn:(NSArray*)types
{
    NSError *error;
    MXCoreDataEvent *cdEvent;

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataEvent"
                                              inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];

    // Use messageForRoom.roomId as filter to search among messages events not state events of the room
    NSPredicate *predicate;
    if (types)
    {
        predicate = [NSPredicate predicateWithFormat:@"messageForRoom.roomId == %@ AND type IN %@", self.roomId, types];
    }
    else
    {
        predicate = [NSPredicate predicateWithFormat:@"messageForRoom.roomId == %@", self.roomId];
    }

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

    MXEvent *event = [self eventFromCoreDataEvent:cdEvent];
    
    return event;
}

- (void)storeState:(NSArray*)stateEvents
{
    NSMutableSet *newState = [NSMutableSet set];
    for (MXEvent *event in stateEvents)
    {
        [newState addObject:[self coreDataEventFromEvent:event]];
    }

    self.state = newState;
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
