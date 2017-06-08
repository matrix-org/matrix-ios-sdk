/*
 Copyright 2017 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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
        [updaterPerSession setObject:updater forKey:mxSession];
    }

    return updater;
}


#pragma mark - MXRoomSummaryUpdating

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withLastEvent:(MXEvent *)event eventState:(MXRoomState *)eventState roomState:(MXRoomState *)roomState
{
    // Do not show redaction events
    if (event.eventType == MXEventTypeRoomRedaction)
    {
        if ([event.redacts isEqualToString:summary.lastMessageEventId])
        {
            [summary resetLastMessage:nil failure:^(NSError *error) {
                NSLog(@"[MXRoomSummaryUpdater] updateRoomSummary: Cannot reset last message after redaction. Room: %@", summary.roomId);
            } commit:YES];
        }
        return NO;
    }

    // Accept redacted event only if configured
    if (_ignoreRedactedEvent && event.isRedactedEvent)
    {
        return NO;
    }

    BOOL updated = NO;

    // Accept event which type is in the filter list
    if (event.eventId && (!_eventsFilterForMessages || (NSNotFound != [_eventsFilterForMessages indexOfObject:event.type])))
    {
        // Accept event related to profile change only if the flag is NO
        if (!_ignoreMemberProfileChanges || !event.isUserProfileChange)
        {
            summary.lastMessageEvent = event;
            updated = YES;
        }
    }

    return updated;
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withStateEvents:(NSArray<MXEvent *> *)stateEvents
{
    MXRoom *room = summary.room;
    if (!room.state)
    {
        // Should not happen
        NSLog(@"[MXRoomSummaryUpdater] updateRoomSummary withStateEvents: room.state not ready");
        return NO;
    }

    BOOL updated = NO;

    for (MXEvent *event in stateEvents)
    {
        switch (event.eventType)
        {
            case MXEventTypeRoomName:
                summary.displayname = room.state.displayname;
                updated = YES;
                break;

            case MXEventTypeRoomAvatar:
                summary.avatar = room.state.avatar;
                updated = YES;
                break;

            case MXEventTypeRoomTopic:
                summary.topic = room.state.topic;
                updated = YES;
                break;

            case MXEventTypeRoomEncryption:
                summary.isEncrypted = room.state.isEncrypted;
                updated = YES;
                break;

            default:
                break;
        }
    }

    return updated;
}

@end
