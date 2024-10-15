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

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXFileStore.h"
#import "MXEventRelations.h"
#import "MXEventReplace.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

static NSString* const kOriginalMessageText = @"Bonjour";
static NSString* const kEditedMessageText = @"I meant Hello";

static NSString* const kOriginalMarkdownMessageText = @"**Bonjour**";
static NSString* const kOriginalMarkdownMessageFormattedText = @"<strong>Bonjour</strong>";
static NSString* const kEditedMarkdownMessageText = @"**I meant Hello**";
static NSString* const kEditedMarkdownMessageFormattedText = @"<strong>I meant Hello</strong>";

@interface MXAggregatedEditsTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}

@end

@implementation MXAggregatedEditsTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;
    
    [super tearDown];
}

// Create a room with an event with an edit it on it
- (void)createScenario:(void(^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId))readyToTest
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [room sendTextMessage:kOriginalMessageText threadId:nil success:^(NSString *eventId) {
            [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
                [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMessageText formattedText:nil localEchoBlock:nil success:^(NSString * _Nonnull editEventId) {
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        readyToTest(mxSession, room, expectation, eventId, editEventId);
                    });

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Create a room with an event with formatted body with an edit on it
- (void)createScenarioWithFormattedText:(void(^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId))readyToTest
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        [room sendTextMessage:kOriginalMarkdownMessageText threadId:nil success:^(NSString *eventId) {
            [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
                [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMarkdownMessageText formattedText:kEditedMarkdownMessageFormattedText localEchoBlock:nil success:^(NSString * _Nonnull editEventId) {
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        readyToTest(mxSession, room, expectation, eventId, editEventId);
                    });
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Send a message
// - Edit it
// -> an edit m.room.message must appear in the timeline
- (void)testEditSendAndReceive
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        // - Send a message
        [room sendTextMessage:kOriginalMessageText threadId:nil success:^(NSString *eventId) {

            [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {

                // Edit it
                [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMessageText formattedText:nil localEchoBlock:nil success:^(NSString * _Nonnull eventId) {
                     XCTAssertNotNil(eventId);
                 } failure:^(NSError *error) {
                     XCTFail(@"The operation should not fail - NSError: %@", error);
                     [expectation fulfill];
                 }];

                [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    // -> an edit m.room.message must appear in the timeline
                    XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);

                    XCTAssertNotNil(event.relatesTo);
                    XCTAssertEqualObjects(event.relatesTo.relationType, MXEventRelationTypeReplace);
                    XCTAssertEqualObjects(event.relatesTo.eventId, eventId);

                    XCTAssertEqualObjects(event.content[kMXMessageContentKeyNewContent][kMXMessageTypeKey], kMXMessageTypeText);
                    XCTAssertEqualObjects(event.content[kMXMessageContentKeyNewContent][kMXMessageBodyKey], kEditedMessageText);

                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Send a formatted message
// - Edit it
// -> an edit m.room.message must appear in the timeline
- (void)testFormattedEditSendAndReceive
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        // - Send a message
        [room sendTextMessage:kOriginalMarkdownMessageText threadId:nil success:^(NSString *eventId) {
            
            [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
                
                // Edit it
                [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMarkdownMessageText formattedText:kEditedMarkdownMessageFormattedText localEchoBlock:nil success:^(NSString * _Nonnull eventId) {
                    XCTAssertNotNil(eventId);
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    
                    // -> an edit m.room.message must appear in the timeline
                    XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                    
                    XCTAssertNotNil(event.relatesTo);
                    XCTAssertEqualObjects(event.relatesTo.relationType, MXEventRelationTypeReplace);
                    XCTAssertEqualObjects(event.relatesTo.eventId, eventId);
                    
                    NSString *compatibilityBody = [NSString stringWithFormat:@"* %@", kEditedMarkdownMessageText];
                    NSString *compatibilityFormattedBody = [NSString stringWithFormat:@"* %@", kEditedMarkdownMessageFormattedText];

                    XCTAssertEqualObjects(event.content[kMXMessageBodyKey], compatibilityBody);
                    XCTAssertEqualObjects(event.content[@"formatted_body"], compatibilityFormattedBody);

                    XCTAssertEqualObjects(event.content[kMXMessageContentKeyNewContent][kMXMessageTypeKey], kMXMessageTypeText);
                    XCTAssertEqualObjects(event.content[kMXMessageContentKeyNewContent][kMXMessageBodyKey], kEditedMarkdownMessageText);
                    XCTAssertEqualObjects(event.content[kMXMessageContentKeyNewContent][@"formatted_body"], kEditedMarkdownMessageFormattedText);
                    
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// -> Check data is correctly aggregated when fetching the edited event directly from the homeserver
- (void)testEditServerSide
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {

        MXEvent *localEditedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        // -> Check data is correctly aggregated when fetching the edited event directly from the homeserver
        [mxSession.matrixRestClient eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
            
            XCTAssertNotNil(event);
            XCTAssertTrue(event.contentHasBeenEdited);
            XCTAssertEqualObjects(event.unsignedData.relations.replace.eventId, editEventId);
            XCTAssertEqualObjects(event.content[kMXMessageBodyKey], kEditedMessageText);
            
            XCTAssertEqualObjects(event.content, localEditedEvent.content);
            XCTAssertEqualObjects(event.JSONDictionary[@"unsigned"][@"relations"], localEditedEvent.JSONDictionary[@"unsigned"][@"relations"]);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// -> Check data is correctly aggregated when fetching the formatted edited event directly from the homeserver
- (void)testFormattedEditServerSide
{
    // - Run the initial condition scenario
    [self createScenarioWithFormattedText:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {
        
        MXEvent *localEditedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        // -> Check data is correctly aggregated when fetching the edited event directly from the homeserver
        [mxSession.matrixRestClient eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
            
            XCTAssertNotNil(event);
            XCTAssertTrue(event.contentHasBeenEdited);
            XCTAssertEqualObjects(event.unsignedData.relations.replace.eventId, editEventId);
            XCTAssertEqualObjects(event.content[kMXMessageBodyKey], kEditedMarkdownMessageText);
            XCTAssertEqualObjects(event.content[@"formatted_body"], kEditedMarkdownMessageFormattedText);
            
            XCTAssertEqualObjects(event.content, localEditedEvent.content);
            XCTAssertEqualObjects(event.JSONDictionary[@"unsigned"][@"relations"], localEditedEvent.JSONDictionary[@"unsigned"][@"relations"]);
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// - Do an initial sync
// -> Data from aggregations must be right
- (void)testEditsFromInitialSync
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {
        
        MXEvent *editedEventBeforeSync = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];

        MXRestClient *restClient = mxSession.matrixRestClient;

        [mxSession.aggregations resetData];
        [mxSession close];
        mxSession = nil;

        // - Do an initial sync
        mxSession = [[MXSession alloc] initWithMatrixRestClient:restClient];
        [matrixSDKTestsData retain:mxSession];
        [mxSession setStore:[[MXMemoryStore alloc] init] success:^{

            [mxSession start:^{

                MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
                
                // -> Data from aggregations must be right
                XCTAssertNotNil(editedEvent);
                XCTAssertTrue(editedEvent.contentHasBeenEdited);
                XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, editEventId);
                XCTAssertEqualObjects(editedEvent.content[kMXMessageBodyKey], kEditedMessageText);
                
                XCTAssertEqualObjects(editedEvent.content, editedEventBeforeSync.content);
                XCTAssertEqualObjects(editedEvent.JSONDictionary[@"unsigned"][@"relations"], editedEventBeforeSync.JSONDictionary[@"unsigned"][@"relations"]);

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// - Do an initial sync
// -> Data from aggregations must be right
- (void)testFormatedEditsFromInitialSync
{
    // - Run the initial condition scenario
    [self createScenarioWithFormattedText:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {
        
        MXEvent *editedEventBeforeSync = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        MXRestClient *restClient = mxSession.matrixRestClient;
        
        [mxSession.aggregations resetData];
        [mxSession close];
        mxSession = nil;
        
        // - Do an initial sync
        mxSession = [[MXSession alloc] initWithMatrixRestClient:restClient];
        [matrixSDKTestsData retain:mxSession];
        [mxSession setStore:[[MXMemoryStore alloc] init] success:^{
            
            [mxSession start:^{
                
                MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
                
                // -> Data from aggregations must be right
                XCTAssertNotNil(editedEvent);
                XCTAssertTrue(editedEvent.contentHasBeenEdited);
                XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, editEventId);
                XCTAssertEqualObjects(editedEvent.content[kMXMessageBodyKey], kEditedMarkdownMessageText);
                XCTAssertEqualObjects(editedEvent.content[@"formatted_body"], kEditedMarkdownMessageFormattedText);
                
                XCTAssertEqualObjects(editedEvent.content, editedEventBeforeSync.content);
                XCTAssertEqualObjects(editedEvent.JSONDictionary[@"unsigned"][@"relations"], editedEventBeforeSync.JSONDictionary[@"unsigned"][@"relations"]);
                
                [expectation fulfill];
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// -> Data from aggregations must be right
- (void)testEditLive
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {
        
        // -> Data from aggregations must be right
        MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        XCTAssertNotNil(editedEvent);
        XCTAssertTrue(editedEvent.contentHasBeenEdited);
        XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, editEventId);
        XCTAssertEqualObjects(editedEvent.content[kMXMessageBodyKey], kEditedMessageText);
        
        [expectation fulfill];
    }];
}

// - Run the initial condition scenario
// -> Data from aggregations must be right
- (void)testFomattedEditAggregationsLive
{
    // - Run the initial condition scenario
    [self createScenarioWithFormattedText:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {
        
        // -> Data from aggregations must be right
        MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        XCTAssertNotNil(editedEvent);
        XCTAssertTrue(editedEvent.contentHasBeenEdited);
        XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, editEventId);
        XCTAssertEqualObjects(editedEvent.content[kMXMessageBodyKey], kEditedMarkdownMessageText);
        XCTAssertEqualObjects(editedEvent.content[@"formatted_body"], kEditedMarkdownMessageFormattedText);
        
        [expectation fulfill];
    }];
}

// - Run the initial condition scenario
// - Edit 2 times
// -> We must get notified about the second replace event
- (void)testEditsListener
{
    NSString *secondEditionTextMessage = @"Oups";
    
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {
        
        // -> We must get notified about the reaction count change
        [mxSession.aggregations listenToEditsUpdateInRoom:room.roomId block:^(MXEvent * _Nonnull replaceEvent) {
            
            MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
            
            XCTAssertNotNil(editedEvent);
            XCTAssertTrue(editedEvent.contentHasBeenEdited);
            XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, replaceEvent.eventId);
            XCTAssertEqualObjects(editedEvent.content[kMXMessageBodyKey], secondEditionTextMessage);
            
            [expectation fulfill];
        }];
        
        MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        [mxSession.aggregations replaceTextMessageEvent:editedEvent withTextMessage:secondEditionTextMessage formattedText:nil localEchoBlock:nil success:^(NSString * _Nonnull eventId) {
            
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// -> The room summary must contain aggregated data
- (void)testEditInRoomSummary
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {

        // -> The room summary must contain aggregated data
        MXRoomSummary *roomSummary = [mxSession roomSummaryWithRoomId:room.roomId];
        
        XCTAssertNotNil(roomSummary.lastMessage);
        
        [mxSession eventWithEventId:roomSummary.lastMessage.eventId
                             inRoom:room.roomId
                            success:^(MXEvent *lastEvent) {
            
            XCTAssertNotNil(lastEvent);
            XCTAssertTrue(lastEvent.contentHasBeenEdited);
            XCTAssertEqualObjects(lastEvent.unsignedData.relations.replace.eventId, editEventId);
            XCTAssertEqualObjects(lastEvent.content[kMXMessageBodyKey], kEditedMessageText);

            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up initial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Send a message
// - Edit its local echo
// -> We must get notified about the replace event
// -> The local echo block must have been called twice
- (void)testEditOfEventBeingSent
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        __block NSString *eventId;
        __block NSUInteger localEchoBlockCount = 0;

        // - Send a message
        MXEvent *localEcho;
        [room sendTextMessage:kOriginalMessageText formattedText:nil threadId:nil localEcho:&localEcho success:^(NSString *theEventId) {
            eventId = theEventId;
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

        // - Edit its local echo
        [mxSession.aggregations replaceTextMessageEvent:localEcho withTextMessage:kEditedMessageText formattedText:nil localEchoBlock:^(MXEvent * _Nonnull localEcho) {

            localEchoBlockCount++;

            XCTAssertEqual(localEcho.sentState, MXEventSentStateSending);
            XCTAssertEqual(localEcho.eventType, MXEventTypeRoomMessage);

            XCTAssertNotNil(localEcho.relatesTo);
            XCTAssertEqualObjects(localEcho.relatesTo.relationType, MXEventRelationTypeReplace);

            XCTAssertEqualObjects(localEcho.content[kMXMessageContentKeyNewContent][kMXMessageTypeKey], kMXMessageTypeText);
            XCTAssertEqualObjects(localEcho.content[kMXMessageContentKeyNewContent][kMXMessageBodyKey], kEditedMessageText);

            switch (localEchoBlockCount) {
                case 1:
                    // The first local echo must point to a local echo
                    XCTAssertTrue([localEcho.relatesTo.eventId hasPrefix:kMXEventLocalEventIdPrefix]);
                    break;
                case 2:
                    // The second local echo must point to the final event id
                    XCTAssertFalse([localEcho.relatesTo.eventId hasPrefix:kMXEventLocalEventIdPrefix]);
                    break;

                default:
                    break;
            }

        } success:^(NSString * _Nonnull eventId) {
            XCTAssertNotNil(eventId);
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        // -> We must get notified about the replace event
        [mxSession.aggregations listenToEditsUpdateInRoom:room.roomId block:^(MXEvent * _Nonnull replaceEvent) {

            XCTAssertNotNil(eventId, @"The original event must have been sent before receiving the final edit");

            MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];

            XCTAssertNotNil(editedEvent);
            XCTAssertTrue(editedEvent.contentHasBeenEdited);
            XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, replaceEvent.eventId);
            XCTAssertEqualObjects(editedEvent.content[kMXMessageBodyKey], kEditedMessageText);

            XCTAssertEqualObjects(replaceEvent.relatesTo.eventId, eventId);

            // -> The local echo block must have been called twice
            XCTAssertEqual(localEchoBlockCount, 2);

            [expectation fulfill];
        }];
    }];
}


#pragma mark - E2E

// Create a room with an event with an edit it on it
- (void)createE2EScenario:(void(^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId))readyToTest
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO aliceStore:[[MXMemoryStore alloc] init] bobStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [mxSession roomWithRoomId:roomId];

        [room sendTextMessage:kOriginalMessageText threadId:nil success:^(NSString *eventId) {
            [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
                [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMessageText formattedText:nil localEchoBlock:nil success:^(NSString * _Nonnull editEventId) {

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        readyToTest(mxSession, room, expectation, eventId, editEventId);
                    });

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


// - Send a message in an e2e room
// - Edit it
// -> an edit m.room.message must appear in the timeline
// -> Check the edited message in the store
- (void)testEditSendAndReceiveInE2ERoom
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO aliceStore:[[MXMemoryStore alloc] init] bobStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        // - Send a message
        [room sendTextMessage:kOriginalMessageText threadId:nil success:^(NSString *eventId) {

            [aliceSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {

                // Edit it
                [aliceSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMessageText formattedText:nil localEchoBlock:nil success:^(NSString * _Nonnull eventId) {
                    XCTAssertNotNil(eventId);
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

                [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *editEvent, MXTimelineDirection direction, MXRoomState *roomState) {

                    // -> an edit m.room.message must appear in the timeline
                    XCTAssertEqual(editEvent.eventType, MXEventTypeRoomMessage);

                    XCTAssertTrue(editEvent.isEncrypted);

                    XCTAssertNotNil(editEvent.relatesTo);
                    XCTAssertEqualObjects(editEvent.relatesTo.relationType, MXEventRelationTypeReplace);
                    XCTAssertEqualObjects(editEvent.relatesTo.eventId, eventId);

                    XCTAssertEqualObjects(editEvent.content[kMXMessageContentKeyNewContent][kMXMessageTypeKey], kMXMessageTypeText);
                    XCTAssertEqualObjects(editEvent.content[kMXMessageContentKeyNewContent][kMXMessageBodyKey], kEditedMessageText);

                    // -> Check the edited message in the store
                    [aliceSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *localEditedEvent) {

                        XCTAssertNotNil(localEditedEvent);

                        XCTAssertTrue(localEditedEvent.isEncrypted);
                        XCTAssertTrue(localEditedEvent.contentHasBeenEdited);

                        XCTAssertEqualObjects(localEditedEvent.content[kMXMessageTypeKey], kMXMessageTypeText);
                        XCTAssertEqualObjects(localEditedEvent.content[kMXMessageBodyKey], kEditedMessageText);

                        // The event content must be encrypted
                        XCTAssertNil(localEditedEvent.wireContent[kMXMessageBodyKey]);
                        XCTAssertNotNil(localEditedEvent.wireContent[@"ciphertext"]);

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial E2E condition scenario
// -> Check data is correctly aggregated when fetching the edited event directly from the homeserver
- (void)testEditServerSideInE2ERoom
{
    // - Run the initial condition scenario
    [self createE2EScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {

        MXEvent *localEditedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];

        // -> Check data is correctly aggregated when fetching the edited event directly from the homeserver
        [mxSession.matrixRestClient eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {

            XCTAssertNotNil(event);

            XCTAssertTrue(event.isEncrypted);
            [mxSession decryptEvents:@[event] inTimeline:nil onComplete:^(NSArray<MXEvent *> *failedEvents) {
                XCTAssertEqual(failedEvents.count, 0, @"Decryption error: %@", event.decryptionError);
                
                // TODO: Synapse does not support aggregation for e2e rooms yet
                XCTAssertTrue(event.contentHasBeenEdited);
                XCTAssertEqualObjects(event.unsignedData.relations.replace.eventId, editEventId);
                XCTAssertEqualObjects(event.content[kMXMessageBodyKey], kEditedMessageText);
                
                XCTAssertEqualObjects(event.content, localEditedEvent.content);
                XCTAssertEqualObjects(event.JSONDictionary[@"unsigned"][@"relations"], localEditedEvent.JSONDictionary[@"unsigned"][@"relations"]);
                
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

#pragma mark - Edits history

// Edit a message a number of times
- (void)addEdits:(NSUInteger)editsCount toEvent:(NSString*)eventId inRoom:(MXRoom*)room mmSession:(MXSession*)mxSession expectation:(XCTestExpectation *)expectation onComplete:(dispatch_block_t)onComplete
{
    [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {

        for (NSUInteger i = 1; i <= editsCount; i++)
        {
            NSString *editMessageText = [NSString stringWithFormat:@"%@ - %@", kEditedMessageText, @(i)];
            [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:editMessageText formattedText:nil localEchoBlock:nil success:^(NSString * _Nonnull eventId) {

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }

        __block NSUInteger receivedEditsCount = 0;
        [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            if (event.isEditEvent)
            {
                if (++receivedEditsCount == editsCount)
                {
                    onComplete();
                }
            }
        }];

    } failure:^(NSError *error) {
        XCTFail(@"The operation should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}


// - Run the initial condition scenario
// - Edit the message 10 more times
// - Paginate one edit
// -> We must get an edit event and a nextBatch
// -> We must get the original event
// - Paginate more
// -> We must get all other edit events and no more nextBatch
// -> We must get the original event
- (void)testEditsHistory
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {

        // - Edit the message 10 more times
        [self addEdits:10 toEvent:eventId inRoom:room mmSession:mxSession expectation:expectation onComplete:^{

            [mxSession.aggregations replaceEventsForEvent:eventId isEncrypted:NO inRoom:room.roomId from:nil limit:1 success:^(MXAggregationPaginatedResponse *paginatedResponse) {

                // -> We must get an edit event and a nextBatch
                XCTAssertNotNil(paginatedResponse);
                XCTAssertEqual(paginatedResponse.chunk.count, 1);
                XCTAssertTrue(paginatedResponse.chunk.firstObject.isEditEvent);
                XCTAssertNotNil(paginatedResponse.nextBatch);

                // -> We must get the original event
                XCTAssertNotNil(paginatedResponse.originalEvent);
                XCTAssertEqualObjects(paginatedResponse.originalEvent.eventId, eventId);
                XCTAssertEqualObjects(paginatedResponse.originalEvent.content[kMXMessageBodyKey], kOriginalMessageText);

                // - Paginate more
                [mxSession.aggregations replaceEventsForEvent:eventId isEncrypted:NO inRoom:room.roomId from:paginatedResponse.nextBatch limit:20 success:^(MXAggregationPaginatedResponse *paginatedResponse) {

                    // -> We must get all other edit events and no more nextBatch
                    XCTAssertNotNil(paginatedResponse);
                    XCTAssertEqual(paginatedResponse.chunk.count, 10);
                    XCTAssertNil(paginatedResponse.nextBatch);

                    for (MXEvent *event in paginatedResponse.chunk)
                    {
                        XCTAssertTrue(event.isEditEvent);
                    }

                    // -> We must get the original event
                    XCTAssertNotNil(paginatedResponse.originalEvent);
                    XCTAssertEqualObjects(paginatedResponse.originalEvent.eventId, eventId);
                    XCTAssertEqualObjects(paginatedResponse.originalEvent.content[kMXMessageBodyKey], kOriginalMessageText);

                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

@end

#pragma clang diagnostic pop
