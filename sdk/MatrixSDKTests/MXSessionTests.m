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

#import "MXSession.h"
#import "MatrixSDKTestsData.h"

@interface MXSessionTests : XCTestCase

@end

@implementation MXSessionTests

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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
        
        XCTAssertTrue([bobSession.homeserver isEqualToString:kMXTestsHomeServerURL], "bobSession.homeserver(%@) is wrong", bobSession.homeserver);
        XCTAssertTrue([bobSession.user_id isEqualToString:sharedData.bobCredentials.user_id], "bobSession.user_id(%@) is wrong", bobSession.user_id);
        XCTAssertTrue([bobSession.access_token isEqualToString:sharedData.bobCredentials.access_token], "bobSession.access_token(%@) is wrong", bobSession.access_token);
        
        [expectation fulfill];
    }];
}

#pragma mark - Room operations
- (void)testPostTextMessage
{
    // This test on postTextMessage validates postMessage and postEvent too
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession postTextMessage:room_id text:@"This is text message" success:^(NSString *event_id) {
            
            XCTAssertNotNil(event_id);
            XCTAssertGreaterThan(event_id.length, 0, @"The event_id string must not be empty");
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testJoinRoom
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession joinRoom:room_id success:^{
            
            // No data to test. Just happy to go here.
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testLeaveRoom
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession leaveRoom:room_id success:^{
            
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
    
    [sharedData doMXSessionTestWithBobAndARoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [sharedData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {
            
            // Do the test
            [bobSession inviteUser:sharedData.aliceCredentials.user_id toRoom:room_id success:^{
                
                // Check room actual members
                [bobSession members:room_id success:^(NSArray *members) {
                    
                    XCTAssertEqual(2, members.count, @"There must be 2 members");
                    
                    for (MXRoomMember *member in members)
                    {
                        if ([member.user_id isEqualToString:sharedData.aliceCredentials.user_id])
                        {
                            XCTAssert([member.membership isEqualToString:kMXMembershipInvite], @"A invited user membership is invite, not %@", member.membership);
                        }
                        else
                        {
                            // The other user is Bob
                            XCTAssert([member.user_id isEqualToString:sharedData.bobCredentials.user_id], @"Unexpected member: %@", member);
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
    
    [sharedData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession kickUser:sharedData.aliceCredentials.user_id fromRoom:room_id reason:@"No particular reason" success:^{
            
            // Check room actual members
            [bobSession members:room_id success:^(NSArray *members) {
                
                XCTAssertEqual(2, members.count, @"There must still be 2 members");
                
                for (MXRoomMember *member in members)
                {
                    if ([member.user_id isEqualToString:sharedData.aliceCredentials.user_id])
                    {
                        XCTAssert([member.membership isEqualToString:kMXMembershipLeave], @"A kicked user membership is leave, not %@", member.membership);
                    }
                    else
                    {
                        // The other user is Bob
                        XCTAssert([member.user_id isEqualToString:sharedData.bobCredentials.user_id], @"Unexpected member: %@", member);
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
    
    [sharedData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession banUser:sharedData.aliceCredentials.user_id inRoom:room_id reason:@"No particular reason" success:^{
            
            // Check room actual members
            [bobSession members:room_id success:^(NSArray *members) {
                
                XCTAssertEqual(2, members.count, @"There must still be 2 members");
                
                for (MXRoomMember *member in members)
                {
                    if ([member.user_id isEqualToString:sharedData.aliceCredentials.user_id])
                    {
                        XCTAssert([member.membership isEqualToString:kMXMembershipBan], @"A banned user membership is ban, not %@", member.membership);
                    }
                    else
                    {
                        // The other user is Bob
                        XCTAssert([member.user_id isEqualToString:sharedData.bobCredentials.user_id], @"Unexpected member: %@", member);
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        // Create a random room with no params
        [bobSession createRoom:nil visibility:nil room_alias_name:nil topic:nil success:^(MXCreateRoomResponse *response) {
            
            XCTAssertNotNil(response);
            XCTAssertNotNil(response.room_id, "The home server should have allocated a room id");
            
            // Do not test response.room_alias as it is not filled here
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMessages
{
    [[MatrixSDKTestsData sharedData]  doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession messages:room_id from:nil to:nil limit:-1 success:^(MXPaginationResponse *paginatedResponse) {
            
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession members:room_id success:^(NSArray *members) {
            
            XCTAssertEqual(members.count, 1);
            
            MXRoomMember *roomMember = members[0];
            XCTAssertTrue([roomMember.user_id isEqualToString:bobSession.user_id]);
            
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {
        
        // Set the name
        __block NSString *newDisplayName = @"mxAlice";
        [aliceSession setDisplayName:newDisplayName success:^{
            
            [[MatrixSDKTestsData sharedData] doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {
                
                // Then retrieve it
                [aliceSession displayName:nil success:^(NSString *displayname) {
                    
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

- (void)testOtherUserDisplayName
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {
        
        // Set the name
        __block NSString *newDisplayName = @"mxAlice";
        [aliceSession setDisplayName:newDisplayName success:^{
            
            [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:nil readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation2) {
                
                MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
                
                // Then retrieve it from a Bob session
                [bobSession displayName:sharedData.aliceCredentials.user_id success:^(NSString *displayname) {
                    
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

- (void)testUserAvatarUrl
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {
        
        // Set the avatar url
        __block NSString *newAvatarUrl = @"http://matrix.org/matrix.png";
        [aliceSession setAvatarUrl:newAvatarUrl success:^{
            
            [[MatrixSDKTestsData sharedData] doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {
                
                // Then retrieve it
                [aliceSession avatarUrl:nil success:^(NSString *avatar_url) {
                    
                    XCTAssertTrue([avatar_url isEqualToString:newAvatarUrl], @"Must retrieved the set string: %@ - %@", avatar_url, newAvatarUrl);
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

- (void)testOtherUserAvatarUrl
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {
        
        // Set the avatar url
        __block NSString *newAvatarUrl = @"http://matrix.org/matrix.png";
        [aliceSession setAvatarUrl:newAvatarUrl success:^{
            
            [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:nil readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation2) {
                
                MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
                
                // Then retrieve it from a Bob session
                [bobSession avatarUrl:sharedData.aliceCredentials.user_id success:^(NSString *avatarUrl) {
                    
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


#pragma mark - Event operations
- (void)testEventsFromTokenServerTimeout
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        NSDate *refDate = [NSDate date];
        
        [bobSession eventsFromToken:@"END" serverTimeout:1000 clientTimeout:40000 success:^(NSDictionary *JSONData) {
            
            XCTAssertNotNil(JSONData);
            
            // Check expected response params
            XCTAssertNotNil(JSONData[@"start"]);
            XCTAssertNotNil(JSONData[@"end"]);
            XCTAssertNotNil(JSONData[@"chunk"]);
            XCTAssertEqual([JSONData[@"chunk"] count], 0, @"Events should not come in this short stream time (1s)");
            
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        NSDate *refDate = [NSDate date];
        
        [bobSession eventsFromToken:@"END" serverTimeout:5000 clientTimeout:1000 success:^(NSDictionary *JSONData) {
            
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
