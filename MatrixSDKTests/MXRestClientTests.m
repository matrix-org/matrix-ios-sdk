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

#import "MXRestClient.h"
#import "MatrixSDKTestsData.h"
#import "MXRoomMember.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXRestClientTests : XCTestCase

@end

@implementation MXRestClientTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testInit
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        
        MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
        
        XCTAssertTrue([bobRestClient.homeserver isEqualToString:kMXTestsHomeServerURL], "bobRestClient.homeserver(%@) is wrong", bobRestClient.homeserver);
        XCTAssertTrue([bobRestClient.credentials.userId isEqualToString:sharedData.bobCredentials.userId], "bobRestClient.userId(%@) is wrong", bobRestClient.credentials.userId);
        XCTAssertTrue([bobRestClient.credentials.accessToken isEqualToString:sharedData.bobCredentials.accessToken], "bobRestClient.accessToken(%@) is wrong", bobRestClient.credentials.accessToken);
        
        [expectation fulfill];
    }];
}

#pragma mark - Room operations
- (void)testSendTextMessage
{
    // This test on sendTextMessage validates sendMessage and sendEvent too
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient sendTextMessageToRoom:roomId text:@"This is text message" success:^(NSString *eventId) {
            
            XCTAssertNotNil(eventId);
            XCTAssertGreaterThan(eventId.length, 0, @"The eventId string must not be empty");
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomTopic
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        __block MXRestClient *bobRestClient2 = bobRestClient;
        [bobRestClient setRoomTopic:roomId topic:@"Topic setter and getter functions are tested here" success:^{
            
            [bobRestClient2 topicOfRoom:roomId success:^(NSString *topic) {
                
                XCTAssertNotNil(topic);
                XCTAssertNotEqual(topic.length, 0);
                XCTAssert([topic isEqualToString:@"Topic setter and getter functions are tested here"], @"Room name must have been changed to \"Topic setter and getter functions are tested here\". Found: %@", topic);
                [expectation fulfill];
                
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

- (void)testRoomAvatar
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        __block MXRestClient *bobRestClient2 = bobRestClient;
        [bobRestClient setRoomAvatar:roomId avatar:@"http://matrix.org/matrix.png" success:^{

            [bobRestClient2 avatarOfRoom:roomId success:^(NSString *avatar) {

                XCTAssertNotNil(avatar);
                XCTAssertNotEqual(avatar.length, 0);
                XCTAssertEqualObjects(avatar, @"http://matrix.org/matrix.png");
                [expectation fulfill];

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

- (void)testRoomName
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        __block MXRestClient *bobRestClient2 = bobRestClient;
        [bobRestClient setRoomName:roomId name:@"My room name" success:^{
            
            [bobRestClient2 nameOfRoom:roomId success:^(NSString *name) {
                
                XCTAssertNotNil(name);
                XCTAssertNotEqual(name.length, 0);
                XCTAssert([name isEqualToString:@"My room name"], @"Room name must have been changed to \"My room name\". Found: %@", name);
                [expectation fulfill];
                
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

- (void)testJoinRoomWithRoomId
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient joinRoom:roomId success:^(NSString *theRoomId) {
            
            // No data to test. Just happy to go here.
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testJoinRoomWithRoomAlias
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        NSString *mxPublicAlias = [NSString stringWithFormat:@"#mxPublic:%@", @"localhost:8480"];

        [bobRestClient joinRoom:mxPublicAlias success:^(NSString *theRoomId) {

            XCTAssertEqualObjects(roomId, theRoomId);
            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testLeaveRoom
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient leaveRoom:roomId success:^{
            
            // No data to test. Just happy to go here.
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testInviteUserToRoom
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            // Do the test
            [bobRestClient inviteUser:sharedData.aliceCredentials.userId toRoom:roomId success:^{
                
                // Check room actual members
                [bobRestClient membersOfRoom:roomId success:^(NSArray *roomMemberEvents) {
                    
                    XCTAssertEqual(2, roomMemberEvents.count, @"There must be 2 members");
                    
                    for (MXEvent *roomMemberEvent in roomMemberEvents)
                    {
                        MXRoomMember *member = [[MXRoomMember alloc] initWithMXEvent:roomMemberEvent];
                        
                        if ([member.userId isEqualToString:sharedData.aliceCredentials.userId])
                        {
                            XCTAssertEqual(member.membership, MXMembershipInvite, @"A invited user membership is invite, not %tu", member.membership);
                        }
                        else
                        {
                            // The other user is Bob
                            XCTAssert([member.userId isEqualToString:sharedData.bobCredentials.userId], @"Unexpected member: %@", member);
                        }
                    }
                    
                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot check test result - error: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        }];
    }];
}

- (void)testKickUserFromRoom
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient kickUser:sharedData.aliceCredentials.userId fromRoom:roomId reason:@"No particular reason" success:^{
            
            // Check room actual members
            [bobRestClient membersOfRoom:roomId success:^(NSArray *roomMemberEvents) {
                
                XCTAssertEqual(2, roomMemberEvents.count, @"There must still be 2 members");
                
                for (MXEvent *roomMemberEvent in roomMemberEvents)
                {
                    MXRoomMember *member = [[MXRoomMember alloc] initWithMXEvent:roomMemberEvent];
                    
                    if ([member.userId isEqualToString:sharedData.aliceCredentials.userId])
                    {
                        XCTAssertEqual(member.membership, MXMembershipLeave, @"A kicked user membership is leave, not %tu", member.membership);
                    }
                    else
                    {
                        // The other user is Bob
                        XCTAssert([member.userId isEqualToString:sharedData.bobCredentials.userId], @"Unexpected member: %@", member);
                    }
                }
                
                [expectation fulfill];
            }
                        failure:^(NSError *error) {
                            NSAssert(NO, @"Cannot check test result - error: %@", error);
                            [expectation fulfill];
                        }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testBanUserInRoom
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient banUser:sharedData.aliceCredentials.userId inRoom:roomId reason:@"No particular reason" success:^{
            
            // Check room actual members
            [bobRestClient membersOfRoom:roomId success:^(NSArray *roomMemberEvents) {
                
                XCTAssertEqual(2, roomMemberEvents.count, @"There must still be 2 members");
                
                for (MXEvent *roomMemberEvent in roomMemberEvents)
                {
                    MXRoomMember *member = [[MXRoomMember alloc] initWithMXEvent:roomMemberEvent];
                    
                    if ([member.userId isEqualToString:sharedData.aliceCredentials.userId])
                    {
                        XCTAssertEqual(member.membership, MXMembershipBan, @"A banned user membership is ban, not %tu", member.membership);
                    }
                    else
                    {
                        // The other user is Bob
                        XCTAssert([member.userId isEqualToString:sharedData.bobCredentials.userId], @"Unexpected member: %@", member);
                    }
                }
                
                [expectation fulfill];
            }
                           failure:^(NSError *error) {
                               NSAssert(NO, @"Cannot check test result - error: %@", error);
                               [expectation fulfill];
                           }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testCreateRoom
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        
        // Create a random room with no params
        [bobRestClient createRoom:nil visibility:nil roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {
            
            XCTAssertNotNil(response);
            XCTAssertNotNil(response.roomId, "The home server should have allocated a room id");
            
            // Do not test response.room_alias as it is not filled here
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMessagesWithNoParams
{
    [[MatrixSDKTestsData sharedData]  doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient messagesForRoom:roomId from:nil to:nil limit:-1 success:^(MXPaginationResponse *paginatedResponse) {
            
            XCTAssertNotNil(paginatedResponse);
            XCTAssertNotNil(paginatedResponse.start);
            XCTAssertNotNil(paginatedResponse.end);
            XCTAssertNotNil(paginatedResponse.chunk);
            XCTAssertGreaterThan(paginatedResponse.chunk.count, 0);
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testMessagesWithOneParam
{
    [[MatrixSDKTestsData sharedData]  doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [bobRestClient messagesForRoom:roomId from:nil to:nil limit:100 success:^(MXPaginationResponse *paginatedResponse) {

            XCTAssertNotNil(paginatedResponse);
            XCTAssertNotNil(paginatedResponse.start);
            XCTAssertNotNil(paginatedResponse.end);
            XCTAssertNotNil(paginatedResponse.chunk);
            XCTAssertGreaterThan(paginatedResponse.chunk.count, 0);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testMembers
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient membersOfRoom:roomId success:^(NSArray *roomMemberEvents) {
            
            XCTAssertEqual(roomMemberEvents.count, 1);
            
            MXEvent *roomMemberEvent = roomMemberEvents[0];
            XCTAssertTrue([roomMemberEvent.sender isEqualToString:bobRestClient.credentials.userId]);
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testStateOfRoom
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient stateOfRoom:roomId success:^(NSDictionary *JSONData) {
            
            XCTAssertNotNil(JSONData);
            
            XCTAssert([JSONData isKindOfClass:[NSArray class]]);
            NSArray *states = (NSArray*)JSONData;
            XCTAssertGreaterThan(states.count, 0);
            
            // Check that all provided events are state events
            for (NSDictionary *eventDict in states)
            {
                MXEvent *event = [MXEvent modelFromJSON:eventDict];
                
                XCTAssertNotNil(event);
                XCTAssert(event.isState);
            }
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testSendTypingNotification
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [bobRestClient sendTypingNotificationInRoom:roomId typing:YES timeout:30000 success:^{

            [bobRestClient sendTypingNotificationInRoom:roomId typing:NO timeout:-1 success:^{

                [expectation fulfill];

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

- (void)testRedactEvent
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [bobRestClient sendTextMessageToRoom:roomId text:@"This is text message" success:^(NSString *eventId) {

            [bobRestClient redactEvent:eventId inRoom:roomId reason:@"No reason" success:^{

                [expectation fulfill];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testInitialSyncOfRoom
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient initialSyncOfRoom:roomId withLimit:3 success:^(MXRoomInitialSync *roomInitialSync) {
            
            XCTAssertNotNil(roomInitialSync);
            XCTAssertNotNil(roomInitialSync.roomId);
            XCTAssertNotNil(roomInitialSync.membership);
            XCTAssertNotNil(roomInitialSync.messages);
            XCTAssertNotNil(roomInitialSync.messages.chunk);
            XCTAssertNotNil(roomInitialSync.state);
            XCTAssertNotNil(roomInitialSync.presence);
            
            XCTAssert([roomInitialSync.roomId isEqualToString:roomId]);
            XCTAssert([roomInitialSync.membership isEqualToString:@"join"]);
            
            XCTAssert([roomInitialSync.messages.chunk isKindOfClass:[NSArray class]]);
            NSArray *messages = roomInitialSync.messages.chunk;
            XCTAssertEqual(messages.count, 3);
            
            XCTAssert([roomInitialSync.state isKindOfClass:[NSArray class]]);
            
            XCTAssert([roomInitialSync.presence isKindOfClass:[NSArray class]]);
            NSArray *presences = roomInitialSync.presence;
            XCTAssertEqual(presences.count, 1);
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Remove the `age` field from a dictionary and all its sub dictionaries
- (void) removeAgeField:(MXRoomInitialSync*)roomInitialSync
{
    for (MXEvent *event in roomInitialSync.messages.chunk)
    {
        event.ageLocalTs = 0;
    }
    
    for (MXEvent *event in roomInitialSync.state)
    {
        event.ageLocalTs = 0;
    }
}

// Compare the result of initialSyncOfRoom with the data retrieved from a global initialSync
- (void)testInitialSyncOfRoomAndGlobalInitialSync
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [bobRestClient initialSyncWithLimit:3 success:^(MXInitialSyncResponse *initialSyncResponse) {

            MXRoomInitialSync *roomDataInGlobal;

            for (MXRoomInitialSync *roomSync in initialSyncResponse.rooms)
            {
                if ([roomId isEqualToString:roomSync.roomId])
                {
                    roomDataInGlobal = roomSync;
                }
            }

            XCTAssertNotNil(roomDataInGlobal);

            [bobRestClient initialSyncOfRoom:roomId withLimit:3 success:^(MXRoomInitialSync *roomInitialSync) {

                XCTAssertNotNil(roomInitialSync);

                // Do some cleaning before comparison
                // Remove presence from initialSyncOfRoom result
                roomInitialSync.presence = nil;

                // Remove new added field receipts from initialSyncOfRoom result
                roomInitialSync.receipts = nil;

                // Remove visibility from global initialSync
                roomDataInGlobal.visibility = nil;

                // Remove the `age` field which is time dynamic
                [self removeAgeField:roomDataInGlobal];
                [self removeAgeField:roomInitialSync];

                // Do the comparison
                XCTAssertEqualObjects(roomDataInGlobal, roomInitialSync);

                [expectation fulfill];

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

- (void)testInitialSyncOfRoomAndGlobalInitialSyncOnRoomWithTwoUsers
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    [sharedData doMXRestClientTestWithBobAndAliceInARoom:self
 readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [sharedData for:bobRestClient andRoom:roomId sendMessages:5 success:^{
            [bobRestClient leaveRoom:roomId success:^{
                [aliceRestClient sendTextMessageToRoom:roomId text:@"Hi bob"  success:^(NSString *eventId) {
                    [aliceRestClient inviteUser:bobRestClient.credentials.userId toRoom:roomId success:^{
                        [bobRestClient joinRoom:roomId success:^(NSString *theRoomId) {

                            [bobRestClient initialSyncWithLimit:10 success:^(MXInitialSyncResponse *initialSyncResponse) {

                                MXRoomInitialSync *roomDataInGlobal;
                                
                                for (MXRoomInitialSync *roomSync in initialSyncResponse.rooms)
                                {
                                    if ([roomId isEqualToString:roomSync.roomId])
                                    {
                                        roomDataInGlobal = roomSync;
                                    }
                                }
                                
                                XCTAssertNotNil(roomDataInGlobal);

                                [bobRestClient initialSyncOfRoom:roomId withLimit:10 success:^(MXRoomInitialSync *roomInitialSync) {

                                    XCTAssertNotNil(roomInitialSync);

                                    // Do some cleaning before comparison
                                    // Remove presence from initialSyncOfRoom result
                                    roomInitialSync.presence = nil;

                                    // Remove new added field receipts from initialSyncOfRoom result
                                    roomInitialSync.receipts = nil;

                                    // Remove visibility from global initialSync
                                    roomDataInGlobal.visibility = nil;

                                    // Remove the `age` field which is time dynamic
                                    [self removeAgeField:roomDataInGlobal];
                                    [self removeAgeField:roomInitialSync];

                                    // Do the comparison
                                    XCTAssertEqualObjects(roomDataInGlobal, roomInitialSync);

                                    //[expectation fulfill];

                                    [bobRestClient messagesForRoom:roomId from:roomDataInGlobal.messages.start to:nil limit:1 success:^(MXPaginationResponse *paginatedResponse) {

                                        //NSLog(@"%@", JSONData[@"messages"][@"chunk"]);
                                        NSLog(@"%@", roomDataInGlobal.messages.chunk);
                                        NSLog(@"-------");
                                        NSLog(@"%@", paginatedResponse.chunk);

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
                            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                        }];
                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];
                }failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];
    }];
}


- (void)testMXRoomMemberEventContent
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient membersOfRoom:roomId success:^(NSArray *roomMemberEvents) {
            for (MXEvent *roomMemberEvent in roomMemberEvents)
            {
                MXRoomMemberEventContent *roomMemberEventContent = [MXRoomMemberEventContent modelFromJSON:roomMemberEvent.content];
                if ([roomMemberEvent.sender isEqualToString:aliceRestClient.credentials.userId])
                {
                    XCTAssert([roomMemberEventContent.displayname isEqualToString:kMXTestsAliceDisplayName], @"displayname is wrong: %@", roomMemberEventContent.displayname);
                    XCTAssert([roomMemberEventContent.avatarUrl isEqualToString:kMXTestsAliceAvatarURL], @"member.avatarUrl is wrong: %@", roomMemberEventContent.avatarUrl);
                }
            }

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark - #pragma mark - Room tags operations
- (void)testAddAndRemoveTag
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        // Add a new tag
        [bobRestClient addTag:@"aTag" withOrder:nil toRoom:roomId success:^{

            // Check it
            [bobRestClient tagsOfRoom:roomId success:^(NSArray<MXRoomTag *> *tags) {

                XCTAssertEqual(tags.count, 1);
                XCTAssertEqualObjects(tags[0].name, @"aTag");
                XCTAssertEqual(tags[0].order, nil);

                // Remove it
                [bobRestClient removeTag:@"aTag" fromRoom:roomId success:^{

                    // Check the deletion
                    [bobRestClient tagsOfRoom:roomId success:^(NSArray<MXRoomTag *> *tags) {

                        XCTAssertEqual(tags.count, 0);
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


#pragma mark - Profile operations
- (void)testUserDisplayName
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {
        
        __block MXRestClient *aliceRestClient2 = aliceRestClient;
        
        // Set the name
        __block NSString *newDisplayName = @"mxAlice2";
        [aliceRestClient setDisplayName:newDisplayName success:^{
            
            // Then retrieve it
            [aliceRestClient2 displayNameForUser:nil success:^(NSString *displayname) {
                
                XCTAssertTrue([displayname isEqualToString:newDisplayName], @"Must retrieved the set string: %@ - %@", displayname, newDisplayName);
                [expectation fulfill];
                
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

- (void)testOtherUserDisplayName
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {
        
        // Set the name
        __block NSString *newDisplayName = @"mxAlice2";
        [aliceRestClient setDisplayName:newDisplayName success:^{
            
            [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:nil readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation2) {
                
                MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
                
                // Then retrieve it from a Bob restClient
                [bobRestClient displayNameForUser:sharedData.aliceCredentials.userId success:^(NSString *displayname) {
                    
                    XCTAssertTrue([displayname isEqualToString:newDisplayName], @"Must retrieved the set string: %@ - %@", displayname, newDisplayName);
                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testUserNilDisplayName
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        [bobRestClient displayNameForUser:nil success:^(NSString *displayname) {

            XCTAssertNil(displayname, @"mxBob has no displayname defined");
            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}


- (void)testUserAvatarUrl
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {
        
        __block MXRestClient *aliceRestClient2 = aliceRestClient;
        
        // Set the avatar url
        __block NSString *newAvatarUrl = @"http://matrix.org/matrix2.png";
        [aliceRestClient setAvatarUrl:newAvatarUrl success:^{
              
            // Then retrieve it
            [aliceRestClient2 avatarUrlForUser:nil success:^(NSString *avatarUrl) {
                
                XCTAssertTrue([avatarUrl isEqualToString:newAvatarUrl], @"Must retrieved the set string: %@ - %@", avatarUrl, newAvatarUrl);
                [expectation fulfill];
                
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

- (void)testOtherUserAvatarUrl
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {
        
        // Set the avatar url
        __block NSString *newAvatarUrl = @"http://matrix.org/matrix2.png";
        [aliceRestClient setAvatarUrl:newAvatarUrl success:^{
            
            [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:nil readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation2) {
                
                MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
                
                // Then retrieve it from a Bob restClient
                [bobRestClient avatarUrlForUser:sharedData.aliceCredentials.userId success:^(NSString *avatarUrl) {
                    
                    XCTAssertTrue([avatarUrl isEqualToString:newAvatarUrl], @"Must retrieved the set string: %@ - %@", avatarUrl, newAvatarUrl);
                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testUserNotNilAvatarUrl
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        [bobRestClient avatarUrlForUser:nil success:^(NSString *avatarUrl) {

            XCTAssert([avatarUrl hasPrefix:@"mxc://"], @"mxBob has no avatar defined. So the home server should have allocated one on the Matrix content repository");
            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}


#pragma mark - Presence operations
- (void)testUserPresence
{
    // Make sure the test is valid once the bug is fixed server side
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {
        
        __block MXRestClient *aliceRestClient2 = aliceRestClient;
        
        // Set new presence
        __block NSString *newStatusMessage = @"Gone for dinner";
        [aliceRestClient setPresence:MXPresenceOnline andStatusMessage:newStatusMessage success:^{
            
            // Then retrieve it
            [aliceRestClient2 presence:nil success:^(MXPresenceResponse *presence) {
                
                XCTAssertNotNil(presence);
                XCTAssert([presence.presence isEqualToString:kMXPresenceOnline]);
                XCTAssertEqual(presence.presenceStatus, MXPresenceOnline);
                XCTAssert([presence.statusMsg isEqualToString:@"Gone for dinner"]);
                
                [expectation fulfill];
                
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


#pragma mark - Event operations
- (void)testEventsFromTokenServerTimeout
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        // Delay the test to filter out Bob presence events the HS can send due to requests made in doMXRestClientTestWithBob
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

            NSDate *refDate = [NSDate date];
            [bobRestClient eventsFromToken:@"END" serverTimeout:1000 clientTimeout:40000 success:^(MXPaginationResponse *paginatedResponse) {

                XCTAssertNotNil(paginatedResponse);

                // Check expected response params
                XCTAssertNotNil(paginatedResponse.start);
                XCTAssertNotNil(paginatedResponse.end);
                XCTAssertNotNil(paginatedResponse.chunk);
                XCTAssertEqual(paginatedResponse.chunk.count, 0, @"Events should not come in this short stream time (1s)");

                if (paginatedResponse.chunk.count) {
                    NSLog(@"####");
                }

                NSDate *now  = [NSDate date];
                XCTAssertLessThanOrEqual([now timeIntervalSinceDate:refDate], 2, @"The HS did not timeout as expected");    // Give 2s for the HS to timeout

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        });
    }];
}

- (void)testEventsFromTokenClientTimeout
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        
        NSDate *refDate = [NSDate date];
        
        [bobRestClient eventsFromToken:@"END" serverTimeout:5000 clientTimeout:1000 success:^(MXPaginationResponse *paginatedResponse) {
            
            XCTFail(@"The request must fail. The client timeout should have fired");
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            
            XCTAssertEqual(error.code, NSURLErrorTimedOut);
            
            NSDate *now  = [NSDate date];
            XCTAssertLessThanOrEqual([now timeIntervalSinceDate:refDate], 2, @"The SDK did not timeout as expected");    // Give 2s for the SDK MXRestClient to timeout

            [expectation fulfill];
        }];
    }];
}


#pragma mark - Content upload
- (void)testUrlOfContent
{
    NSString *mxcURI = @"mxc://matrix.org/rQkrOoaFIRgiACATXUdQIuNJ";

    MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:@"http://matrix.org"
                                        andOnUnrecognizedCertificateBlock:nil];

    NSString *contentURL = [mxRestClient urlOfContent:mxcURI];
    XCTAssertEqualObjects(contentURL, @"http://matrix.org/_matrix/media/v1/download/matrix.org/rQkrOoaFIRgiACATXUdQIuNJ");
}

- (void)testUrlOfContentThumbnail
{
    NSString *mxcURI = @"mxc://matrix.org/rQkrOoaFIRgiACATXUdQIuNJ";

    MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:@"http://matrix.org"
                                        andOnUnrecognizedCertificateBlock:nil];
    
    CGFloat scale = [[UIScreen mainScreen] scale];
    CGSize viewSize = CGSizeMake(320, 320);

    NSString *thumbnailURL = [mxRestClient urlOfContentThumbnail:mxcURI toFitViewSize:viewSize withMethod:MXThumbnailingMethodScale];
    NSString *expected = [NSString stringWithFormat:@"http://matrix.org/_matrix/media/v1/thumbnail/matrix.org/rQkrOoaFIRgiACATXUdQIuNJ?width=%tu&height=%tu&method=scale", (NSUInteger)(viewSize.width * scale), (NSUInteger)(viewSize.height * scale)];
    XCTAssertEqualObjects(thumbnailURL, expected);
}


#pragma mark - Push rules
// This test is based on default notification rules of a local home server.
// The test must be updated if those HS default rules change.
- (void)testPushRules
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        [bobRestClient pushRules:^(MXPushRulesResponse *pushRules) {

            XCTAssertNotNil(pushRules.global, @"The demo home server defines some global default rules");

            // Check data sent by the home server has been correcltly modelled
            XCTAssertTrue([pushRules.global isKindOfClass:[MXPushRulesSet class]]);

            XCTAssertNotNil(pushRules.global.content);
            XCTAssertTrue([pushRules.global.content isKindOfClass:[NSArray class]]);

            MXPushRule *pushRule = pushRules.global.content[0];
            XCTAssertTrue([pushRule isKindOfClass:[MXPushRule class]]);

            XCTAssertNotNil(pushRule.actions);

            MXPushRuleAction *pushAction = pushRule.actions[0];
            XCTAssertTrue([pushAction isKindOfClass:[MXPushRuleAction class]]);

            // Test a rule with room_member_count condition. There must be one for 1:1 in underride rules
            MXPushRule *roomMemberCountRule;
            for (MXPushRule *pushRule in pushRules.global.underride)
            {
                if (pushRule.conditions.count)
                {
                    MXPushRuleCondition *condition = pushRule.conditions[0];
                    if (condition.kindType == MXPushRuleConditionTypeRoomMemberCount)
                    {
                        roomMemberCountRule = pushRule;
                        break;
                    }
                }
            }
            XCTAssertNotNil(roomMemberCountRule);

            MXPushRuleCondition *condition = roomMemberCountRule.conditions[0];
            XCTAssertNotNil(condition);
            XCTAssertEqualObjects(condition.kind, kMXPushRuleConditionStringRoomMemberCount);

            XCTAssertEqual(condition.kindType, MXPushRuleConditionTypeRoomMemberCount);

            XCTAssertNotNil(condition.parameters);
            NSNumber *number= condition.parameters[@"is"];
            XCTAssertEqual(number.intValue, 2);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark - Search
- (void)testSearchText
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [bobRestClient searchMessageText:@"Fake message"
                                 inRooms:@[roomId]
                             beforeLimit:0
                              afterLimit:0
                               nextBatch:nil
                                 success:^(MXSearchRoomEventResults *roomEventResults) {

                                     XCTAssertEqual(roomEventResults.count, 5);
                                     XCTAssertEqual(roomEventResults.results.count, 5);

                                     MXSearchResult *result = roomEventResults.results[0];

                                     XCTAssertEqualObjects(roomId, result.result.roomId);

                                     XCTAssertEqual(result.context.eventsBefore.count, 0);
                                     XCTAssertEqual(result.context.eventsAfter.count, 0);

                                     XCTAssertNil(roomEventResults.nextBatch, @"The result contains all matching events");

                                     [expectation fulfill];

                                 } failure:^(NSError *error) {
                                     XCTFail(@"The request should not fail - NSError: %@", error);
                                     [expectation fulfill];
                                 }];
    }];
}

- (void)testSearchUniqueTextAcrossRooms
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        NSString *message = [[NSProcessInfo processInfo] globallyUniqueString];
        __block NSString *messageEventId;

        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXEventDirection direction, id customObject) {

            [mxSession.matrixRestClient searchMessageText:message
                                                  inRooms:nil
                                              beforeLimit:3
                                               afterLimit:1
                                                nextBatch:nil
                                                  success:^(MXSearchRoomEventResults *roomEventResults) {

                                                      XCTAssertEqual(roomEventResults.count, 1);
                                                      XCTAssertEqual(roomEventResults.results.count, 1);

                                                      MXSearchResult *result = roomEventResults.results[0];

                                                      XCTAssertEqualObjects(messageEventId, result.result.eventId);

                                                      XCTAssertEqual(result.context.eventsBefore.count, 3);
                                                      XCTAssertEqual(result.context.eventsAfter.count, 0, @"This is the last message of the room. So there must be no message after");

                                                      XCTAssertNil(roomEventResults.nextBatch, @"The result contains all matching events");

                                                      [expectation fulfill];
                                                      
                                                  } failure:^(NSError *error) {
                                                      XCTFail(@"The request should not fail - NSError: %@", error);
                                                      [expectation fulfill];
                                                  }];
        }];

        [room sendTextMessage:message success:^(NSString *eventId) {
            messageEventId = eventId;
        } failure:nil];
    }];
}

- (void)testSearchPaginate
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        // Add 50 messages to the room
        [[MatrixSDKTestsData sharedData] for:bobRestClient andRoom:roomId sendMessages:20 success:^{

            [bobRestClient searchMessageText:@"Fake message"
                                     inRooms:@[roomId]
                                 beforeLimit:0
                                  afterLimit:0
                                   nextBatch:nil
                                     success:^(MXSearchRoomEventResults *roomEventResults) {

                                         XCTAssertEqual(roomEventResults.count, 20);
                                         XCTAssertEqual(roomEventResults.results.count, 10);    // With the assumption that HS returns 10-events batches

                                         MXSearchResult *topMostRecentResult = roomEventResults.results[0];

                                         XCTAssertNotNil(roomEventResults.nextBatch);

                                         // Paginate the search
                                         [bobRestClient searchMessageText:@"Fake message"
                                                                  inRooms:@[roomId]
                                                              beforeLimit:0
                                                               afterLimit:0
                                                                nextBatch:roomEventResults.nextBatch
                                                                  success:^(MXSearchRoomEventResults *roomEventResults) {

                                                                      XCTAssertEqual(roomEventResults.count, 20);
                                                                      XCTAssertEqual(roomEventResults.results.count, 10);    // With the assumption that HS returns 10-events batches

                                                                      MXSearchResult *top2ndBatchResult = roomEventResults.results[0];

                                                                      XCTAssertLessThan(top2ndBatchResult.result.originServerTs, topMostRecentResult.result.originServerTs);

                                                                      // Paginate the search
                                                                      [bobRestClient searchMessageText:@"Fake message"
                                                                                               inRooms:@[roomId]
                                                                                           beforeLimit:0
                                                                                            afterLimit:0
                                                                                             nextBatch:roomEventResults.nextBatch
                                                                                               success:^(MXSearchRoomEventResults *roomEventResults) {

                                                                                                   XCTAssertEqual(roomEventResults.count, 20);
                                                                                                   XCTAssertEqual(roomEventResults.results.count, 0, @"We must have reach the end");

                                                                                                   XCTAssertNil(roomEventResults.nextBatch);
                                                                                                   
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
    }];
}

@end

#pragma clang diagnostic pop

