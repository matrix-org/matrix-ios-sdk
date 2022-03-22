/*
 * Copyright 2019 The Matrix.org Foundation C.I.C
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <XCTest/XCTest.h>

#import "MXEvent.h"
#import "MXEnumConstants.h"
#import "MXEventRelations.h"
#import "MXEventReplace.h"


static NSString* const kOriginalMessageText = @"Bonjour";
static NSString* const kEditedMessageText = @"I meant Hello";

static NSString* const kOriginalMarkdownMessageText = @"**Bonjour**";
static NSString* const kOriginalMarkdownMessageFormattedText = @"<strong>Bonjour</strong>";
static NSString* const kEditedMarkdownMessageText = @"**I meant Hello**";
static NSString* const kEditedMarkdownMessageFormattedText = @"<strong>I meant Hello</strong>";

@interface MXAggregatedEditsUnitTests : XCTestCase
@end

@implementation MXAggregatedEditsUnitTests

- (void)testEditingEventManually
{
    NSDictionary *messageEventDict = @{
        @"content": @{
            kMXMessageBodyKey: kOriginalMessageText,
            kMXMessageTypeKey: kMXMessageTypeText
        },
        @"event_id": @"$messageeventid:matrix.org",
        @"origin_server_ts": @(1560253386247),
        @"sender": @"@billsam:matrix.org",
        @"type": kMXEventTypeStringRoomMessage,
        @"unsigned": @{
            @"age": @(6117832)
        },
        @"room_id": @"!roomid:matrix.org"
    };
    
    NSDictionary *replaceEventDict = @{
        @"content": @{
            kMXMessageBodyKey: [NSString stringWithFormat:@"* %@", kEditedMessageText],
            kMXMessageContentKeyNewContent: @{
                kMXMessageBodyKey: kEditedMessageText,
                kMXMessageTypeKey: kMXMessageTypeText
            },
            kMXEventRelationRelatesToKey: @{
                kMXEventContentRelatesToKeyEventId: @"$messageeventid:matrix.org",
                kMXEventContentRelatesToKeyRelationType: MXEventRelationTypeReplace
            },
            kMXMessageTypeKey: kMXMessageTypeText
        },
        @"event_id": @"$replaceeventid:matrix.org",
        @"origin_server_ts": @(1560254175300),
        @"sender": @"@billsam:matrix.org",
        @"type": kMXEventTypeStringRoomMessage,
        @"unsigned": @{
            @"age": @(5328779)
        },
        @"room_id": @"!roomid:matrix.org"
    };
    
    
    MXEvent *messageEvent = [MXEvent modelFromJSON:messageEventDict];
    MXEvent *replaceEvent = [MXEvent modelFromJSON:replaceEventDict];
    
    MXEvent *editedEvent = [messageEvent editedEventFromReplacementEvent:replaceEvent];
    
    XCTAssertNotNil(editedEvent);
    XCTAssertTrue(editedEvent.contentHasBeenEdited);
    XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, replaceEvent.eventId);
    XCTAssertEqualObjects(editedEvent.content[kMXMessageBodyKey], kEditedMessageText);
}

- (void)testEditingFormattedEventManually
{
    NSDictionary *messageEventDict = @{
        @"content": @{
            kMXMessageBodyKey: kOriginalMarkdownMessageText,
            @"formatted_body": kOriginalMarkdownMessageFormattedText,
            @"format": kMXRoomMessageFormatHTML,
            kMXMessageTypeKey: kMXMessageTypeText
        },
        @"event_id": @"$messageeventid:matrix.org",
        @"origin_server_ts": @(1560253386247),
        @"sender": @"@billsam:matrix.org",
        @"type": kMXEventTypeStringRoomMessage,
        @"unsigned": @{
            @"age": @(6117832)
        },
        @"room_id": @"!roomid:matrix.org"
    };
    
    NSDictionary *replaceEventDict = @{
        @"content": @{
            kMXMessageBodyKey: [NSString stringWithFormat:@"* %@", kEditedMarkdownMessageText],
            @"formatted_body": [NSString stringWithFormat:@"* %@", kEditedMarkdownMessageFormattedText],
            @"format": kMXRoomMessageFormatHTML,
            kMXMessageContentKeyNewContent: @{
                kMXMessageBodyKey: kEditedMarkdownMessageText,
                @"formatted_body": kEditedMarkdownMessageFormattedText,
                @"format": kMXRoomMessageFormatHTML,
                kMXMessageTypeKey: kMXMessageTypeText
            },
            kMXEventRelationRelatesToKey: @{
                kMXEventContentRelatesToKeyEventId: @"$messageeventid:matrix.org",
                kMXEventContentRelatesToKeyRelationType: MXEventRelationTypeReplace
            },
            kMXMessageTypeKey: kMXMessageTypeText
        },
        @"event_id": @"$replaceeventid:matrix.org",
        @"origin_server_ts": @(1560254175300),
        @"sender": @"@billsam:matrix.org",
        @"type": kMXEventTypeStringRoomMessage,
        @"unsigned": @{
            @"age": @(5328779)
        },
        @"room_id": @"!roomid:matrix.org"
    };
    
    
    MXEvent *messageEvent = [MXEvent modelFromJSON:messageEventDict];
    MXEvent *replaceEvent = [MXEvent modelFromJSON:replaceEventDict];
    
    MXEvent *editedEvent = [messageEvent editedEventFromReplacementEvent:replaceEvent];
    
    XCTAssertNotNil(editedEvent);
    XCTAssertTrue(editedEvent.contentHasBeenEdited);
    XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, replaceEvent.eventId);
    
    XCTAssertEqualObjects(editedEvent.content[kMXMessageBodyKey], kEditedMarkdownMessageText);
    XCTAssertEqualObjects(editedEvent.content[@"formatted_body"], kEditedMarkdownMessageFormattedText);
}

@end

