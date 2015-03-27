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
NSString *const kMXKRoomBubbleCellDataIdentifier = @"kMXKRoomBubbleCellDataIdentifier";

NSString *const kMXKRoomIncomingTextMsgBubbleTableViewCellIdentifier = @"kMXKRoomIncomingTextMsgBubbleTableViewCellIdentifier";
NSString *const kMXKRoomOutgoingTextMsgBubbleTableViewCellIdentifier = @"kMXKRoomOutgoingTextMsgBubbleTableViewCellIdentifier";
NSString *const kMXKRoomIncomingAttachmentBubbleTableViewCellIdentifier = @"kMXKRoomIncomingAttachmentBubbleTableViewCellIdentifier";
NSString *const kMXKRoomOutgoingAttachmentBubbleTableViewCellIdentifier = @"kMXKRoomOutgoingAttachmentBubbleTableViewCellIdentifier";


@interface MXKRoomDataSource () {

    /**
     The matrix session.
     */
    MXSession *mxSession;

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

    /**
     Mapping between events ids and bubbles.
     */
    NSMutableDictionary *eventIdToBubbleMap;

    /**
     Local echo events which requests are pending.
     */
    NSMutableArray *pendingLocalEchoes;
}

@end

@implementation MXKRoomDataSource

- (instancetype)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)matrixSession {
    self = [super initWithMatrixSession:matrixSession];
    if (self) {

        _roomId = roomId;
        mxSession = matrixSession;
        processingQueue = dispatch_queue_create("MXKRoomDataSource", DISPATCH_QUEUE_SERIAL);
        bubbles = [NSMutableArray array];
        eventsToProcess = [NSMutableArray array];
        eventIdToBubbleMap = [NSMutableDictionary dictionary];
        pendingLocalEchoes = [NSMutableArray array];
        
        // Set default data and view classes
        // Cell data
        [self registerCellDataClass:MXKRoomBubbleMergingMessagesCellData.class forCellIdentifier:kMXKRoomBubbleCellDataIdentifier];
        // For incoming messages
        [self registerCellViewClass:MXKRoomIncomingBubbleTableViewCell.class forCellIdentifier:kMXKRoomIncomingTextMsgBubbleTableViewCellIdentifier];
        [self registerCellViewClass:MXKRoomIncomingBubbleTableViewCell.class forCellIdentifier:kMXKRoomIncomingAttachmentBubbleTableViewCellIdentifier];
        // And outgoing messages
        [self registerCellViewClass:MXKRoomOutgoingBubbleTableViewCell.class forCellIdentifier:kMXKRoomOutgoingTextMsgBubbleTableViewCellIdentifier];
        [self registerCellViewClass:MXKRoomOutgoingBubbleTableViewCell.class forCellIdentifier:kMXKRoomOutgoingAttachmentBubbleTableViewCellIdentifier];
        
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

            // Check for local echo suppression
            if (pendingLocalEchoes.count && [event.userId isEqualToString:mxSession.myUser.userId]) {

                MXEvent *localEchoEvent = [self pendingLocalEchoRelatedToEvent:event];
                if (localEchoEvent) {

                    // Remove the event from the pending local echo list
                    [self removePendingLocalEcho:localEchoEvent];

                    // Remove the local echo from its bubble data
                    [self removeLocalEchoFromCellData:localEchoEvent];
                }
            }

            // Post incoming events for later processing
            [self queueEventForProcessing:event withRoomState:roomState direction:MXEventDirectionForwards];
            [self processQueuedEvents:nil];
        }
    }];
}


#pragma mark - Public methods
- (id<MXKRoomBubbleCellDataStoring>)cellDataAtIndex:(NSInteger)index {

    id<MXKRoomBubbleCellDataStoring> bubbleData;
    @synchronized(bubbles) {
        bubbleData = bubbles[index];
    }
    return bubbleData;
}

-(id<MXKRoomBubbleCellDataStoring>)cellDataOfEventWithEventId:(NSString *)eventId {

    id<MXKRoomBubbleCellDataStoring> bubbleData;
    @synchronized(eventIdToBubbleMap) {
        bubbleData = eventIdToBubbleMap[eventId];
    }
    return bubbleData;
}


