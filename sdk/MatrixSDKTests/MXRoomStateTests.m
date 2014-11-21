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

@interface MXRoomStateTests : XCTestCase
{
    MXSession *mxSession;
}
@end

@implementation MXRoomStateTests

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

- (void)testIsPublic
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        mxSession = mxSession2;

        XCTAssertTrue(room.state.isPublic, @"The room must be public");
        
        [expectation fulfill];
    }];
}

- (void)testIsPublicForAPrivateRoom
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        XCTAssertFalse(room.state.isPublic, @"This room must be private");
        
        [expectation fulfill];
    }];
}

- (void)testRoomTopicProvidedByInitialSync
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        [bobRestClient setRoomTopic:room_id topic:@"My topic" success:^{
            
            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [mxSession start:^{
                
                MXRoom *room = [mxSession room:room_id];
                
                XCTAssertNotNil(room.state.topic);
                XCTAssert([room.state.topic isEqualToString:@"My topic"], @"The room topic shoud be \"My topic\". Found: %@", room.state.topic);
                
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

- (void)testRoomTopicLive
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{
            
            MXRoom *room = [mxSession room:room_id];
            
            XCTAssertNil(room.state.topic, @"There must be no room topic yet. Found: %@", room.state.topic);
            
            // Listen to live event. We should receive only one: a m.room.topic event
            [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                
                XCTAssertEqual(event.eventType, MXEventTypeRoomTopic);
                
                XCTAssertNotNil(room.state.topic);
                XCTAssert([room.state.topic isEqualToString:@"My topic"], @"The room topic shoud be \"My topic\". Found: %@", room.state.topic);
                
                [expectation fulfill];
                
            }];
        
            // Change the topic
            [bobRestClient2 setRoomTopic:room_id topic:@"My topic" success:^{
                
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


- (void)testRoomNameProvidedByInitialSync
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        [bobRestClient setRoomName:room_id name:@"My room name" success:^{
            
            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [mxSession start:^{
                
                MXRoom *room = [mxSession room:room_id];
                
                XCTAssertNotNil(room.state.name);
                XCTAssert([room.state.name isEqualToString:@"My room name"], @"The room name shoud be \"My room name\". Found: %@", room.state.name);
                
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

- (void)testRoomNameLive
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{
            
            MXRoom *room = [mxSession room:room_id];
            
            XCTAssertNil(room.state.name, @"There must be no room name yet. Found: %@", room.state.name);
            
            // Listen to live event. We should receive only one: a m.room.name event
            [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                
                XCTAssertEqual(event.eventType, MXEventTypeRoomName);
                
                XCTAssertNotNil(room.state.name);
                XCTAssert([room.state.name isEqualToString:@"My room name"], @"The room topic shoud be \"My room name\". Found: %@", room.state.name);
                
                [expectation fulfill];
                
            }];
            
            // Change the topic
            [bobRestClient2 setRoomName:room_id name:@"My room name" success:^{
                
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
            
            XCTAssertNotNil([room.state memberWithUserId:bobRestClient.credentials.userId], @"Bob must be retrieved");
            
            XCTAssertNil([room.state memberWithUserId:@"NonExistingUserId"], @"getMember must return nil if the user does not exist");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMemberName
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
        
        NSString *bobUserId = sharedData.bobCredentials.userId;
        NSString *bobMemberName = [room.state  memberName:bobUserId];
        
        XCTAssertNotNil(bobMemberName);
        XCTAssertFalse([bobMemberName isEqualToString:@""], @"bobMemberName must not be an empty string");
        
        XCTAssert([[room.state memberName:@"NonExistingUserId"] isEqualToString:@"NonExistingUserId"], @"memberName must return his id if the user does not exist");
        
        [expectation fulfill];
    }];
}

- (void)testStateEvents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        XCTAssertNotNil(room.state.stateEvents);
        XCTAssertGreaterThan(room.state.stateEvents.count, 0);
        
        [expectation fulfill];
    }];
}

- (void)testAliases
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        XCTAssertNotNil(room.state.displayname);
        XCTAssertTrue([room.state.displayname hasPrefix:@"MX Public Room test (#mxPublic:"], @"We must retrieve the #mxPublic room settings");
        
        [expectation fulfill];
    }];
}

// Test the room display name formatting: "userID" (self chat)
- (void)testDisplayName2
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        // Test room the display formatting: "roomName (roomAlias)"
        XCTAssertNotNil(room.state.displayname);
        XCTAssertTrue([room.state.displayname isEqualToString:mxSession.matrixRestClient.credentials.userId], @"The room name must be Bob's userID as he has no displayname: %@ - %@", room.state.displayname, mxSession.matrixRestClient.credentials.userId);
        
        [expectation fulfill];
    }];
}


/*
 Creates a room with the following historic.
 This scenario tests the "invite by other" behavior.
 
 0 - Bob creates a private room
 1 - ... (random events generated by the home server)
 2 - Bob: "Hello World"
 3 - Bob set the room topic to "We test room invitation here"
 4 - Bob invites Alice
 5 - Bob: "I wait for Alice"
 */
