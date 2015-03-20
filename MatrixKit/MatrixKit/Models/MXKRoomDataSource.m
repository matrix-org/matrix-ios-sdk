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

#import "MXKRoomDataSource.h"

#import "MXKQueuedEvent.h"
#import "MXKRoomBubbleTableViewCell.h"

#import "MXKRoomBubbleMergingMessagesCellData.h"
#import "MXKRoomIncomingBubbleTableViewCell.h"
#import "MXKRoomOutgoingBubbleTableViewCell.h"

#pragma mark - Constant definitions
NSString *const kMXKIncomingRoomBubbleCellIdentifier = @"kMXKIncomingRoomBubbleCellIdentifier";
NSString *const kMXKOutgoingRoomBubbleCellIdentifier = @"kMXKOutgoingRoomBubbleCellIdentifier";;


@interface MXKRoomDataSource () {

    /**
     The listener to incoming events in the room.
     */
    id liveEventsListener;

    /**
     [MXKRoomDataSource paginateBackMessages] or [MXKRoomDataSource paginateBackMessagesToFillRect]
     can be called where as the MXRoom object is not ready.
     `pendingPaginationRequestBlock` stores the request to execute it once MXRoom is ready.
     */
    void (^pendingPaginationRequestBlock)(void);
}

@end

@implementation MXKRoomDataSource

- (instancetype)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)matrixSession {
    self = [super initWithMatrixSession:matrixSession];
    if (self) {

        _roomId = roomId;
        processingQueue = dispatch_queue_create("MXKRoomDataSource", DISPATCH_QUEUE_SERIAL);
        bubbles = [NSMutableArray array];
        eventsToProcess = [NSMutableArray array];
        
        // Set default data and view classes
        // For incoming messages
        [self registerCellDataClass:MXKRoomBubbleMergingMessagesCellData.class forCellIdentifier:kMXKIncomingRoomBubbleCellIdentifier];
        [self registerCellViewClass:MXKRoomIncomingBubbleTableViewCell.class forCellIdentifier:kMXKIncomingRoomBubbleCellIdentifier];
        // And outgoing messages
        [self registerCellDataClass:MXKRoomBubbleMergingMessagesCellData.class forCellIdentifier:kMXKOutgoingRoomBubbleCellIdentifier];
        [self registerCellViewClass:MXKRoomOutgoingBubbleTableViewCell.class forCellIdentifier:kMXKOutgoingRoomBubbleCellIdentifier];

        // Set default MXEvent -> NSString formatter
        _eventFormatter = [[MXKEventFormatter alloc] initWithMatrixSession:self.mxSession];

        // Display only a subset of events
        _eventsFilterForMessages = @[
                                     kMXEventTypeStringRoomName,
                                     kMXEventTypeStringRoomTopic,
                                     kMXEventTypeStringRoomMember,
                                     kMXEventTypeStringRoomMessage
                                     ];

        [self didMXSessionStateChange];
    }
    return self;
}

- (void)dealloc {
    self.delegate = nil;

    if (_room && liveEventsListener) {
        [_room removeListener:liveEventsListener];
        liveEventsListener = nil;
    }
}

- (void)didMXSessionStateChange {

    if (MXSessionStateStoreDataReady < self.mxSession.state) {

        if (!_room) {

            _room = [self.mxSession roomWithRoomId:_roomId];
            if (_room) {
                // @TODO: SDK: we need a reference when paginating back.
                // Else, how to not conflict with other view controller?
                [_room resetBackState];

                // Force to set the filter at the MXRoom level
                self.eventsFilterForMessages = _eventsFilterForMessages;

                // If the view controller requests pagination before _room was ready, it is
                // the right time to do it
                if (pendingPaginationRequestBlock) {
                    pendingPaginationRequestBlock();
                }
            }
            else {
                NSLog(@"[MXKRoomDataSource] The user does not know the room %@", _roomId);
            }

            pendingPaginationRequestBlock = nil;
        }
    }
}

