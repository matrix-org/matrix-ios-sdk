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

#import "MXEvent.h"

/**
 The `MXStoreEventsEnumerator` protocol defines an interface that must be implemented 
 in order to iterate on a list of events.

 The `MXStoreEventsEnumerator` implementation must follow the following rules:
     - The enumerator starts on the most recent events of the list
     - The enumarated list of events is mutable: the enumerator must be able to provide
       events that have been added at the head of the events list after the enumerator
       creation
 */
@protocol MXStoreEventsEnumerator <NSObject>

/**
 Return next events in the enumerator.
 
 @eventsCount the number of events to get.
 @return an array of events in chronological order.
 */
- (NSArray<MXEvent*>*)nextEventsBatch:(NSUInteger)eventsCount;

/**
 The current number of events that still remain to get from the enumerator.
 
 @discussion
 For performance reason, the value may be not garanteed when the enumarator is done on a 
 filtered list of events.
 In this case, the implemtation must return NSUIntegerMax.
 */
@property (nonatomic, readonly) NSUInteger remaining;

@end
