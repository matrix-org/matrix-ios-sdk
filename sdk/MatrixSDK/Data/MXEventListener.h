/*
 Copyright 2014 OpenMarket Ltd
 
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

#import "MXEvent.h"

@class MXRoom;

/**
 Block called when an event of the registered types has been handled by the Matrix SDK.
 
 @param sender the object that handled the event (`MXSession` or `MXRoom` instance)
 @param event the new event.
 @param isLive YES if it is new event.
 */
typedef void (^MXEventListenerBlock)(id sender, MXEvent *event, BOOL isLive);

/**
 The `MXEventListener` class stores information about a listener to MXEvents that
 are handled by the Matrix SDK.
 */
@interface MXEventListener : NSObject

- (instancetype)initWithSender:(id)sender
                 andEventTypes:(NSArray*)eventTypes
              andListenerBlock:(MXEventListenerBlock)listenerBlock;

/**
 Inform the listener about a new event.
 
 The listener will fire `listenerBlock` to its owner if the event matches `eventTypes`.

 @param event the new event.
 @param isLive YES if it is new event.
 */

- (void)notify:(MXEvent*)event isLiveEvent:(BOOL)isLiveEvent;

@property (nonatomic, readonly) id sender;
@property (nonatomic, readonly) NSArray* eventTypes;
@property (nonatomic, readonly) MXEventListenerBlock listenerBlock;

@end