- (void)setEventsFilterForMessages:(NSArray *)eventsFilterForMessages {

    // Remove the previous live listener
    if (liveEventsListener) {
        [_room removeListener:liveEventsListener];
    }

    // And register a new one with the requested filter
    _eventsFilterForMessages = [eventsFilterForMessages copy];
    liveEventsListener = [_room listenToEventsOfTypes:_eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
        if (MXEventDirectionForwards == direction) {
            // Post incoming events for later processing
            [self queueEventForProcessing:event withRoomState:roomState direction:MXEventDirectionForwards];
            [self processQueuedEvents:nil];
        }
    }];
}

- (void)paginateBackMessages:(NSUInteger)numItems success:(void (^)())success failure:(void (^)(NSError *error))failure {

    NSAssert(nil == pendingPaginationRequestBlock, @"paginateBackMessages cannot be called while a paginate request is pending");

    void (^paginate)(void) = ^(void) {

        // Keep events from the past to later processing
        id backPaginateListener = [_room listenToEventsOfTypes:_eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            if (MXEventDirectionBackwards == direction) {
                [self queueEventForProcessing:event withRoomState:roomState direction:MXEventDirectionBackwards];
            }
        }];

        // Launch the pagination
        [_room paginateBackMessages:numItems complete:^{

            // Once done, process retrieved events
            [_room removeListener:backPaginateListener];
            [self processQueuedEvents:success];

        } failure:^(NSError *error) {
            NSLog(@"[MXKRoomDataSource] paginateBackMessages fails. Error: %@", error);

            if (failure) {
                failure(error);
            }
        }];
    };

    // Check MXSession is ready to serve data for the room
    if (MXSessionStateStoreDataReady < self.mxSession.state) {

        // Yes, do it right now
        paginate();
    }
    else {
        // Else postpone the request until MXSession is ready
        pendingPaginationRequestBlock = paginate;
    }
};

- (void)paginateBackMessagesToFillRect:(CGRect)rect success:(void (^)())success failure:(void (^)(NSError *error))failure {

    NSAssert(nil == pendingPaginationRequestBlock, @"paginateBackMessages cannot be called while a paginate request is pending");

    [self paginateBackMessages:10 success:success failure:failure];
}


#pragma mark - Events processing
/**
 Queue an event in order to process its display later.

 @param event the event to process.
 @param roomState the state of the room when the event fired.
 @param direction the order of the events in the arrays
 */
- (void)queueEventForProcessing:(MXEvent*)event withRoomState:(MXRoomState*)roomState direction:(MXEventDirection)direction {

    MXKQueuedEvent *queuedEvent = [[MXKQueuedEvent alloc] initWithEvent:event andRoomState:roomState direction:direction];

    @synchronized(eventsToProcess) {
        [eventsToProcess addObject:queuedEvent];
    }
}

/**
 Start processing prending events.
 
 @param onComplete a block called (on the main thread) when the processing has been done. Can be nil.
 */
- (void)processQueuedEvents:(void (^)())onComplete {

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
}


#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    NSInteger count;
    @synchronized(bubbles) {
        count = bubbles.count;
    }
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    id<MXKRoomBubbleCellDataStoring> bubbleData;
    @synchronized(bubbles) {
        bubbleData = bubbles[indexPath.row];
    }

    // The cell to use depends if this is a message from the user or not
    // Then use the cell class defined by the table view
    MXKRoomBubbleTableViewCell *cell;
    if ([bubbleData.senderId isEqualToString:self.mxSession.matrixRestClient.credentials.userId]) {
        cell = [tableView dequeueReusableCellWithIdentifier:kMXKOutgoingRoomBubbleCellIdentifier forIndexPath:indexPath];
    }
    else {
        cell = [tableView dequeueReusableCellWithIdentifier:kMXKIncomingRoomBubbleCellIdentifier forIndexPath:indexPath];
    }

    // Make the bubble display the data
    [cell render:bubbleData];

    return cell;
}

@end
