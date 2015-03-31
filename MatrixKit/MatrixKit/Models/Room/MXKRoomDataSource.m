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

#import "MXKTools.h"

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
     Potential request in progress to join the selected room
     */
    MXHTTPOperation *joinRequestInProgress;

    /**
     The listener to incoming events in the room.
     */
    id liveEventsListener;
    
    /**
     The listener to redaction events in the room.
     */
    id redactionListener;

    /**
     Mapping between events ids and bubbles.
     */
    NSMutableDictionary *eventIdToBubbleMap;

    /**
     Local echo events which requests are pending.
     */
    NSMutableArray *pendingLocalEchoes;
    
    /**
     Typing notifications listener.
     */
    id typingNotifListener;
    
    /**
     List of members who are typing in the room.
     */
    NSArray *currentTypingUsers;
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
    
    if (joinRequestInProgress) {
        [joinRequestInProgress cancel];
        joinRequestInProgress = nil;
    }

    if (_room && liveEventsListener) {
        [_room removeListener:liveEventsListener];
        liveEventsListener = nil;
        
        [_room removeListener:redactionListener];
        redactionListener = nil;
    }
    
    if (_room && typingNotifListener) {
        [_room removeListener:typingNotifListener];
        typingNotifListener = nil;
    }
    currentTypingUsers = nil;
}

- (void)didMXSessionStateChange {

    if (MXSessionStateStoreDataReady < self.mxSession.state) {

        // Check whether the room is not already set (and if no request is in progress to join the room)
        if (!_room && !joinRequestInProgress) {

            MXRoom *selectedRoom = [self.mxSession roomWithRoomId:_roomId];
            if (selectedRoom) {
                // Check first whether we have to join the room
                if (selectedRoom.state.membership == MXMembershipInvite) {
                    joinRequestInProgress = [selectedRoom join:^{
                        joinRequestInProgress = nil;
                        [self didMXSessionStateChange];
                    } failure:^(NSError *error) {
                        joinRequestInProgress = nil;
                        NSLog(@"[MXKRoomDataSource] Failed to join room (%@): %@", selectedRoom.state.displayname, error);
                        // TODO Alert user
                        //                        [[AppDelegate theDelegate] showErrorAsAlert:error];
                    }];
                    return;
                }
                
                _room = selectedRoom;
                
                // @TODO: SDK: we need a reference when paginating back.
                // Else, how to not conflict with other view controller?
                [_room resetBackState];

                // Force to set the filter at the MXRoom level
                self.eventsFilterForMessages = _eventsFilterForMessages;
                
                // Register on typing notif
                [self listenTypingNotifications];
                
                // Update here data source state if it is not already ready
                state = MXKDataSourceStateReady;
            }
            else {
                NSLog(@"[MXKRoomDataSource] The user does not know the room %@", _roomId);
                
                // Update here data source state if it is not already ready
                state = MXKDataSourceStateFailed;
            }
            
            if (self.delegate && [self.delegate respondsToSelector:@selector(dataSource:didStateChange:)]) {
                [self.delegate dataSource:self didStateChange:state];
            }
        }
    }
}

