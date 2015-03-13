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

#import "MXKRecentListDataSource.h"

#import "MXKRecentCellData.h"
#import "MXKRecentTableViewCell.h"

#pragma mark - Constant definitions
NSString *const kMXKRoomCellIdentifier = @"kMXKRoomCellIdentifier";


@interface MXKRecentListDataSource () {

    // The listener to incoming events in the room
    id liveEventsListener;
}

@end

@implementation MXKRecentListDataSource

- (instancetype)initWithMatrixSession:(MXSession *)matrixSession {
    self = [super init];
    if (self) {

        _mxSession = matrixSession;

        // Set default data and view classes
        [self registerCellDataClass:MXKRecentCellData.class forCellIdentifier:kMXKRoomCellIdentifier];
        [self registerCellViewClass:MXKRecentTableViewCell.class forCellIdentifier:kMXKRoomCellIdentifier];

        // Set default MXEvent -> NSString formatter
        _eventFormatter = [[MXKEventFormatter alloc] initWithMatrixSession:_mxSession];
        _eventFormatter.isForSubtitle = YES;

        // Display only a subset of events
        self.eventsFilterForMessages = @[
                                         kMXEventTypeStringRoomName,
                                         kMXEventTypeStringRoomTopic,
                                         kMXEventTypeStringRoomMember,
                                         kMXEventTypeStringRoomMessage
                                         ];;
    }
    return self;
}

- (void)dealloc {
    self.delegate = nil;

    if (liveEventsListener) {
        liveEventsListener = nil;
    }
}

- (void)setEventsFilterForMessages:(NSArray *)eventsFilterForMessages {

    // Remove the previous live listener
    if (liveEventsListener) {
        [_mxSession removeListener:liveEventsListener];
    }

    // And register a new one with the requested filter
    _eventsFilterForMessages = [eventsFilterForMessages copy];
    liveEventsListener = [_mxSession listenToEventsOfTypes:_eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
        if (MXEventDirectionForwards == direction) {
            // Post incoming events for later processing
            //[self queueEventForProcessing:event withRoomState:roomState direction:MXEventDirectionForwards];
            //[self processQueuedEvents:nil];
        }
    }];
}


#pragma mark - Events processing

/**
 Start processing prending events.
 
 @param onComplete a block called (on the main thread) when the processing has been done. Can be nil.
 */
- (void)processQueuedEvents:(void (^)())onComplete {

    /*
    // Do the processing on the processing queue
    dispatch_async(processingQueue, ^{

        // Note: As this block is always called from the same processing queue,
        // only one batch process is done at a time. Thus, an event cannot be
        // processed twice

        // Make a quick copy of changing data to avoid to lock it too long time
        NSMutableArray *eventsToProcessSnapshot;
        @synchronized(eventsToProcess) {
            eventsToProcessSnapshot = [eventsToProcess copy];
        }
        NSMutableArray *bubblesSnapshot;
        @synchronized(bubbles) {
            bubblesSnapshot = [bubbles mutableCopy];
        }

        for (MXKQueuedEvent *queuedEvent in eventsToProcessSnapshot) {

            // Retrieve the MXKCellData class to manage the data
            Class class = [self cellDataClassForCellIdentifier:kMXKIncomingRoomBubbleCellIdentifier];
            NSAssert([class conformsToProtocol:@protocol(MXKRoomBubbleCellDataStoring)], @"MXKRoomDataSource only manages MXKCellData that conforms to MXKRoomBubbleCellDataStoring protocol");

            BOOL eventManaged = NO;
            if ([class instancesRespondToSelector:@selector(addEvent:andRoomState:)] && 0 < bubblesSnapshot.count) {

                // Try to concatenate the event to the last or the oldest bubble?
                id<MXKRoomBubbleCellDataStoring> bubbleData;
                if (queuedEvent.direction == MXEventDirectionBackwards) {
                    bubbleData = bubblesSnapshot.firstObject;
                }
                else {
                    bubbleData = bubblesSnapshot.lastObject;
                }

                eventManaged = [bubbleData addEvent:queuedEvent.event andRoomState:queuedEvent.state];
            }

            if (NO == eventManaged) {
                // The event has not been concatenated to an existing cell, create a new bubble for this event
                id<MXKRoomBubbleCellDataStoring> bubble = [[class alloc] initWithEvent:queuedEvent.event andRoomState:queuedEvent.state andRoomDataSource:self];
                if (queuedEvent.direction == MXEventDirectionBackwards) {
                    [bubblesSnapshot insertObject:bubble atIndex:0];
                }
                else {
                    [bubblesSnapshot addObject:bubble];
                }
            }

            // The event can be now unqueued
            @synchronized(eventsToProcess) {
                [eventsToProcess removeObject:queuedEvent];
            }
        }

        // Updated data can be displayed now
        dispatch_async(dispatch_get_main_queue(), ^{
            bubbles = bubblesSnapshot;

            if (self.delegate) {
                [self.delegate dataSource:self didChange:nil];
            }

            // Inform about the end if requested
            if (onComplete) {
                onComplete();
            }
        });
    });
     */
}


#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    return rooms.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    id<MXKRecentCellDataStoring> roomData = rooms[indexPath.row];

    MXKRecentTableViewCell *cell  = [tableView dequeueReusableCellWithIdentifier:kMXKRoomCellIdentifier forIndexPath:indexPath];

    // Make the bubble display the data
    [cell render:roomData];

    return cell;
}

@end
