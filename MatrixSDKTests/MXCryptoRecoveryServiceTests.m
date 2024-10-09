/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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

#import "MXMemoryStore.h"

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"
#import "MatrixSDKTestsSwiftHeader.h"

@interface MXCryptoRecoveryServiceTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}

@end


@implementation MXCryptoRecoveryServiceTests

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


#pragma mark - Scenarii

// - Create Alice
// - Bootstrap cross-singing on Alice using password
- (void)doTestWithAliceWithCrossSigning:(XCTestCase*)testCase
                            readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:testCase andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

         // - Bootstrap cross-singing on Alice using password
         [aliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
             
             // Send a message to a have megolm key in the store
             MXRoom *room = [aliceSession roomWithRoomId:roomId];
             [room sendTextMessage:@"message" threadId:nil success:^(NSString *eventId) {
                 
                 readyToTest(aliceSession, roomId, expectation);
                 
             } failure:^(NSError *error) {
                 XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                 [expectation fulfill];
             }];
             
         } failure:^(NSError *error) {
             XCTFail(@"Cannot set up intial test conditions - error: %@", error);
             [expectation fulfill];
         }];
     }];
}

// - Create Alice
// - Bootstrap cross-singing on Alice using password
// - Setup key backup
- (void)doTestWithAliceWithCrossSigningAndKeyBackup:(XCTestCase*)testCase
                                        readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doTestWithAliceWithCrossSigning:testCase readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Setup key backup
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:nil success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                [aliceSession.crypto.backup backupAllGroupSessions:^{
                    
                    readyToTest(aliceSession, roomId, expectation);
                    
                } progress:nil failure:^(NSError * _Nonnull error) {
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
    }];
}


// Test bad recovery key string format
//
// - Have Alice with cross-signing bootstrapped
// - Call privateKeyFromRecoveryKey: with a badly formatted recovery key
// -> It must error with expected NSError domain and code
- (void)testBadRecoveryKeyFormat
{
    // - Have Alice with cross-signing bootstrapped
    [self doTestWithAliceWithCrossSigning:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRecoveryService *recoveryService = aliceSession.crypto.recoveryService;
        
        // Call privateKeyFromRecoveryKey: with a badly formatted recovery key
        NSError *error;
        NSData *wrongRecoveryKey = [recoveryService privateKeyFromRecoveryKey:@"Surely not a recovery key string" error:&error];
        
        // -> It must error with expected NSError domain and code
        XCTAssertNil(wrongRecoveryKey);
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(error.domain, MXRecoveryServiceErrorDomain);
        XCTAssertEqual(error.code, MXRecoveryServiceBadRecoveryKeyFormatErrorCode);
        
        [expectation fulfill];
    }];
}

@end
