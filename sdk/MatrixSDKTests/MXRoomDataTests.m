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

#import "MXData.h"

@interface MXRoomDataTests : XCTestCase
{
}

@end

@implementation MXRoomDataTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)doMXRoomDataTestWithBobAndARoomWithMessages:(void (^)(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation))readyToTest
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        MXData *matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        
        [matrixData start:^{
            MXRoomData *roomData = [matrixData getRoomData:room_id];
            
            readyToTest(matrixData, roomData, expectation);
            
        } failure:^(NSError *error) {
            
        }];
    }];
}

- (void)doMXRoomDataTestWithBobAndThePublicRoom:(void (^)(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation))readyToTest
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        MXData *matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        
        [matrixData start:^{
            MXRoomData *roomData = [matrixData getRoomData:room_id];
            
            readyToTest(matrixData, roomData, expectation);
            
        } failure:^(NSError *error) {
            
        }];
    }];
}

- (void)assertNoDuplicate:(NSArray*)events text:(NSString*)text
{
    NSMutableDictionary *eventIDs = [NSMutableDictionary dictionary];
    
    for (MXEvent *event in events)
    {
        if ([eventIDs objectForKey:event.event_id])
        {
            XCTAssert(NO, @"Duplicated event in %@ - MXEvent: %@", text, event);
        }
        eventIDs[event.event_id] = event;
    }
}


- (void)testIsPublic
{
    [self doMXRoomDataTestWithBobAndThePublicRoom:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        XCTAssertTrue(roomData.isPublic, @"The room must be public");
            
        [expectation fulfill];
    }];
}

- (void)testIsPublicForAPrivateRoom
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        XCTAssertFalse(roomData.isPublic, @"This room must be private");
        
        [expectation fulfill];
    }];
}

