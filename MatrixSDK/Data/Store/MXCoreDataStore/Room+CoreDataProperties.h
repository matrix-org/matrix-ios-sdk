//
//  Room+CoreDataProperties.h
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 14/10/15.
//  Copyright © 2015 matrix.org. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "Room.h"
#import "MXEventEntity.h"

NS_ASSUME_NONNULL_BEGIN

@interface Room (CoreDataProperties)

@property (nullable, nonatomic, retain) NSNumber *hasReachedHomeServerPaginationEnd;
@property (nullable, nonatomic, retain) NSString *paginationToken;
@property (nullable, nonatomic, retain) NSString *roomId;

// The events downloaded so far.
// The order is chronological: the first item is the oldest message.
@property (nullable, nonatomic, retain) NSOrderedSet<MXEventEntity *> *messages;

@property (nullable, nonatomic, retain) NSSet<MXEventEntity *> *state;

@end

@interface Room (CoreDataGeneratedAccessors)

- (void)insertObject:(NSManagedObject *)value inMessagesAtIndex:(NSUInteger)idx;
- (void)removeObjectFromMessagesAtIndex:(NSUInteger)idx;
- (void)insertMessages:(NSArray<MXEventEntity *> *)value atIndexes:(NSIndexSet *)indexes;
- (void)removeMessagesAtIndexes:(MXEventEntity *)indexes;
- (void)replaceObjectInMessagesAtIndex:(NSUInteger)idx withObject:(MXEventEntity *)value;
- (void)replaceMessagesAtIndexes:(NSIndexSet *)indexes withMessages:(NSArray<MXEventEntity *> *)values;
- (void)addMessagesObject:(MXEventEntity *)value;
- (void)removeMessagesObject:(MXEventEntity *)value;
- (void)addMessages:(NSOrderedSet<MXEventEntity *> *)values;
- (void)removeMessages:(NSOrderedSet<MXEventEntity *> *)values;

- (void)addStateObject:(MXEventEntity *)value;
- (void)removeStateObject:(MXEventEntity *)value;
- (void)addState:(NSSet<MXEventEntity *> *)values;
- (void)removeState:(NSSet<MXEventEntity *> *)values;

@end

NS_ASSUME_NONNULL_END
