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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"

#import "MXSession.h"
#import "MXTools.h"
#import "MXMemoryStore.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
#pragma clang diagnostic ignored "-Wdeprecated"

@interface MXRoomStateTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
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
    matrixSDKTestsData = nil;
    
    [super tearDown];
}

- (void)testIsJoinRulePublic
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [room state:^(MXRoomState *roomState) {

            XCTAssertTrue(roomState.isJoinRulePublic, @"The room join rule must be public");

            [expectation fulfill];
        }];
    }];
}

- (void)testIsJoinRulePublicForAPrivateRoom
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [room state:^(MXRoomState *roomState) {
            XCTAssertFalse(roomState.isJoinRulePublic, @"This room join rule must be private");

            [expectation fulfill];
        }];
    }];
}

- (void)testRoomTopicProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        [bobRestClient setRoomTopic:roomId topic:@"My topic" success:^{
            
            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [matrixSDKTestsData retain:mxSession];
            
            [mxSession start:^{
                
                MXRoom *room = [mxSession roomWithRoomId:roomId];

                [room state:^(MXRoomState *roomState) {
                    XCTAssertNotNil(roomState.topic);
                    XCTAssertEqualObjects(roomState.topic, @"My topic");

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

- (void)testRoomTopicLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];

            // Listen to live event. We should receive only one: a m.room.topic event
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                XCTAssertNil(liveTimeline.state.topic, @"There must be no room topic yet. Found: %@", liveTimeline.state.topic);


                [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(event.eventType, MXEventTypeRoomTopic);

                    XCTAssertNotNil(liveTimeline.state.topic);
                    XCTAssertEqualObjects(liveTimeline.state.topic, @"My topic");

                    [expectation fulfill];

                }];

                // Change the topic
                [bobRestClient2 setRoomTopic:roomId topic:@"My topic" success:^{

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


- (void)testRoomAvatarProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomAvatar:roomId avatar:@"http://matrix.org/matrix.png" success:^{

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [matrixSDKTestsData retain:mxSession];
            
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                [room state:^(MXRoomState *roomState) {
                    XCTAssertNotNil(roomState.avatar);
                    XCTAssertEqualObjects(roomState.avatar, @"http://matrix.org/matrix.png");

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

- (void)testRoomAvatarLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            // Listen to live event. We should receive only one: a m.room.avatar event
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                XCTAssertNil(liveTimeline.state.avatar, @"There must be no room avatar yet. Found: %@", liveTimeline.state.avatar);

                [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(event.eventType, MXEventTypeRoomAvatar);

                    XCTAssertNotNil(liveTimeline.state.avatar);
                    XCTAssertEqualObjects(liveTimeline.state.avatar, @"http://matrix.org/matrix.png");

                    [expectation fulfill];

                }];

                // Change the avatar
                [bobRestClient2 setRoomAvatar:roomId avatar:@"http://matrix.org/matrix.png" success:^{

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

- (void)testRoomNameProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        [bobRestClient setRoomName:roomId name:@"My room name" success:^{
            
            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [matrixSDKTestsData retain:mxSession];
            
            [mxSession start:^{
                
                MXRoom *room = [mxSession roomWithRoomId:roomId];

                [room state:^(MXRoomState *roomState) {

                    XCTAssertNotNil(roomState.name);
                    XCTAssertEqualObjects(roomState.name, @"My room name");

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

- (void)testRoomNameLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];

            // Listen to live event. We should receive only one: a m.room.name event
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                XCTAssertNil(liveTimeline.state.name, @"There must be no room name yet. Found: %@", liveTimeline.state.name);

                [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(event.eventType, MXEventTypeRoomName);

                    XCTAssertNotNil(liveTimeline.state.name);
                    XCTAssertEqualObjects(liveTimeline.state.name, @"My room name");

                    [expectation fulfill];

                }];

                // Change the topic
                [bobRestClient2 setRoomName:roomId name:@"My room name" success:^{

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

- (void)testRoomHistoryVisibilityProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomHistoryVisibility:roomId historyVisibility:kMXRoomHistoryVisibilityWorldReadable success:^{

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [matrixSDKTestsData retain:mxSession];
            
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                [room state:^(MXRoomState *roomState) {

                    XCTAssertNotNil(roomState.historyVisibility);
                    XCTAssertEqualObjects(roomState.historyVisibility, kMXRoomHistoryVisibilityWorldReadable, @"The room history visibility is wrong");

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

- (void)testRoomHistoryVisibilityLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            // Listen to live event. We should receive only one: a m.room.name event
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                XCTAssertEqualObjects(liveTimeline.state.historyVisibility, kMXRoomHistoryVisibilityShared, @"The default room history visibility should be shared");

                [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(event.eventType, MXEventTypeRoomHistoryVisibility);

                    XCTAssertNotNil(liveTimeline.state.historyVisibility);
                    XCTAssertEqualObjects(liveTimeline.state.historyVisibility, kMXRoomHistoryVisibilityInvited, @"The room history visibility is wrong");
                    ;

                    [expectation fulfill];

                }];

                // Change the history visibility
                [room setHistoryVisibility:kMXRoomHistoryVisibilityInvited success:^{

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

- (void)testRoomJoinRuleProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomJoinRule:roomId joinRule:kMXRoomJoinRulePublic success:^{

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [matrixSDKTestsData retain:mxSession];
            
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                [room state:^(MXRoomState *roomState) {
                    XCTAssertNotNil(roomState.joinRule);
                    XCTAssertEqualObjects(roomState.joinRule, kMXRoomJoinRulePublic, @"The room join rule is wrong");

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

- (void)testRoomJoinRuleLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            // Listen to live event. We should receive only one: a m.room.name event
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                XCTAssertEqualObjects(liveTimeline.state.joinRule, kMXRoomJoinRuleInvite, @"The default room join rule should be invite");

                [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(event.eventType, MXEventTypeRoomJoinRules);

                    XCTAssertNotNil(liveTimeline.state.joinRule);
                    XCTAssertEqualObjects(liveTimeline.state.joinRule, kMXRoomJoinRulePublic, @"The room join rule is wrong");

                    [expectation fulfill];

                }];

                // Change the join rule
                [room setJoinRule:kMXRoomJoinRulePublic success:^{

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

- (void)testRoomGuestAccessProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomGuestAccess:roomId guestAccess:kMXRoomGuestAccessCanJoin success:^{

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [matrixSDKTestsData retain:mxSession];
            
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                [room state:^(MXRoomState *roomState) {
                    XCTAssertNotNil(roomState.joinRule);
                    XCTAssertEqualObjects(roomState.guestAccess, kMXRoomGuestAccessCanJoin, @"The room guest access is wrong");

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

- (void)testRoomGuestAccessLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            // Listen to live event. We should receive only one: a m.room.name event
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                XCTAssertEqualObjects(liveTimeline.state.guestAccess, kMXRoomGuestAccessCanJoin, @"The default room guest access should be forbidden");

                [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(event.eventType, MXEventTypeRoomGuestAccess);

                    XCTAssertNotNil(liveTimeline.state.guestAccess);
                    XCTAssertEqualObjects(liveTimeline.state.guestAccess, kMXRoomGuestAccessForbidden, @"The room guest access is wrong");

                    [expectation fulfill];
                }];

                // Change the guest access
                [room setGuestAccess:kMXRoomGuestAccessForbidden success:^{

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
                
                MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
                [matrixSDKTestsData retain:mxSession];
                
                [mxSession start:^{
                    
                    MXRoom *room = [mxSession roomWithRoomId:roomId];

                    [room state:^(MXRoomState *roomState) {

                        XCTAssertNotNil(roomState.aliases);
                        XCTAssertEqual(roomState.aliases.count, 1);
                        XCTAssertEqualObjects(roomState.aliases.firstObject, roomAlias, @"The room alias is wrong");

                        XCTAssertNotNil(roomState.canonicalAlias);
                        XCTAssertNotEqual(roomState.canonicalAlias.length, 0);
                        XCTAssertEqualObjects(roomState.canonicalAlias, roomAlias, @"The room canonical alias is wrong");

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

- (void)testRoomCanonicalAliasLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXRestClient *bobRestClient2 = bobRestClient;
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            NSString *globallyUniqueString = [[NSProcessInfo processInfo] globallyUniqueString];
            NSString *roomAlias = [NSString stringWithFormat:@"#%@%@", globallyUniqueString, bobRestClient.homeserverSuffix];
            
            // Listen to live event. We should receive only: a m.room.aliases and m.room.canonical_alias events
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                XCTAssertNil(liveTimeline.state.aliases);
                XCTAssertNil(liveTimeline.state.canonicalAlias);

                [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    if(event.eventType == MXEventTypeRoomAliases)
                    {
                        XCTAssertNotNil(liveTimeline.state.aliases);
                        XCTAssertEqual(liveTimeline.state.aliases.count, 1);
                        XCTAssertEqualObjects(liveTimeline.state.aliases.firstObject, roomAlias, @"The room alias is wrong");
                    }
                    else if (event.eventType == MXEventTypeRoomCanonicalAlias)
                    {
                        XCTAssertNotNil(liveTimeline.state.canonicalAlias);
                        XCTAssertNotEqual(liveTimeline.state.canonicalAlias.length, 0);
                        XCTAssertEqualObjects(liveTimeline.state.canonicalAlias, roomAlias, @"The room canonical alias is wrong");

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
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            XCTAssertNotNil(room);

            [room members:^(MXRoomMembers *roomMembers) {

                NSArray *members = roomMembers.members;
                XCTAssertEqual(members.count, 1, "There must be only one member: mxBob, the creator");

                for (MXRoomMember *member in roomMembers.members)
                {
                    XCTAssertTrue([member.userId isEqualToString:bobRestClient.credentials.userId], "This must be mxBob");
                }

                XCTAssertNotNil([roomMembers memberWithUserId:bobRestClient.credentials.userId], @"Bob must be retrieved");

                XCTAssertNil([roomMembers memberWithUserId:@"NonExistingUserId"], @"getMember must return nil if the user does not exist");

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

- (void)testMemberName
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        NSString *bobUserId = matrixSDKTestsData.bobCredentials.userId;

        [room members:^(MXRoomMembers *roomMembers) {
            NSString *bobMemberName = [roomMembers memberName:bobUserId];

            XCTAssertNotNil(bobMemberName);
            XCTAssertFalse([bobMemberName isEqualToString:@""], @"bobMemberName must not be an empty string");

            XCTAssert([[roomMembers memberName:@"NonExistingUserId"] isEqualToString:@"NonExistingUserId"], @"memberName must return his id if the user does not exist");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testStateEvents
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [room state:^(MXRoomState *roomState) {
            XCTAssertNotNil(roomState.stateEvents);
            XCTAssertGreaterThan(roomState.stateEvents.count, 0);

            [expectation fulfill];
        }];
    }];
}

- (void)testAliases
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [room state:^(MXRoomState *roomState) {
            XCTAssertNotNil(roomState.aliases);
            XCTAssertGreaterThanOrEqual(roomState.aliases.count, 1);

            NSString *alias = roomState.aliases[0];

            XCTAssertTrue([alias hasPrefix:@"#mxPublic"]);

            [expectation fulfill];
        }];
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
    [bobRestClient sendTextMessageToRoom:roomId threadId:nil text:@"Hello world" success:^(NSString *eventId) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomName:roomId name:@"Invite test" success:^{

            [bobRestClient setRoomTopic:roomId topic:@"We test room invitation here" success:^{

                [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

                    if (inviteAlice)
                    {
                        [bobRestClient2 inviteUser:matrixSDKTestsData.aliceCredentials.userId toRoom:roomId success:^{

                            [bobRestClient2 sendTextMessageToRoom:roomId threadId:nil text:@"I wait for Alice" success:^(NSString *eventId) {

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
            
            [matrixSDKTestsData doMXSessionTestWithAlice:nil andStore:[MXMemoryStore new] readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {
                
                MXRoom *newRoom = [mxSession roomWithRoomId:roomId];
                
                XCTAssertNotNil(newRoom);
                
                XCTAssertEqual(newRoom.summary.membership, MXMembershipInvite);
                
                // The room has 2 members (Alice & Bob)
                XCTAssertEqual(newRoom.summary.membersCount.members, 2);

                [newRoom members:^(MXRoomMembers *roomMembers) {

                    MXRoomMember *alice = [roomMembers memberWithUserId:mxSession.myUserId];
                    XCTAssertNotNil(alice);
                    XCTAssertEqual(alice.membership, MXMembershipInvite);
                    XCTAssert([alice.originUserId isEqualToString:bobRestClient.credentials.userId], @"Wrong inviter: %@", alice.originUserId);

                    // The last message should be an invite m.room.member
                    [mxSession eventWithEventId:newRoom.summary.lastMessage.eventId
                                         inRoom:newRoom.roomId
                                        success:^(MXEvent *lastMessage) {
                        
                        XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMember, @"The last message should be an invite m.room.member");
                        XCTAssertLessThan([[NSDate date] timeIntervalSince1970] * 1000 - lastMessage.originServerTs, 3000);

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

- (void)testInviteByOtherInLive
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [matrixSDKTestsData doMXSessionTestWithAlice:nil andStore:[MXMemoryStore new] readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {
            
            __block MXRoom *newRoom;
            __block id listener;
            
            listener = [mxSession listenToEvents:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                
                if ([event.roomId isEqualToString:roomId])
                {
                    newRoom = [mxSession roomWithRoomId:roomId];
                    
                    XCTAssertNotNil(newRoom);
                    
                    if (newRoom.summary.membership != MXMembershipUnknown)
                    {
                        [mxSession removeListener:listener];
                        XCTAssertEqual(newRoom.summary.membership, MXMembershipInvite);
                        
                        // The room has 2 members (Alice & Bob)
                        XCTAssertEqual(newRoom.summary.membersCount.members, 2);
                        
                        [newRoom members:^(MXRoomMembers *roomMembers) {
                            
                            MXRoomMember *alice = [roomMembers memberWithUserId:mxSession.myUserId];
                            XCTAssertNotNil(alice);
                            XCTAssertEqual(alice.membership, MXMembershipInvite);
                            XCTAssert([alice.originUserId isEqualToString:bobRestClient.credentials.userId], @"Wrong inviter: %@", alice.originUserId);
                            
                            // The last message should be an invite m.room.member
                            dispatch_async(dispatch_get_main_queue(), ^{    // We could also wait for kMXRoomSummaryDidChangeNotification
                                
                                [mxSession eventWithEventId:newRoom.summary.lastMessage.eventId
                                                     inRoom:newRoom.roomId
                                                    success:^(MXEvent *lastMessage) {
                                    
                                    XCTAssertNotNil(lastMessage);
                                    XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMember, @"The last message should be an invite m.room.member");
                                    XCTAssertLessThan([[NSDate date] timeIntervalSince1970] * 1000 - lastMessage.originServerTs, 3000);
                                    
                                    [expectation fulfill];
                                    
                                } failure:^(NSError *error) {
                                    XCTFail(@"The request should not fail - NSError: %@", error);
                                    [expectation fulfill];
                                }];
                                
                            });
                            
                        } failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                    }
                }
                
            }];
            
            [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:YES expectation:expectation onComplete:^{
                
                // Make sure we have tested something
                XCTAssertNotNil(newRoom);
                
            }];
                
        }];
        
    }];
}


- (void)testMXRoomJoin
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:YES expectation:expectation onComplete:^{
            
            [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                [matrixSDKTestsData retain:mxSession];
                
                [mxSession start:^{
                    
                    MXRoom *newRoom = [mxSession roomWithRoomId:roomId];

                    [newRoom liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                        [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                            if (MXTimelineDirectionForwards == event)
                            {
                                // We should receive only join events in live
                                XCTAssertEqual(event.eventType, MXEventTypeRoomMember);

                                MXRoomMemberEventContent *roomMemberEventContent = [MXRoomMemberEventContent modelFromJSON:event.content];
                                XCTAssert([roomMemberEventContent.membership isEqualToString:kMXMembershipStringJoin]);
                            }
                        }];
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
                        XCTAssertEqual(newRoom.summary.membersCount.members, 2);
                        XCTAssertEqualObjects(newRoom.summary.topic, @"We test room invitation here");
                        
                        XCTAssertEqual(newRoom.summary.membership, MXMembershipJoin);

                        XCTAssertNotNil(newRoom.summary.lastMessage.eventId);
                        
                        [mxSession eventWithEventId:newRoom.summary.lastMessage.eventId
                                             inRoom:newRoom.roomId
                                            success:^(MXEvent *event) {
                            
                            XCTAssertNotNil(event);
                            
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMember, @"The last should be a m.room.member event indicating Alice joining the room");
                            
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
        
    }];
}


- (void)testMXSessionJoinOnPublicRoom
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndAPublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createInviteByUserScenario:bobRestClient inRoom:roomId inviteAlice:NO expectation:expectation onComplete:^{
            
            [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
                
                MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                [matrixSDKTestsData retain:mxSession];
                
                [mxSession start:^{
                    
                    MXRoom *room = [mxSession roomWithRoomId:roomId];
                    
                    XCTAssertNil(room, @"The room must not be known yet by the user");
                    
                    [mxSession joinRoom:roomId viaServers:nil success:^(MXRoom *room) {
                        
                        XCTAssert([room.roomId isEqualToString:roomId]);
                        
                        MXRoom *newRoom = [mxSession roomWithRoomId:roomId];
                        XCTAssert(newRoom, @"The room must be known now by the user");

                        [newRoom state:^(MXRoomState *roomState) {

                            // Now, we must have more information about the room
                            // Check its new state
                            XCTAssertEqual(roomState.isJoinRulePublic, YES);
                            XCTAssertEqual(newRoom.summary.membersCount.members, 2);
                            XCTAssertEqualObjects(roomState.topic, @"We test room invitation here");

                            XCTAssertEqual(newRoom.summary.membership, MXMembershipJoin);
                            XCTAssertNotNil(newRoom.summary.lastMessage);
                            
                            [mxSession eventWithEventId:newRoom.summary.lastMessage.eventId
                                                 inRoom:newRoom.roomId
                                                success:^(MXEvent *event) {
                                
                                XCTAssertEqual(event.eventType, MXEventTypeRoomMember, @"The last should be a m.room.member event indicating Alice joining the room");

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

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            [room state:^(MXRoomState *roomState) {

                MXRoomPowerLevels *roomPowerLevels = roomState.powerLevels;

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
            }];

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

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:mxSession];
        
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
                    XCTAssertEqual(room.summary.membersCount.members, 2, @"If this count is wrong, the room state is invalid");

                    [expectation fulfill];
                }
            }];

            // Create a conversation on another MXRestClient. For the current `mxSession`, this other MXRestClient behaves like another device.
            [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:nil readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

                newRoomId = roomId;

                [bobRestClient sendTextMessageToRoom:roomId threadId:nil text:@"Hi Alice!" success:^(NSString *eventId) {

                    [bobRestClient sendTextMessageToRoom:roomId threadId:nil text:@"Hi Alice 2!" success:^(NSString *eventId) {

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

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{

            __block NSString *newRoomId;

            // Check MXSessionNewRoomNotification reception
            __block __weak id newRoomObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                newRoomId = note.userInfo[kMXSessionNotificationRoomIdKey];

                MXRoom *room = [mxSession roomWithRoomId:newRoomId];
                XCTAssertNotNil(room);
                
                BOOL isSync = (room.summary.membership != MXMembershipInvite && room.summary.membership != MXMembershipUnknown);
                XCTAssertFalse(isSync, @"The room is not yet sync'ed");

                [[NSNotificationCenter defaultCenter] removeObserver:newRoomObserver];
            }];

            // Check kMXRoomInitialSyncNotification that must be then received
            __block __weak id initialSyncObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                XCTAssertNotNil(note.object);

                MXRoom *room = note.object;

                XCTAssertEqualObjects(newRoomId, room.roomId);
                
                BOOL isSync = (room.summary.membership != MXMembershipInvite && room.summary.membership != MXMembershipUnknown);
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

- (void)testDeallocation
{
    __weak __block MXRoomState *weakState;
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        [room state:^(MXRoomState *roomState) {
            weakState = roomState;
            XCTAssertNotNil(weakState);
            [expectation fulfill];
        }];
    }];
    XCTAssertNil(weakState);
}

- (void)testCopying
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [room state:^(MXRoomState *roomState) {
            MXRoomState *roomStateCopy = [roomState copy];
            XCTAssertEqual(roomStateCopy.members.members.count, roomState.members.members.count);
            [expectation fulfill];
        }];
    }];
}

#pragma clang diagnostic pop

@end