- (void)testMembers
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXSession *bobSession, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        MXData *matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        [matrixData start:^{
            
            MXRoomData *roomData = [matrixData getRoomData:room_id];
            XCTAssertNotNil(roomData);
            
            NSArray *members = roomData.members;
            XCTAssertEqual(members.count, 1, "There must be only one member: mxBob, the creator");
            
            for (MXRoomMember *member in roomData.members)
            {
                XCTAssertTrue([member.user_id isEqualToString:bobSession.user_id], "This must be mxBob");
            }
            
            XCTAssertNotNil([roomData getMember:bobSession.user_id], @"Bob must be retrieved");
            
            XCTAssertNil([roomData getMember:@"NonExistingUserId"], @"getMember must return nil if the user does not exist");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMemberName
{
    [self doMXRoomDataTestWithBobAndThePublicRoom:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
        
        NSString *bobUserId = sharedData.bobCredentials.user_id;
        NSString *bobMemberName = [roomData memberName:bobUserId];
        
        XCTAssertNotNil(bobMemberName);
        XCTAssertFalse([bobMemberName isEqualToString:@""], @"bobMemberName must not be an empty string");
        
       XCTAssertNil([roomData memberName:@"NonExistingUserId"], @"memberName must return nil if the user does not exist");
        
        [expectation fulfill];
    }];
}

- (void)testMessagesPropertyCopy
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        NSArray *messagesBeforePagination = roomData.messages;
        
        XCTAssertEqual(messagesBeforePagination.count, 1, @"Just after initialSync, we should have 1 message");
        
        MXEvent *event = messagesBeforePagination[0];
        NSString *event_id = event.event_id;
        
        [roomData paginateBackMessages:50 success:^(NSArray *messages) {
            
            
            XCTAssertEqual(messagesBeforePagination.count, 1, @"roomData.messages is a copy property. messagesBeforePagination must not have changed");
            
            MXEvent *eventAfterPagination = messagesBeforePagination[0];
            
            XCTAssertEqual(eventAfterPagination, event, @"The only event must be the same as before the pagination action");
            XCTAssertTrue([eventAfterPagination.event_id isEqualToString:event_id], @"The only event content must be the same as before the pagination action");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMessagesOrder
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        [roomData paginateBackMessages:100 success:^(NSArray *messages) {
            
            NSUInteger prev_ts = 0;
            for (MXEvent *event in roomData.messages)
            {
                if (event.ts)
                {
                    XCTAssertGreaterThanOrEqual(event.ts, prev_ts, @"Events in messages must be listed in chronological order");
                    prev_ts = event.ts;
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


- (void)testPaginateBack
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        NSArray *messagesBeforePagination = roomData.messages;
        
        [roomData paginateBackMessages:5 success:^(NSArray *messages) {
            
            NSArray *messagesAfterPagination = roomData.messages;
            
            XCTAssertEqual(messages.count, 5, @"We should get as many messages as requested");

            XCTAssertEqual(messagesAfterPagination.count, messagesBeforePagination.count + messages.count, @"roomData.messages count must have increased by the number of new messages got by pagination");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackOrder
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        [roomData paginateBackMessages:100 success:^(NSArray *messages) {
            
            NSUInteger prev_ts = ULONG_MAX;
            for (MXEvent *event in messages)
            {
                if (event.ts)
                {
                    XCTAssertLessThanOrEqual(event.ts, prev_ts, @"Events in messages must be listed in antichronological order");
                    prev_ts = event.ts;
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
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        [roomData paginateBackMessages:100 success:^(NSArray *messages) {
            
            [self assertNoDuplicate:messages text:@"the 'messages' array response of paginateBackMessages"];
            
            [self assertNoDuplicate:roomData.messages text:@" roomData.messages"];
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackWithNoInitialSync
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        // Instantiate another MXRoomData object and test pagination from cold
        MXRoomData *roomData2 = [[MXRoomData alloc] initWithRoomId:roomData.room_id andMatrixData:matrixData];
        
        XCTAssertEqual(roomData2.messages.count, 0, @"No initialSync means no data");
        
        [roomData2 paginateBackMessages:5 success:^(NSArray *messages) {
            
            XCTAssertEqual(messages.count, 5, @"We should get as many messages as requested");
            
            XCTAssertEqual(roomData2.messages.count, 5, @"roomData.messages count must be 5 now");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testSeveralPaginateBacks
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        [roomData paginateBackMessages:100 success:^(NSArray *messages) {
            
            // Use another MXRoomData instance to do pagination in several times
            MXRoomData *roomData2 = [[MXRoomData alloc] initWithRoomId:roomData.room_id andMatrixData:matrixData];
            
            // The several paginations
            [roomData2 paginateBackMessages:2 success:^(NSArray *messages) {
                
                [roomData2 paginateBackMessages:5 success:^(NSArray *messages) {
                    
                    [roomData2 paginateBackMessages:100 success:^(NSArray *messages) {
                        
                        // Now, compare the result with the reference
                        XCTAssertEqual(roomData2.messages.count, roomData.messages.count);
                        
                        // Compare events one by one
                        for (NSUInteger i = 0; i < roomData2.messages.count; i++)
                        {
                            MXEvent *event = roomData.messages[i];
                            MXEvent *event2 = roomData2.messages[i];
                            
                            XCTAssertTrue([event2.event_id isEqualToString:event.event_id], @"Events mismatch: %@ - %@", event, event2);
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
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        XCTAssertTrue(roomData.canPaginate, @"We can always paginate at the beginning");
        
        [roomData paginateBackMessages:100 success:^(NSArray *messages) {
            
            XCTAssertFalse(roomData.canPaginate, @"We must have reached the end of the pagination");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testStateEvents
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        XCTAssertNotNil(roomData.stateEvents);
        XCTAssertGreaterThan(roomData.stateEvents.count, 0);
 
        [expectation fulfill];
    }];
}

- (void)testAliases
{
    [self doMXRoomDataTestWithBobAndThePublicRoom:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        XCTAssertNotNil(roomData.aliases);
        XCTAssertGreaterThanOrEqual(roomData.aliases.count, 1);
        
        NSString *alias = roomData.aliases[0];
        
        XCTAssertTrue([alias hasPrefix:@"#mxPublic:"]);
        
        [expectation fulfill];
    }];
}

// Test the room display name formatting: "roomName (roomAlias)"
- (void)testDisplayName1
{
    [self doMXRoomDataTestWithBobAndThePublicRoom:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        XCTAssertNotNil(roomData.displayname);
        XCTAssertTrue([roomData.displayname hasPrefix:@"MX Public Room test (#mxPublic:"], @"We must retrieve the #mxPublic room settings");
        
        [expectation fulfill];
    }];
}

// Test the room display name formatting: "userID" (self chat)
- (void)testDisplayName2
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXData *matrixData, MXRoomData *roomData, XCTestExpectation *expectation) {
        
        // Test room the display formatting: "roomName (roomAlias)"
        XCTAssertNotNil(roomData.displayname);
        XCTAssertTrue([roomData.displayname isEqualToString:matrixData.matrixSession.user_id], @"The room name must be Bob's userID as he has no displayname: %@ - %@", roomData.displayname, matrixData.matrixSession.user_id);
        
        [expectation fulfill];
    }];
}

@end
