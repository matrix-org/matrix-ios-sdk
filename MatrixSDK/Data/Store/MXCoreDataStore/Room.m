//
//  Room.m
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 14/10/15.
//  Copyright © 2015 matrix.org. All rights reserved.
//

#import "Room.h"

#import "objc/objc-class.h"

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
    Class currentClass = [self class];
    while (currentClass) {
        // Iterate over all instance methods for this class
        unsigned int methodCount;
        Method *methodList = class_copyMethodList(currentClass, &methodCount);
        unsigned int i = 0;
        for (; i < methodCount; i++) {
            NSLog(@"%@ - %@", [NSString stringWithCString:class_getName(currentClass) encoding:NSUTF8StringEncoding], [NSString stringWithCString:sel_getName(method_getName(methodList[i])) encoding:NSUTF8StringEncoding]);
        }

        free(methodList);
        currentClass = class_getSuperclass(currentClass);
    }
    
    NSError *error;
    MXEventEntity *eventEntity = [MTLManagedObjectAdapter managedObjectFromModel:event
                                                            insertingIntoContext:self.managedObjectContext
                                                                           error:&error];
    if (MXEventDirectionForwards == direction || 0 == self.messages.count)
    {
        NSLog(@"### storeEvent addMessagesObject to %@", self.roomId);
        [self addMessagesObject:eventEntity];
        [self.managedObjectContext save:nil];
    }
    else
    {
        NSLog(@"### storeEvent insertMessages to %@", self.roomId);
        //[self addMessagesObject:eventEntity];
        [self insertMessages:@[eventEntity] atIndexes:[NSIndexSet indexSetWithIndex:0]];
    }
}

- (void)replaceEvent:(MXEvent*)event
{

}

- (MXEvent *)eventWithEventId:(NSString *)eventId
{
    NSError *error;

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXEventEntity"
                                              inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"roomId == %@ AND eventId == %@", self.roomId, eventId];
    [fetchRequest setPredicate:predicate];

    MXEventEntity *eventEntity;
    NSArray *fetchedObjects = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];
    if (fetchedObjects.count)
    {
        eventEntity = fetchedObjects[0];
    }

    MXEvent *event = [MTLManagedObjectAdapter modelOfClass:MXEvent.class
                                         fromManagedObject:eventEntity
                                                     error:&error];

    return event;
}


- (void)resetPagination
{
    paginationPosition = self.messages.count;
}

- (NSArray *)paginate:(NSUInteger)numMessages
{
    NSError *error;

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
            NSLog(@"#### %@", self.messages.array);
            paginatedMessagesEntities = [self.messages.array subarrayWithRange:NSMakeRange(0, paginationPosition)];
            paginationPosition = 0;
        }
    }

    NSMutableArray *paginatedMessages = [NSMutableArray arrayWithCapacity:paginatedMessagesEntities.count];
    for (MXEventEntity *eventEntity in paginatedMessagesEntities)
    {
        MXEvent *event = [MTLManagedObjectAdapter modelOfClass:MXEvent.class
                                             fromManagedObject:eventEntity
                                                         error:&error];

        [paginatedMessages addObject:event];
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

        // TODO
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"roomId == %@ AND type == %@", self.roomId, types[0]];
        [fetchRequest setPredicate:predicate];

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

    MXEvent *event = [MTLManagedObjectAdapter modelOfClass:MXEvent.class
                                         fromManagedObject:eventEntity
                                                     error:&error];
    
    return event;
}

- (void)flush
{
    //self.hasReachedHomeServerPaginationEnd = @NO;
    //paginationPosition = 0;
    //[self removeMessages:self.messages];
    //[self removeState:self.state];
}

//- (NSString *)description
//{
//    return [NSString stringWithFormat:@"%tu messages - paginationToken: %@ - hasReachedHomeServerPaginationEnd: %d", messages.count, _paginationToken, _hasReachedHomeServerPaginationEnd];
//}

@end
