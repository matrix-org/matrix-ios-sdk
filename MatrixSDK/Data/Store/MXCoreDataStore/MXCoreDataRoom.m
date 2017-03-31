/*
 Copyright 2015 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#ifdef MXCOREDATA_STORE

#import "MXCoreDataEvent.h"
#import "MXCoreDataRoomState.h"

@interface MXCoreDataRoom ()
{
    // The pagination references
    NSArray *paginatedMessagesEntities;
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

- (void)storeEvent:(MXEvent *)event direction:(MXTimelineDirection)direction
{
	// Convert Mantle MXEvent object to MXCoreDataEvent
    MXCoreDataEvent *cdEvent = [self coreDataEventFromEvent:event];

    // For info, do not set the room, it is automatically done by the CoreDataGeneratedAccessors methods
    // Setting it automatically adds the message to the tail of self.messages and prevents insertObject
    // from working
    //cdEvent.room = self;

    if (MXTimelineDirectionForwards == direction)
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
    MXCoreDataEvent *cdEvent = [MXCoreDataRoom coreDataEventWithEventId:event.eventId roomId:self.roomId moc:self.managedObjectContext];
    NSUInteger index = [self.messages indexOfObject:cdEvent];

    [self replaceObjectInMessagesAtIndex:index withObject:[self coreDataEventFromEvent:event]];
}

- (MXEvent *)eventWithEventId:(NSString *)eventId
{
    MXEvent *event;
    MXCoreDataEvent *cdEvent = [MXCoreDataRoom coreDataEventWithEventId:eventId roomId:self.roomId moc:self.managedObjectContext];
    if (cdEvent)
    {
        event = [MXCoreDataRoom eventFromCoreDataEvent:cdEvent];
    }
    return event;
}

+ (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId moc:(NSManagedObjectContext*)moc
{
    MXEvent *event;
    MXCoreDataEvent *cdEvent = [MXCoreDataRoom coreDataEventWithEventId:eventId roomId:roomId moc:moc];
    if (cdEvent)
    {
        event = [MXCoreDataRoom eventFromCoreDataEvent:cdEvent];
    }
    return event;
}

- (void)removeAllMessages
{
    [self removeMessagesAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.messages.count)]];
}

- (void)resetPagination
{
    // Take a snapshot of messages in the db
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataEvent"
                                              inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];

    // Search for messages older than the pagination start point event
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"room.roomId == %@", self.roomId];
    fetchRequest.fetchBatchSize = 20;

    // Sort by age
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"ageLocalTs" ascending:YES]];

    NSError *error;
    paginatedMessagesEntities = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];

    paginationOffset = 0;
}

- (NSArray *)paginate:(NSUInteger)numMessages
{
    // Check the message boundary
    NSInteger currentPosition = paginatedMessagesEntities.count - paginationOffset;
    if (currentPosition < numMessages)
    {
        numMessages = currentPosition;
    }

    // Convert `numMessages` Core Data messages into MXEvents
    NSMutableArray *paginatedMessages = [NSMutableArray arrayWithCapacity:numMessages];
    for (NSInteger i = currentPosition - numMessages ; i < currentPosition; i++)
    {
        MXCoreDataEvent *cdEvent = paginatedMessagesEntities[i];
        [paginatedMessages addObject:[MXCoreDataRoom eventFromCoreDataEvent:cdEvent]];
    }

    // Move the pagination cursor
    paginationOffset += numMessages;

    return paginatedMessages;
}

- (NSUInteger)remainingMessagesForPagination
{
    return paginatedMessagesEntities.count - paginationOffset;
}

- (void)storeState:(NSArray*)stateEvents
{
    // Create state entity if not already here
    if (!self.state)
    {
        self.state = [NSEntityDescription
                      insertNewObjectForEntityForName:@"MXCoreDataRoomState"
                      inManagedObjectContext:self.managedObjectContext];

    }

    NSDate *startDate = [NSDate date];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:stateEvents];
    NSLog(@"[MXCoreDataStore] storeStateForRoom CONVERSION in %.3fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

    self.state.state = data;
}

- (NSArray*)stateEvents
{
    NSArray *stateEvents;
    
    if (self.state && self.state.state)
    {
        NSDate *startDate = [NSDate date];
        stateEvents = [NSKeyedUnarchiver unarchiveObjectWithData:self.state.state];
        NSLog(@"[MXCoreDataStore] stateOfRoom CONVERSION in %.3fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
    }

    return stateEvents;
}


#pragma mark - Private methods
+ (MXCoreDataEvent *)coreDataEventWithEventId:(NSString *)eventId roomId:(NSString*)roomId moc:(NSManagedObjectContext*)moc
{
    NSError *error;

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataEvent"
                                              inManagedObjectContext:moc];
    [fetchRequest setEntity:entity];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"eventId == %@", eventId];
    [fetchRequest setPredicate:predicate];
    [fetchRequest setFetchBatchSize:1];
    [fetchRequest setFetchLimit:1];

    MXCoreDataEvent *cdEvent;
    NSArray *fetchedObjects = [moc executeFetchRequest:fetchRequest error:&error];

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
+ (MXEvent*)eventFromCoreDataEvent:(MXCoreDataEvent*)cdEvent
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

#endif //  MXCOREDATA_STORE
