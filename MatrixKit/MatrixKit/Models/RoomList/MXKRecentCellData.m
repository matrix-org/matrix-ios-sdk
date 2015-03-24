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

#import "MXKRecentCellData.h"

#import "MXKRecentListDataSource.h"

@interface MXKRecentCellData () {

    MXKRecentListDataSource *recentListDataSource;

    MXRoom *mxRoom;
    id backPaginationListener;
    MXHTTPOperation *backPaginationOperation;

    // Keep reference on last event (used in case of redaction)
    MXEvent *lastEvent;
}

@end

@implementation MXKRecentCellData
@synthesize room, lastEvent, roomDisplayname, lastEventDescription, lastEventDate, unreadCount, containsBingUnread;

- (instancetype)initWithLastEvent:(MXEvent*)event andRoomState:(MXRoomState*)roomState markAsUnread:(BOOL)isUnread andRecentListDataSource:(MXKRecentListDataSource*)recentListDataSource2 {

    self = [self init];
    if (self) {
        recentListDataSource = recentListDataSource2;
        room = [recentListDataSource.mxSession roomWithRoomId:event.roomId];

        [self updateWithLastEvent:event andRoomState:roomState markAsUnread:isUnread];

        // @TODO: Do some cleaning: following code seems duplicating what updateWithLastEvent: does
        unreadCount = isUnread ? 1 : 0;

        MXKEventFormatterError error;
        lastEventDescription = [recentListDataSource.eventFormatter stringFromEvent:event withRoomState:roomState error:&error];

        // In case of unread, check whether the last event description contains bing words
        containsBingUnread = (isUnread && !event.isState && !event.redactedBecause && NO /*[mxHandler containsBingWord:_lastEventDescription] @TODO*/);

        // Keep ref on event
        lastEvent = event;

        if (!lastEventDescription.length) {
            // Trigger back pagination to get an event with a non empty description
            [self triggerBackPagination];
        }
    }
    return self;
}

- (BOOL)updateWithLastEvent:(MXEvent*)event andRoomState:(MXRoomState*)roomState markAsUnread:(BOOL)isUnread {

    lastEvent = event;
    roomDisplayname = room.state.displayname;

    // Check whether the description of the provided event is not empty
    MXKEventFormatterError error;
    NSString *description = [recentListDataSource.eventFormatter stringFromEvent:event withRoomState:roomState error:&error];

    if (description.length) {
        [self cancelBackPagination];
        // Update current last event
        lastEvent = event;
        lastEventDescription = description;
        lastEventDate = [recentListDataSource.eventFormatter dateStringForEvent:event];
        if (isUnread) {
            unreadCount ++;
            containsBingUnread = (containsBingUnread || (!event.isState && !event.redactedBecause && NO /*[mxHandler containsBingWord:_lastEventDescription] @TODO*/));
        }
        return YES;
    } else if (lastEventDescription.length) {
        // Here we tried to update the last event with a new live one, but the description of this new one is empty.
        // Consider the specific case of redaction event
        if (event.eventType == MXEventTypeRoomRedaction) {
            // Check whether the redacted event is the current last event
            if ([event.redacts isEqualToString:lastEvent.eventId]) {
                // Update last event description
                MXEvent *redactedEvent = [lastEvent prune];
                redactedEvent.redactedBecause = event.originalDictionary;

                lastEventDescription = [recentListDataSource.eventFormatter stringFromEvent:redactedEvent withRoomState:nil error:&error];
                if (!lastEventDescription.length) {
                    // The current last event must be removed, decrement the unread count (if not null)
                    if (unreadCount) {
                        unreadCount--;

                        if (unreadCount == 0) {
                            containsBingUnread = NO;
                        } // else _containsBingUnread may be false, we should perhaps reset this flag here
                    }
                    // Trigger back pagination to get an event with a non empty description
                    [self triggerBackPagination];
                }
                return YES;
            }
        }
    }
    return NO;
}

- (void)resetUnreadCount {
    unreadCount = 0;
    containsBingUnread = NO;
}


- (void)dealloc {
    [self cancelBackPagination];
    lastEvent = nil;
    lastEventDescription = nil;
}

- (void)triggerBackPagination {
    // Add listener if it is not already done
    if (!backPaginationListener) {

        backPaginationListener = [mxRoom listenToEventsOfTypes:recentListDataSource.eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            // Handle only backward events (Sanity check: be sure that the description has not been set by an other way)
            if (direction == MXEventDirectionBackwards && !lastEventDescription.length) {
                if ([self updateWithLastEvent:event andRoomState:roomState markAsUnread:NO]) {
                    // Indicate the change to the data source
                    [recentListDataSource didCellDataChange:self];
                }
            }
        }];

        // Trigger a back pagination by reseting first backState to get room history from live
        [mxRoom resetBackState];
    }

    if (room.canPaginate) {
        backPaginationOperation = [mxRoom paginateBackMessages:10 complete:^{
            backPaginationOperation = nil;
            // Check whether another back pagination is required
            if (!lastEventDescription.length) {
                [self triggerBackPagination];
            }
        } failure:^(NSError *error) {
            backPaginationOperation = nil;
            NSLog(@"[RecentRoom] Failed to paginate back: %@", error);
            [self cancelBackPagination];
        }];
    } else {
        // Force recents refresh
        // Indicate the change to the data source
        [recentListDataSource didCellDataChange:self];
        [self cancelBackPagination];
    }
}

- (void)cancelBackPagination {
    if (backPaginationListener && mxRoom) {
        [mxRoom removeListener:backPaginationListener];
        backPaginationListener = nil;
        mxRoom = nil;
    }
    if (backPaginationOperation) {
        [backPaginationOperation cancel];
        backPaginationOperation = nil;
    }
}

@end
