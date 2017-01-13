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

#import "MXRoomSummaryUpdater.h"

#import "MXRoom.h"

@implementation MXRoomSummaryUpdater

+ (instancetype)roomSummaryUpdaterForSession:(MXSession *)mxSession
{
    static NSMapTable<MXSession*, MXRoomSummaryUpdater*> *updaterPerSession;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        updaterPerSession = [[NSMapTable alloc] init];
    });

    MXRoomSummaryUpdater *updater = [updaterPerSession objectForKey:mxSession];
    if (!updater)
    {
        updater = [[MXRoomSummaryUpdater alloc] init];
    }

    return updater;
}

- (void)updateSummaryFromRoomState:(MXRoomSummary *)summary
{
    MXRoom *room = summary.room;

    // @TODO: Manage all summary properties
    summary.avatar = room.state.avatar;
    summary.displayname = room.state.displayname;
    summary.topic = room.state.topic;
}

#pragma mark - MXRoomSummaryUpdating

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withLastEvent:(MXEvent *)event oldState:(MXRoomState *)oldState
{
    BOOL updated = NO;

    // Accept event which type is in the filter list
    if (event.eventId && (!_eventsFilterForMessages || (NSNotFound != [_eventsFilterForMessages indexOfObject:event.type])))
    {
        // Accept event related to profile change only if the flag is NO
        if (!_ignoreMemberProfileChanges || !event.isUserProfileChange)
        {
            summary.lastEventId = event.eventId;
            updated = YES;
        }
    }

    // @TODO: Manage redaction

    return updated;
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withStateEvent:(MXEvent *)event
{
    // @TODO: this call is a bit too much, no?
    [self updateSummaryFromRoomState:summary];
    return YES;
}

//// @TODO: to use
//- (void)handleNewEvent:(MXEvent*)event oldState:(MXRoomState*)oldState
//{
//    // Update data from room state
//    switch (event.eventType)
//    {
//        case MXEventTypeRoomName:
//            _displayname = _room.state.displayname;
//            break;
//
//        case MXEventTypeRoomAvatar:
//            _avatar = _room.state.avatar;
//            break;
//
//        case MXEventTypeRoomTopic:
//            _topic = _room.state.topic;
//            break;
//
//        case MXEventTypeRoomMember:
//        {
//            // In case of invite, retrieve data from the room state
//            if (_room.state.membership == MXMembershipInvite)
//            {
//                [self updateFromRoomState];
//            }
//        }
//
//        default:
//            break;
//    }
//
//    BOOL updated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withEvent:event oldState:oldState];
//
//    NSLog(@"need to store %@: %@", _roomId, @(updated));
//}


@end
