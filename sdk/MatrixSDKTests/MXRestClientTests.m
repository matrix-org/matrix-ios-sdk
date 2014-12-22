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
        XCTAssertTrue([bobRestClient.credentials.accessToken isEqualToString:sharedData.bobCredentials.accessToken], "bobRestClient.access_token(%@) is wrong", bobRestClient.credentials.accessToken);
        
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
    
    [sharedData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
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
    
    [sharedData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
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
            XCTAssertTrue([roomMemberEvent.userId isEqualToString:bobRestClient.credentials.userId]);
            
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

- (void)testInitialSyncOfRoom
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient initialSyncOfRoom:roomId withLimit:3 success:^(NSDictionary *JSONData) {
            
            XCTAssertNotNil(JSONData);
            XCTAssertNotNil(JSONData[@"room_id"]);
            XCTAssertNotNil(JSONData[@"membership"]);
            XCTAssertNotNil(JSONData[@"messages"]);
            XCTAssertNotNil(JSONData[@"messages"][@"chunk"]);
            XCTAssertNotNil(JSONData[@"state"]);
            XCTAssertNotNil(JSONData[@"presence"]);
            
            XCTAssert([JSONData[@"room_id"] isEqualToString:roomId]);
            XCTAssert([JSONData[@"membership"] isEqualToString:@"join"]);
            
            XCTAssert([JSONData[@"messages"][@"chunk"] isKindOfClass:[NSArray class]]);
            NSArray *messages = JSONData[@"messages"][@"chunk"];
            XCTAssertEqual(messages.count, 3);
            
            XCTAssert([JSONData[@"state"] isKindOfClass:[NSArray class]]);
            
            XCTAssert([JSONData[@"presence"] isKindOfClass:[NSArray class]]);
            NSArray *presences = JSONData[@"presence"];
            XCTAssertEqual(presences.count, 1);
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Remove the `age` field from a dictionary and all its sub dictionaries
- (NSDictionary*)removeAgeFieldFromJSONDictionary:(NSDictionary*)JSONDict
{
    // As JSONDict is unmutable, transform it to a JSON string, remove the lines containing `age`
    // and convert back the string to a JSON dict
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:JSONDict
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    NSString *JSONString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\"age\"(.*)," options:NSRegularExpressionCaseInsensitive error:&error];
    NSString *modifiedJSONString = [regex stringByReplacingMatchesInString:JSONString options:0 range:NSMakeRange(0, JSONString.length) withTemplate:@""];

    NSData *data = [modifiedJSONString dataUsingEncoding:NSUTF8StringEncoding];

    return [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
}

// Compare the result of initialSyncOfRoom with the data retrieved from a global initialSync
- (void)testInitialSyncOfRoomAndGlobalInitialSync
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [bobRestClient initialSyncWithLimit:3 success:^(NSDictionary *JSONData) {

            NSDictionary *JSONRoomDataInGlobal;

            for (NSDictionary *roomDict in JSONData[@"rooms"])
            {
                if ([roomId isEqualToString:roomDict[@"room_id"]])
                {
                    JSONRoomDataInGlobal = roomDict;
                }
            }

            XCTAssertNotNil(JSONRoomDataInGlobal);

            [bobRestClient initialSyncOfRoom:roomId withLimit:3 success:^(NSDictionary *JSONData) {

                XCTAssertNotNil(JSONData);

                // Do some cleaning before comparison
                // Remove presence from initialSyncOfRoom result
                NSMutableDictionary *JSONData2 = [NSMutableDictionary dictionaryWithDictionary:JSONData];
                [JSONData2 removeObjectForKey:@"presence"];

                // Remove visibility from global initialSync
                NSMutableDictionary *JSONRoomDataInGlobal2 = [NSMutableDictionary dictionaryWithDictionary:JSONRoomDataInGlobal];
                [JSONRoomDataInGlobal2 removeObjectForKey:@"visibility"];

                // Remove the `age` field which is time dynamic
                NSDictionary *JSONData3 = [self removeAgeFieldFromJSONDictionary:JSONData2];
                NSDictionary *JSONRoomDataInGlobal3 = [self removeAgeFieldFromJSONDictionary:JSONRoomDataInGlobal2];

                // Do the comparison
                XCTAssertEqualObjects(JSONRoomDataInGlobal3, JSONData3);

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
    [sharedData doMXSessionTestWithBobAndAliceInARoom:self
 readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [sharedData for:bobRestClient andRoom:roomId sendMessages:5 success:^{
            [bobRestClient leaveRoom:roomId success:^{
                [aliceRestClient sendTextMessageToRoom:roomId text:@"Hi bob"  success:^(NSString *eventId) {
                    [aliceRestClient inviteUser:bobRestClient.credentials.userId toRoom:roomId success:^{
                        [bobRestClient joinRoom:roomId success:^(NSString *theRoomId) {

                            [bobRestClient initialSyncWithLimit:10 success:^(NSDictionary *JSONData) {

                                NSDictionary *JSONRoomDataInGlobal;

                                for (NSDictionary *roomDict in JSONData[@"rooms"])
                                {
                                    if ([roomId isEqualToString:roomDict[@"room_id"]])
                                    {
                                        JSONRoomDataInGlobal = roomDict;
                                    }
                                }

                                XCTAssertNotNil(JSONRoomDataInGlobal);

                                [bobRestClient initialSyncOfRoom:roomId withLimit:10 success:^(NSDictionary *JSONData) {

                                    XCTAssertNotNil(JSONData);

                                    // Do some cleaning before comparison
                                    // Remove presence from initialSyncOfRoom result
                                    NSMutableDictionary *JSONData2 = [NSMutableDictionary dictionaryWithDictionary:JSONData];
                                    [JSONData2 removeObjectForKey:@"presence"];

                                    // Remove visibility from global initialSync
                                    NSMutableDictionary *JSONRoomDataInGlobal2 = [NSMutableDictionary dictionaryWithDictionary:JSONRoomDataInGlobal];
                                    [JSONRoomDataInGlobal2 removeObjectForKey:@"visibility"];

                                    // Remove the `age` field which is time dynamic
                                    NSDictionary *JSONData3 = [self removeAgeFieldFromJSONDictionary:JSONData2];
                                    NSDictionary *JSONRoomDataInGlobal3 = [self removeAgeFieldFromJSONDictionary:JSONRoomDataInGlobal2];

                                    // Do the comparison
                                    XCTAssertEqualObjects(JSONRoomDataInGlobal3, JSONData3);

                                    //[expectation fulfill];

                                    [bobRestClient messagesForRoom:roomId from:JSONRoomDataInGlobal[@"messages"][@"start"] to:nil limit:1 success:^(MXPaginationResponse *paginatedResponse) {

                                        //NSLog(@"%@", JSONData[@"messages"][@"chunk"]);
                                        NSLog(@"%@", JSONRoomDataInGlobal[@"messages"][@"chunk"]);
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [bobRestClient membersOfRoom:roomId success:^(NSArray *roomMemberEvents) {
            for (MXEvent *roomMemberEvent in roomMemberEvents)
            {
                MXRoomMemberEventContent *roomMemberEventContent = [MXRoomMemberEventContent modelFromJSON:roomMemberEvent.content];
                if ([roomMemberEvent.userId isEqualToString:aliceRestClient.credentials.userId])
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

- (void)testUserNilAvatarUrl
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        [bobRestClient avatarUrlForUser:nil success:^(NSString *avatarUrl) {

            XCTAssertNil(avatarUrl, @"mxBob has no avatar defined");
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
        
        NSDate *refDate = [NSDate date];
        
        [bobRestClient eventsFromToken:@"END" serverTimeout:1000 clientTimeout:40000 success:^(MXPaginationResponse *paginatedResponse) {
            
            XCTAssertNotNil(paginatedResponse);
            
            // Check expected response params
            XCTAssertNotNil(paginatedResponse.start);
            XCTAssertNotNil(paginatedResponse.end);
            XCTAssertNotNil(paginatedResponse.chunk);
            XCTAssertEqual(paginatedResponse.chunk.count, 0, @"Events should not come in this short stream time (1s)");
            
            NSDate *now  = [NSDate date];
            XCTAssertLessThanOrEqual([now timeIntervalSinceDate:refDate], 2, @"The HS did not timeout as expected");    // Give 2s for the HS to timeout
 
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
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

@end
