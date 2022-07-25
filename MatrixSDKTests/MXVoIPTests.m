/*
 Copyright 2015 OpenMarket Ltd

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

#import "MXMockCallStack.h"
#import "MXMockCallStackCall.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"

@interface MXVoIPTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}

@end

@implementation MXVoIPTests

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


#pragma mark - Tests with no call stack
- (void)testNoVoIPStackMXRoomCall
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *mxSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [mxSession roomWithRoomId:roomId];

        // Make sure there is no VoIP stack
        mxSession.callManager.callStack = nil;

        [room placeCallWithVideo:NO success:^(MXCall *call) {

            XCTAssertNil(@"MXCall cannot be created if there is no VoIP stack");
            [expectation fulfill];

        } failure:^(NSError *error) {
            [expectation fulfill];
        }];

    }];
}

- (void)testNoVoIPStackOnCallInvite
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *mxSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        // Make sure there is no VoIP stack
        mxSession.callManager.callStack = nil;


        NSString *callId = @"callId";

        // The call invite can sent to the HS
        NSDictionary *content = @{
                                  @"call_id": callId,
                                  @"offer": @{
                                          @"type": @"offer",
                                          @"sdp": @"A SDP"
                                          },
                                  @"version": kMXCallVersion,
                                  @"lifetime": @(30 * 1000),
                                  @"invitee": mxSession.myUserId,
                                  @"party_id": mxSession.myDeviceId
                                  };


        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringCallInvite] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            MXCall *call = [mxSession.callManager callWithCallId:callId];

            XCTAssertNil(call, @"MXCall cannot be created if there is no VoIP stack");
            [expectation fulfill];
        }];

        [aliceRestClient sendEventToRoom:roomId threadId:nil eventType:kMXEventTypeStringCallInvite content:content txnId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark - Tests with a call stack mock
//- (void)testMXRoomCall
//{
//    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
//
//        mxSession = bobSession;
//        MXRoom *room = [mxSession roomWithRoomId:roomId];
//
//        // Set up the mock
//        MXMockCallStack *callStackMock = [[MXMockCallStack alloc] init];
//        mxSession.callManager.callStack = callStackMock;
//
//        MXCall *call = [room placeCallWithVideo:NO];
//
//        XCTAssert(call, @"MXCall must be created on [room placeCallWithVideo:]");
//        XCTAssertNotNil(call.callId);
//        XCTAssertEqual(call.state, MXCallStateWaitLocalMedia);
//
//        MXCall *callInRoom = [mxSession.callManager callInRoom:roomId];
//        XCTAssertEqual(call, callInRoom, @"[MXCallManager callInRoom:] must retrieve the same call");
//
//        [expectation fulfill];
//    }];
//}



@end

#pragma clang diagnostic pop
