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

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXRoomTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;

    MXSession *mxSession;
}

@end

@implementation MXRoomTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    if (mxSession)
    {
        [matrixSDKTestsData closeMXSession:mxSession];
        mxSession = nil;
    }
    [super tearDown];
}


- (void)testListenerForAllLiveEvents
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSString *sentMessageEventID;
        __block NSString *receivedMessageEventID;
        
        void (^checkEventIDs)() = ^ void ()
        {
            if (sentMessageEventID && receivedMessageEventID)
            {
                XCTAssertTrue([receivedMessageEventID isEqualToString:sentMessageEventID]);
                
                [expectation fulfill];
            }
        };
        
        // Register the listener
        [room.liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            
            XCTAssertEqual(direction, MXTimelineDirectionForwards);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
            
            XCTAssertNotNil(event.eventId);
            
            receivedMessageEventID = event.eventId;
           
            checkEventIDs();
        }];
        
        
        // Populate a text message in parallel
        [matrixSDKTestsData doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {
            
            [bobRestClient sendTextMessageToRoom:roomId text:@"Hello listeners!" success:^(NSString *eventId) {
                
                NSAssert(nil != eventId, @"Cannot set up intial test conditions");
                
                sentMessageEventID = eventId;
                
                checkEventIDs();
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
        
    }];
}


- (void)testListenerForRoomMessageLiveEvents
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSString *sentMessageEventID;
        __block NSString *receivedMessageEventID;
        
        void (^checkEventIDs)() = ^ void ()
        {
            if (sentMessageEventID && receivedMessageEventID)
            {
                XCTAssertTrue([receivedMessageEventID isEqualToString:sentMessageEventID]);
                
                [expectation fulfill];
            }
        };
        
        // Register the listener for m.room.message.only
        [room.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                          onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            
            XCTAssertEqual(direction, MXTimelineDirectionForwards);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                                              
            XCTAssertNotNil(event.eventId);
                                              
            receivedMessageEventID = event.eventId;
                                              
            checkEventIDs();
        }];
        
        // Populate a text message in parallel
        [matrixSDKTestsData doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {
            
            [bobRestClient sendTextMessageToRoom:roomId text:@"Hello listeners!" success:^(NSString *eventId) {
                
                NSAssert(nil != eventId, @"Cannot set up intial test conditions");
                
                sentMessageEventID = eventId;
                
                checkEventIDs();
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
        
    }];
}

- (void)testLeave
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        NSString *roomId = room.state.roomId;

        __block MXMembership lastKnownMembership = MXMembershipUnknown;
        [room.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            lastKnownMembership = room.state.membership;
        }];
        
        // This implicitly tests MXSession leaveRoom
        [room leave:^{

            XCTAssertEqual(lastKnownMembership, MXMembershipLeave, @"MXMembershipLeave must have been received before killing the MXRoom object");

            MXRoom *room2 = [mxSession roomWithRoomId:roomId];
            XCTAssertNil(room2, @"The room must be no more part of the MXSession rooms");

            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testJoin
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

            mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];

            [bobRestClient inviteUser:aliceRestClient.credentials.userId toRoom:roomId success:^{

                [mxSession startWithMessagesLimit:0 onServerSyncDone:^{

                    MXRoom *room = [mxSession roomWithRoomId:roomId];

                    XCTAssertEqual(room.state.membership, MXMembershipInvite);
                    XCTAssertEqual(room.state.members.count, 1, @"The room state information is limited while the room is joined");

                    [room join:^{

                        XCTAssertEqual(room.state.membership, MXMembershipJoin);
                        XCTAssertEqual(room.state.members.count, 2, @"The room state must be fully known (after an initialSync on the room");

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];


                } failure:^(NSError *error) {;
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testSetPowerLevelOfUser
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            [room.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomPowerLevels] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual([room.state.powerLevels powerLevelOfUserWithUserID:aliceRestClient.credentials.userId], 36);

               [expectation fulfill];
            }];

            [room setPowerLevelOfUserWithUserID:aliceRestClient.credentials.userId powerLevel:36 success:^{

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackMessagesCancel
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [mxSession startWithMessagesLimit:0 onServerSyncDone:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];

            __block NSUInteger eventCount = 0;
            [room.liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                eventCount++;
                XCTFail(@"We should not receive events. Received: %@", event);
                [expectation fulfill];

            }];

            [room.liveTimeline resetPagination];
            MXHTTPOperation *pagination = [room.liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                XCTFail(@"The cancelled operation must not complete");
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTAssertEqual(eventCount, 0, "We should have received events in registerEventListenerForTypes");
                [expectation fulfill];
            }];

            XCTAssertNotNil(pagination);

            [pagination cancel];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testTypingUsersNotifications
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            XCTAssertEqual(room.typingUsers.count, 0);

            [room.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringTypingNotification] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(room.typingUsers.count, 1);
                XCTAssertEqualObjects(room.typingUsers[0], bobRestClient.credentials.userId);

                [expectation fulfill];
            }];

            [room sendTypingNotification:YES timeout:30000 success:^{

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testAddAndRemoveTag
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        mxSession = mxSession2;

        NSString *tag = @"aTag";
        NSString *order = @"0.5";

        __block NSUInteger tagEventUpdata = 0;

        // Wait for the m.tag event to get the room tags update
        [room.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomTag] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if (++tagEventUpdata == 1)
            {
                // This event is fired after the [room addTag:] request
                MXRoomTag *roomTag = room.accountData.tags[tag];

                XCTAssertNotNil(roomTag);
                XCTAssertEqualObjects(roomTag.name, tag);
                XCTAssertEqualObjects(roomTag.order, order);

                [room removeTag:tag success:nil failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }
            else if (tagEventUpdata == 2)
            {
                // This event is fired after the [room removeTag:] request
                XCTAssertNotNil(room.accountData.tags);
                XCTAssertEqual(room.accountData.tags.count, 0);

                [expectation fulfill];
            }
        }];

        // Do the test
        [room addTag:tag withOrder:order success:nil failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testReplaceTag
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        mxSession = mxSession2;

        NSString *tag = @"aTag";
        NSString *order = @"0.5";
        NSString *newTag = @"newTag";
        NSString *newTagOrder = nil;

        // Wait for the m.tag event that corresponds to "newTag"
        [room.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomTag] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            MXRoomTag *newRoomTag = room.accountData.tags[newTag];
            if (newRoomTag)
            {
                XCTAssertNotNil(newRoomTag);
                XCTAssertEqualObjects(newRoomTag.name, newTag);
                XCTAssertEqualObjects(newRoomTag.order, newTagOrder);

                [expectation fulfill];
            }
        }];

        // Prepare initial condition: have a tag
        [room addTag:tag withOrder:order success:^{

            // Do the test
            [room replaceTag:tag byTag:newTag withOrder:newTagOrder success:nil failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomDirectoryVisibilityProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomDirectoryVisibility:roomId directoryVisibility:kMXRoomDirectoryVisibilityPublic success:^{

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                [room directoryVisibility:^(MXRoomDirectoryVisibility directoryVisibility) {

                    XCTAssertNotNil(directoryVisibility);
                    XCTAssertEqualObjects(directoryVisibility, kMXRoomDirectoryVisibilityPublic, @"The room directory visibility is wrong");

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

    }];
}

- (void)tesRoomDirectoryVisibilityLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            [room directoryVisibility:^(MXRoomDirectoryVisibility directoryVisibility) {

                XCTAssertNotNil(directoryVisibility);
                XCTAssertEqualObjects(directoryVisibility, kMXRoomDirectoryVisibilityPrivate, @"The room directory visibility is wrong");


                // Change the directory visibility
                [bobRestClient setRoomDirectoryVisibility:roomId directoryVisibility:kMXRoomDirectoryVisibilityPublic success:^{

                    [room directoryVisibility:^(MXRoomDirectoryVisibility directoryVisibility) {

                        XCTAssertNotNil(directoryVisibility);
                        XCTAssertEqualObjects(directoryVisibility, kMXRoomDirectoryVisibilityPublic, @"The room directory visibility is wrong");

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

@end

#pragma clang diagnostic pop
