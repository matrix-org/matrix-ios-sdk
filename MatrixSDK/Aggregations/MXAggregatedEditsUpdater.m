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

@interface MXAggregatedEditsUpdater ()

@property (nonatomic) NSString *myUserId;
@property (nonatomic, weak) id<MXStore> matrixStore;
@property (nonatomic, weak) id<MXAggregationsStore> store;  // TODO(@steve): To remove. As said IRL, we do not need the aggregations db. We update the event directly in matrixStore
//@property (nonatomic) NSMutableArray<MXReactionCountChangeListener*> *listeners;

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
        self.store = store;
        self.matrixStore = matrixStore;

        //self.listeners = [NSMutableArray array];
    }
    return self;
}


#pragma mark - Data update listener

//- (id)listenToEditsUpdateInRoom:(NSString *)roomId block:(void (^)(NSDictionary<NSString *,MXReactionCountChange *> * _Nonnull))block;
//- (void)removeListener:(id)listener;


#pragma mark - Data update

- (void)handleReplace:(MXEvent *)replaceEvent
{
    NSString *roomId = replaceEvent.roomId;
    MXEvent *event = [self.matrixStore eventWithEventId:replaceEvent.relatesTo.eventId inRoom:roomId];
    if (event)
    {
        // TODO(@steve): do all the business to update `event` as if we have received from an initial /sync

        [self.matrixStore storeEventForRoom:roomId event:event direction:MXTimelineDirectionForwards];
    }
}

//- (void)handleRedaction:(MXEvent *)event
//{
//}

@end
