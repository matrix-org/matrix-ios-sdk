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
#import "MXEventRelations.h"
#import "MXEventReferenceChunk.h"


static NSString* const kOriginalMessageText = @"Bonjour";
static NSString* const kThreadedMessage1Text = @"Morning!";


@interface MXAggregatedReferenceUnitTests : XCTestCase
@end

@implementation MXAggregatedReferenceUnitTests

- (void)testReferenceEventManually
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

    NSDictionary *referenceEventDict = @{
        @"content": @{
            kMXMessageBodyKey: kThreadedMessage1Text,
            kMXMessageTypeKey: kMXMessageTypeText,
            kMXEventRelationRelatesToKey: @{
                kMXEventContentRelatesToKeyEventId: @"$messageeventid:matrix.org",
                kMXEventContentRelatesToKeyRelationType: MXEventRelationTypeReplace
            }
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
    MXEvent *referenceEvent = [MXEvent modelFromJSON:referenceEventDict];

    MXEvent *referencedEvent = [messageEvent eventWithNewReferenceRelation:referenceEvent];

    XCTAssertNotNil(referencedEvent);

    MXEventReferenceChunk *references = referencedEvent.unsignedData.relations.reference;
    XCTAssertNotNil(references);
    XCTAssertEqualObjects(references.chunk.firstObject.eventId, @"$replaceeventid:matrix.org");

    XCTAssertEqual(references.count, 1);
    XCTAssertFalse(references.limited);
    XCTAssertEqualObjects(references.chunk.firstObject.type, kMXEventTypeStringRoomMessage);
}

@end
