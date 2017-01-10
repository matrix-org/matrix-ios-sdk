/*
 Copyright 2017 OpenMarket Ltd

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

#import "MXRoomSummary.h"

#import "MXRoom.h"
#import "MXSession.h"

NSString *const kMXRoomSummaryDidChangeNotification = @"kMXRoomSummaryDidChangeNotification";

@implementation MXRoomSummary

- (instancetype)initWithRoomId:(NSString *)theRoomId andMatrixSession:(MXSession *)matrixSession
{
    self = [super init];
    if (self)
    {
        _roomId = theRoomId;
        _mxSession = matrixSession;
    }

    return self;
}

- (void)loadFromStore
{
    MXRoom *room = self.room;

    // Well, load it from the room state data
    // @TODO: Make MXStore manage room summaries
    [self updateFromRoomState];

    id<MXEventsEnumerator> messagesEnumerator = room.enumeratorForStoredMessages;
    MXEvent *event = messagesEnumerator.nextEvent;

    MXRoomState *state = self.room.state;

    BOOL lastEventUpdated = NO;
    while (event && !lastEventUpdated)
    {
        if (event.isState)
        {
            // @TODO: udpate state
        }

        lastEventUpdated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event oldState:state];

        event = messagesEnumerator.nextEvent;
    }

    [self save];
}

- (void)save
{
    // @TODO: storage

    // Broadcast the change
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomSummaryDidChangeNotification object:self userInfo:nil];
}

- (MXRoom *)room
{
    // That makes self.room a really weak reference
    return [_mxSession roomWithRoomId:_roomId];
}


- (void)updateFromRoomState
{
    MXRoom *room = self.room;

    // @TODO: Manage all summary properties
    _avatar = room.state.avatar;
    _displayname = room.state.displayname;
    _topic = room.state.topic;
}

#pragma mark - Server sync
- (void)handleJoinedRoomSync:(MXRoomSync*)roomSync
{
    // Handle first changes due to state events
    BOOL updated = NO;
    for (MXEvent *event in roomSync.state.events)
    {
        updated |= [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvent:event];
    }

    // There may be state events in the timeline too
    for (MXEvent *event in roomSync.timeline.events)
    {
        if (event.isState)
        {
            updated |= [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvent:event];
        }
    }

    // Handle the last event starting by the more recent one
    // Then, if the delegate refuses it as last event, pass the previous event.
    BOOL lastEventUpdated = NO;
    MXRoomState *state = self.room.state;
    for (MXEvent *event in roomSync.timeline.events.reverseObjectEnumerator)
    {
        if (event.isState)
        {
            // @TODO: udpate state
        }

        lastEventUpdated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event oldState:state];
        if (lastEventUpdated)
        {
            break;
        }
    }

    if (updated || lastEventUpdated)
    {
        [self save];
    }
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync*)invitedRoomSync
{
    BOOL updated = NO;

    for (MXEvent *event in invitedRoomSync.inviteState.events)
    {
        updated |= [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvent:event];
    }

    // Fake the last event with the invitation event contained in invitedRoomSync.inviteState
    // @TODO: Make sure that is true
    [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:invitedRoomSync.inviteState.events.lastObject oldState:self.room.state];

    if (updated)
    {
        [self save];
    }
}

@end
