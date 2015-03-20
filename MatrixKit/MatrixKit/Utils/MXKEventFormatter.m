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

#import "MXKEventFormatter.h"

#import "MXEvent+MatrixKit.h"

NSString *const kMXKEventFormatterUnsupportedEventDescriptionPrefix = @"Unsupported event: ";

@interface MXKEventFormatter () {
    /**
     The matrix session. Used to get contextual data.
     */
    MXSession *mxSession;
}
@end

@implementation MXKEventFormatter

- (instancetype)initWithMatrixSession:(MXSession *)matrixSession {
    self = [super init];
    if (self) {
        mxSession = matrixSession;
    }
    return self;
}

// Checks whether the event is related to an attachment and if it is supported
- (BOOL)isSupportedAttachment:(MXEvent*)event {
    BOOL isSupportedAttachment = NO;

    if (event.eventType == MXEventTypeRoomMessage) {
        NSString *msgtype = event.content[@"msgtype"];
        NSString *requiredField;

        if ([msgtype isEqualToString:kMXMessageTypeImage]) {
            requiredField = event.content[@"url"];
            if (requiredField.length) {
                isSupportedAttachment = YES;
            }
        } else if ([msgtype isEqualToString:kMXMessageTypeAudio]) {
            // Not supported yet
        } else if ([msgtype isEqualToString:kMXMessageTypeVideo]) {
            requiredField = event.content[@"url"];
            if (requiredField) {
                isSupportedAttachment = YES;
            }
        } else if ([msgtype isEqualToString:kMXMessageTypeLocation]) {
            // Not supported yet
        }
    }
    return isSupportedAttachment;
}

- (NSString*)senderDisplayNameForEvent:(MXEvent*)event withRoomState:(MXRoomState*)roomState {
    // Consider first the current display name defined in provided room state (Note: this room state is supposed to not take the new event into account)
    NSString *senderDisplayName = [roomState memberName:event.userId];
    // Check whether this sender name is updated by the current event (This happens in case of new joined member)
    if ([event.content[@"displayname"] length]) {
        // Use the actual display name
        senderDisplayName = event.content[@"displayname"];
    }
    return senderDisplayName;
}

- (NSString*)senderAvatarUrlForEvent:(MXEvent*)event withRoomState:(MXRoomState*)roomState {
    // Consider first the avatar url defined in provided room state (Note: this room state is supposed to not take the new event into account)
    NSString *senderAvatarUrl = [roomState memberWithUserId:event.userId].avatarUrl;
    // Check whether this avatar url is updated by the current event (This happens in case of new joined member)
    if ([event.content[@"avatar_url"] length]) {
        // Use the actual display name
        senderAvatarUrl = event.content[@"avatar_url"];
    }
    return senderAvatarUrl;
}

