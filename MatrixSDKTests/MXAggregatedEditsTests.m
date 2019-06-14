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
}

@end

@implementation MXAggregatedEditsTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
}

// Create a room with an event with an edit it on it
- (void)createScenario:(void(^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId))readyToTest
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [room sendTextMessage:kOriginalMessageText success:^(NSString *eventId) {
            [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
                [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMessageText formattedText:nil localEcho:nil success:^(NSString * _Nonnull editEventId) {
                    
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
        
        [room sendTextMessage:kOriginalMarkdownMessageText success:^(NSString *eventId) {
            [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
                [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMarkdownMessageText formattedText:kEditedMarkdownMessageFormattedText localEcho:nil success:^(NSString * _Nonnull editEventId) {
                    
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

- (void)testEditingEventManually
{
    NSDictionary *messageEventDict = @{
                                       @"content": @{
                                               @"body": kOriginalMessageText,
                                               @"msgtype": @"m.text"
                                               },
                                       @"event_id": @"$messageeventid:matrix.org",
                                       @"origin_server_ts": @(1560253386247),
                                       @"sender": @"@billsam:matrix.org",
                                       @"type": @"m.room.message",
                                       @"unsigned": @{
                                               @"age": @(6117832)
                                               },
                                       @"room_id": @"!roomid:matrix.org"
                                       };
    
    NSDictionary *replaceEventDict = @{
                                       @"content": @{
                                               @"body": [NSString stringWithFormat:@"* %@", kEditedMessageText],
                                               @"m.new_content": @{
                                                       @"body": kEditedMessageText,
                                                       @"msgtype": @"m.text"
                                                       },
                                               @"m.relates_to": @{
                                                       @"event_id": @"$messageeventid:matrix.org",
                                                       @"rel_type": @"m.replace"
                                                       },
                                               @"msgtype": @"m.text"
                                               },
                                       @"event_id": @"$replaceeventid:matrix.org",
                                       @"origin_server_ts": @(1560254175300),
                                       @"sender": @"@billsam:matrix.org",
                                       @"type": @"m.room.message",
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
    XCTAssertEqualObjects(editedEvent.content[@"body"], kEditedMessageText);
}

- (void)testEditingFormattedEventManually
{
    NSDictionary *messageEventDict = @{
                                       @"content": @{
                                               @"body": kOriginalMarkdownMessageText,
                                               @"formatted_body": kOriginalMarkdownMessageFormattedText,
                                               @"format": kMXRoomMessageFormatHTML,
                                               @"msgtype": @"m.text"
                                               },
                                       @"event_id": @"$messageeventid:matrix.org",
                                       @"origin_server_ts": @(1560253386247),
                                       @"sender": @"@billsam:matrix.org",
                                       @"type": @"m.room.message",
                                       @"unsigned": @{
                                               @"age": @(6117832)
                                               },
                                       @"room_id": @"!roomid:matrix.org"
                                       };
    
    NSDictionary *replaceEventDict = @{
                                       @"content": @{
                                               @"body": [NSString stringWithFormat:@"* %@", kEditedMarkdownMessageText],
                                               @"formatted_body": [NSString stringWithFormat:@"* %@", kEditedMarkdownMessageFormattedText],
                                               @"format": kMXRoomMessageFormatHTML,
                                               @"m.new_content": @{
                                                       @"body": kEditedMarkdownMessageText,
                                                       @"formatted_body": kEditedMarkdownMessageFormattedText,
                                                       @"format": kMXRoomMessageFormatHTML,
                                                       @"msgtype": @"m.text"
                                                       },
                                               @"m.relates_to": @{
                                                       @"event_id": @"$messageeventid:matrix.org",
                                                       @"rel_type": @"m.replace"
                                                       },
                                               @"msgtype": @"m.text"
                                               },
                                       @"event_id": @"$replaceeventid:matrix.org",
                                       @"origin_server_ts": @(1560254175300),
                                       @"sender": @"@billsam:matrix.org",
                                       @"type": @"m.room.message",
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
    
    XCTAssertEqualObjects(editedEvent.content[@"body"], kEditedMarkdownMessageText);
    XCTAssertEqualObjects(editedEvent.content[@"formatted_body"], kEditedMarkdownMessageFormattedText);
}


// - Send a message
// - Edit it
// -> an edit m.room.message must appear in the timeline
- (void)testEditSendAndReceive
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        // - Send a message
        [room sendTextMessage:kOriginalMessageText success:^(NSString *eventId) {

            [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {

                // Edit it
                [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMessageText formattedText:nil localEcho:nil success:^(NSString * _Nonnull eventId) {
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

                    XCTAssertEqualObjects(event.content[@"m.new_content"][@"msgtype"], kMXMessageTypeText);
                    XCTAssertEqualObjects(event.content[@"m.new_content"][@"body"], kEditedMessageText);

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
        [room sendTextMessage:kOriginalMarkdownMessageText success:^(NSString *eventId) {
            
            [mxSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
                
                // Edit it
                [mxSession.aggregations replaceTextMessageEvent:event withTextMessage:kEditedMarkdownMessageText formattedText:kEditedMarkdownMessageFormattedText localEcho:nil success:^(NSString * _Nonnull eventId) {
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

                    XCTAssertEqualObjects(event.content[@"body"], compatibilityBody);
                    XCTAssertEqualObjects(event.content[@"formatted_body"], compatibilityFormattedBody);

                    XCTAssertEqualObjects(event.content[@"m.new_content"][@"msgtype"], kMXMessageTypeText);
                    XCTAssertEqualObjects(event.content[@"m.new_content"][@"body"], kEditedMarkdownMessageText);
                    XCTAssertEqualObjects(event.content[@"m.new_content"][@"formatted_body"], kEditedMarkdownMessageFormattedText);
                    
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
- (void)testAggregatedEditServerSide
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {

        MXEvent *localEditedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        // -> Check data is correctly aggregated when fetching the edited event directly from the homeserver
        [mxSession.matrixRestClient eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
            
            XCTAssertNotNil(event);
            XCTAssertTrue(event.contentHasBeenEdited);
            XCTAssertEqualObjects(event.unsignedData.relations.replace.eventId, editEventId);
            XCTAssertEqualObjects(event.content[@"body"], kEditedMessageText);
            
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
- (void)testAggregatedFormattedEditServerSide
{
    // - Run the initial condition scenario
    [self createScenarioWithFormattedText:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {
        
        MXEvent *localEditedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        // -> Check data is correctly aggregated when fetching the edited event directly from the homeserver
        [mxSession.matrixRestClient eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {
            
            XCTAssertNotNil(event);
            XCTAssertTrue(event.contentHasBeenEdited);
            XCTAssertEqualObjects(event.unsignedData.relations.replace.eventId, editEventId);
            XCTAssertEqualObjects(event.content[@"body"], kEditedMarkdownMessageText);
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
        [mxSession setStore:[[MXMemoryStore alloc] init] success:^{

            [mxSession start:^{

                MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
                
                // -> Data from aggregations must be right
                XCTAssertNotNil(editedEvent);
                XCTAssertTrue(editedEvent.contentHasBeenEdited);
                XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, editEventId);
                XCTAssertEqualObjects(editedEvent.content[@"body"], kEditedMessageText);
                
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
        [mxSession setStore:[[MXMemoryStore alloc] init] success:^{
            
            [mxSession start:^{
                
                MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
                
                // -> Data from aggregations must be right
                XCTAssertNotNil(editedEvent);
                XCTAssertTrue(editedEvent.contentHasBeenEdited);
                XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, editEventId);
                XCTAssertEqualObjects(editedEvent.content[@"body"], kEditedMarkdownMessageText);
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
- (void)testAggregationsLive
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {
        
        // -> Data from aggregations must be right
        MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        XCTAssertNotNil(editedEvent);
        XCTAssertTrue(editedEvent.contentHasBeenEdited);
        XCTAssertEqualObjects(editedEvent.unsignedData.relations.replace.eventId, editEventId);
        XCTAssertEqualObjects(editedEvent.content[@"body"], kEditedMessageText);
        
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
        XCTAssertEqualObjects(editedEvent.content[@"body"], kEditedMarkdownMessageText);
        XCTAssertEqualObjects(editedEvent.content[@"formatted_body"], kEditedMarkdownMessageFormattedText);
        
        [expectation fulfill];
    }];
}

// - Run the initial condition scenario
// - Edit 2 times
// -> We must get notified about the second replace event
- (void)testAggregationsListener
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
            XCTAssertEqualObjects(editedEvent.content[@"body"], secondEditionTextMessage);
            
            [expectation fulfill];
        }];
        
        MXEvent *editedEvent = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];
        
        [mxSession.aggregations replaceTextMessageEvent:editedEvent withTextMessage:secondEditionTextMessage formattedText:nil localEcho:nil success:^(NSString * _Nonnull eventId) {
            
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// TODO(@steve): phase:2
//- (void)testReactionsWhenPaginatingFromAGappySync
//- (void)testReactionsWhenPaginatingFromAGappyInitialSync
//- (void)testReactionsOnPermalinkFromAGappySync
//- (void)testReactionsOnPermalinkFromAGappyInitialSync

@end

#pragma clang diagnostic pop