#pragma mark - Pagination
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

    NSAssert(nil == pendingPaginationRequestBlock, @"paginateBackMessages cannot be called while a paginate request is processing");

    [self paginateBackMessages:10 success:success failure:failure];
}


#pragma mark - Sending
- (void)sendTextMessage:(NSString *)text success:(void (^)(NSString *))success failure:(void (^)(NSError *))failure {

    MXMessageType msgType = kMXMessageTypeText;

    // Check whether the message is an emote
    if ([text hasPrefix:@"/me "]) {
        msgType = kMXMessageTypeEmote;

        // Remove "/me " string
        text = [text substringFromIndex:4];
    }

    // Prepare the message content for building an echo message
    NSDictionary *msgContent = @{
                                 @"msgtype": msgType,
                                 @"body": text
                                 };

    // Make the data source digest this fake local echo message
    MXEvent *localEcho = [_eventFormatter fakeRoomMessageEventForRoomId:_roomId withEventId:nil andContent:msgContent];
    localEcho.mxkState = MXKEventStateSending;

    [self queueEventForProcessing:localEcho withRoomState:_room.state direction:MXEventDirectionForwards];
    [self processQueuedEvents:nil];

    // Register the echo as pending for its future deletion
    [self addPendingLocalEcho:localEcho];

    // Make the request to the homeserver
    [_room sendMessageOfType:msgType content:msgContent success:^(NSString *eventId) {

        // Nothing to do here
        // The local echo will be removed when the corresponding event will comes through the events stream

    } failure:^(NSError *error) {

        // Update the local echo with the error state
        localEcho.mxkState = MXKEventStateSendingFailed;

        id<MXKRoomBubbleCellDataStoring> bubbleData = [self cellDataOfEventWithEventId:localEcho.eventId];
        @synchronized (bubbleData) {
            [bubbleData updateEvent:localEcho.eventId withEvent:localEcho];
        }

        // Inform the delegate
        if (self.delegate) {
            [self.delegate dataSource:self didChange:nil];
        }
    }];
}


#pragma mark - Private methods
- (void)removeLocalEchoFromCellData:(MXEvent*)localEchoEvent {

    // Remove the event from the cell data
    id<MXKRoomBubbleCellDataStoring> bubbleData = [self cellDataOfEventWithEventId:localEchoEvent.eventId];

    NSUInteger remainingEvents;
    @synchronized (bubbleData) {
        remainingEvents = [bubbleData removeEvent:localEchoEvent.eventId];
    }

    // Remove the broken link from the map
    @synchronized (eventIdToBubbleMap) {
        [eventIdToBubbleMap removeObjectForKey:localEchoEvent.eventId];
    }

    // If there is no more events, kill the bubble
    if (0 == remainingEvents) {
        [self removeCellData:bubbleData];
    }

    // Update the delegate
    if (self.delegate) {
        [self.delegate dataSource:self didChange:nil];
    }
}

- (void)removeCellData:(id<MXKRoomBubbleCellDataStoring>)cellData {

    @synchronized(bubbles) {
        [bubbles removeObject:cellData];
    }
}


