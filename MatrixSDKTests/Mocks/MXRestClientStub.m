// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

#import <Foundation/Foundation.h>
#import "MXRestClientStub.h"

@implementation MXRestClientStub

- (MXHTTPOperation *)stateOfRoom:(NSString *)roomId success:(void (^)(NSArray *))success failure:(void (^)(NSError *))failure
{
    success(self.stubbedStatePerRoom[roomId]);
    return [[MXHTTPOperation alloc] init];
}

- (MXHTTPOperation *)setAccountData:(NSDictionary *)data forType:(NSString *)type success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    if (success)
    {
        success();
    }
    return [[MXHTTPOperation alloc] init];
}

-(MXHTTPOperation *)deleteAccountDataWithType:(NSString *)type success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    if (success)
    {
        success();
    }
    return [MXHTTPOperation new];
}

- (MXHTTPOperation *)syncFromToken:(NSString *)token serverTimeout:(NSUInteger)serverTimeout clientTimeout:(NSUInteger)clientTimeout setPresence:(NSString *)setPresence filter:(NSString *)filterId success:(void (^)(MXSyncResponse *))success failure:(void (^)(NSError *))failure
{
    if (success)
    {
        success(nil);
    }
    return [[MXHTTPOperation alloc] init];
}

- (MXHTTPOperation *)relationsForEvent:(NSString *)eventId inRoom:(NSString *)roomId relationType:(NSString *)relationType eventType:(NSString *)eventType from:(NSString *)from direction:(MXTimelineDirection)direction limit:(NSInteger)limit success:(void (^)(MXAggregationPaginatedResponse *))success failure:(void (^)(NSError *))failure {
    
    MXAggregationPaginatedResponse* response = self.stubbedRelatedEventsPerEvent[eventId];
    
    if (response) {
        success(response);
        return [MXHTTPOperation new];
    } else {
        return [super relationsForEvent:eventId
                                 inRoom:roomId
                           relationType:relationType
                              eventType:eventType
                                   from:from
                              direction:direction
                                  limit:limit
                                success:success
                                failure:failure];
    }
}

@end
