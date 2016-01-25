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
#import "MXTools.h"


// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

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
        [[MatrixSDKTestsData sharedData] closeMXSession:mxSession];
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
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        [bobRestClient setRoomTopic:roomId topic:@"My topic" success:^{
            
            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [mxSession start:^{
                
                MXRoom *room = [mxSession roomWithRoomId:roomId];
                
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
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            XCTAssertNil(room.state.topic, @"There must be no room topic yet. Found: %@", room.state.topic);
            
            // Listen to live event. We should receive only one: a m.room.topic event
            [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                
                XCTAssertEqual(event.eventType, MXEventTypeRoomTopic);
                
                XCTAssertNotNil(room.state.topic);
                XCTAssert([room.state.topic isEqualToString:@"My topic"], @"The room topic shoud be \"My topic\". Found: %@", room.state.topic);
                
                [expectation fulfill];
                
            }];
        
            // Change the topic
            [bobRestClient2 setRoomTopic:roomId topic:@"My topic" success:^{
                
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


- (void)testRoomAvatarProvidedByInitialSync
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomAvatar:roomId avatar:@"http://matrix.org/matrix.png" success:^{

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                XCTAssertNotNil(room.state.avatar);
                XCTAssertEqualObjects(room.state.avatar, @"http://matrix.org/matrix.png");

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

- (void)testRoomAvatarLive
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            XCTAssertNil(room.state.avatar, @"There must be no room avatar yet. Found: %@", room.state.avatar);

            // Listen to live event. We should receive only one: a m.room.avatar event
            [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(event.eventType, MXEventTypeRoomAvatar);

                XCTAssertNotNil(room.state.avatar);
                XCTAssertEqualObjects(room.state.avatar, @"http://matrix.org/matrix.png");

                [expectation fulfill];

            }];

            // Change the avatar
            [bobRestClient2 setRoomAvatar:roomId avatar:@"http://matrix.org/matrix.png" success:^{

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
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        [bobRestClient setRoomName:roomId name:@"My room name" success:^{
            
            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [mxSession start:^{
                
                MXRoom *room = [mxSession roomWithRoomId:roomId];
                
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
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            XCTAssertNil(room.state.name, @"There must be no room name yet. Found: %@", room.state.name);
            
            // Listen to live event. We should receive only one: a m.room.name event
            [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                
                XCTAssertEqual(event.eventType, MXEventTypeRoomName);
                
                XCTAssertNotNil(room.state.name);
                XCTAssert([room.state.name isEqualToString:@"My room name"], @"The room topic shoud be \"My room name\". Found: %@", room.state.name);
                
                [expectation fulfill];
                
            }];
            
            // Change the topic
            [bobRestClient2 setRoomName:roomId name:@"My room name" success:^{
                
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
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
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
 3 - Bob set the room name to "Invite test"
 4 - Bob set the room topic to "We test room invitation here"
 5 - Bob invites Alice
 6 - Bob: "I wait for Alice"
 */
- (void)createInviteByUserScenario:(MXRestClient*)bobRestClient inRoom:(NSString*)roomId inviteAlice:(BOOL)inviteAlice onComplete:(void(^)())onComplete
{
    [bobRestClient sendTextMessageToRoom:roomId text:@"Hello world" success:^(NSString *eventId) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomName:roomId name:@"Invite test" success:^{

            [bobRestClient setRoomTopic:roomId topic:@"We test room invitation here" success:^{

                MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];

                [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

                    if (inviteAlice)
                    {
                        [bobRestClient2 inviteUser:sharedData.aliceCredentials.userId toRoom:roomId success:^{

                            [bobRestClient2 sendTextMessageToRoom:roomId text:@"I wait for Alice" success:^(NSString *eventId) {

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
        
    } failure:^(NSError *error) {
        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
    }];
}

- (void)testInviteByOtherInInitialSync
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:YES onComplete:^{
            
            [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                
                [mxSession start:^{
                    
                    MXRoom *newRoom = [mxSession roomWithRoomId:roomId];
                    
                    XCTAssertNotNil(newRoom);
                    
                    XCTAssertEqual(newRoom.state.membership, MXMembershipInvite);

                    XCTAssertEqualObjects(newRoom.state.name, @"Invite test");
                    
                    // The room must have only one member: Alice who has been invited by Bob.
                    // While Alice does not join the room, we cannot get more information
                    XCTAssertEqual(newRoom.state.members.count, 1);
                    
                    MXRoomMember *alice = [newRoom.state memberWithUserId:aliceRestClient.credentials.userId];
                    XCTAssertNotNil(alice);
                    XCTAssertEqual(alice.membership, MXMembershipInvite);
                    XCTAssert([alice.originUserId isEqualToString:bobRestClient.credentials.userId], @"Wrong inviter: %@", alice.originUserId);
                    
                    // The last message should be an invite m.room.member
                    MXEvent *lastMessage = [newRoom lastMessageWithTypeIn:nil];
                    XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMember, @"The last message should be an invite m.room.member");
                    XCTAssertLessThan([[NSDate date] timeIntervalSince1970] * 1000 - lastMessage.originServerTs, 3000);
                    
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
    
    [sharedData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            
            [mxSession start:^{
                
                __block MXRoom *newRoom;
                
                [mxSession listenToEvents:^(MXEvent *event, MXEventDirection direction, id customObject) {
                    
                    if ([event.roomId isEqualToString:roomId])
                    {
                        newRoom = [mxSession roomWithRoomId:roomId];
                        
                        XCTAssertNotNil(newRoom);
                        
                        XCTAssertEqual(newRoom.state.membership, MXMembershipInvite);

                        XCTAssertEqualObjects(newRoom.state.name, @"Invite test");
                        
                        // The room must have only one member: Alice who has been invited by Bob.
                        // While Alice does not join the room, we cannot get more information
                        XCTAssertEqual(newRoom.state.members.count, 1);
                        
                        MXRoomMember *alice = [newRoom.state memberWithUserId:aliceRestClient.credentials.userId];
                        XCTAssertNotNil(alice);
                        XCTAssertEqual(alice.membership, MXMembershipInvite);
                        XCTAssert([alice.originUserId isEqualToString:bobRestClient.credentials.userId], @"Wrong inviter: %@", alice.originUserId);

                        // The last message should be an invite m.room.member
                        MXEvent *lastMessage = [newRoom lastMessageWithTypeIn:nil];
                        XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMember, @"The last message should be an invite m.room.member");
                        XCTAssertLessThan([[NSDate date] timeIntervalSince1970] * 1000 - lastMessage.originServerTs, 3000);
                    }
                    
                }];
                
                [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:YES onComplete:^{
                    
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
    
    [sharedData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:YES onComplete:^{
            
            [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                
                [mxSession start:^{
                    
                    MXRoom *newRoom = [mxSession roomWithRoomId:roomId];
                    
                    [newRoom listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                        if (MXEventDirectionForwards == event)
                        {
                            // We should receive only join events in live
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMember);

                            MXRoomMemberEventContent *roomMemberEventContent = [MXRoomMemberEventContent modelFromJSON:event.content];
                            XCTAssert([roomMemberEventContent.membership isEqualToString:kMXMembershipStringJoin]);
                        }
                    }];
                    
                    [mxSession listenToEvents:^(MXEvent *event, MXEventDirection direction, id customObject) {
                        // Except presence, we should receive only join events in live
                        if (MXEventDirectionForwards == event && MXEventTypePresence != event.eventType)
                        {
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMember);
                            
                            MXRoomMemberEventContent *roomMemberEventContent = [MXRoomMemberEventContent modelFromJSON:event.content];
                            XCTAssert([roomMemberEventContent.membership isEqualToString:kMXMembershipStringJoin]);                      
                        }
                    }];
                    
                    [newRoom join:^{
                        
                        // Now, we must have more information about the room
                        // Check its new state
                        XCTAssertEqual(newRoom.state.members.count, 2);
                        XCTAssert([newRoom.state.topic isEqualToString:@"We test room invitation here"], @"Wrong topic. Found: %@", newRoom.state.topic);
                        
                        XCTAssertEqual(newRoom.state.membership, MXMembershipJoin);
                        
                        XCTAssertEqual([newRoom lastMessageWithTypeIn:nil].eventType, MXEventTypeRoomMember, @"The last should be a m.room.member event indicating Alice joining the room");
                        
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
    
    [sharedData doMXRestClientTestWithBobAndAPublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:NO onComplete:^{
            
            [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                
                [mxSession start:^{
                    
                    MXRoom *room = [mxSession roomWithRoomId:roomId];
                    
                    XCTAssertNil(room, @"The room must not be known yet by the user");
                    
                    [mxSession joinRoom:roomId success:^(MXRoom *room) {
                        
                        XCTAssert([room.state.roomId isEqualToString:roomId]);
                        
                        MXRoom *newRoom = [mxSession roomWithRoomId:roomId];
                        XCTAssert(newRoom, @"The room must be known now by the user");
                        
                        // Now, we must have more information about the room
                        // Check its new state
                        XCTAssertEqual(newRoom.state.isPublic, YES);
                        XCTAssertEqual(newRoom.state.members.count, 2);
                        XCTAssert([newRoom.state.topic isEqualToString:@"We test room invitation here"], @"Wrong topic. Found: %@", newRoom.state.topic);
                        
                        XCTAssertEqual(newRoom.state.membership, MXMembershipJoin);
                        
                        XCTAssertEqual([newRoom lastMessageWithTypeIn:nil].eventType, MXEventTypeRoomMember, @"The last should be a m.room.member event indicating Alice joining the room");
                        
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

- (void)testPowerLevels
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            MXRoomPowerLevels *roomPowerLevels = room.state.powerLevels;

            XCTAssertNotNil(roomPowerLevels);

            // Check the user power level
            XCTAssertNotNil(roomPowerLevels.users);
            XCTAssertEqual(roomPowerLevels.users.count, 1);
            XCTAssertEqualObjects(roomPowerLevels.users[bobRestClient.credentials.userId], [NSNumber numberWithUnsignedInteger: 100], @"By default power level of room creator is 100");

            NSUInteger powerlLevel = [roomPowerLevels powerLevelOfUserWithUserID:bobRestClient.credentials.userId];
            XCTAssertEqual(powerlLevel, 100, @"By default power level of room creator is 100");

            powerlLevel = [roomPowerLevels powerLevelOfUserWithUserID:@"randomUserId"];
            XCTAssertEqual(powerlLevel, roomPowerLevels.usersDefault, @"Power level of user with no attributed power level must default to usersDefault");

            // Check minimum power level for actions
            // Hope the HS will not change these values
            XCTAssertEqual(roomPowerLevels.ban, 50);
            XCTAssertEqual(roomPowerLevels.kick, 50);
            XCTAssertEqual(roomPowerLevels.redact, 50);

            // Check power level to send events
            XCTAssertNotNil(roomPowerLevels.events);
            XCTAssertGreaterThan(roomPowerLevels.events.allKeys.count, 0);

            NSUInteger minimumPowerLevelForEvent;
            for (MXEventTypeString eventTypeString in roomPowerLevels.events.allKeys)
            {
                minimumPowerLevelForEvent = [roomPowerLevels minimumPowerLevelForSendingEventAsStateEvent:eventTypeString];

                XCTAssertEqualObjects(roomPowerLevels.events[eventTypeString], [NSNumber numberWithUnsignedInteger:minimumPowerLevelForEvent]);
            }

            minimumPowerLevelForEvent = [roomPowerLevels minimumPowerLevelForSendingEventAsMessage:kMXEventTypeStringRoomMessage];
            XCTAssertEqual(minimumPowerLevelForEvent, roomPowerLevels.eventsDefault);


            minimumPowerLevelForEvent = [roomPowerLevels minimumPowerLevelForSendingEventAsStateEvent:kMXEventTypeStringRoomTopic];
            XCTAssertEqual(minimumPowerLevelForEvent, roomPowerLevels.stateDefault);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

// Test for https://matrix.org/jira/browse/SYIOS-105
- (void)testRoomStateWhenARoomHasBeenJoinedOnAnotherMatrixClient
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [mxSession start:^{

            __block NSString *newRoomId;
            NSMutableArray *receivedMessages = [NSMutableArray array];
            [mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXEventDirection direction, id customObject) {

                if (MXEventDirectionForwards == direction && [event.roomId isEqualToString:newRoomId])
                {
                    [receivedMessages addObject:event];
                }

                // We expect receiving 2 text messages
                if (2 <= receivedMessages.count)
                {
                    MXRoom *room = [mxSession roomWithRoomId:event.roomId];

                    XCTAssert(room);
                    XCTAssertEqual(room.state.members.count, 2, @"If this count is wrong, the room state is invalid");

                    [expectation fulfill];
                }
            }];

            // Create a conversation on another MXRestClient. For the current `mxSession`, this other MXRestClient behaves like another device.
            [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndAliceInARoom:nil readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

                newRoomId = roomId;

                [bobRestClient sendTextMessageToRoom:roomId text:@"Hi Alice!" success:^(NSString *eventId) {

                    [bobRestClient sendTextMessageToRoom:roomId text:@"Hi Alice 2!" success:^(NSString *eventId) {

                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

// Test for https://matrix.org/jira/browse/SYIOS-105 using notifications
- (void)testRoomStateWhenARoomHasBeenJoinedOnAnotherMatrixClientAndNotifications {
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [mxSession start:^{

            __block NSString *newRoomId;

            // Check MXSessionNewRoomNotification reception
            __block __weak id newRoomObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                newRoomId = note.userInfo[kMXSessionNotificationRoomIdKey];

                MXRoom *room = [mxSession roomWithRoomId:newRoomId];
                XCTAssertNotNil(room);
                
                BOOL isSync = (room.state.membership != MXMembershipInvite && room.state.membership != MXMembershipUnknown);
                XCTAssertFalse(isSync, @"The room is not yet sync'ed");

                [[NSNotificationCenter defaultCenter] removeObserver:newRoomObserver];
            }];

            // Check kMXRoomInitialSyncNotification that must be then received
            __block __weak id initialSyncObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                XCTAssertNotNil(note.object);

                MXRoom *room = note.object;

                XCTAssertEqualObjects(newRoomId, room.state.roomId);
                
                BOOL isSync = (room.state.membership != MXMembershipInvite && room.state.membership != MXMembershipUnknown);
                XCTAssert(isSync, @"The room must be sync'ed now");

                [[NSNotificationCenter defaultCenter] removeObserver:initialSyncObserver];
                [expectation fulfill];
            }];

            // Create a conversation on another MXRestClient. For the current `mxSession`, this other MXRestClient behaves like another device.
            [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndAliceInARoom:nil readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

#pragma clang diagnostic pop

@end
