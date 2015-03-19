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
NSString *const kMXKRecentCellIdentifier = @"kMXKRecentCellIdentifier";


@interface MXKRecentListDataSource () {

    // The listener to incoming events in the room
    id liveEventsListener;
}

@end

@implementation MXKRecentListDataSource

- (instancetype)initWithMatrixSession:(MXSession *)matrixSession {
    self = [super initWithMatrixSession:matrixSession];
    if (self) {

        cellDataArray = [NSMutableArray array];

        // Set default data and view classes
        [self registerCellDataClass:MXKRecentCellData.class forCellIdentifier:kMXKRecentCellIdentifier];
        [self registerCellViewClass:MXKRecentTableViewCell.class forCellIdentifier:kMXKRecentCellIdentifier];

        // Set default MXEvent -> NSString formatter
        _eventFormatter = [[MXKEventFormatter alloc] initWithMatrixSession:self.mxSession];
        _eventFormatter.isForSubtitle = YES;

        // Display only a subset of events
        self.eventsFilterForMessages = @[
                                         kMXEventTypeStringRoomName,
                                         kMXEventTypeStringRoomTopic,
                                         kMXEventTypeStringRoomMember,
                                         kMXEventTypeStringRoomMessage
                                         ];
    }
    return self;
}

- (void)dealloc {
    self.delegate = nil;
    cellDataArray = nil;

    if (liveEventsListener) {
        liveEventsListener = nil;
    }
}

- (void)didMXSessionStateChange {
    if (MXSessionStateStoreDataReady < self.mxSession.state) {
        [self loadData];
    }
}

- (id<MXKRecentCellDataStoring>)cellDataAtIndex:(NSInteger)index {

    return cellDataArray[index];
}

- (void)didCellDataChange:(id<MXKRecentCellDataStoring>)cellData {

    if (self.delegate) {
        [self.delegate dataSource:self didChange:nil];
    }}

- (void)setEventsFilterForMessages:(NSArray *)eventsFilterForMessages {

    // Remove the previous live listener
    if (liveEventsListener) {
        [self.mxSession removeListener:liveEventsListener];
    }

    // And register a new one with the requested filter
    _eventsFilterForMessages = [eventsFilterForMessages copy];
    liveEventsListener = [self.mxSession listenToEventsOfTypes:_eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
        if (MXEventDirectionForwards == direction) {

            // Check user's membership in live room state (We will remove left rooms from recents)
            MXRoom *mxRoom = [self.mxSession roomWithRoomId:event.roomId];
            BOOL isLeft = (mxRoom == nil || mxRoom.state.membership == MXMembershipLeave || mxRoom.state.membership == MXMembershipBan);

            // Consider this new event as unread only if the sender is not the user and if the room is not visible
            BOOL isUnread = (![event.userId isEqualToString:self.mxSession.matrixRestClient.credentials.userId]
                             /* @TODO: Applicable at this low level? && ![[AppDelegate theDelegate].masterTabBarController.visibleRoomId isEqualToString:event.roomId]*/);

            // Look for the room
            BOOL isFound = NO;
            for (NSUInteger index = 0; index < cellDataArray.count; index++) {
                id<MXKRecentCellDataStoring> cellData = cellDataArray[index];
                if ([event.roomId isEqualToString:cellData.roomId]) {
                    isFound = YES;
                    // Decrement here unreads count for this recent (we will add later the refreshed count)
                    // @TODO unreadCount -= recentRoom.unreadCount;

                    if (isLeft) {
                        // Remove left room
                        [cellDataArray removeObjectAtIndex:index];

                        /* @TODO
                        if (filteredRecents) {
                            NSUInteger filteredIndex = [filteredRecents indexOfObject:recentRoom];
                            if (filteredIndex != NSNotFound) {
                                [filteredRecents removeObjectAtIndex:filteredIndex];
                            }
                        }
                         */
                    } else {
                        if ([cellData updateWithLastEvent:event andRoomState:roomState markAsUnread:isUnread]) {
                            if (index) {
                                // Move this room at first position
                                [cellDataArray removeObjectAtIndex:index];
                                [cellDataArray insertObject:cellData atIndex:0];
                            }
                            // Update filtered recents (if any)
                            /* @TODO: Do it at this level?
                            if (filteredRecents) {
                                NSUInteger filteredIndex = [filteredRecents indexOfObject:recentRoom];
                                if (filteredIndex && filteredIndex != NSNotFound) {
                                    [filteredRecents removeObjectAtIndex:filteredIndex];
                                    [filteredRecents insertObject:recentRoom atIndex:0];
                                }
                            }
                             */
                        }
                        // Refresh global unreads count
                        // @TODO unreadCount += recentRoom.unreadCount;
                    }

                    // Signal change
                    if (self.delegate) {
                        [self.delegate dataSource:self didChange:nil];
                    }
                    break;
                }
            }

            if (!isFound && !isLeft) {
                // Insert in first position this new room
                Class class = [self cellDataClassForCellIdentifier:kMXKRecentCellIdentifier];
                id<MXKRecentCellDataStoring> cellData = [[class alloc] initWithLastEvent:event andRoomState:mxRoom.state markAsUnread:isUnread andRecentListDataSource:self];
                if (cellData) {

                    [cellDataArray insertObject:cellData atIndex:0];

                    // Signal change
                    if (self.delegate) {
                        [self.delegate dataSource:self didChange:nil];
                    }
                }
            }
        }
    }];

    [self loadData];
}


#pragma mark - Events processing
- (void)loadData {
    NSArray *recentEvents = [self.mxSession recentsWithTypeIn:_eventsFilterForMessages];

    // Retrieve the MXKCellData class to manage the data
    Class class = [self cellDataClassForCellIdentifier:kMXKRecentCellIdentifier];
    NSAssert([class conformsToProtocol:@protocol(MXKRecentCellDataStoring)], @"MXKRecentListDataSource only manages MXKCellData that conforms to MXKRecentCellDataStoring protocol");

    for (MXEvent *recentEvent in recentEvents) {

        MXRoom *mxRoom = [self.mxSession roomWithRoomId:recentEvent.roomId];
        id<MXKRecentCellDataStoring> cellData = [[class alloc] initWithLastEvent:recentEvent andRoomState:mxRoom.state markAsUnread:NO andRecentListDataSource:self];
        if (cellData) {
            [cellDataArray addObject:cellData];
        }
    }

    [self.delegate dataSource:self didChange:nil];
}


#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    return cellDataArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    id<MXKRecentCellDataStoring> roomData = [self cellDataAtIndex:indexPath.row];

    MXKRecentTableViewCell *cell  = [tableView dequeueReusableCellWithIdentifier:kMXKRecentCellIdentifier forIndexPath:indexPath];

    // Make the bubble display the data
    [cell render:roomData];

    return cell;
}

@end