- (void)setEventsFilterForMessages:(NSArray *)eventsFilterForMessages {

    // Remove the previous live listener
    if (liveEventsListener) {
        [_room removeListener:liveEventsListener];
        [_room removeListener:redactionListener];
    }

    // And register a new one with the requested filter
    _eventsFilterForMessages = [eventsFilterForMessages copy];
    liveEventsListener = [_room listenToEventsOfTypes:_eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        if (MXEventDirectionForwards == direction) {

            // Check for local echo suppression
            MXEvent *localEcho;
            if (pendingLocalEchoes.count && [event.userId isEqualToString:mxSession.myUser.userId]) {

                localEcho = [self pendingLocalEchoRelatedToEvent:event];
                if (localEcho) {

                    // Replace the local echo by the true event sent by the homeserver
                    [self replaceLocalEcho:localEcho withEvent:event];
                }
            }

            if (nil == localEcho) {
                // Post incoming events for later processing
                [self queueEventForProcessing:event withRoomState:roomState direction:MXEventDirectionForwards];
                [self processQueuedEvents:nil];
            }
        }
    }];
    
    // Register a listener to handle redaction in live stream
    redactionListener = [_room listenToEventsOfTypes:@[kMXEventTypeStringRoomRedaction] onEvent:^(MXEvent *redactionEvent, MXEventDirection direction, MXRoomState *roomState) {
        
        // Consider only live redaction events
        if (direction == MXEventDirectionForwards) {
            
            // Do the processing on the processing queue
            dispatch_async(processingQueue, ^{
                
                // Check whether a message contains the redacted event
                id<MXKRoomBubbleCellDataStoring> bubbleData = [self cellDataOfEventWithEventId:redactionEvent.redacts];
                if (bubbleData) {
                    NSUInteger remainingEvents = 0;

                    @synchronized (bubbleData) {
                        // Retrieve the original event to redact it
                        NSArray *events = bubbleData.events;
                        MXEvent *redactedEvent = nil;
                        for (MXEvent *event in events) {
                            if ([event.eventId isEqualToString:redactionEvent.redacts]) {
                                redactedEvent = [event prune];
                                redactedEvent.redactedBecause = redactionEvent.originalDictionary;
                                break;
                            }
                        }
                        
                        if (redactedEvent.isState) {
                            // FIXME: The room state must be refreshed here since this redacted event.
                            NSLog(@"[MXKRoomVC] Warning: A state event has been redacted, room state may not be up to date");
                        }
                        
                        if (redactedEvent) {
                            remainingEvents = [bubbleData updateEvent:redactionEvent.redacts withEvent:redactedEvent];
                        }
                    }
                    
                    // If there is no more events, remove the bubble
                    if (0 == remainingEvents) {
                        // Remove the broken link from the map
                        @synchronized (eventIdToBubbleMap) {
                            [eventIdToBubbleMap removeObjectForKey:redactionEvent.redacts];
                        }
                        
                        [self removeCellData:bubbleData];
                        
                        // TODO GFO: check whether the adjacent bubbles can merge together
                    }
                    
                    // Update the delegate on main thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.delegate) {
                            [self.delegate dataSource:self didCellChange:nil];
                        }
                    });
                }
            });
        }
    }];
}

- (void)listenTypingNotifications {
    
    // Remove the previous live listener
    if (typingNotifListener) {
        [_room removeListener:typingNotifListener];
        currentTypingUsers = nil;
    }
    
    // Add typing notification listener
    typingNotifListener = [_room listenToEventsOfTypes:@[kMXEventTypeStringTypingNotification] onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
        
        // Handle only live events
        if (direction == MXEventDirectionForwards) {
            // Retrieve typing users list
            NSMutableArray *typingUsers = [NSMutableArray arrayWithArray:_room.typingUsers];
            // Remove typing info for the current user
            NSUInteger index = [typingUsers indexOfObject:mxSession.myUser.userId];
            if (index != NSNotFound) {
                [typingUsers removeObjectAtIndex:index];
            }
            // Ignore this notification if both arrays are empty
            if (currentTypingUsers.count || typingUsers.count) {
                currentTypingUsers = typingUsers;
                
                if (self.delegate) {
                    [self.delegate dataSource:self didCellChange:nil];
                }
            }
        }
    }];
    currentTypingUsers = _room.typingUsers;
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

    // Check current state
    if (state != MXKDataSourceStateReady) {
        if (failure) {
            failure(nil);
        }
        return;
    }
    
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

- (void)paginateBackMessagesToFillRect:(CGRect)rect success:(void (^)())success failure:(void (^)(NSError *error))failure {

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
    MXEvent *localEcho = [self addLocalEchoForMessageContent:msgContent];

    // Make the request to the homeserver
    [_room sendMessageOfType:msgType content:msgContent success:^(NSString *eventId) {

        // Nothing to do here
        // The local echo will be removed when the corresponding event will come through the events stream

    } failure:^(NSError *error) {

        // Update the local echo with the error state
        localEcho.mxkState = MXKEventStateSendingFailed;
        [self updateLocalEcho:localEcho];
    }];
}