- (void)createInviteByUserScenario:(MXRestClient*)bobRestClient inRoom:(NSString*)room_id inviteAlice:(BOOL)inviteAlice onComplete:(void(^)())onComplete
{
    [bobRestClient postTextMessageToRoom:room_id text:@"Hello world" success:^(NSString *event_id) {
        
        [bobRestClient setRoomTopic:room_id topic:@"We test room invitation here" success:^{
            
            MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
            
            [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                if (inviteAlice)
                {
                    [bobRestClient inviteUser:sharedData.aliceCredentials.userId toRoom:room_id success:^{
                        
                        [bobRestClient postTextMessageToRoom:room_id text:@"I wait for Alice" success:^(NSString *event_id) {
                            
                            onComplete();
                            
                        } failure:^(NSError *error) {
                            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                        }];
                        
                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];
                }
                else
                {
                    onComplete();
                }
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
        
    } failure:^(NSError *error) {
        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
    }];
}

- (void)testInviteByOtherInInitialSync
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:room_id inviteAlice:YES onComplete:^{
            
            [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                
                [mxSession start:^{
                    
                    MXRoom *newRoom = [mxSession room:room_id];
                    
                    XCTAssertNotNil(newRoom);
                    
                    XCTAssertEqual(newRoom.state.membership, MXMembershipInvite);
                    
                    // The room must have only one member: Alice who has been invited by Bob.
                    // While Alice does not join the room, we cannot get more information
                    XCTAssertEqual(newRoom.state.members.count, 1);
                    
                    MXRoomMember *alice = [newRoom.state memberWithUserId:aliceRestClient.credentials.userId];
                    XCTAssertNotNil(alice);
                    XCTAssertEqual(alice.membership, MXMembershipInvite);
                    XCTAssert([alice.originUserId isEqualToString:bobRestClient.credentials.userId], @"Wrong inviter: %@", alice.originUserId);
                    
                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }];
            
        }];
        
    }];
}

- (void)testInviteByOtherInLive
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            
            [mxSession start:^{
                
                __block MXRoom *newRoom;
                
                [mxSession listenToEvents:^(MXEvent *event, MXEventDirection direction, id customObject) {
                    
                    if ([event.roomId isEqualToString:room_id])
                    {
                        newRoom = [mxSession room:room_id];
                        
                        XCTAssertNotNil(newRoom);
                        
                        XCTAssertEqual(newRoom.state.membership, MXMembershipInvite);
                        
                        // The room must have only one member: Alice who has been invited by Bob.
                        // While Alice does not join the room, we cannot get more information
                        XCTAssertEqual(newRoom.state.members.count, 1);
                        
                        MXRoomMember *alice = [newRoom.state memberWithUserId:aliceRestClient.credentials.userId];
                        XCTAssertNotNil(alice);
                        XCTAssertEqual(alice.membership, MXMembershipInvite);
                        XCTAssert([alice.originUserId isEqualToString:bobRestClient.credentials.userId], @"Wrong inviter: %@", alice.originUserId);
                    }
                    
                }];
                
                [self createInviteByUserScenario:bobRestClient inRoom:room_id inviteAlice:YES onComplete:^{
                    
                    // Make sure we have tested something
                    XCTAssertNotNil(newRoom);
                    [expectation fulfill];
                    
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        }];
        
    }];
}


- (void)testMXRoomJoin
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:room_id inviteAlice:YES onComplete:^{
            
            [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                
                [mxSession start:^{
                    
                    MXRoom *newRoom = [mxSession room:room_id];
                    
                    [newRoom join:^{
                        
                        // Now, we must have more information about the room
                        // Check its new state
                        XCTAssertEqual(newRoom.state.members.count, 2);
                        XCTAssert([newRoom.state.topic isEqualToString:@"We test room invitation here"], @"Wrong topic. Found: %@", newRoom.state.topic);
                        
                        XCTAssertEqual(newRoom.state.membership, MXMembershipJoin);
                        
                        XCTAssertEqual(newRoom.lastMessage.eventType, MXEventTypeRoomMember, @"The last should be a m.room.member event indicating Alice joining the room");
                        
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
            
        }];
        
    }];
}


- (void)testMXSessionJoinOnPublicRoom
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData doMXRestClientTestWithBobAndAPublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:room_id inviteAlice:NO onComplete:^{
            
            [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                
                [mxSession start:^{
                    
                    MXRoom *room = [mxSession room:room_id];
                    
                    XCTAssertNil(room, @"The room must not be known yet by the user");
                    
                    [mxSession joinRoom:room_id success:^(MXRoom *room) {
                        
                        XCTAssert([room.state.room_id isEqualToString:room_id]);
                        
                        MXRoom *newRoom = [mxSession room:room_id];
                        XCTAssert(newRoom, @"The room must be known now by the user");
                        
                        // Now, we must have more information about the room
                        // Check its new state
                        XCTAssertEqual(newRoom.state.isPublic, YES);
                        XCTAssertEqual(newRoom.state.members.count, 2);
                        XCTAssert([newRoom.state.topic isEqualToString:@"We test room invitation here"], @"Wrong topic. Found: %@", newRoom.state.topic);
                        
                        XCTAssertEqual(newRoom.state.membership, MXMembershipJoin);
                        
                        XCTAssertEqual(newRoom.lastMessage.eventType, MXEventTypeRoomMember, @"The last should be a m.room.member event indicating Alice joining the room");
                        
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
            
        }];
        
    }];
}


@end
