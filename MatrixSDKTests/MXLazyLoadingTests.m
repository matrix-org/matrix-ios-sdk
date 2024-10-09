/*
 Copyright 2018 New Vector Ltd

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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MXSDKOptions.h"

#import "MXHTTPClient_Private.h"
#import "MXFileStore.h"
#import "MatrixSDKTestsSwiftHeader.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

NSString * const bobMessage = @"I am Bob";

@interface MXLazyLoadingTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;

    // The id of the message by Bob in the scenario
    NSString *bobMessageEventId;
}

@end

@implementation MXLazyLoadingTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    [MXHTTPClient removeAllDelays];
    matrixSDKTestsData = nil;
    
    [super tearDown];
}

/**
Common initial conditions:
 - Alice, Bob in a room
 - Charlie joins the room
 - Dave is invited
 - Alice sends 50 messages
 - Bob sends one message
 - Alice sends 50 messages
 - Alice makes an initial /sync with lazy-loading enabled or not
*/
- (void)createScenarioWithLazyLoading:(BOOL)lazyLoading
                          readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self createScenarioWithLazyLoading:lazyLoading inARoomWithName:YES readyToTest:readyToTest];
}

- (void)createScenarioWithLazyLoading:(BOOL)lazyLoading
                      inARoomWithName:(BOOL)inARoomWithName
                          readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    // - Alice, Bob in a room
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        if (inARoomWithName)
        {
            // Set a room name to prevent the HS from sending us heroes through the summary API.
            // When the HS sends heroes, it also sends m.room.membership events for them. This breaks
            // how this tests suite was written.
            [roomFromBobPOV setName:@"A name" success:nil failure:nil];
        }

        [roomFromBobPOV setJoinRule:kMXRoomJoinRulePublic success:^{

            // - Charlie joins the room
            [matrixSDKTestsData doMXSessionTestWithAUser:nil readyToTest:^(MXSession *charlieSession, XCTestExpectation *expectation2) {
                [charlieSession joinRoom:roomId viaServers:nil success:^(MXRoom *room) {

                    // - Dave is invited
                    [roomFromBobPOV inviteUser:@"@dave:localhost:8480" success:^{

                        //  - Alice sends 50 messages
                        [matrixSDKTestsData for:aliceRestClient andRoom:roomId sendMessages:50 testCase:self success:^{

                            // - Bob sends a message
                            [roomFromBobPOV sendTextMessage:bobMessage threadId:nil success:^(NSString *eventId) {

                                bobMessageEventId = eventId;

                                // - Alice sends 50 messages
                                [matrixSDKTestsData for:aliceRestClient andRoom:roomId sendMessages:50 testCase:self success:^{

                                    // - Alice makes an initial /sync
                                    MXSession *aliceSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                                    [matrixSDKTestsData retain:aliceSession];


                                    // Alice makes an initial /sync with lazy-loading enabled or not
                                    MXFilterJSONModel *filter;
                                    if (lazyLoading)
                                    {
                                        filter = [MXFilterJSONModel syncFilterForLazyLoading];
                                    }

                                    [aliceSession startWithSyncFilter:filter onServerSyncDone:^{

                                        // We are done
                                        readyToTest(aliceSession, bobSession, charlieSession, roomId, expectation);

                                    } failure:^(NSError *error) {
                                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                        [expectation fulfill];
                                    }];
                                }];
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

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 Common initial conditions:
 - We have Alice & Bob
 - Alice creates a direct chat with Bob
 - Bob joins it
 - Alice makes an initial /sync with lazy-loading enabled or not
 */
- (void)createDirectChatScenarioWithLazyLoading:(BOOL)lazyLoading
                                    readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    // - We have Alice & Bob
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        __block NSString *theRoomId;

        // - Alice create a direct chat with Bob
        __block id observer;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionDirectRoomsDidChangeNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            if (observer)
            {
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                observer = nil;

                [bobSession joinRoom:theRoomId viaServers:nil success:^(MXRoom *room) {

                    // - Alice makes an initial /sync
                    MXSession *aliceSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                    [matrixSDKTestsData retain:aliceSession];

                    // Alice makes an initial /sync with lazy-loading enabled or not
                    MXFilterJSONModel *filter;
                    if (lazyLoading)
                    {
                        filter = [MXFilterJSONModel syncFilterForLazyLoading];
                    }

                    [aliceSession startWithSyncFilter:filter onServerSyncDone:^{

                        readyToTest(aliceSession, bobSession, theRoomId, expectation);

                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }
        }];

        // - Alice create a direct chat with Bob
        MXRoomCreationParameters *parameters = [MXRoomCreationParameters parametersForDirectRoomWithUser:bobSession.myUser.userId];
        [aliceRestClient createRoomWithParameters:parameters success:^(MXCreateRoomResponse *response) {

            theRoomId = response.roomId;

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}



- (void)testLazyLoadingFilterSupportHSSide
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        MXFilterJSONModel *lazyLoadingFilter = [MXFilterJSONModel syncFilterForLazyLoading];

        [mxSession startWithSyncFilter:lazyLoadingFilter onServerSyncDone:^{

            XCTAssertNotNil(mxSession.syncFilterId);
            XCTAssertTrue(mxSession.syncWithLazyLoadOfRoomMembers);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


// After the test scenario, room state should be lazy loaded and partial.
// There should be only Alice and state.members.count = 1
- (void)checkRoomStateWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        [room state:^(MXRoomState *roomState) {

            MXRoomMembers *lazyloadedRoomMembers = roomState.members;

            XCTAssert([lazyloadedRoomMembers memberWithUserId:aliceSession.myUser.userId]);

            if (lazyLoading)
            {
                XCTAssertEqual(lazyloadedRoomMembers.members.count, 1, @"There should be only Alice in the lazy loaded room state");

                XCTAssertEqual(roomState.membersCount.members, 1);
                XCTAssertEqual(roomState.membersCount.joined, 1);
                XCTAssertEqual(roomState.membersCount.invited, 0);
            }
            else
            {
                // The room members list in the room state is full known
                XCTAssertEqual(lazyloadedRoomMembers.members.count, 4);

                XCTAssertEqual(roomState.membersCount.members, 4);
                XCTAssertEqual(roomState.membersCount.joined, 3);
                XCTAssertEqual(roomState.membersCount.invited, 1);
            }

            [expectation fulfill];
        }];
    }];
}

- (void)testRoomState
{
    [self checkRoomStateWithLazyLoading:YES];
}

- (void)testRoomStateWithLazyLoadingOFF
{
    [self checkRoomStateWithLazyLoading:NO];
}

// Check lazy loaded romm state when Charlie sends a new message
- (void)checkRoomStateOnIncomingMessage:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromCharlie = @"A new message from Charlie";

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqualObjects(event.content[kMXMessageBodyKey], messageFromCharlie);

                XCTAssert([roomState.members memberWithUserId:aliceSession.myUser.userId]);
                XCTAssert([roomState.members memberWithUserId:charlieSession.myUser.userId]);

                if (lazyLoading)
                {
                    XCTAssertEqual(roomState.members.members.count, 2, @"There should only Alice and Charlie now in the lazy loaded room state");

                    XCTAssertEqual(roomState.membersCount.members, 2);
                    XCTAssertEqual(roomState.membersCount.joined, 2);
                    XCTAssertEqual(roomState.membersCount.invited, 0);
                }
                else
                {
                    // The room members list in the room state is full known
                    XCTAssertEqual(roomState.members.members.count, 4);

                    XCTAssertEqual(roomState.membersCount.members, 4);
                    XCTAssertEqual(roomState.membersCount.joined, 3);
                    XCTAssertEqual(roomState.membersCount.invited, 1);
                }

                [expectation fulfill];
            }];

            MXRoom *roomFromCharliePOV = [charlieSession roomWithRoomId:roomId];
            [roomFromCharliePOV sendTextMessage:messageFromCharlie threadId:nil success:nil failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        }];
    }];
}

- (void)testRoomStateOnIncomingMessage
{
    [self checkRoomStateOnIncomingMessage:YES];
}

- (void)testRoomStateOnIncomingMessageLazyLoadingOFF
{
    [self checkRoomStateOnIncomingMessage:NO];
}


// When paginating back to the beginning, lazy loaded room state passed in pagination callback must be updated with Bob, then Charlie and Dave.
- (void)checkRoomStateWhilePaginatingWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            __block NSUInteger messageCount = 0;
            [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                switch (++messageCount) {
                    case 50:
                        if (lazyLoading)
                        {
                            XCTAssertNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
                            XCTAssertNil([liveTimeline.state.members memberWithUserId:bobSession.myUser.userId]);
                            XCTAssertNil([liveTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                        }
                        else
                        {
                            XCTAssertNotNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
                        }

                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:aliceSession.myUser.userId]);
                        break;
                    case 51:
                        XCTAssert([roomState.members memberWithUserId:bobSession.myUser.userId]);

                        if (lazyLoading)
                        {
                            XCTAssertNil([roomState.members memberWithUserId:charlieSession.myUser.userId]);
                            XCTAssertNil([liveTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                        }
                        else
                        {
                            XCTAssert([roomState.members memberWithUserId:charlieSession.myUser.userId]);
                        }

                        // The room state of the room should have been enriched
                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:bobSession.myUser.userId]);

                        break;

                    case 110:
                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:aliceSession.myUser.userId]);
                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:bobSession.myUser.userId]);
                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                        break;

                    default:
                        break;
                }
            }];

            // Paginate the 50 last message where there is only Alice talking
            [liveTimeline resetPagination];
            [liveTimeline paginate:50 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                // Pagine a bit more to get Bob's message
                [liveTimeline paginate:25 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                    // Paginate all to get a full room state
                    [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                        XCTAssertGreaterThan(messageCount, 110, @"The test has not fully run");

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

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

- (void)testRoomStateWhilePaginating
{
    [self checkRoomStateWhilePaginatingWithLazyLoading:YES];
}

- (void)testRoomStateWhilePaginatingWithLazyLoadingOFF
{
    [self checkRoomStateWhilePaginatingWithLazyLoading:NO];
}


// As members is only partial, [room members:] should trigger an HTTP request
// and returns the 4 members.
- (void)checkRoomMembersWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        __block BOOL firstRequestComplete = NO;

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        MXHTTPOperation *operation = [room members:^(MXRoomMembers *roomMembers) {

            // The room members list in the room state is full known
            XCTAssertEqual(roomMembers.members.count, 4);
            XCTAssertEqual(roomMembers.joinedMembers.count, 3);
            XCTAssertEqual([roomMembers membersWithMembership:MXMembershipInvite].count, 1);

            firstRequestComplete = YES;

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        if (lazyLoading)
        {
            XCTAssert(operation.operation, @"As members is only partial, [room members:] should trigger an HTTP request");
        }
        else
        {
            XCTAssertNil(operation.operation);
        }

        MXHTTPOperation *secondOperation = [room members:^(MXRoomMembers *roomMembers) {

            XCTAssertTrue(firstRequestComplete);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        XCTAssertNil(secondOperation.operation, @"There must be no second request to /members");
    }];
}

- (void)testRoomMembers
{
    [self checkRoomMembersWithLazyLoading:YES];
}

- (void)testRoomMembersWithLazyLoadingOFF
{
    [self checkRoomMembersWithLazyLoading:NO];
}

// From the scenario:
// - Alice calls [MXRoom members:] with the underlying HTTP request that will be fakely delayed
// - Bob changes his name
// - [MXRoom members:] completes
// -> Bob name must be correct
- (void)checkRoomMembersRaceConditionsWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            NSString *newBobName = @"NewBob";

            // updatedFromSync is used to check the test itself
            __block BOOL updatedFromSync = NO;
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if (direction == MXTimelineDirectionForwards)
                {
                    updatedFromSync = YES;
                }
            }];

            // - Alice calls [MXRoom members:] with the underlying HTTP request that will be fakely delayed
            [MXHTTPClient setDelay:2000 toRequestsContainingString:@"/members"];
            [room members:^(MXRoomMembers *roomMembers) {

                // - [MXRoom members:] completes
                XCTAssertTrue(updatedFromSync);

                // -> Bob name must be correct
                MXRoomMember *bob = [roomMembers memberWithUserId:bobSession.myUser.userId];
                XCTAssertEqualObjects(bob.displayname, newBobName);

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            [bobSession.myUser setDisplayName:newBobName success:nil failure:nil];
        }];
    }];
}

- (void)testRoomMembersRaceConditions
{
    [self checkRoomMembersRaceConditionsWithLazyLoading:YES];
}

// There cannot be race conditions without LL
//- (void)testRoomMembersRaceConditionsWithLazyLoadingOFF
//{
//    [self checkRoomMembersRaceConditionsWithLazyLoading:NO];
//}


// From the scenario:
// - Pause Alice MXSession
// - 5 Eves join the room
// - Eve0 sends 20 messages
// - Resume Alice MXSession
// -> Alice must know all Eves
- (void)checkRoomMembersAfterLimitedSyncWithLazyLoading:(BOOL)lazyLoading
{
    // - Run the scenario
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Pause Alice MXSession
        [aliceSession pause];

        // - 5 Eve joins the room
        [matrixSDKTestsData doMXSessionTestWithAUser:nil readyToTest:^(MXSession *eve0Session, XCTestExpectation *expectation2) {
            [eve0Session joinRoom:roomId viaServers:nil success:^(MXRoom *room) {

                [matrixSDKTestsData doMXSessionTestWithAUser:nil readyToTest:^(MXSession *eve1Session, XCTestExpectation *expectation2) {
                    [eve1Session joinRoom:roomId viaServers:nil success:^(MXRoom *room) {

                        [matrixSDKTestsData doMXSessionTestWithAUser:nil readyToTest:^(MXSession *eve2Session, XCTestExpectation *expectation2) {
                            [eve2Session joinRoom:roomId viaServers:nil success:^(MXRoom *room) {

                                [matrixSDKTestsData doMXSessionTestWithAUser:nil readyToTest:^(MXSession *eve3Session, XCTestExpectation *expectation2) {
                                    [eve3Session joinRoom:roomId viaServers:nil success:^(MXRoom *room) {

                                        [matrixSDKTestsData doMXSessionTestWithAUser:nil readyToTest:^(MXSession *eve4Session, XCTestExpectation *expectation2) {
                                            [eve4Session joinRoom:roomId viaServers:nil success:^(MXRoom *room) {


                                                // - Eve0 sends 20 messages
                                                [matrixSDKTestsData for:eve0Session.matrixRestClient andRoom:roomId sendMessages:20 testCase:self success:^{

                                                    // - Resume Alice MXSession
                                                    [aliceSession resume:^{

                                                        MXRoom *room = [aliceSession roomWithRoomId:roomId];
                                                        [room state:^(MXRoomState *roomState) {

                                                            // -> Alice must know all Eves
                                                            XCTAssertNotNil([roomState.members memberWithUserId:eve0Session.myUser.userId]);
                                                            XCTAssertNotNil([roomState.members memberWithUserId:eve1Session.myUser.userId]);
                                                            XCTAssertNotNil([roomState.members memberWithUserId:eve2Session.myUser.userId]);
                                                            XCTAssertNotNil([roomState.members memberWithUserId:eve3Session.myUser.userId]);
                                                            XCTAssertNotNil([roomState.members memberWithUserId:eve4Session.myUser.userId]);

                                                            [expectation fulfill];
                                                        }];
                                                    }];
                                                }];

                                            } failure:^(NSError *error) {
                                                XCTFail(@"The operation should not fail - NSError: %@", error);
                                                [expectation fulfill];
                                            }];
                                        }];
                                    } failure:^(NSError *error) {
                                        XCTFail(@"The operation should not fail - NSError: %@", error);
                                        [expectation fulfill];
                                    }];
                                }];
                            } failure:^(NSError *error) {
                                XCTFail(@"The operation should not fail - NSError: %@", error);
                                [expectation fulfill];
                            }];
                        }];
                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testRoomMembersAfterLimitedSync
{
    [self checkRoomMembersAfterLimitedSyncWithLazyLoading:YES];
}

- (void)testRoomMembersAfterLimitedSyncLazyLoadingOFF
{
    [self checkRoomMembersAfterLimitedSyncWithLazyLoading:NO];
}


// [MXRoom members:] should make an HTTP request to fetch members only once
- (void)checkSingleRoomMembersRequestWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [room members:^(MXRoomMembers *members) {

            MXHTTPOperation *operation = [room members:^(MXRoomMembers *roomMembers) {

                // The room members list in the room state is full known
                XCTAssertEqual(roomMembers.members.count, 4);
                XCTAssertEqual(roomMembers.joinedMembers.count, 3);
                XCTAssertEqual([roomMembers membersWithMembership:MXMembershipInvite].count, 1);

                [expectation fulfill];
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            XCTAssertNil(operation.operation);

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testSingleRoomMembersRequest
{
    [self checkSingleRoomMembersRequestWithLazyLoading:YES];
}

- (void)testSingleRoomMembersRequestWithLazyLoadingOFF
{
    [self checkSingleRoomMembersRequestWithLazyLoading:NO];
}


// Check [room members:lazyLoadedMembers:] callbacks call
- (void)checkRoomMembersAndLazyLoadedMembersWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [room members:^(MXRoomMembers *members) {

            // The room members list in the room state is full known
            XCTAssertEqual(members.members.count, 4);
            XCTAssertEqual(members.joinedMembers.count, 3);
            XCTAssertEqual([members membersWithMembership:MXMembershipInvite].count, 1);

            [expectation fulfill];

        } lazyLoadedMembers:^(MXRoomMembers *lazyLoadedMembers) {

            if (lazyLoading)
            {
                XCTAssertEqual(lazyLoadedMembers.members.count, 1, @"There should be only Alice in the lazy loaded room state");
                XCTAssertEqual(lazyLoadedMembers.joinedMembers.count, 1);
                XCTAssertEqual([lazyLoadedMembers membersWithMembership:MXMembershipInvite].count, 0);
            }
            else
            {
                XCTFail(@"This block should not be called when we already know all room members");
            }

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomMembersAndLazyLoadedMembers
{
    [self checkRoomMembersAndLazyLoadedMembersWithLazyLoading:YES];
}

- (void)testRoomMembersAndLazyLoadedMembersWithLazyLoadingOFF
{
    [self checkRoomMembersAndLazyLoadedMembersWithLazyLoading:NO];
}


// Test MXRoomSummary.membership
// With the scenario, if Alice and Charlie do an /initialSync, they must see them as joined
// in the room.
- (void)checkSummaryMembershipWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        [room state:^(MXRoomState *roomState) {

            // Check Alice membership
            MXRoomSummary *roomSummary = [aliceSession roomSummaryWithRoomId:roomId];
            XCTAssertEqual(roomSummary.membership, MXMembershipJoin);


            // Check Charlie POV
            // - Charlie makes an initial /sync
            MXSession *charlieSession2 = [[MXSession alloc] initWithMatrixRestClient:charlieSession.matrixRestClient];
            [charlieSession close];
            [matrixSDKTestsData retain:charlieSession2];

            MXFilterJSONModel *filter;
            if (lazyLoading)
            {
                filter = [MXFilterJSONModel syncFilterForLazyLoading];
            }

            [charlieSession2 startWithSyncFilter:filter onServerSyncDone:^{

                // Check Charlie membership
               MXRoomSummary *roomFromCharliePOVSummary = [charlieSession2 roomSummaryWithRoomId:roomId];
                XCTAssertEqual(roomFromCharliePOVSummary.membership, MXMembershipJoin);

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testSummaryMembership
{
    [self checkSummaryMembershipWithLazyLoading:YES];
}

- (void)testSummaryMembershipWithLazyLoadingOFF
{
    [self checkSummaryMembershipWithLazyLoading:NO];
}

// Complementary test to testSummaryMembership
// - Run the scenario
// - Pause Alice MXSession
// - Make her leave the room outside her MXSession
// - Bob sends 50 messages
// - Resume Alice MXSession
// -> Alice must not know the room anymore
- (void)checkRoomAfterLeavingFromAnotherDeviceWithLazyLoading:(BOOL)lazyLoading
{
    // - Run the scenario
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        MXRoomSummary *summary = [aliceSession roomSummaryWithRoomId:roomId];

        XCTAssertNotNil(room);
        XCTAssertNotNil(summary);

        // - Pause Alice MXSession
        [aliceSession pause];

        // - Make her leave the room outside her MXSession
        [aliceSession.matrixRestClient leaveRoom:roomId success:^{

            // - Bob sends 50 messages
            [matrixSDKTestsData for:bobSession.matrixRestClient andRoom:roomId sendMessages:50 testCase:self success:^{

                // - Resume Alice MXSession
                [aliceSession resume:^{

                    MXRoom *room = [aliceSession roomWithRoomId:roomId];
                    MXRoomSummary *summary = [aliceSession roomSummaryWithRoomId:roomId];

                    XCTAssertNil(room);
                    XCTAssertNil(summary);

                    [expectation fulfill];
                }];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomAfterLeavingFromAnotherDevice
{
    [self checkRoomAfterLeavingFromAnotherDeviceWithLazyLoading:YES];
}

- (void)testRoomAfterLeavingFromAnotherDeviceWithLazyLoadingOFF
{
    [self checkRoomAfterLeavingFromAnotherDeviceWithLazyLoading:NO];
}


// Complementary test to testRoomAfterLeavingFromAnotherDevice to check
// the regression described at https://github.com/vector-im/riot-ios/issues/2082:
// - Run the scenario
// - Restart Alice session with a permanent store (MXFileStore)
// - Alice requests all members from the HS
// - and make a pagination request, because there is a bug here too
// - Meanwhile, Alice leaves the room
// - Close and reopen Alice session
// -> Alice must not know the room anymore
- (void)checkRoomAfterLeavingWithLazyLoading:(BOOL)lazyLoading
{
    // - Run the scenario
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        MXRoomSummary *summary = [aliceSession roomSummaryWithRoomId:roomId];
        XCTAssertNotNil(room);
        XCTAssertNotNil(summary);

        // - Restart Alice session with a permanent store (MXFileStore)
        MXRestClient *aliceRestClient = aliceSession.matrixRestClient;
        [aliceSession close];
        aliceSession = nil;

        MXFileStore *store = [[MXFileStore alloc] init];
        __block MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:aliceSession2];
        [aliceSession2 setStore:store success:^{
            [aliceSession2 start:^{

                MXRoom *room2 = [aliceSession2 roomWithRoomId:roomId];
                MXRoomSummary *summary2 = [aliceSession2 roomSummaryWithRoomId:roomId];
                XCTAssertNotNil(room2);
                XCTAssertNotNil(summary2);

                [room2 liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                    // - Alice requests all members from the HS
                    // Force [MXRoom members:] to make a request
                    [aliceSession2.store storeHasLoadedAllRoomMembersForRoom:roomId andValue:NO];

                    [MXHTTPClient setDelay:1000 toRequestsContainingString:@"/members"];
                    [room2 members:^(MXRoomMembers *members) {

                        MXRoom *room2a = [aliceSession2 roomWithRoomId:roomId];
                        MXRoomSummary *summary2a = [aliceSession2 roomSummaryWithRoomId:roomId];
                        XCTAssertNil(room2a);
                        XCTAssertNil(summary2a);

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];


                    // - and a pagination request, because there is a bug here too
                    [MXHTTPClient setDelay:1000 toRequestsContainingString:@"/messages"];
                    [liveTimeline resetPagination];
                    [liveTimeline paginate:30 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                        MXRoom *room2a = [aliceSession2 roomWithRoomId:roomId];
                        MXRoomSummary *summary2a = [aliceSession2 roomSummaryWithRoomId:roomId];
                        XCTAssertNil(room2a);
                        XCTAssertNil(summary2a);

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];


                    // - Meanwhile, she leaves the room
                    [room2 leave:^{

                        // Let time for the pagination to complete
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2000 * USEC_PER_SEC), dispatch_get_main_queue(), ^{

                            // Keep a ref to room2 so that requests on it can complete
                            MXLogDebug(@"%@", room2);

                            MXRoom *room2b = [aliceSession2 roomWithRoomId:roomId];
                            MXRoomSummary *summary2b = [aliceSession2 roomSummaryWithRoomId:roomId];
                            XCTAssertNil(room2b);
                            XCTAssertNil(summary2b);

                            // - Close and reopen Alice session
                            [aliceSession2 close];
                            aliceSession2 = nil;

                            MXFileStore *store = [[MXFileStore alloc] init];
                            MXSession *aliceSession3 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                            [matrixSDKTestsData retain:aliceSession3];
                            [aliceSession3 setStore:store success:^{
                                [aliceSession3 start:^{

                                    // -> Alice must not know the room anymore
                                    MXRoom *room3 = [aliceSession3 roomWithRoomId:roomId];
                                    MXRoomSummary *summary3 = [aliceSession3 roomSummaryWithRoomId:roomId];
                                    XCTAssertNil(room3);
                                    XCTAssertNil(summary3);

                                    [expectation fulfill];

                                } failure:^(NSError *error) {
                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                    [expectation fulfill];
                                }];
                            } failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];
                        });
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

- (void)testRoomAfterLeaving
{
    [self checkRoomAfterLeavingWithLazyLoading:YES];
}

- (void)testRoomAfterLeavingWithLazyLoadingOFF
{
    [self checkRoomAfterLeavingWithLazyLoading:NO];
}


// roomSummary.membersCount must be right in both cases
- (void)checkRoomSummaryMembersCountWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoomSummary *roomSummary = [aliceSession roomSummaryWithRoomId:roomId];

        XCTAssertEqual(roomSummary.membersCount.members, 4);
        XCTAssertEqual(roomSummary.membersCount.joined, 3);
        XCTAssertEqual(roomSummary.membersCount.invited, 1);

        [expectation fulfill];
    }];
}

- (void)testRoomSummaryMembersCount
{
    [self checkRoomSummaryMembersCountWithLazyLoading:YES];
}

- (void)testRoomSummaryMembersCountWithLazyLoadingOFF
{
    [self checkRoomSummaryMembersCountWithLazyLoading:NO];
}


// Check room display name computed from heroes provided in the room summary
- (void)checkRoomSummaryDisplayNameFromHeroesWithLazyLoading:(BOOL)lazyLoading
{
    // Do not set a room name for this test
    [self createScenarioWithLazyLoading:lazyLoading inARoomWithName:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        [room state:^(MXRoomState *roomState) {

            // Membership events for heroes must have been lazy-loaded
            // There are used to compute roomSummary.displayname
            XCTAssertNotNil([roomState.members memberWithUserId:aliceSession.myUser.userId]);
            XCTAssertNotNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
            XCTAssertNotNil([roomState.members memberWithUserId:charlieSession.myUser.userId]);

            MXRoomSummary *roomSummary = [aliceSession roomSummaryWithRoomId:roomId];

            XCTAssertTrue(roomSummary.displayName.length
                              && ![roomSummary.displayName isEqualToString:@"Empty room"], @"Unexpected null room name: %@", roomSummary.displayName);

            [expectation fulfill];
        }];
    }];
}

- (void)testRoomSummaryDisplayNameFromHeroes
{
    [self checkRoomSummaryDisplayNameFromHeroesWithLazyLoading:YES];
}

- (void)testRoomSummaryDisplayNameFromHeroesWithLazyLoadingOFF
{
    [self checkRoomSummaryDisplayNameFromHeroesWithLazyLoading:NO];
}


// Check Synapse issue (https://github.com/matrix-org/synapse/issues/4194): the CS API should provide heroes if room name is ""
// After the test scenario,
// Remove the room name
// -> The room name should be "Bob & 2 others"
// Make alice do an initial sync
// -> The room name should be "Bob & 2 others"
- (void)checkRoomSummaryDisplayNameWhenNoMoreNameWithLazyLoading:(BOOL)lazyLoading
{
    // After the test scenario
    [self createScenarioWithLazyLoading:lazyLoading inARoomWithName:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        [roomFromBobPOV setName:@"" success:^{

            MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
            [roomFromAlicePOV state:^(MXRoomState *roomState) {

                // -> The room name should be "Bob & 2 others"
                MXRoomSummary *roomSummary = [aliceSession roomSummaryWithRoomId:roomId];
                XCTAssertTrue(roomSummary.displayName.length
                              && ![roomSummary.displayName isEqualToString:@"Empty room"], @"Unexpected null room name: %@", roomSummary.displayName);


                 // Make alice do an initial sync
                MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceSession.matrixRestClient];
                [matrixSDKTestsData retain:aliceSession2];
                [aliceSession close];

                MXFilterJSONModel *filter;
                if (lazyLoading)
                {
                    filter = [MXFilterJSONModel syncFilterForLazyLoading];
                }
                [aliceSession2 startWithSyncFilter:filter onServerSyncDone:^{

                    MXRoom *room2 = [aliceSession2 roomWithRoomId:roomId];
                    [room2 state:^(MXRoomState *roomState) {

                        // -> The room name should be "Bob & 2 others"
                        MXRoomSummary *roomSummary2 = [aliceSession2 roomSummaryWithRoomId:roomId];
                        XCTAssertTrue(roomSummary2.displayName.length
                                      && ![roomSummary2.displayName isEqualToString:@"Empty room"], @"Unexpected null room name: %@", roomSummary2.displayName);


                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];

            }];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testRoomSummaryDisplayNameWhenNoMoreName
{
    [self checkRoomSummaryDisplayNameWhenNoMoreNameWithLazyLoading:YES];
}

- (void)testRoomSummaryDisplayNameWhenNoMoreNameWithLazyLoadingOFF
{
    [self checkRoomSummaryDisplayNameWhenNoMoreNameWithLazyLoading:NO];
}

// Check use case described in https://github.com/matrix-org/matrix-ios-sdk/pull/605
// where display name for a direct chat becomes empty after a limited /sync
//
// After the direct chat test scenario
// - Alice pauses its session
// - Bob sends 50 messages
// - Alice resumes (there will be a limited /sync)
// -> The room name should be still the same
- (void)checkRoomSummaryDisplayNameInDirectChatWithLazyLoading:(BOOL)lazyLoading
{
    [self createDirectChatScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoomSummary *roomSummary = [aliceSession roomSummaryWithRoomId:roomId];
        XCTAssertTrue(roomSummary.displayName.length
                      && ![roomSummary.displayName isEqualToString:@"Empty room"], @"Unexpected null room name: %@", roomSummary.displayName);

        NSString *roomDisplayName = roomSummary.displayName;

        [aliceSession pause];

        //  - Bob sends 50 messages
        [matrixSDKTestsData for:bobSession.matrixRestClient andRoom:roomId sendMessages:50 testCase:self success:^{

            // - Alice resumes (there will a limited /sync)
            [aliceSession resume:^{

                // -> The room name should be still the same
                MXRoomSummary *roomSummary2 = [aliceSession roomSummaryWithRoomId:roomId];
                XCTAssertEqualObjects(roomSummary2.displayName, roomDisplayName);

                [expectation fulfill];
            }];
        }];

    }];
}

- (void)testRoomSummaryDisplayNameInDirectChat
{
    [self checkRoomSummaryDisplayNameInDirectChatWithLazyLoading:YES];
}

- (void)testRoomSummaryDisplayNameInDirectChatWithLazyLoadingOFF
{
    [self checkRoomSummaryDisplayNameInDirectChatWithLazyLoading:NO];
}


// After the test scenario, create a temporary timeline on the last event.
// The timeline state should be lazy loaded and partial.
// There should be only Alice and state.members.count = 1
- (void)checkPermalinkRoomStateWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoomSummary *summary = [aliceSession roomSummaryWithRoomId:roomId];
        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        id<MXEventTimeline> eventTimeline = [room timelineOnEvent:summary.lastMessage.eventId];

        [eventTimeline resetPaginationAroundInitialEventWithLimit:10 success:^{

            MXRoomState *roomState = eventTimeline.state;

            MXRoomMembers *lazyloadedRoomMembers = roomState.members;

            XCTAssert([lazyloadedRoomMembers memberWithUserId:aliceSession.myUser.userId]);

            if (lazyLoading)
            {
                XCTAssertEqual(lazyloadedRoomMembers.members.count, 1, @"There should be only Alice in the lazy loaded room state");

                XCTAssertEqual(roomState.membersCount.members, 1);
                XCTAssertEqual(roomState.membersCount.joined, 1);
                XCTAssertEqual(roomState.membersCount.invited, 0);
            }
            else
            {
                // The room members list in the room state is full known
                XCTAssertEqual(lazyloadedRoomMembers.members.count, 4);

                XCTAssertEqual(roomState.membersCount.members, 4);
                XCTAssertEqual(roomState.membersCount.joined, 3);
                XCTAssertEqual(roomState.membersCount.invited, 1);
            }

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPermalinkRoomState
{
    [self checkPermalinkRoomStateWithLazyLoading:YES];
}

- (void)testPermalinkRoomStateWithLazyLoadingOFF
{
    [self checkPermalinkRoomStateWithLazyLoading:NO];
}


// Test lazy loaded members sent by the HS when paginating backward from a permalink
// When paginating back to the beginning, lazy loaded room state passed in pagination callback must be updated with Bob, then Charlie and Dave.
// Almost the same test as `checkRoomStateWhilePaginatingWithLazyLoading`.
- (void)checkPermalinkRoomStateWhilePaginatingBackwardWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoomSummary *summary = [aliceSession roomSummaryWithRoomId:roomId];
        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        id<MXEventTimeline> eventTimeline = [room timelineOnEvent:summary.lastMessage.eventId];

        __block NSUInteger messageCount = 0;
        [eventTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            switch (++messageCount)
            {
                case 1:
                    XCTAssertEqualObjects(event.sender, aliceSession.myUser.userId);

                    if (lazyLoading)
                    {
                        XCTAssertNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
                        XCTAssertNil([eventTimeline.state.members memberWithUserId:bobSession.myUser.userId]);
                        XCTAssertNil([eventTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                    }
                    else
                    {
                        XCTAssertNotNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
                    }

                    XCTAssertNotNil([eventTimeline.state.members memberWithUserId:aliceSession.myUser.userId]);
                    break;

                case 50:
                    if (lazyLoading)
                    {
                        // Disabled because the HS sends too early the Bob membership event (but not Charlie nor Dave)
                        //XCTAssertNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
                        //XCTAssertNil([eventTimeline.state.members memberWithUserId:bobSession.myUser.userId]);
                        XCTAssertNil([eventTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                    }
                    else
                    {
                        XCTAssertNotNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
                    }

                    XCTAssertNotNil([eventTimeline.state.members memberWithUserId:aliceSession.myUser.userId]);
                    break;
                case 51:
                    XCTAssert([roomState.members memberWithUserId:bobSession.myUser.userId]);

                    if (lazyLoading)
                    {
                        XCTAssertNil([roomState.members memberWithUserId:charlieSession.myUser.userId]);
                        XCTAssertNil([eventTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                    }
                    else
                    {
                        XCTAssert([roomState.members memberWithUserId:charlieSession.myUser.userId]);
                    }

                    // The room state of the room should have been enriched
                    XCTAssertNotNil([eventTimeline.state.members memberWithUserId:bobSession.myUser.userId]);

                    break;

                case 110:
                    XCTAssertNotNil([eventTimeline.state.members memberWithUserId:aliceSession.myUser.userId]);
                    XCTAssertNotNil([eventTimeline.state.members memberWithUserId:bobSession.myUser.userId]);
                    XCTAssertNotNil([eventTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                    break;

                default:
                    break;
            }
        }];

        [eventTimeline resetPaginationAroundInitialEventWithLimit:0 success:^{

            // Paginate the 50 last message where there is only Alice talking
            [eventTimeline paginate:50 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                // Pagine a bit more to get Bob's message
                [eventTimeline paginate:25 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                    // Paginate all to get a full room state
                    [eventTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                        XCTAssertGreaterThan(messageCount, 110, @"The test has not fully run");

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }
        failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPermalinkRoomStateWhilePaginatingBackward
{
    [self checkPermalinkRoomStateWhilePaginatingBackwardWithLazyLoading:YES];
}

- (void)testPermalinkRoomStateWhilePaginatingWithLazyLoadingOFF
{
    [self checkPermalinkRoomStateWhilePaginatingBackwardWithLazyLoading:NO];
}


// Test lazy loaded members sent by the HS when paginating forward
// - Come back to Bob message
// - We should only know Bob membership
// - Paginate forward to get Alice next message
// - We should know Alice membership now
- (void)checkPermalinkRoomStateWhilePaginatingForwardWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        id<MXEventTimeline> eventTimeline = [room timelineOnEvent:bobMessageEventId];

        __block NSUInteger messageCount = 0;
        [eventTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            switch (++messageCount)
            {
                case 1:
                    // Bob message
                    // - We should only know Bob membership
                    XCTAssertEqualObjects(event.sender, bobSession.myUser.userId);

                    if (lazyLoading)
                    {
                        XCTAssertNil([eventTimeline.state.members memberWithUserId:aliceSession.myUser.userId]);
                        XCTAssertNil([eventTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                    }
                    else
                    {
                        XCTAssertNotNil([roomState.members memberWithUserId:aliceSession.myUser.userId]);
                    }

                    XCTAssertNotNil([eventTimeline.state.members memberWithUserId:bobSession.myUser.userId]);
                    break;

                case 2:
                    // First next message from Alice
                    // - We should know Alice membership now
                    XCTAssertEqualObjects(event.sender, aliceSession.myUser.userId);

                    if (lazyLoading)
                    {
                        XCTAssertNil([eventTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                    }

                    XCTAssertNotNil([eventTimeline.state.members memberWithUserId:aliceSession.myUser.userId]);
                    XCTAssertNotNil([eventTimeline.state.members memberWithUserId:bobSession.myUser.userId]);
                    break;

                default:
                    break;
            }
        }];

        // - Come back to Bob message
        [eventTimeline resetPaginationAroundInitialEventWithLimit:0 success:^{

            // - Paginate forward to get Alice next message
            [eventTimeline paginate:1 direction:MXTimelineDirectionForwards onlyFromStore:NO complete:^{

                XCTAssertGreaterThanOrEqual(messageCount, 2, @"The test has not fully run");

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
}

- (void)testPermalinkRoomStateWhilePaginatingForward
{
    [self checkPermalinkRoomStateWhilePaginatingForwardWithLazyLoading:YES];
}

- (void)testPermalinkRoomStateWhilePaginatingForwardWithLazyLoadingOFF
{
    [self checkPermalinkRoomStateWhilePaginatingForwardWithLazyLoading:NO];
}


// After the test scenario, search for the message sent by Bob.
// We should be able to display 
- (void)checkSearchWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        [aliceSession.matrixRestClient searchMessagesWithText:bobMessage roomEventFilter:nil beforeLimit:0 afterLimit:0 nextBatch:nil success:^(MXSearchRoomEventResults *roomEventResults) {

            XCTAssertEqual(roomEventResults.results.count, 1);

            if (roomEventResults.results.count)
            {
                XCTAssertNotNil(roomEventResults.results.firstObject.context.profileInfo[bobSession.myUser.userId].displayName);
            }

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testSearch
{
    [self checkSearchWithLazyLoading:YES];
}

- (void)testSearchWithLazyLoadingOFF
{
    [self checkSearchWithLazyLoading:NO];
}


// Copied from testDirectRoomsAfterInitialSync
// After the test scenario:
// - Alice sets the room as direct
// - Alice invites Bob in a direct chat
// - Charlie invites Alice in a direct chat
// - Alice does an initial /sync
// -> Alice must still see 2 direct rooms with Alice and 1 with Charlie
- (void)checkDirectRoomWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        __block id observer;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionDirectRoomsDidChangeNotification object:aliceSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            // Wait until we get the 3 direct rooms
            if (observer
                && aliceSession.directRooms[bobSession.myUser.userId].count == 2
                && aliceSession.directRooms[charlieSession.myUser.userId].count == 1)
            {
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                observer = nil;

                // - Bob does an initial /sync
                MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceSession.matrixRestClient];
                [matrixSDKTestsData retain:aliceSession2];
                [aliceSession close];

                // Alice makes an initial /sync with lazy-loading enabled or not
                MXFilterJSONModel *filter;
                if (lazyLoading)
                {
                    filter = [MXFilterJSONModel syncFilterForLazyLoading];
                }

                __block NSUInteger directRoomsDidChangeNotificationCountWhileStarting = 0;
                [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionDirectRoomsDidChangeNotification object:aliceSession2 queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    directRoomsDidChangeNotificationCountWhileStarting++;

                    // We must receive a single big update
                    // Else the code decided to update direct rooms while processing the /sync responce.
                    // which means there is a race condition like in https://github.com/vector-im/riot-ios/issues/1983
                    XCTAssertEqual(aliceSession2.directRooms.count, 2);
                    XCTAssertEqual(aliceSession2.directRooms[bobSession.myUser.userId].count, 2);
                    XCTAssertEqual(aliceSession2.directRooms[charlieSession.myUser.userId].count, 1);

                    if (directRoomsDidChangeNotificationCountWhileStarting > 1)
                    {
                        XCTFail(@"We should receive one big kMXSessionDirectRoomsDidChangeNotification");
                    }
                }];


                [aliceSession2 startWithSyncFilter:filter onServerSyncDone:^{

                    // -> He must still see 2 direct rooms with Alice and 1 with Charlie
                    XCTAssertEqual(aliceSession2.directRooms.count, 2);
                    XCTAssertEqual(aliceSession2.directRooms[bobSession.myUser.userId].count, 2);
                    XCTAssertEqual(aliceSession2.directRooms[charlieSession.myUser.userId].count, 1);
                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }
        }];


        // - Bob set the room as direct
        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        [room setIsDirect:YES withUserId:bobSession.myUser.userId success:nil failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        // - Alice invites Bob in a direct chat
        MXRoomCreationParameters *parameters = [MXRoomCreationParameters new];
        parameters.inviteArray = @[bobSession.myUser.userId];
        parameters.isDirect = YES;
        parameters.visibility = kMXRoomDirectoryVisibilityPrivate;
        [aliceSession createRoomWithParameters:parameters success:nil failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        // - Charlie invites Alice in a direct chat
        parameters = [MXRoomCreationParameters new];
        parameters.visibility = kMXRoomDirectoryVisibilityPrivate;
        parameters.isDirect = YES;
        parameters.inviteArray = @[aliceSession.myUser.userId];
        [charlieSession createRoomWithParameters:parameters success:nil failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testDirectRoom
{
    [self checkDirectRoomWithLazyLoading:YES];
}

- (void)testDirectRoomWithLazyLoadingOFF
{
    [self checkDirectRoomWithLazyLoading:NO];
}


/*
 @TODO(lazy-loading):
 - test read receipts
 */
@end

#pragma clang diagnostic pop

