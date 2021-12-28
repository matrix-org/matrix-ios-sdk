// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "MXMemoryRoomSummaryStore.h"

@interface MXMemoryRoomSummaryStore()

@property (atomic, strong) NSMutableDictionary<NSString *, id<MXRoomSummaryProtocol>> *cache;

@end

@implementation MXMemoryRoomSummaryStore

- (instancetype)init
{
    if (self = [super init])
    {
        self.cache = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - MXRoomSummaryStore

- (NSArray<NSString *> *)rooms
{
    return self.cache.allKeys;
}

- (NSUInteger)countOfRooms
{
    return self.cache.count;
}

- (void)storeSummary:(id<MXRoomSummaryProtocol>)summary
{
    self.cache[summary.roomId] = summary;
}

- (id<MXRoomSummaryProtocol>)summaryOfRoom:(NSString *)roomId
{
    return self.cache[roomId];
}

- (void)removeSummaryOfRoom:(NSString *)roomId
{
    [self.cache removeObjectForKey:roomId];
}

- (void)removeAllSummaries
{
    [self.cache removeAllObjects];
}

- (void)fetchAllSummaries:(void (^)(NSArray<id<MXRoomSummaryProtocol>> * _Nonnull))completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(self.cache.allValues);
    });
}

@end
