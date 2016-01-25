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

#ifdef MXCOREDATA_STORE

NS_ASSUME_NONNULL_BEGIN

@interface MXCoreDataRoom (CoreDataProperties)

@property (nullable, nonatomic, retain) NSNumber *hasReachedHomeServerPaginationEnd;
@property (nullable, nonatomic, retain) NSString *paginationToken;
@property (nullable, nonatomic, retain) NSString *roomId;
@property (nullable, nonatomic, retain) MXCoreDataAccount *account;
@property (nullable, nonatomic, retain) NSOrderedSet<MXCoreDataEvent *> *messages;
@property (nullable, nonatomic, retain) MXCoreDataRoomState *state;

@end

@interface MXCoreDataRoom (CoreDataGeneratedAccessors)

- (void)insertObject:(MXCoreDataEvent *)value inMessagesAtIndex:(NSUInteger)idx;
- (void)removeObjectFromMessagesAtIndex:(NSUInteger)idx;
- (void)insertMessages:(NSArray<MXCoreDataEvent *> *)value atIndexes:(NSIndexSet *)indexes;
- (void)removeMessagesAtIndexes:(NSIndexSet *)indexes;
- (void)replaceObjectInMessagesAtIndex:(NSUInteger)idx withObject:(MXCoreDataEvent *)value;
- (void)replaceMessagesAtIndexes:(NSIndexSet *)indexes withMessages:(NSArray<MXCoreDataEvent *> *)values;
- (void)addMessagesObject:(MXCoreDataEvent *)value;
- (void)removeMessagesObject:(MXCoreDataEvent *)value;
- (void)addMessages:(NSOrderedSet<MXCoreDataEvent *> *)values;
- (void)removeMessages:(NSOrderedSet<MXCoreDataEvent *> *)values;

@end

NS_ASSUME_NONNULL_END

#endif // MXCOREDATA_STORE
