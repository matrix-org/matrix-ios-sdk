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

#import "MXRoomMember.h"

@interface MXRoomMemberTests : XCTestCase

@end

@implementation MXRoomMemberTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testKickedMember
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobRestClient kickUser:sharedData.aliceCredentials.userId fromRoom:room_id reason:@"No particular reason" success:^{
            
            // Check room actual members
            [bobRestClient membersOfRoom:room_id success:^(NSArray *roomMemberEvents) {
                
                for (MXEvent *roomMemberEvent in roomMemberEvents)
                {
                    MXRoomMember *member = [[MXRoomMember alloc] initWithMXEvent:roomMemberEvent];
                    
                    if ([member.userId isEqualToString:sharedData.aliceCredentials.userId])
                    {
                        XCTAssertEqual(member.membership, MXMembershipLeave, @"A kicked user membership is leave, not %lu", member.membership);
                        XCTAssertEqual(member.prevMembership, MXMembershipJoin, @"The previous membership of a kicked user must be join, not %lu", member.prevMembership);
                        
                        XCTAssert([member.originUserId isEqualToString:sharedData.bobCredentials.userId], @"This is Bob who kicked Alice, not %@", member.originUserId);
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
}

@end
