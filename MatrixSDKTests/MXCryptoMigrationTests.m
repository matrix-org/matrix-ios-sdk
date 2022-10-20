// 
// Copyright 2020 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <XCTest/XCTest.h>

#import "MXCryptoMigration.h"

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"
#import "MXCrypto_Private.h"
#import "MatrixSDKTestsSwiftHeader.h"


@interface MXCryptoMigration ()

- (void)migrateToCryptoVersion2:(void (^)(void))success failure:(void (^)(NSError *))failure;
- (void)claimOwnOneTimeKeys:(NSUInteger)keyCount success:(void (^)(NSUInteger keyClaimed))success failure:(void (^)(NSError *))failure;

@end


@interface MXCryptoMigrationTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}
@end


@implementation MXCryptoMigrationTests

- (void)setUp
{
    [super setUp];
    
    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;
    
    [super tearDown];
}

/**
 Test shouldMigrate.
 
 - Have Alice
 -> There is no need to migrate on a fresh login
 */
- (void)testShouldMigrate
{
    // - Have Alice
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {
        
        MXCryptoMigration *cryptoMigration = [[MXCryptoMigration alloc] initWithCrypto:aliceSession.crypto];

        // -> There is no need to migrate on a fresh login
        XCTAssertFalse([cryptoMigration shouldMigrate]);
        
        [expectation fulfill];
    }];
}

/**
 Test migration to MXCryptoVersion2, which purges all published one time keys.
 
 - Alice and Bob are in a room
 - Consume some one time keys to check later that the migration actually completes after having uploading the fresh 50 OTKs
 - Bob does a migration
 -> Bob must have 50 OTKs available again
 - Alice sends a message (it will use an olm session based one of those new OTKs)
 -> Bob must be able to decrypt the message
 */
- (void)testMigrationToMXCryptoVersion2
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXCryptoMigration *bobCryptoMigration = [[MXCryptoMigration alloc] initWithCrypto:bobSession.crypto];
        
        // - Consume some one time keys to check later that the migration actually completes after having uploading the fresh 50 OTKs
        [bobCryptoMigration claimOwnOneTimeKeys:3 success:^(NSUInteger keyClaimed) {
            XCTAssertEqual(keyClaimed, 3);
            
            // - Bob does a migration
            [bobCryptoMigration migrateToCryptoVersion2:^{
                
                // -> Bob must have 50 OTKs available again
                [bobSession.legacyCrypto publishedOneTimeKeysCount:^(NSUInteger publishedKeyCount) {
                    
                    XCTAssertEqual(publishedKeyCount, 50);
                    
                    // - Alice sends a message (it will use an olm session based one of those new OTKs)
                    NSString *messageFromAlice = @"Hello I'm Alice!";
                    
                    MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
                    MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
                    
                    XCTAssert(roomFromBobPOV.summary.isEncrypted);
                    XCTAssert(roomFromAlicePOV.summary.isEncrypted);
                    
                    [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                        
                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                            
                            // -> Bob must be able to decrypt the message
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                            XCTAssertNil(event.decryptionError);
                            
                            [expectation fulfill];
                        }];
                    }];
                    
                    [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

@end