#pragma mark - Asynchronous events processing
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
            Class class = [self cellDataClassForCellIdentifier:kMXKRoomBubbleCellDataIdentifier];
            NSAssert([class conformsToProtocol:@protocol(MXKRoomBubbleCellDataStoring)], @"MXKRoomDataSource only manages MXKCellData that conforms to MXKRoomBubbleCellDataStoring protocol");

            BOOL eventManaged = NO;
            id<MXKRoomBubbleCellDataStoring> bubbleData;
            if ([class instancesRespondToSelector:@selector(addEvent:andRoomState:)] && 0 < bubblesSnapshot.count) {

                // Try to concatenate the event to the last or the oldest bubble?
                if (queuedEvent.direction == MXEventDirectionBackwards) {
                    bubbleData = bubblesSnapshot.firstObject;
                }
                else {
                    bubbleData = bubblesSnapshot.lastObject;
                }

                @synchronized (bubbleData) {
                    eventManaged = [bubbleData addEvent:queuedEvent.event andRoomState:queuedEvent.state];
                }
            }

            if (NO == eventManaged) {

                // The event has not been concatenated to an existing cell, create a new bubble for this event
                bubbleData = [[class alloc] initWithEvent:queuedEvent.event andRoomState:queuedEvent.state andRoomDataSource:self];
                if (queuedEvent.direction == MXEventDirectionBackwards) {
                    [bubblesSnapshot insertObject:bubbleData atIndex:0];
                }
                else {
                    [bubblesSnapshot addObject:bubbleData];
                }
            }

            // Store event-bubble link to the map
            @synchronized (eventIdToBubbleMap) {
                eventIdToBubbleMap[queuedEvent.event.eventId] = bubbleData;
            }

            // The event can be now unqueued
            @synchronized (eventsToProcess) {
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

    id<MXKRoomBubbleCellDataStoring> bubbleData = [self cellDataAtIndex:indexPath.row];

    // The cell to use depends if this is a message from the user or not
    // Then use the cell class defined by the table view
    MXKRoomBubbleTableViewCell *cell;
    
    if (bubbleData.isIncoming) {
        if (bubbleData.isAttachment) {
            cell = [tableView dequeueReusableCellWithIdentifier:kMXKRoomIncomingAttachmentBubbleTableViewCellIdentifier forIndexPath:indexPath];
        } else {
            cell = [tableView dequeueReusableCellWithIdentifier:kMXKRoomIncomingTextMsgBubbleTableViewCellIdentifier forIndexPath:indexPath];
        }
    } else if (bubbleData.isAttachment) {
        cell = [tableView dequeueReusableCellWithIdentifier:kMXKRoomOutgoingAttachmentBubbleTableViewCellIdentifier forIndexPath:indexPath];
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:kMXKRoomOutgoingTextMsgBubbleTableViewCellIdentifier forIndexPath:indexPath];
    }

    // Make sure we listen to user actions on the cell
    if (!cell.delegate) {
        cell.delegate = self;
    }

    // Make the bubble display the data
    [cell render:bubbleData];

    return cell;
}


#pragma mark - Local echo suppression
// @TODO: All these dirty methods will be removed once CS v2 is available.

/**
 Add a local echo event waiting for the true event coming down from the event stream.
 
 @param localEchoEvent the local echo.
 */
- (void)addPendingLocalEcho:(MXEvent*)localEchoEvent {

    [pendingLocalEchoes addObject:localEchoEvent];
}

/**
 Remove the local echo from the pending queue.
 
 @discussion
 It can be removed from the list because we received the true event from the event stream
 or the corresponding request has failed.
 */
- (void)removePendingLocalEcho:(MXEvent*)localEchoEvent {

    [pendingLocalEchoes removeObject:localEchoEvent];
}

/**
 Try to determine if an event coming down from the events stream has a local echo.
 
 @param event the event from the events stream
 @return a local echo event corresponding to the event. Nil if there is no match.
 */
- (MXEvent*)pendingLocalEchoRelatedToEvent:(MXEvent*)event {

    // Note: event is supposed here to be an outgoing event received from event stream.
    // This method returns a pending event (if any) whose content matches with received event content.
    NSString *msgtype = event.content[@"msgtype"];

    MXEvent *localEchoEvent = nil;
    for (NSInteger index = 0; index < pendingLocalEchoes.count; index++) {
        localEchoEvent = [pendingLocalEchoes objectAtIndex:index];
        NSString *pendingEventType = localEchoEvent.content[@"msgtype"];

        if ([msgtype isEqualToString:pendingEventType]) {
            if ([msgtype isEqualToString:kMXMessageTypeText] || [msgtype isEqualToString:kMXMessageTypeEmote]) {
                // Compare content body
                if ([event.content[@"body"] isEqualToString:localEchoEvent.content[@"body"]]) {
                    break;
                }
            } else if ([msgtype isEqualToString:kMXMessageTypeLocation]) {
                // Compare geo uri
                if ([event.content[@"geo_uri"] isEqualToString:localEchoEvent.content[@"geo_uri"]]) {
                    break;
                }
            } else {
                // Here the type is kMXMessageTypeImage, kMXMessageTypeAudio or kMXMessageTypeVideo
                if ([event.content[@"url"] isEqualToString:localEchoEvent.content[@"url"]]) {
                    break;
                }
            }
        }
        localEchoEvent = nil;
    }

    return localEchoEvent;
}

@end