- (void)sendImage:(UIImage *)image success:(void (^)(NSString *))success failure:(void (^)(NSError *))failure {

    // Make sure the uploaded image orientation is up
    image = [MXKTools forceImageOrientationUp:image];

    // @TODO: Does not limit images to jpeg
    NSString *mimetype = @"image/jpeg";
    NSData *imageData = UIImageJPEGRepresentation(image, 0.8);

    // Use the uploader id as fake URL for this image data
    // The URL does not need to be valid as the MediaManager will get the data
    // directly from its cache
    // Pass this id in the URL is a nasty trick to retrieve it later
    MXKMediaLoader *uploader = [MXKMediaManager prepareUploaderWithMatrixSession:mxSession initialRange:0 andRange:1];
    NSString *fakeMediaManagerURL = uploader.uploadId;

    NSString *cacheFilePath = [MXKMediaManager cachePathForMediaWithURL:fakeMediaManagerURL inFolder:self.roomId];
    [MXKMediaManager writeMediaData:imageData toFilePath:cacheFilePath];

    // Prepare the message content for building an echo message
    NSDictionary *msgContent = @{
                                     @"msgtype": kMXMessageTypeImage,
                                     @"body": @"Image",
                                     @"url": fakeMediaManagerURL,
                                     @"info": @{
                                             @"mimetype": mimetype,
                                             @"w": @(image.size.width),
                                             @"h": @(image.size.height),
                                             @"size": @(imageData.length)
                                             }
                                 };
    MXEvent *localEcho = [self addLocalEchoForMessageContent:msgContent withState:MXKEventStateUploading];

    // Launch the upload to the Matrix Content repository
    [uploader uploadData:imageData mimeType:mimetype success:^(NSString *url) {

        // Update the local echo state: move from content uploading to event sending
        localEcho.mxkState = MXKEventStateSending;
        [self updateLocalEcho:localEcho];

        // Update the message content with the mxc:// of the media on the homeserver
        NSMutableDictionary *msgContent2 = [NSMutableDictionary dictionaryWithDictionary:msgContent];
        msgContent2[@"url"] = url;

        // Update the local echo event too. It will be used to suppress this echo in [self pendingLocalEchoRelatedToEvent];
        localEcho.content = msgContent2;

        // Make the final request that posts the image event
        [_room sendMessageOfType:kMXMessageTypeImage content:msgContent2 success:^(NSString *eventId) {

            // Nothing to do here
            // The local echo will be removed when the corresponding event will come through the events stream

        } failure:^(NSError *error) {

            // Update the local echo with the error state
            localEcho.mxkState = MXKEventStateSendingFailed;
            [self updateLocalEcho:localEcho];
        }];

    } failure:^(NSError *error) {

        // Update the local echo with the error state
        localEcho.mxkState = MXKEventStateSendingFailed;

        id<MXKRoomBubbleCellDataStoring> bubbleData = [self cellDataOfEventWithEventId:localEcho.eventId];
        @synchronized (bubbleData) {
            [bubbleData updateEvent:localEcho.eventId withEvent:localEcho];
        }

        // Inform the delegate
        if (self.delegate) {
            [self.delegate dataSource:self didCellChange:nil];
        }
    }];
}


#pragma mark - Private methods
- (MXEvent*)addLocalEchoForMessageContent:(NSDictionary*)msgContent {

    return [self addLocalEchoForMessageContent:msgContent withState:MXKEventStateSending];
}

