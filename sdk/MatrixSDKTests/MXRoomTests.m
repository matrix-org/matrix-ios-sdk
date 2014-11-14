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

- (void)testMessagesPropertyCopy
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        mxSession = mxSession2;

        NSArray *messagesBeforePagination = room.messages;
        
        XCTAssertEqual(messagesBeforePagination.count, 1, @"Just after initialSync, we should have 1 message");
        
        MXEvent *event = messagesBeforePagination[0];
        NSString *event_id = event.eventId;
        
        [room resetBackState];
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        [room resetBackState];
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        [room resetBackState];
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        NSArray *messagesBeforePagination = room.messages;
        
        [room resetBackState];
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        [room resetBackState];
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        [room resetBackState];
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        [room resetBackState];
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        // Instantiate another MXRoom object and test pagination from cold
        MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.state.room_id andMatrixSession:mxSession];
        
        XCTAssertEqual(room2.messages.count, 0, @"No initialSync means no data");
        
       [room2 resetBackState];
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        [room resetBackState];
        [room paginateBackMessages:100 success:^(NSArray *messages) {
            
            mxSession = mxSession2;

            // Use another MXRoom instance to do pagination in several times
            MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.state.room_id andMatrixSession:mxSession];
            
            // The several paginations
            [room2 resetBackState];
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        XCTAssertTrue(room.canPaginate, @"We can always paginate at the beginning");
        
        [room resetBackState];
        [room paginateBackMessages:100 success:^(NSArray *messages) {
            
            XCTAssertFalse(room.canPaginate, @"We must have reached the end of the pagination");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testListenerForAllLiveEvents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSString *messageEventID;
        
        // Register the listener
        [room registerEventListenerForTypes:nil block:^(MXRoom *room2, MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSString *messageEventID;
        
        // Register the listener for m.room.message.only
        [room registerEventListenerForTypes:@[kMXEventTypeStringRoomMessage]
                                          block:^(MXRoom *room2, MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            
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
