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

#ifndef MXRestClientStub_h
#define MXRestClientStub_h

#import "MXRestClient.h"
#import "MXAggregationPaginatedResponse.h"

/**
 Stubbed version of MXRestClient which can be used in unit tests without making any actual API calls
 */
@interface MXRestClientStub : MXRestClient

/**
 Stubbed data that will be returned when calling `stateOfRoom` instead of making HTTP requests
 */
@property (nonatomic, strong) NSDictionary<NSString *, NSArray <NSDictionary *>*> *stubbedStatePerRoom;

/**
 Stubbed data that will be returned when calling `relationsForEvent` instead of making HTTP requests
 */
@property (nonatomic, strong) NSDictionary<NSString *, MXAggregationPaginatedResponse *> *stubbedRelatedEventsPerEvent;

@end

#endif /* MXRestClientStub_h */
