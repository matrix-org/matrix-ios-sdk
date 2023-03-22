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
 -> No cross-signing, no trust
 */
- (void)testNoCrossSigningNoTrust
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{

            // -> No cross-signing, no trust
            MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
            MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
            
            XCTAssertNotNil(trust);
            XCTAssertEqual(trust.trustedUsersProgress.totalUnitCount, 2);
            XCTAssertEqual(trust.trustedUsersProgress.completedUnitCount, 0);
            XCTAssertEqual(trust.trustedUsersProgress.fractionCompleted, 0);
            
            XCTAssertEqual(trust.trustedDevicesProgress.totalUnitCount, 0);
            XCTAssertEqual(trust.trustedDevicesProgress.completedUnitCount, 0);
            XCTAssertEqual(trust.trustedDevicesProgress.fractionCompleted, 0);

            [expectation fulfill];
        });
    }];
}

/**
 - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
 -> All should be green
 */
- (void)testAllTrusted
{
    // - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            
            // -> All should be green
            MXRoom *roomFromAlicePOV = [aliceSession1 roomWithRoomId:roomId];
            MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
            
            XCTAssertNotNil(trust);
            XCTAssertEqual(trust.trustedUsersProgress.totalUnitCount, 2);
            XCTAssertEqual(trust.trustedUsersProgress.completedUnitCount, 2);
            XCTAssertEqual(trust.trustedUsersProgress.fractionCompleted, 1);

            XCTAssertEqual(trust.trustedDevicesProgress.totalUnitCount, 3);
            XCTAssertEqual(trust.trustedDevicesProgress.completedUnitCount, 3);
            XCTAssertEqual(trust.trustedDevicesProgress.fractionCompleted, 1);

            [expectation fulfill];
        });
    }];
}

/**
 - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
 - Bob signs in on a new device
 -> Not all must be trusted.
 */
- (void)testNotFullyTrusted
{
    // - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession1, NSString *roomId, XCTestExpectation *expectation) {
        
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:bobSession1.matrixRestClient.credentials withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                
                // -> Not all must be trusted
                MXRoom *roomFromAlicePOV = [aliceSession1 roomWithRoomId:roomId];
                MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
                
                XCTAssertNotNil(trust);
                XCTAssertEqual(trust.trustedUsersProgress.totalUnitCount, 2);
                XCTAssertEqual(trust.trustedUsersProgress.completedUnitCount, 2);
                XCTAssertEqual(trust.trustedUsersProgress.fractionCompleted, 1);
                
                XCTAssertEqual(trust.trustedDevicesProgress.totalUnitCount, 4);
                XCTAssertEqual(trust.trustedDevicesProgress.completedUnitCount, 3);
                XCTAssertNotEqual(trust.trustedDevicesProgress.fractionCompleted, 1);

                [expectation fulfill];
            });
            
        }];
    }];
}

/**
 - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
 -> All must be trusted.
 - Bob signs in on a new device
 -> Alice must be notified there is no more 100% of trust in this room
 */
- (void)testTrustChangeAfterUserSignInOnNewDevice
{
    // - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession1, NSString *roomId, XCTestExpectation *expectation) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            
            // -> All must be trusted
            MXRoom *roomFromAlicePOV = [aliceSession1 roomWithRoomId:roomId];
            MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
            XCTAssertEqual(trust.trustedUsersProgress.fractionCompleted, 1);
            XCTAssertEqual(trust.trustedDevicesProgress.fractionCompleted, 1);
            
            // - Bob signs in on a new device
            [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:bobSession1.matrixRestClient.credentials withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
            }];
            
            // -> Alice must be notified there is no more 100% of trust in this room
            id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:roomFromAlicePOV.summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
                
                MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
                XCTAssertEqual(trust.trustedUsersProgress.fractionCompleted, 1);
                XCTAssertNotEqual(trust.trustedDevicesProgress.fractionCompleted, 1);
                
                [expectation fulfill];
            }];
            
            [observers addObject:observer];
        });
    }];
}

/**
 - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
 - Bob signs in on a new device
 -> Not all must be trusted.
 - Bob trusts the new device
 -> Alice must be notified for 100% of trust in this room
 */
