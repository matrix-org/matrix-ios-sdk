/*
 Copyright 2016 OpenMarket Ltd

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

/**
 Data source which provides the most up-to-date event to an enumerator
 based on the event identifier.
 */
@protocol MXEventsEnumeratorDataSource
- (MXEvent *)eventWithEventId:(NSString *)eventId;
@end

/**
 Generic events enumerator on an array of event identifiers that are
 translated to events on demand.
 */
@interface MXEventsEnumeratorOnArray : NSObject <MXEventsEnumerator>

/**
 Construct an enumerator based on an array of event identifiers.

 @param eventIds the list of event identifiers to enumerate.
                 The order is chronological where the first item is the oldest event
 @param dataSource object responsible for translating an event identifier into
                   the most recent version of the event.
 
 @return the newly created instance.
 */
- (instancetype)initWithEventIds:(NSArray<NSString *> *)eventIds
                      dataSource:(id<MXEventsEnumeratorDataSource>)dataSource;

@end
