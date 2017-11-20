/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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
    MatrixSDKTestsData *matrixSDKTestsData;

    MXSession *mxSession;
}
@end

@implementation MXRoomStateTests

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

- (void)testIsJoinRulePublic
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        mxSession = mxSession2;

        XCTAssertTrue(room.state.isJoinRulePublic, @"The room join rule must be public");
        
        [expectation fulfill];
    }];
}

- (void)testIsJoinRulePublicForAPrivateRoom
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        XCTAssertFalse(room.state.isJoinRulePublic, @"This room join rule must be private");
        
        [expectation fulfill];
    }];
}

- (void)testRoomTopicProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
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
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            XCTAssertNil(room.state.topic, @"There must be no room topic yet. Found: %@", room.state.topic);
            
            // Listen to live event. We should receive only one: a m.room.topic event
            [room.liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                
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
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

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
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            XCTAssertNil(room.state.avatar, @"There must be no room avatar yet. Found: %@", room.state.avatar);

            // Listen to live event. We should receive only one: a m.room.avatar event
            [room.liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

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
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
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
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            XCTAssertNil(room.state.name, @"There must be no room name yet. Found: %@", room.state.name);
            
            // Listen to live event. We should receive only one: a m.room.name event
            [room.liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                
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

- (void)testRoomHistoryVisibilityProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomHistoryVisibility:roomId historyVisibility:kMXRoomHistoryVisibilityWorldReadable success:^{

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                XCTAssertNotNil(room.state.historyVisibility);
                XCTAssertEqualObjects(room.state.historyVisibility, kMXRoomHistoryVisibilityWorldReadable, @"The room history visibility is wrong");

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

- (void)testRoomHistoryVisibilityLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            XCTAssertEqualObjects(room.state.historyVisibility, kMXRoomHistoryVisibilityShared, @"The default room history visibility should be shared");

            // Listen to live event. We should receive only one: a m.room.name event
            [room.liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(event.eventType, MXEventTypeRoomHistoryVisibility);

                XCTAssertNotNil(room.state.historyVisibility);
                XCTAssertEqualObjects(room.state.historyVisibility, kMXRoomHistoryVisibilityInvited, @"The room history visibility is wrong");
;

                [expectation fulfill];

            }];

            // Change the history visibility
            [room setHistoryVisibility:kMXRoomHistoryVisibilityInvited success:^{

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

- (void)testRoomJoinRuleProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomJoinRule:roomId joinRule:kMXRoomJoinRulePublic success:^{

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                XCTAssertNotNil(room.state.joinRule);
                XCTAssertEqualObjects(room.state.joinRule, kMXRoomJoinRulePublic, @"The room join rule is wrong");

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

- (void)testRoomJoinRuleLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            XCTAssertEqualObjects(room.state.joinRule, kMXRoomJoinRuleInvite, @"The default room join rule should be invite");

            // Listen to live event. We should receive only one: a m.room.name event
            [room.liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(event.eventType, MXEventTypeRoomJoinRules);

                XCTAssertNotNil(room.state.joinRule);
                XCTAssertEqualObjects(room.state.joinRule, kMXRoomJoinRulePublic, @"The room join rule is wrong");

                [expectation fulfill];

            }];

            // Change the join rule
            [room setJoinRule:kMXRoomJoinRulePublic success:^{

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

- (void)testRoomGuestAccessProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomGuestAccess:roomId guestAccess:kMXRoomGuestAccessCanJoin success:^{

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                XCTAssertNotNil(room.state.joinRule);
                XCTAssertEqualObjects(room.state.guestAccess, kMXRoomGuestAccessCanJoin, @"The room guest access is wrong");

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

- (void)testRoomGuestAccessLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            XCTAssertEqualObjects(room.state.guestAccess, kMXRoomGuestAccessCanJoin, @"The default room guest access should be forbidden");

            // Listen to live event. We should receive only one: a m.room.name event
            [room.liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(event.eventType, MXEventTypeRoomGuestAccess);

                XCTAssertNotNil(room.state.guestAccess);
                XCTAssertEqualObjects(room.state.guestAccess, kMXRoomGuestAccessForbidden, @"The room guest access is wrong");

                [expectation fulfill];

            }];

            // Change the guest access
            [room setGuestAccess:kMXRoomGuestAccessForbidden success:^{

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

- (void)testRoomCanonicalAliasProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        NSString *globallyUniqueString = [[NSProcessInfo processInfo] globallyUniqueString];
        NSString *roomAlias = [NSString stringWithFormat:@"#%@%@", globallyUniqueString, bobRestClient.homeserverSuffix];
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        // Create first a room alias
        [bobRestClient addRoomAlias:roomId alias:roomAlias success:^{
            
            // Use this alias as the canonical alias
            [bobRestClient2 setRoomCanonicalAlias:roomId canonicalAlias:roomAlias success:^{
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
                [mxSession start:^{
                    
                    MXRoom *room = [mxSession roomWithRoomId:roomId];
                    
                    XCTAssertNotNil(room.state.aliases);
                    XCTAssertEqual(room.state.aliases.count, 1);
                    XCTAssertEqualObjects(room.state.aliases.firstObject, roomAlias, @"The room alias is wrong");
                    
                    XCTAssertNotNil(room.state.canonicalAlias);
                    XCTAssertNotEqual(room.state.canonicalAlias.length, 0);
                    XCTAssertEqualObjects(room.state.canonicalAlias, roomAlias, @"The room canonical alias is wrong");
                    
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

- (void)testRoomCanonicalAliasLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            NSString *globallyUniqueString = [[NSProcessInfo processInfo] globallyUniqueString];
            NSString *roomAlias = [NSString stringWithFormat:@"#%@%@", globallyUniqueString, bobRestClient.homeserverSuffix];
            
            XCTAssertNil(room.state.aliases);
            XCTAssertNil(room.state.canonicalAlias);
            
            // Listen to live event. We should receive only: a m.room.aliases and m.room.canonical_alias events
            [room.liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                
                if(event.eventType == MXEventTypeRoomAliases)
                {
                    XCTAssertNotNil(room.state.aliases);
                    XCTAssertEqual(room.state.aliases.count, 1);
                    XCTAssertEqualObjects(room.state.aliases.firstObject, roomAlias, @"The room alias is wrong");
                }
                else if (event.eventType == MXEventTypeRoomCanonicalAlias)
                {
                    XCTAssertNotNil(room.state.canonicalAlias);
                    XCTAssertNotEqual(room.state.canonicalAlias.length, 0);
                    XCTAssertEqualObjects(room.state.canonicalAlias, roomAlias, @"The room canonical alias is wrong");
                    
                    [expectation fulfill];
                }
                else
                {
                    XCTFail(@"The event type is unexpected - type: %@", event.type);
                }
                
            }];
            
            // Set room alias
            [room addAlias:roomAlias success:^{
                
                [room setCanonicalAlias:roomAlias success:^{
                    
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

- (void)testMembers
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
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
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        NSString *bobUserId = matrixSDKTestsData.bobCredentials.userId;
        NSString *bobMemberName = [room.state  memberName:bobUserId];
        
        XCTAssertNotNil(bobMemberName);
        XCTAssertFalse([bobMemberName isEqualToString:@""], @"bobMemberName must not be an empty string");
        
        XCTAssert([[room.state memberName:@"NonExistingUserId"] isEqualToString:@"NonExistingUserId"], @"memberName must return his id if the user does not exist");
        
        [expectation fulfill];
    }];
}

- (void)testStateEvents
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        XCTAssertNotNil(room.state.stateEvents);
        XCTAssertGreaterThan(room.state.stateEvents.count, 0);
        
        [expectation fulfill];
    }];
}

- (void)testAliases
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        XCTAssertNotNil(room.state.aliases);
        XCTAssertGreaterThanOrEqual(room.state.aliases.count, 1);
        
        NSString *alias = room.state.aliases[0];
        
        XCTAssertTrue([alias hasPrefix:@"#mxPublic"]);
        
        [expectation fulfill];
    }];
}

// Test the room display name formatting: "roomName (roomAlias)"
- (void)testDisplayName1
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        XCTAssertNotNil(room.state.displayname);
        XCTAssertTrue([room.state.displayname hasPrefix:@"MX Public Room test (#mxPublic"], @"We must retrieve the #mxPublic room settings");
        
        [expectation fulfill];
    }];
}

// Test the room display name formatting: "userID" (self chat)
- (void)testDisplayName2
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
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
- (void)createInviteByUserScenario:(MXRestClient*)bobRestClient inRoom:(NSString*)roomId inviteAlice:(BOOL)inviteAlice expectation:(XCTestExpectation*)expectation onComplete:(void(^)(void))onComplete
{
    [bobRestClient sendTextMessageToRoom:roomId text:@"Hello world" success:^(NSString *eventId) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomName:roomId name:@"Invite test" success:^{

            [bobRestClient setRoomTopic:roomId topic:@"We test room invitation here" success:^{

                [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

                    if (inviteAlice)
                    {
                        [bobRestClient2 inviteUser:matrixSDKTestsData.aliceCredentials.userId toRoom:roomId success:^{

                            [bobRestClient2 sendTextMessageToRoom:roomId text:@"I wait for Alice" success:^(NSString *eventId) {

                                onComplete();

                            } failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];

                        } failure:^(NSError *error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];
                    }
                    else
                    {
                        onComplete();
                    }
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
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
}

- (void)testInviteByOtherInInitialSync
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:YES expectation:expectation onComplete:^{
            
            [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                
                [mxSession start:^{
                    
                    MXRoom *newRoom = [mxSession roomWithRoomId:roomId];
                    
                    XCTAssertNotNil(newRoom);
                    
                    XCTAssertEqual(newRoom.state.membership, MXMembershipInvite);
                    
                    // The room must have only one member: Alice who has been invited by Bob.
                    // While Alice does not join the room, we cannot get more information
                    XCTAssertEqual(newRoom.state.members.count, 1);
                    
                    MXRoomMember *alice = [newRoom.state memberWithUserId:aliceRestClient.credentials.userId];
                    XCTAssertNotNil(alice);
                    XCTAssertEqual(alice.membership, MXMembershipInvite);
                    XCTAssert([alice.originUserId isEqualToString:bobRestClient.credentials.userId], @"Wrong inviter: %@", alice.originUserId);
                    
                    // The last message should be an invite m.room.member
                    MXEvent *lastMessage = newRoom.summary.lastMessageEvent;
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
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            
            [mxSession start:^{
                
                __block MXRoom *newRoom;
                
                [mxSession listenToEvents:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                    
                    if ([event.roomId isEqualToString:roomId])
                    {
                        newRoom = [mxSession roomWithRoomId:roomId];
                        
                        XCTAssertNotNil(newRoom);

                        if (newRoom.state.membership != MXMembershipUnknown)
                        {
                            XCTAssertEqual(newRoom.state.membership, MXMembershipInvite);

                             // The room must have only one member: Alice who has been invited by Bob.
                            // While Alice does not join the room, we cannot get more information
                            XCTAssertEqual(newRoom.state.members.count, 1);

                            MXRoomMember *alice = [newRoom.state memberWithUserId:aliceRestClient.credentials.userId];
                            XCTAssertNotNil(alice);
                            XCTAssertEqual(alice.membership, MXMembershipInvite);
                            XCTAssert([alice.originUserId isEqualToString:bobRestClient.credentials.userId], @"Wrong inviter: %@", alice.originUserId);

                            // The last message should be an invite m.room.member
                            dispatch_async(dispatch_get_main_queue(), ^{    // We could also wait for kMXRoomSummaryDidChangeNotification

                                MXEvent *lastMessage = newRoom.summary.lastMessageEvent;
                                XCTAssertNotNil(lastMessage);
                                XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMember, @"The last message should be an invite m.room.member");
                                XCTAssertLessThan([[NSDate date] timeIntervalSince1970] * 1000 - lastMessage.originServerTs, 3000);

                            });
                        }
                    }
                    
                }];
                
                [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:YES expectation:expectation onComplete:^{
                    
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
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:YES expectation:expectation onComplete:^{
            
            [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                
                [mxSession start:^{
                    
                    MXRoom *newRoom = [mxSession roomWithRoomId:roomId];
                    
                    [newRoom.liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                        if (MXTimelineDirectionForwards == event)
                        {
                            // We should receive only join events in live
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMember);

                            MXRoomMemberEventContent *roomMemberEventContent = [MXRoomMemberEventContent modelFromJSON:event.content];
                            XCTAssert([roomMemberEventContent.membership isEqualToString:kMXMembershipStringJoin]);
                        }
                    }];
                    
                    [mxSession listenToEvents:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                        // Except presence, we should receive only join events in live
                        if (MXTimelineDirectionForwards == event && MXEventTypePresence != event.eventType)
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

                        XCTAssertNotNil(newRoom.summary.lastMessageEventId);
                        XCTAssertNotNil(newRoom.summary.lastMessageEvent);
                        
                        XCTAssertEqual(newRoom.summary.lastMessageEvent.eventType, MXEventTypeRoomMember, @"The last should be a m.room.member event indicating Alice joining the room");
                        
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
    [matrixSDKTestsData doMXRestClientTestWithBobAndAPublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:NO expectation:expectation onComplete:^{
            
            [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
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
                        XCTAssertEqual(newRoom.state.isJoinRulePublic, YES);
                        XCTAssertEqual(newRoom.state.members.count, 2);
                        XCTAssert([newRoom.state.topic isEqualToString:@"We test room invitation here"], @"Wrong topic. Found: %@", newRoom.state.topic);
                        
                        XCTAssertEqual(newRoom.state.membership, MXMembershipJoin);
                        XCTAssertNotNil(newRoom.summary.lastMessageEvent);
                        XCTAssertEqual(newRoom.summary.lastMessageEvent.eventType, MXEventTypeRoomMember, @"The last should be a m.room.member event indicating Alice joining the room");
                        
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
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

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
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [mxSession start:^{

            __block NSString *newRoomId;
            NSMutableArray *receivedMessages = [NSMutableArray array];
            [mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

                if (MXTimelineDirectionForwards == direction && [event.roomId isEqualToString:newRoomId])
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
            [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:nil readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

                newRoomId = roomId;

                [bobRestClient sendTextMessageToRoom:roomId text:@"Hi Alice!" success:^(NSString *eventId) {

                    [bobRestClient sendTextMessageToRoom:roomId text:@"Hi Alice 2!" success:^(NSString *eventId) {

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

// Test for https://matrix.org/jira/browse/SYIOS-105 using notifications
- (void)testRoomStateWhenARoomHasBeenJoinedOnAnotherMatrixClientAndNotifications {
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

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
            [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:nil readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

#pragma clang diagnostic pop

@end
