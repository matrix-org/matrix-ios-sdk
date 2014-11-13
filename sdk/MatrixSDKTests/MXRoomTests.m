/*
 Copyright 2014 OpenMarket Ltd
 
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

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

@interface MXRoomTests : XCTestCase
{
    MXSession *mxSession;
}

@end

@implementation MXRoomTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    if (mxSession)
    {
        [mxSession close];
        mxSession = nil;
    }
    [super tearDown];
}

- (void)doMXRoomTestWithBobAndARoomWithMessages:(void (^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation))readyToTest
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        [mxSession start:^{
            MXRoom *room = [mxSession room:room_id];
            
            readyToTest(mxSession, room, expectation);
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)doMXRoomTestWithBobAndThePublicRoom:(void (^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation))readyToTest
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        [mxSession start:^{
            MXRoom *room = [mxSession room:room_id];
            
            readyToTest(mxSession, room, expectation);
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)assertNoDuplicate:(NSArray*)events text:(NSString*)text
{
    NSMutableDictionary *eventIDs = [NSMutableDictionary dictionary];
    
    for (MXEvent *event in events)
    {
        if ([eventIDs objectForKey:event.eventId])
        {
            XCTAssert(NO, @"Duplicated event in %@ - MXEvent: %@", text, event);
        }
        eventIDs[event.eventId] = event;
    }
}


- (void)testIsPublic
{
    [self doMXRoomTestWithBobAndThePublicRoom:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        XCTAssertTrue(room.state.isPublic, @"The room must be public");
            
        [expectation fulfill];
    }];
}

- (void)testIsPublicForAPrivateRoom
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        XCTAssertFalse(room.state.isPublic, @"This room must be private");
        
        [expectation fulfill];
    }];
}

- (void)testMembers
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession start:^{
            
            MXRoom *room = [mxSession room:room_id];
            XCTAssertNotNil(room);
            
            NSArray *members = room.state.members;
            XCTAssertEqual(members.count, 1, "There must be only one member: mxBob, the creator");
            
            for (MXRoomMember *member in room.state.members)
            {
                XCTAssertTrue([member.userId isEqualToString:bobRestClient.credentials.userId], "This must be mxBob");
            }
            
            XCTAssertNotNil([room.state getMember:bobRestClient.credentials.userId], @"Bob must be retrieved");
            
            XCTAssertNil([room.state getMember:@"NonExistingUserId"], @"getMember must return nil if the user does not exist");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMemberName
{
    [self doMXRoomTestWithBobAndThePublicRoom:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
        
        NSString *bobUserId = sharedData.bobCredentials.userId;
        NSString *bobMemberName = [room.state  memberName:bobUserId];
        
        XCTAssertNotNil(bobMemberName);
        XCTAssertFalse([bobMemberName isEqualToString:@""], @"bobMemberName must not be an empty string");
        
        XCTAssert([[room.state memberName:@"NonExistingUserId"] isEqualToString:@"NonExistingUserId"], @"memberName must return his id if the user does not exist");
        
        [expectation fulfill];
    }];
}

- (void)testMessagesPropertyCopy
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        NSArray *messagesBeforePagination = room.messages;
        
        XCTAssertEqual(messagesBeforePagination.count, 1, @"Just after initialSync, we should have 1 message");
        
        MXEvent *event = messagesBeforePagination[0];
        NSString *event_id = event.eventId;
        
        [room paginateBackMessages:50 success:^(NSArray *messages) {
            
            
            XCTAssertEqual(messagesBeforePagination.count, 1, @"room.messages is a copy property. messagesBeforePagination must not have changed");
            
            MXEvent *eventAfterPagination = messagesBeforePagination[0];
            
            XCTAssertEqual(eventAfterPagination, event, @"The only event must be the same as before the pagination action");
            XCTAssertTrue([eventAfterPagination.eventId isEqualToString:event_id], @"The only event content must be the same as before the pagination action");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMessagesOrder
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        [room paginateBackMessages:100 success:^(NSArray *messages) {
            
            NSUInteger prev_ts = 0;
            for (MXEvent *event in room.messages)
            {
                if (event.originServerTs)
                {
                    XCTAssertGreaterThanOrEqual(event.originServerTs, prev_ts, @"Events in messages must be listed in chronological order");
                    prev_ts = event.originServerTs;
                }
                else
                {
                    NSLog(@"No timestamp in the event data: %@", event);
                }
            }
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


- (void)testMessagesFilter
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        [room paginateBackMessages:100 success:^(NSArray *messages) {
            
            for (MXEvent *event in room.messages)
            {
                // Only events with a type declared in `eventsFilterForMessages`
                // must appear in messages
                XCTAssertNotEqual([mxSession.eventsFilterForMessages indexOfObject:event.type], NSNotFound, "Event of this type must not be in messages. Event: %@", event);
            }
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


- (void)testPaginateBack
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        NSArray *messagesBeforePagination = room.messages;
        
        [room paginateBackMessages:5 success:^(NSArray *messages) {
            
            NSArray *messagesAfterPagination = room.messages;
            
            XCTAssertEqual(messages.count, 5, @"We should get as many messages as requested");

            XCTAssertEqual(messagesAfterPagination.count, messagesBeforePagination.count + messages.count, @"room.messages count must have increased by the number of new messages got by pagination");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackFilter
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        [room paginateBackMessages:100 success:^(NSArray *messages) {
            
            for (MXEvent *event in messages)
            {
                // Only events with a type declared in `eventsFilterForMessages`
                // must appear in messages
                XCTAssertNotEqual([mxSession.eventsFilterForMessages indexOfObject:event.type], NSNotFound, "Event of this type must not be in messages. Event: %@", event);
            }
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackOrder
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        [room paginateBackMessages:100 success:^(NSArray *messages) {
            
            NSUInteger prev_ts = 0;
            for (MXEvent *event in messages)
            {
                if (event.originServerTs)
                {
                    XCTAssertGreaterThanOrEqual(event.originServerTs, prev_ts, @"Events in messages must be listed in chronological order");
                    prev_ts = event.originServerTs;
                }
                else
                {
                    NSLog(@"No timestamp in the event data: %@", event);
                }
            }
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackDuplicates
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        [room paginateBackMessages:100 success:^(NSArray *messages) {
            
            [self assertNoDuplicate:messages text:@"the 'messages' array response of paginateBackMessages"];
            
            [self assertNoDuplicate:room.messages text:@" room.messages"];
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackWithNoInitialSync
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        // Instantiate another MXRoom object and test pagination from cold
        MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.state.room_id andMatrixSession:mxSession];
        
        XCTAssertEqual(room2.messages.count, 0, @"No initialSync means no data");
        
        [room2 paginateBackMessages:5 success:^(NSArray *messages) {
            
            XCTAssertEqual(messages.count, 5, @"We should get as many messages as requested");
            
            XCTAssertEqual(room2.messages.count, 5, @"room.messages count must be 5 now");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testSeveralPaginateBacks
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        [room paginateBackMessages:100 success:^(NSArray *messages) {
            
            mxSession = mxSession2;

            // Use another MXRoom instance to do pagination in several times
            MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.state.room_id andMatrixSession:mxSession];
            
            // The several paginations
            [room2 paginateBackMessages:2 success:^(NSArray *messages) {
                
                [room2 paginateBackMessages:5 success:^(NSArray *messages) {
                    
                    [room2 paginateBackMessages:100 success:^(NSArray *messages) {
                        
                        // Now, compare the result with the reference
                        XCTAssertEqual(room2.messages.count, room.messages.count);
                        
                        // Compare events one by one
                        for (NSUInteger i = 0; i < room2.messages.count; i++)
                        {
                            MXEvent *event = room.messages[i];
                            MXEvent *event2 = room2.messages[i];
                            
                            XCTAssertTrue([event2.eventId isEqualToString:event.eventId], @"Events mismatch: %@ - %@", event, event2);
                        }
                        
                        [expectation fulfill];
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testCanPaginate
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        XCTAssertTrue(room.canPaginate, @"We can always paginate at the beginning");
        
        [room paginateBackMessages:100 success:^(NSArray *messages) {
            
            XCTAssertFalse(room.canPaginate, @"We must have reached the end of the pagination");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testStateEvents
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        XCTAssertNotNil(room.state.stateEvents);
        XCTAssertGreaterThan(room.state.stateEvents.count, 0);
 
        [expectation fulfill];
    }];
}

- (void)testAliases
{
    [self doMXRoomTestWithBobAndThePublicRoom:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        XCTAssertNotNil(room.state.aliases);
        XCTAssertGreaterThanOrEqual(room.state.aliases.count, 1);
        
        NSString *alias = room.state.aliases[0];
        
        XCTAssertTrue([alias hasPrefix:@"#mxPublic:"]);
        
        [expectation fulfill];
    }];
}

// Test the room display name formatting: "roomName (roomAlias)"
- (void)testDisplayName1
{
    [self doMXRoomTestWithBobAndThePublicRoom:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        XCTAssertNotNil(room.state.displayname);
        XCTAssertTrue([room.state.displayname hasPrefix:@"MX Public Room test (#mxPublic:"], @"We must retrieve the #mxPublic room settings");
        
        [expectation fulfill];
    }];
}

// Test the room display name formatting: "userID" (self chat)
- (void)testDisplayName2
{
    [self doMXRoomTestWithBobAndARoomWithMessages:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        // Test room the display formatting: "roomName (roomAlias)"
        XCTAssertNotNil(room.state.displayname);
        XCTAssertTrue([room.state.displayname isEqualToString:mxSession.matrixRestClient.credentials.userId], @"The room name must be Bob's userID as he has no displayname: %@ - %@", room.state.displayname, mxSession.matrixRestClient.credentials.userId);
        
        [expectation fulfill];
    }];
}

- (void)testListenerForAllLiveEvents
{
    [self doMXRoomTestWithBobAndThePublicRoom:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        __block NSString *messageEventID;
        
        // Register the listener
        [room registerEventListenerForTypes:nil block:^(MXRoom *room2, MXEvent *event, BOOL isLive) {
            
            XCTAssertEqual(room, room2);
            XCTAssertTrue(isLive);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
            XCTAssertTrue([event.eventId isEqualToString:messageEventID]);
            
            
            [expectation fulfill];
            
        }];
        
        
        // Populate a text message in parallel
        [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation2) {
            
            [bobRestClient postTextMessage:room_id text:@"Hello listeners!" success:^(NSString *event_id) {
                
                messageEventID = event_id;
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];
        
    }];
}

- (void)testListenerForRoomMessageLiveEvents
{
    [self doMXRoomTestWithBobAndThePublicRoom:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        __block NSString *messageEventID;
        
        // Register the listener for m.room.message.only
        [room registerEventListenerForTypes:@[kMXEventTypeStringRoomMessage]
                                          block:^(MXRoom *room2, MXEvent *event, BOOL isLive) {
            
            XCTAssertEqual(room, room2);
            XCTAssertTrue(isLive);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
            XCTAssertTrue([event.eventId isEqualToString:messageEventID]);
            
            
            [expectation fulfill];
            
        }];
        
        // Populate a text message in parallel
        [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation2) {
            
            [bobRestClient postTextMessage:room_id text:@"Hello listeners!" success:^(NSString *event_id) {
                
                messageEventID = event_id;
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];
        
    }];
}

@end