- (void)testTrustChangeAfterUserCompleteSecurity
{
    // - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession1, NSString *roomId, XCTestExpectation *expectation) {
        
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:bobSession1.matrixRestClient.credentials withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                
                // -> Not all must be trusted
                MXRoom *roomFromAlicePOV = [aliceSession1 roomWithRoomId:roomId];
                MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
                XCTAssertEqual(trust.trustedUsersProgress.fractionCompleted, 1);
                XCTAssertNotEqual(trust.trustedDevicesProgress.fractionCompleted, 1);
                
                // - Bob trusts the new device
                [bobSession1.crypto setDeviceVerification:MXDeviceVerified forDevice:bobSession2.myDeviceId ofUser:bobSession2.myUserId success:^{
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
                
                // -> Alice must be notified for 100% of trust in this room
                id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:roomFromAlicePOV.summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
                    
                    MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
                    if (trust.trustedDevicesProgress.fractionCompleted == 1)   // It could take for the SDK to update the trust right
                    {
                        XCTAssertEqual(trust.trustedUsersProgress.fractionCompleted, 1);
                        XCTAssertEqual(trust.trustedDevicesProgress.fractionCompleted, 1);
                        [expectation fulfill];
                    }
                }];

                [observers addObject:observer];
            });
        }];
    }];
}

/**
 - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
 -> All must be trusted.
 - Bob rotates their cross-signing
 -> Alice must be notified there is no more 100% of trust in this room
 */
- (void)testTrustChangeAfterUserRotateMSK
{
    // - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession1, NSString *roomId, XCTestExpectation *expectation) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            
            // -> All must be trusted
            MXRoom *roomFromAlicePOV = [aliceSession1 roomWithRoomId:roomId];
            MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
            XCTAssertEqual(trust.trustedUsersProgress.fractionCompleted, 1);
            XCTAssertEqual(trust.trustedDevicesProgress.fractionCompleted, 1);
            
            // - Bob rotates their cross-signing
            [bobSession1.crypto.crossSigning setupWithPassword:MXTESTS_BOB_PWD success:^{
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
            
            // -> Alice must be notified there is no more 100% of trust in this room
            id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:roomFromAlicePOV.summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
                
                MXUsersTrustLevelSummary *trust = roomFromAlicePOV.summary.trust;
                XCTAssertNotEqual(trust.trustedUsersProgress.fractionCompleted, 1);
                XCTAssertEqual(trust.trustedDevicesProgress.fractionCompleted, 1);      // 100% Because all devices of trusted users are verified
                
                [expectation fulfill];
            }];
            
            [observers addObject:observer];
        });
    }];
}

/**
 Test that we do not send too much kMXRoomSummaryDidChangeNotification.
 
 Test for https://github.com/vector-im/riot-ios/issues/3121 (Too much MXDeviceInfoTrustLevelDidChangeNotification
 and MXCrossSigningInfoTrustLevelDidChangeNotification).
 
 - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
 - Alice re-download all keys
 -> Alice must not be notified for more trust changes
 */
- (void)testNoExtraTrustLevelDidChangeNotifications
{
    // - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Alice download all keys
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            
            MXRoom *roomFromAlicePOV = [aliceSession1 roomWithRoomId:roomId];
            
            // - Alice re-download all keys
            [aliceSession1.crypto downloadKeys:@[aliceSession1.myUserId, bobSession.myUserId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                // Wait a bit
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    [expectation fulfill];
                });
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
            
            // -> Alice must not be notified for more trust changes
            id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:roomFromAlicePOV.summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
                
                XCTFail(@"They must be no more trust changes");
            }];
            [observers addObject:observer];
        });
    }];
}

/**
 Test MXRoomSummary.enableTrustTracking(enable:)
 
 - Disable computeE2ERoomSummaryTrust
 - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
 -> Trust must not be automatically computed
 - Enable trust computation
 -> Trust be available and everything should be green
 */
- (void)testEnableTrustTracking
{
    // - Disable computeE2ERoomSummaryTrust
    [MXSDKOptions sharedInstance].computeE2ERoomSummaryTrust = NO;
    
    // - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            
            // -> Trust must not be automatically computed
            MXRoomSummary *roomSummaryFromAlicePOV = [aliceSession1 roomWithRoomId:roomId].summary;
            MXUsersTrustLevelSummary *trust = roomSummaryFromAlicePOV.trust;
            XCTAssertNil(trust);

            // - Enable trust computation
            [roomSummaryFromAlicePOV enableTrustTracking:YES];
            
            id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:roomSummaryFromAlicePOV queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
                
                // -> Trust be available and everything should be green
                MXUsersTrustLevelSummary *trust = roomSummaryFromAlicePOV.trust;
                XCTAssertEqual(trust.trustedUsersProgress.fractionCompleted, 1);
                XCTAssertEqual(trust.trustedDevicesProgress.fractionCompleted, 1);
                
                [expectation fulfill];
            }];
            
            [observers addObject:observer];
        });
    }];
}

@end

#pragma clang diagnostic pop
