/*
 * Copyright 2019 New Vector Ltd
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"


// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

// TODO: To remove
static NSUInteger const kMXRoomSummaryTrustComputationDelayMs = 1000;


@interface MXRoomSummaryTrustTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
    
    NSMutableArray<id> *observers;
}
@end

@implementation MXRoomSummaryTrustTests

- (void)setUp
{
    [super setUp];
    
    [MXSDKOptions sharedInstance].computeE2ERoomSummaryTrust = YES;
    
    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
    
    observers = [NSMutableArray array];
}

- (void)tearDown
{
    matrixSDKTestsE2EData = nil;
    matrixSDKTestsData = nil;
    [MXSDKOptions sharedInstance].computeE2ERoomSummaryTrust = NO;

    for (id observer in observers)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }
    
    [super tearDown];
}

/**
 - Alice and Bob are in a room
 -> Alice must see 0% of trust in this room
 */
- (void)testOtherNotTrusted
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{

            // -> Alice must see 0% of trust in this room
            MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
            MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
            
            XCTAssertNotNil(trust);
            XCTAssertEqual(trust.trustedUsersProgress.totalUnitCount, 1);
            XCTAssertEqual(trust.trustedUsersProgress.completedUnitCount, 0);
            XCTAssertEqual(trust.trustedDevicesProgress.totalUnitCount, 1);
            XCTAssertEqual(trust.trustedDevicesProgress.completedUnitCount, 0);
            
            [expectation fulfill];
        });
    }];
}

/**
 - Alice and Bob are in a room
 - Alice trusts Bob devices locally
 -> Alice must be notified for 100% of trust in this room
 */
- (void)testTrustLive
{
    //  - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{

            MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
            MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
            
            XCTAssertNotNil(trust);
            XCTAssertEqual(trust.trustedDevicesProgress.completedUnitCount, 0);
            
            id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:roomFromAlicePOV.summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
                
                // -> Alice must be notified for 100% of trust in this room
                MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
                XCTAssertEqual(trust.trustedDevicesProgress.completedUnitCount, 1);
                [expectation fulfill];
                
            }];
            [observers addObject:observer];
            
            // - Alice trusts Bob devices locally
            MXCredentials *bob = bobSession.matrixRestClient.credentials;
            [aliceSession.crypto setDeviceVerification:MXDeviceVerified forDevice:bob.deviceId ofUser:bob.userId success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        });
    }];
}

/**
 - Alice and Bob are in a room
 - Alice trusts Bob devices locally
 - Bob signs in on a new device
 -> Alice must be notified for no more trust in this room
 */
// TODO: To fix. It sometimes does not pass.
- (void)testIncomingUntrustedDeviceLive
{
    //  - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // - Alice trusts Bob devices locally
        MXCredentials *bob = bobSession.matrixRestClient.credentials;
        [aliceSession.crypto setDeviceVerification:MXDeviceVerified forDevice:bob.deviceId ofUser:bob.userId success:^{
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{

                MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
                XCTAssertEqual(trust.trustedDevicesProgress.completedUnitCount, 1);
                
                // - Bob signs in on a new device
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                [matrixSDKTestsData relogUserSessionWithNewDevice:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
                }];
                
                id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:roomFromAlicePOV.summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
                    
                    // -> Alice must be notified for 100% of trust in this room
                    MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
                    if (trust.trustedDevicesProgress.totalUnitCount == 2)   // If could take for the SDK to detect the second Bob's device
                    {
                        XCTAssertEqual(trust.trustedDevicesProgress.completedUnitCount, 1);
                        XCTAssertEqual(trust.trustedDevicesProgress.totalUnitCount, 2);
                        [expectation fulfill];
                    }
                }];
                [observers addObject:observer];
                
            });
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop
