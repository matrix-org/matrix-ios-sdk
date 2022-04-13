/*
 Copyright 2016 OpenMarket Ltd
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

#import <Foundation/Foundation.h>

#import "MXEventsEnumerator.h"
#import "MXEventsEnumeratorOnArray.h"

/**
 Generic events enumerator on an array of event identifiers with a filter on events types.
 */
@interface MXEventsByTypesEnumeratorOnArray : NSObject <MXEventsEnumerator>

/**
 Construct an enumerator based on an array of event identifiers.

 @param eventIds the list of eventIds to enumerate on.
 @param types an array of event types strings to use as a filter filter.
 @param dataSource object responsible for translating an event identifier into
                   the most recent version of the event.

 @return the newly created instance.
 */
- (instancetype)initWithEventIds:(NSArray<NSString *> *)eventIds
                      andTypesIn:(NSArray*)types
                      dataSource:(id<MXEventsEnumeratorDataSource>)dataSource;

@end