- (MXEvent*)addLocalEchoForMessageContent:(NSDictionary*)msgContent withState:(MXKEventState)eventState {

    // Make the data source digest this fake local echo message
    MXEvent *localEcho = [_eventFormatter fakeRoomMessageEventForRoomId:_roomId withEventId:nil andContent:msgContent];
    localEcho.mxkState = eventState;

    [self queueEventForProcessing:localEcho withRoomState:_room.state direction:MXEventDirectionForwards];
    [self processQueuedEvents:nil];

    // Register the echo as pending for its future deletion
    [self addPendingLocalEcho:localEcho];

    return localEcho;
}

- (void)updateLocalEcho:(MXEvent*)localEcho {

    // Retrieve the cell data hosting the local echo
    id<MXKRoomBubbleCellDataStoring> bubbleData = [self cellDataOfEventWithEventId:localEcho.eventId];
    @synchronized (bubbleData) {
        [bubbleData updateEvent:localEcho.eventId withEvent:localEcho];
    }

    // Inform the delegate
    if (self.delegate) {
        [self.delegate dataSource:self didCellChange:nil];
    }
}

- (void)replaceLocalEcho:(MXEvent*)localEcho withEvent:(MXEvent*)event {

    // Remove the event from the pending local echo list
    [self removePendingLocalEcho:localEcho];

    // Remove the event from its cell data
    id<MXKRoomBubbleCellDataStoring> bubbleData = [self cellDataOfEventWithEventId:localEcho.eventId];

    NSUInteger remainingEvents;
    @synchronized (bubbleData) {
       remainingEvents = [bubbleData updateEvent:localEcho.eventId withEvent:event];
    }

    // Remove the broken link from the map
    @synchronized (eventIdToBubbleMap) {
        [eventIdToBubbleMap removeObjectForKey:localEcho.eventId];
    }

    // If there is no more events in the bubble, kill it
    if (0 == remainingEvents) {
        [self removeCellData:bubbleData];
    }

    // Update the delegate
    if (self.delegate) {
        [self.delegate dataSource:self didCellChange:nil];
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
                [self.delegate dataSource:self didCellChange:nil];
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
    
    // Update typing flag before rendering
    bubbleData.isTyping = ([currentTypingUsers indexOfObject:bubbleData.senderId] != NSNotFound);

    // Make the bubble display the data
    [cell render:bubbleData];

    return cell;
}


#pragma mark - Local echo suppression
// @TODO: All these dirty methods will be removed once CS v2 is available.

/**
 Add a local echo event waiting for the true event coming down from the event stream.
 
 @param localEcho the local echo.
 */
- (void)addPendingLocalEcho:(MXEvent*)localEcho {

    [pendingLocalEchoes addObject:localEcho];
}

/**
 Remove the local echo from the pending queue.
 
 @discussion
 It can be removed from the list because we received the true event from the event stream
 or the corresponding request has failed.
 */
- (void)removePendingLocalEcho:(MXEvent*)localEcho {

    [pendingLocalEchoes removeObject:localEcho];
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

    MXEvent *localEcho = nil;
    for (NSInteger index = 0; index < pendingLocalEchoes.count; index++) {
        localEcho = [pendingLocalEchoes objectAtIndex:index];
        NSString *pendingEventType = localEcho.content[@"msgtype"];

        if ([msgtype isEqualToString:pendingEventType]) {
            if ([msgtype isEqualToString:kMXMessageTypeText] || [msgtype isEqualToString:kMXMessageTypeEmote]) {
                // Compare content body
                if ([event.content[@"body"] isEqualToString:localEcho.content[@"body"]]) {
                    break;
                }
            } else if ([msgtype isEqualToString:kMXMessageTypeLocation]) {
                // Compare geo uri
                if ([event.content[@"geo_uri"] isEqualToString:localEcho.content[@"geo_uri"]]) {
                    break;
                }
            } else {
                // Here the type is kMXMessageTypeImage, kMXMessageTypeAudio or kMXMessageTypeVideo
                if ([event.content[@"url"] isEqualToString:localEcho.content[@"url"]]) {
                    break;
                }
            }
        }
        localEcho = nil;
    }

    return localEcho;
}

@end
