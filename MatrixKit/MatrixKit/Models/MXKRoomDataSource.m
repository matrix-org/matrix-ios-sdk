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


#pragma mark - Constant definitions
NSString *const kMXKIncomingRoomBubbleCellIdentifier = @"kMXKIncomingRoomBubbleCellIdentifier";
NSString *const kMXKOutgoingRoomBubbleCellIdentifier = @"kMXKOutgoingRoomBubbleCellIdentifier";;


@interface MXKRoomDataSource ()

@end

@implementation MXKRoomDataSource

- (instancetype)initWithRoom:(MXRoom *)aRoom andMatrixSession:(MXSession *)session {
    self = [super init];
    if (self) {

        room = aRoom;
        mxSession = session;
        processingQueue = dispatch_queue_create("MXKRoomDataSource", DISPATCH_QUEUE_SERIAL);
        bubbles = [NSMutableArray array];
        eventsToProcess = [NSMutableArray array];

        // @TODO: SDK: we need a reference when paginating back.
        // Else, how to not conflict with other view controller?
        [room resetBackState];

        // Listen to live events in the room
        // @TODO: How to set events filter?
        [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

            if (MXEventDirectionForwards == direction) {
                // Post incoming events for later processing
                [self queueEventForProcessing:event withRoomState:roomState direction:MXEventDirectionForwards];
                [self processQueuedEvents:nil];
            }
        }];
    }
    return self;
}

- (void)dealloc {
    // @TODO: In the future, we should release the delegate hete
    // Check it works
}

- (void)paginateBackMessages:(NSUInteger)numItems success:(void (^)())success failure:(void (^)(NSError *error))failure {

    // Keep events from the past to later processing
    id backPaginateListener = [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
        if (MXEventDirectionBackwards == direction) {
            [self queueEventForProcessing:event withRoomState:roomState direction:MXEventDirectionBackwards];
        }
    }];

    // Launch the pagination
    [room paginateBackMessages:numItems complete:^{

        // Once done, process retrieved events
        [room removeListener:backPaginateListener];
        [self processQueuedEvents:success];

    } failure:^(NSError *error) {
        NSLog(@"[MXKRoomDataSource] paginateBackMessages fails. Error: %@", error);

        if (failure) {
            failure(error);
        }
    }];
};

- (void)paginateBackMessagesToFillRect:(CGRect)rect success:(void (^)())success failure:(void (^)(NSError *error))failure {
    // @TODO
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

            MXKRoomBubble *bubble = [[MXKRoomBubble alloc] initWithEvent:queuedEvent.event andRoomState:queuedEvent.state];

            // @TODO: Group messages in bubbles
            if (queuedEvent.direction == MXEventDirectionBackwards) {
                [bubblesSnapshot insertObject:bubble atIndex:0];
            }
            else {
                [bubblesSnapshot addObject:bubble];
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

    MXKRoomBubble *bubble;
    @synchronized(bubbles) {
        bubble = bubbles[indexPath.row];
    }

    // The cell to use depends if this is a message from the user or not
    // Then use the cell class defined by the table view
    MXKRoomBubbleTableViewCell *cell;
    if ([bubble.senderId isEqualToString:mxSession.matrixRestClient.credentials.userId]) {
        cell = [tableView dequeueReusableCellWithIdentifier:kMXKOutgoingRoomBubbleCellIdentifier forIndexPath:indexPath];
    }
    else {
        cell = [tableView dequeueReusableCellWithIdentifier:kMXKIncomingRoomBubbleCellIdentifier forIndexPath:indexPath];
    }

    // Make the bubble display the data
    [cell displayBubble:bubble];

    return cell;
}

@end