- (NSString*)stringFromEvent:(MXEvent*)event withRoomState:(MXRoomState*)roomState error:(MXKEventFormatterError*)error {

    // Check we can output the error
    NSParameterAssert(error);

    *error = MXKEventFormatterErrorNone;

    // Check first whether the event has been redacted
    NSString *redactedInfo = nil;
    BOOL isRedacted = (event.redactedBecause != nil);
    if (isRedacted) {
        NSLog(@"[MXKEventFormatter] Redacted event %@ (%@)", event.description, event.redactedBecause);
        // Check whether redacted information is required
        if (!_isForSubtitle && !_hideRedactions) {
            redactedInfo = @"<redacted>";
            // Consider live room state to resolve redactor name if no roomState is provided
            MXRoomState *aRoomState = roomState ? roomState : [mxSession roomWithRoomId:event.roomId].state;
            NSString *redactedBy = [aRoomState memberName:event.redactedBecause[@"user_id"]];
            NSString *redactedReason = (event.redactedBecause[@"content"])[@"reason"];
            if (redactedReason.length) {
                if (redactedBy.length) {
                    redactedBy = [NSString stringWithFormat:@"by %@ [reason: %@]", redactedBy, redactedReason];
                } else {
                    redactedBy = [NSString stringWithFormat:@"[reason: %@]", redactedReason];
                }
            } else if (redactedBy.length) {
                redactedBy = [NSString stringWithFormat:@"by %@", redactedBy];
            }

            if (redactedBy.length) {
                redactedInfo = [NSString stringWithFormat:@"<redacted %@>", redactedBy];
            }
        }
    }

    // Prepare returned description
    NSString *displayText = nil;
    // Prepare display name for concerned users
    NSString *senderDisplayName = roomState ? [self senderDisplayNameForEvent:event withRoomState:roomState] : event.userId;
    NSString *targetDisplayName = nil;
    if (event.stateKey) {
        targetDisplayName = roomState ? [roomState memberName:event.stateKey] : event.stateKey;
    }

    switch (event.eventType) {
        case MXEventTypeRoomName: {
            NSString *roomName = event.content[@"name"];
            if (isRedacted) {
                if (!redactedInfo) {
                    // Here the event is ignored (no display)
                    return nil;
                }
                roomName = redactedInfo;
            }

            if (roomName.length) {
                displayText = [NSString stringWithFormat:@"%@ changed the room name to: %@", senderDisplayName, roomName];
            } else {
                displayText = [NSString stringWithFormat:@"%@ removed the room name", senderDisplayName];
            }
            break;
        }
        case MXEventTypeRoomTopic: {
            NSString *roomTopic = event.content[@"topic"];
            if (isRedacted) {
                if (!redactedInfo) {
                    // Here the event is ignored (no display)
                    return nil;
                }
                roomTopic = redactedInfo;
            }

            if (roomTopic.length) {
                displayText = [NSString stringWithFormat:@"%@ changed the topic to: %@", senderDisplayName, roomTopic];
            } else {
                displayText = [NSString stringWithFormat:@"%@ removed the topic", senderDisplayName];
            }

            break;
        }
        case MXEventTypeRoomMember: {
            // Presently only change on membership, display name and avatar are supported

            // Retrieve membership
            NSString* membership = event.content[@"membership"];
            NSString *prevMembership = nil;
            if (event.prevContent) {
                prevMembership = event.prevContent[@"membership"];
            }

            // Check whether the sender has updated his profile (the membership is then unchanged)
            if (prevMembership && membership && [membership isEqualToString:prevMembership]) {
                // Is redacted event?
                if (isRedacted) {
                    if (!redactedInfo) {
                        // Here the event is ignored (no display)
                        return nil;
                    }
                    displayText = [NSString stringWithFormat:@"%@ updated their profile %@", senderDisplayName, redactedInfo];;
                } else {
                    // Check whether the display name has been changed
                    NSString *displayname = event.content[@"displayname"];
                    NSString *prevDisplayname =  event.prevContent[@"displayname"];
                    if (!displayname.length) {
                        displayname = nil;
                    }
                    if (!prevDisplayname.length) {
                        prevDisplayname = nil;
                    }
                    if ((displayname || prevDisplayname) && ([displayname isEqualToString:prevDisplayname] == NO)) {
                        if (!prevDisplayname) {
                            displayText = [NSString stringWithFormat:@"%@ set their display name to %@", event.userId, displayname];
                        } else if (!displayname) {
                            displayText = [NSString stringWithFormat:@"%@ removed their display name (previouly named %@)", event.userId, prevDisplayname];
                        } else {
                            displayText = [NSString stringWithFormat:@"%@ changed their display name from %@ to %@", event.userId, prevDisplayname, displayname];
                        }
                    }

                    // Check whether the avatar has been changed
                    NSString *avatar = event.content[@"avatar_url"];
                    NSString *prevAvatar = event.prevContent[@"avatar_url"];
                    if (!avatar.length) {
                        avatar = nil;
                    }
                    if (!prevAvatar.length) {
                        prevAvatar = nil;
                    }
                    if ((prevAvatar || avatar) && ([avatar isEqualToString:prevAvatar] == NO)) {
                        if (displayText) {
                            displayText = [NSString stringWithFormat:@"%@ (picture profile was changed too)", displayText];
                        } else {
                            displayText = [NSString stringWithFormat:@"%@ changed their picture profile", senderDisplayName];
                        }
                    }
                }
            } else {
                // Consider here a membership change
                if ([membership isEqualToString:@"invite"]) {
                    displayText = [NSString stringWithFormat:@"%@ invited %@", senderDisplayName, targetDisplayName];
                } else if ([membership isEqualToString:@"join"]) {
                    displayText = [NSString stringWithFormat:@"%@ joined", senderDisplayName];
                } else if ([membership isEqualToString:@"leave"]) {
                    if ([event.userId isEqualToString:event.stateKey]) {
                        displayText = [NSString stringWithFormat:@"%@ left", senderDisplayName];
                    } else if (prevMembership) {
                        if ([prevMembership isEqualToString:@"join"] || [prevMembership isEqualToString:@"invite"]) {
                            displayText = [NSString stringWithFormat:@"%@ kicked %@", senderDisplayName, targetDisplayName];
                            if (event.content[@"reason"]) {
                                displayText = [NSString stringWithFormat:@"%@: %@", displayText, event.content[@"reason"]];
                            }
                        } else if ([prevMembership isEqualToString:@"ban"]) {
                            displayText = [NSString stringWithFormat:@"%@ unbanned %@", senderDisplayName, targetDisplayName];
                        }
                    }
                } else if ([membership isEqualToString:@"ban"]) {
                    displayText = [NSString stringWithFormat:@"%@ banned %@", senderDisplayName, targetDisplayName];
                    if (event.content[@"reason"]) {
                        displayText = [NSString stringWithFormat:@"%@: %@", displayText, event.content[@"reason"]];
                    }
                }

                // Append redacted info if any
                if (redactedInfo) {
                    displayText = [NSString stringWithFormat:@"%@ %@", displayText, redactedInfo];
                }

                if (!displayText) {
                    *error = MXKEventFormatterErrorUnexpected;
                }
            }
            break;
        }
        case MXEventTypeRoomCreate: {
            NSString *creatorId = event.content[@"creator"];
            if (creatorId) {
                displayText = [NSString stringWithFormat:@"%@ created the room", (roomState ? [roomState memberName:creatorId] : creatorId)];
                // Append redacted info if any
                if (redactedInfo) {
                    displayText = [NSString stringWithFormat:@"%@ %@", displayText, redactedInfo];
                }
            }
            break;
        }
        case MXEventTypeRoomJoinRules: {
            NSString *joinRule = event.content[@"join_rule"];
            if (joinRule) {
                displayText = [NSString stringWithFormat:@"The join rule is: %@", joinRule];
                // Append redacted info if any
                if (redactedInfo) {
                    displayText = [NSString stringWithFormat:@"%@ %@", displayText, redactedInfo];
                }
            }
            break;
        }
        case MXEventTypeRoomPowerLevels: {
            displayText = @"The power level of room members are:";
            NSDictionary *users = event.content[@"users"];
            for (NSString *key in users.allKeys) {
                displayText = [NSString stringWithFormat:@"%@\r\n\u2022 %@: %@", displayText, key, [users objectForKey:key]];
            }
            if (event.content[@"users_default"]) {
                displayText = [NSString stringWithFormat:@"%@\r\n\u2022 %@: %@", displayText, @"default", event.content[@"users_default"]];
            }

            displayText = [NSString stringWithFormat:@"%@\r\nThe minimum power levels that a user must have before acting are:", displayText];
            if (event.content[@"ban"]) {
                displayText = [NSString stringWithFormat:@"%@\r\n\u2022 ban: %@", displayText, event.content[@"ban"]];
            }
            if (event.content[@"kick"]) {
                displayText = [NSString stringWithFormat:@"%@\r\n\u2022 kick: %@", displayText, event.content[@"kick"]];
            }
            if (event.content[@"redact"]) {
                displayText = [NSString stringWithFormat:@"%@\r\n\u2022 redact: %@", displayText, event.content[@"redact"]];
            }
            if (event.content[@"invite"]) {
                displayText = [NSString stringWithFormat:@"%@\r\n\u2022 invite: %@", displayText, event.content[@"invite"]];
            }

            displayText = [NSString stringWithFormat:@"%@\r\nThe minimum power levels related to events are:", displayText];
            NSDictionary *events = event.content[@"events"];
            for (NSString *key in events.allKeys) {
                displayText = [NSString stringWithFormat:@"%@\r\n\u2022 %@: %@", displayText, key, [events objectForKey:key]];
            }
            if (event.content[@"events_default"]) {
                displayText = [NSString stringWithFormat:@"%@\r\n\u2022 %@: %@", displayText, @"events_default", event.content[@"events_default"]];
            }
            if (event.content[@"state_default"]) {
                displayText = [NSString stringWithFormat:@"%@\r\n\u2022 %@: %@", displayText, @"state_default", event.content[@"state_default"]];
            }

            // Append redacted info if any
            if (redactedInfo) {
                displayText = [NSString stringWithFormat:@"%@\r\n %@", displayText, redactedInfo];
            }
            break;
        }
        case MXEventTypeRoomAliases: {
            NSArray *aliases = event.content[@"aliases"];
            if (aliases) {
                displayText = [NSString stringWithFormat:@"The room aliases are: %@", aliases];
                // Append redacted info if any
                if (redactedInfo) {
                    displayText = [NSString stringWithFormat:@"%@\r\n %@", displayText, redactedInfo];
                }
            }
            break;
        }
        case MXEventTypeRoomMessage: {
            // Is redacted?
            if (isRedacted) {
                if (!redactedInfo) {
                    // Here the event is ignored (no display)
                    return nil;
                }
                displayText = redactedInfo;
            } else {
                NSString *msgtype = event.content[@"msgtype"];
                displayText = [event.content[@"body"] isKindOfClass:[NSString class]] ? event.content[@"body"] : nil;

                if ([msgtype isEqualToString:kMXMessageTypeEmote]) {
                    displayText = [NSString stringWithFormat:@"* %@ %@", senderDisplayName, displayText];
                } else if ([msgtype isEqualToString:kMXMessageTypeImage]) {
                    displayText = displayText? displayText : @"image attachment";
                    // Check attachment validity
                    if (![self isSupportedAttachment:event]) {
                        NSLog(@"[MXKEventFormatter] Warning: Unsupported attachment %@", event.description);
                        displayText = @"invalid image attachment";
                        *error = MXKEventFormatterErrorUnsupported;
                    }
                } else if ([msgtype isEqualToString:kMXMessageTypeAudio]) {
                    displayText = displayText? displayText : @"audio attachment";
                    if (![self isSupportedAttachment:event]) {
                        NSLog(@"[MXKEventFormatter] Warning: Unsupported attachment %@", event.description);
                        displayText = [NSString stringWithFormat:@"%@%@", kMXKEventFormatterUnsupportedEventDescriptionPrefix, event.description];
                        *error = MXKEventFormatterErrorUnsupported;
                    }
                } else if ([msgtype isEqualToString:kMXMessageTypeVideo]) {
                    displayText = displayText? displayText : @"video attachment";
                    if (![self isSupportedAttachment:event]) {
                        NSLog(@"[MXKEventFormatter] Warning: Unsupported attachment %@", event.description);
                        displayText = [NSString stringWithFormat:@"%@%@", kMXKEventFormatterUnsupportedEventDescriptionPrefix, event.description];
                        *error = MXKEventFormatterErrorUnsupported;
                    }
                } else if ([msgtype isEqualToString:kMXMessageTypeLocation]) {
                    displayText = displayText? displayText : @"location attachment";
                    if (![self isSupportedAttachment:event]) {
                        NSLog(@"[MXKEventFormatter] Warning: Unsupported attachment %@", event.description);
                        displayText = [NSString stringWithFormat:@"%@%@", kMXKEventFormatterUnsupportedEventDescriptionPrefix, event.description];
                        *error = MXKEventFormatterErrorUnsupported;
                    }
                }

                // Check whether the sender name has to be added
                if (displayText && _isForSubtitle && [msgtype isEqualToString:kMXMessageTypeEmote] == NO) {
                    displayText = [NSString stringWithFormat:@"%@: %@", senderDisplayName, displayText];
                }
            }
            break;
        }
        case MXEventTypeRoomMessageFeedback: {
            NSString *type = event.content[@"type"];
            NSString *eventId = event.content[@"target_event_id"];
            if (type && eventId) {
                displayText = [NSString stringWithFormat:@"Feedback event (id: %@): %@", eventId, type];
                // Append redacted info if any
                if (redactedInfo) {
                    displayText = [NSString stringWithFormat:@"%@ %@", displayText, redactedInfo];
                }
            }
            break;
        }
        case MXEventTypeRoomRedaction: {
            NSString *eventId = event.redacts;
            displayText = [NSString stringWithFormat:@"%@ redacted an event (id: %@)", senderDisplayName, eventId];
        }

        default:
            *error = MXKEventFormatterErrorUnknownEventType;
            break;
    }

    if (!displayText) {
        NSLog(@"[MXKEventFormatter] Warning: Unsupported event %@)", event.description);
        if (!_isForSubtitle && !_hideUnsupportedEvents) {
            // Return event content as unsupported event
            displayText = [NSString stringWithFormat:@"%@%@", kMXKEventFormatterUnsupportedEventDescriptionPrefix, event.description];

            if (MXKEventFormatterErrorNone == *error) {
                *error = MXKEventFormatterErrorUnsupported;
            }
        }
    }
    
    return displayText;
}

- (NSDictionary*)stringAttributesForEvent:(MXEvent*)event {

    UIColor *textColor;
    UIFont *font;
    
    switch (event.mxkState) {
        case MXKEventStateDefault:
            textColor = [UIColor blackColor];
            break;
        case MXKEventStateBing:
            textColor = [UIColor blueColor];
            break;
        case MXKEventStateSending:
            textColor = [UIColor lightGrayColor];
            break;
        case MXKEventStateSendingFailed:
        case MXKEventStateUnsupported:
        case MXKEventStateUnexpected:
        case MXKEventStateUnknownType:
            textColor = [UIColor redColor];
            break;
        default:
            textColor = [UIColor blackColor];
            break;
    }
    
    if (event.isState) {
        font = [UIFont italicSystemFontOfSize:14];
    } else {
        font = [UIFont systemFontOfSize:14];
    }
    
    return @{
             NSForegroundColorAttributeName : textColor,
             NSFontAttributeName: font
             };
}

@end
