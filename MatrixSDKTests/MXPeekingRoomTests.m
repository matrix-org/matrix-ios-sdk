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
#import "MXError.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXPeekingRoomTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
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
    matrixSDKTestsData = nil;

    [super tearDown];
}

- (void)testPeeking
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        [room setHistoryVisibility:kMXRoomHistoryVisibilityWorldReadable success:^{

            [matrixSDKTestsData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {

                XCTAssertEqual(mxSession.rooms.count, 0);

                [mxSession peekInRoomWithRoomId:room.roomId success:^(MXPeekingRoom *peekingRoom) {

                    XCTAssertEqual(mxSession.rooms.count, 0, @"MXPeekingRoom must not be listed by mxSession.rooms");
                    XCTAssertEqual(peekingRoom.roomId, room.roomId);

                    [peekingRoom state:^(MXRoomState *roomState) {

                        XCTAssertNotNil(roomState.name);
                        XCTAssertNotNil(roomState.topic);
                        XCTAssertEqual(roomState.membersCount.members, 1, @"The MXPeekingRoom state must be known now");

                        [mxSession stopPeeking:peekingRoom];

                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPeekingSummary
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        [room setHistoryVisibility:kMXRoomHistoryVisibilityWorldReadable success:^{

            [matrixSDKTestsData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {

                XCTAssertEqual(mxSession.rooms.count, 0);

                [mxSession peekInRoomWithRoomId:room.roomId success:^(MXPeekingRoom *peekingRoom) {

                    XCTAssertEqual(mxSession.rooms.count, 0, @"MXPeekingRoom must not be listed by mxSession.rooms");
                    XCTAssertEqual(peekingRoom.roomId, room.roomId);

                    XCTAssertNotNil(peekingRoom.summary);

                    XCTAssertNotNil(peekingRoom.summary.displayName);
                    XCTAssertNotNil(peekingRoom.summary.topic);
                    XCTAssertEqual(peekingRoom.summary.membersCount.members, 1, @"The MXPeekingRoom state must be known now");

                    [mxSession stopPeeking:peekingRoom];

                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


- (void)testPeekingOnNonWorldReadable
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {

            XCTAssertEqual(mxSession.rooms.count, 0);

            [mxSession peekInRoomWithRoomId:room.roomId success:^(MXPeekingRoom *peekingRoom) {

                XCTFail(@"Peeking on non world_readable room must fail");
                [expectation fulfill];

            } failure:^(NSError *error) {

                MXError *mxError = [[MXError alloc] initWithNSError:error];
                XCTAssertEqualObjects(mxError.errcode, kMXErrCodeStringGuestAccessForbidden);

                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testPeekingWithMemberAlreadyInRoom
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        XCTAssertEqual(mxSession.rooms.count, 1);
        XCTAssertEqual(room.summary.membersCount.members, 1);

        [mxSession peekInRoomWithRoomId:room.roomId success:^(MXPeekingRoom *peekingRoom) {

            XCTAssertEqual(mxSession.rooms.count, 1, @"MXPeekingRoom must not be listed by mxSession.rooms");
            XCTAssertEqual(peekingRoom.roomId, room.roomId);

            [peekingRoom state:^(MXRoomState *roomState) {
                XCTAssertEqual(roomState.membersCount.members, 1, @"The MXPeekingRoom state must be known now");

                [mxSession stopPeeking:peekingRoom];

                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop
