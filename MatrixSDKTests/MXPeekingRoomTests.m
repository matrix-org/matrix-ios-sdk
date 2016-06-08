/*
 Copyright 2016 OpenMarket Ltd

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
#import "MXPeekingRoom.h"

@interface MXPeekingRoomTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;

    MXSession *mxSession;
}
@end

@implementation MXPeekingRoomTests

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
        matrixSDKTestsData = nil;
    }
    [super tearDown];
}

- (void)testPeeking
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        // TODO: Set the room history_visibility to world_readable

        [matrixSDKTestsData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {

            mxSession = aliceSession;

            XCTAssertEqual(mxSession.rooms.count, 0);

            [mxSession peekInRoomWithRoomId:room.roomId success:^(MXPeekingRoom *peekingRoom) {

                XCTAssertEqual(mxSession.rooms.count, 1, @"MXPeekingRoom must not be listed by mxSession.rooms");
                XCTAssertEqual(peekingRoom.roomId, room.roomId);

                XCTAssertEqual(peekingRoom.state.members.count, 1, @"The MXPeekingRoom state must be known now");

                [mxSession stopPeeking:peekingRoom];

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testPeekingOnNonWorldReadable
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {

            mxSession = aliceSession;

            XCTAssertEqual(mxSession.rooms.count, 0);

            [mxSession peekInRoomWithRoomId:room.roomId success:^(MXPeekingRoom *peekingRoom) {

                XCTFail(@"Peeking on non world_readable room must fail");
                [expectation fulfill];

            } failure:^(NSError *error) {

                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testPeekingWithMemberAlreadyInRoom
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        mxSession = mxSession2;

        XCTAssertEqual(mxSession.rooms.count, 1);
        XCTAssertEqual(room.state.members.count, 1);

        [mxSession peekInRoomWithRoomId:room.roomId success:^(MXPeekingRoom *peekingRoom) {

            XCTAssertEqual(mxSession.rooms.count, 1, @"MXPeekingRoom must not be listed by mxSession.rooms");
            XCTAssertEqual(peekingRoom.roomId, room.roomId);

            XCTAssertEqual(peekingRoom.state.members.count, 1, @"The MXPeekingRoom state must be known now");

            [mxSession stopPeeking:peekingRoom];

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end
