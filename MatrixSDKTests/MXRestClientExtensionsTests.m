// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXSession.h"
#import "MatrixSDKSwiftHeader.h"


@interface MXRestClientExtensionsTests : XCTestCase
{
    MatrixSDKTestsData *testData;
    MatrixSDKTestsE2EData *e2eTestData;
}

@end

@implementation MXRestClientExtensionsTests

- (void)setUp
{
    [super setUp];
    
    testData = [[MatrixSDKTestsData alloc] init];
    e2eTestData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:testData];
}

- (void)tearDown
{
    testData = nil;
    e2eTestData = nil;
    
    [super tearDown];
}


- (void)createScenario:(void(^)(MXSession *aliceSession, MXSession *bobSession, MXSession *samSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    // - Have 3 people in an e2e room
    [e2eTestData doE2ETestWithAliceAndBobAndSamInARoom:self cryptedBob:YES cryptedSam:YES warnOnUnknowDevices:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *samSession, NSString *roomId, XCTestExpectation *expectation) {
        
        [aliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
            [bobSession.crypto.crossSigning setupWithPassword:MXTESTS_BOB_PWD success:^{
                readyToTest(aliceSession, bobSession, samSession, roomId, expectation);
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 Test downloadKeysByChunkForUsers with small chunks
 
 - Have 3 people in an e2e room
 - Get users keys in the normal way
 - Get them from small chunks
 -> Result must be the same
 */
- (void)testDownloadKeysByChunkForUsers
{
    // - Have 3 people in an e2e room
    [self createScenario:^(MXSession *aliceSession, MXSession *bobSession, MXSession *samSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSArray *userIds = @[aliceSession.myUserId, bobSession.myUserId, samSession.myUserId];
        
        // - Get users keys in the normal way
        [aliceSession.matrixRestClient downloadKeysForUsers:userIds token:nil success:^(MXKeysQueryResponse *keysQueryResponse) {
            XCTAssertEqual(keysQueryResponse.deviceKeys.userIds.count, userIds.count);
            
            // - Get them from small chunks
            MXHTTPOperation *operation = [aliceSession.matrixRestClient downloadKeysByChunkForUsers:userIds token:nil chunkSize:1 success:^(MXKeysQueryResponse * _Nonnull chunkedKeysQueryResponse) {
                
                // -> Result must be the same
                XCTAssertEqualObjects(keysQueryResponse.deviceKeys.map, chunkedKeysQueryResponse.deviceKeys.map);
                XCTAssertEqualObjects(keysQueryResponse.failures, chunkedKeysQueryResponse.failures);
                
                for (NSString *userId in keysQueryResponse.crossSigningKeys)
                {
                    MXCrossSigningInfo *crossSigningKeys = keysQueryResponse.crossSigningKeys[userId];
                    MXCrossSigningInfo *chunkedCrossSigningKeys = chunkedKeysQueryResponse.crossSigningKeys[userId];
                    
                    XCTAssertEqualObjects(crossSigningKeys.masterKeys.signalableJSONDictionary, chunkedCrossSigningKeys.masterKeys.signalableJSONDictionary);
                    XCTAssertEqualObjects(crossSigningKeys.userSignedKeys.signalableJSONDictionary, chunkedCrossSigningKeys.userSignedKeys.signalableJSONDictionary);
                    XCTAssertEqualObjects(crossSigningKeys.selfSignedKeys.signalableJSONDictionary, chunkedCrossSigningKeys.selfSignedKeys.signalableJSONDictionary);
                }
                
                [expectation fulfill];
                
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            XCTAssertNotNil(operation);
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 Test downloadKeysByChunkForUsers with small chunks
 
 - Have 3 people in an e2e room
 - Get users keys in the normal way
 - Get them from a big chunk request
 -> Result must be the same
 */
- (void)testDownloadKeysByOneChunkForUsers
{
    // - Have 3 people in an e2e room
    [self createScenario:^(MXSession *aliceSession, MXSession *bobSession, MXSession *samSession, NSString *roomId, XCTestExpectation *expectation) {

        NSArray *userIds = @[aliceSession.myUserId, bobSession.myUserId, samSession.myUserId];
        
        // - Get users keys in the normal way
        [aliceSession.matrixRestClient downloadKeysForUsers:userIds token:nil success:^(MXKeysQueryResponse *keysQueryResponse) {
            XCTAssertEqual(keysQueryResponse.deviceKeys.userIds.count, userIds.count);
            
            // - Get them from a big chunk request
            MXHTTPOperation *operation = [aliceSession.matrixRestClient downloadKeysByChunkForUsers:userIds token:nil chunkSize:250 success:^(MXKeysQueryResponse * _Nonnull chunkedKeysQueryResponse) {
                
                // -> Result must be the same
                XCTAssertEqualObjects(keysQueryResponse.deviceKeys.map, chunkedKeysQueryResponse.deviceKeys.map);
                XCTAssertEqualObjects(keysQueryResponse.failures, chunkedKeysQueryResponse.failures);
                
                for (NSString *userId in keysQueryResponse.crossSigningKeys)
                {
                    MXCrossSigningInfo *crossSigningKeys = keysQueryResponse.crossSigningKeys[userId];
                    MXCrossSigningInfo *chunkedCrossSigningKeys = chunkedKeysQueryResponse.crossSigningKeys[userId];
                    
                    XCTAssertEqualObjects(crossSigningKeys.masterKeys.signalableJSONDictionary, chunkedCrossSigningKeys.masterKeys.signalableJSONDictionary);
                    XCTAssertEqualObjects(crossSigningKeys.userSignedKeys.signalableJSONDictionary, chunkedCrossSigningKeys.userSignedKeys.signalableJSONDictionary);
                    XCTAssertEqualObjects(crossSigningKeys.selfSignedKeys.signalableJSONDictionary, chunkedCrossSigningKeys.selfSignedKeys.signalableJSONDictionary);
                }
                
                [expectation fulfill];
                
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            XCTAssertNotNil(operation);
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 Test cancel on downloadKeysByChunkForUsers
 
 - Have 3 people in an e2e room
 - Get users keys in the normal way
 - Get them from a big chunk request
 -> Result must be the same
 */
- (void)testDownloadKeysForUsersCancel
{
    // - Have 3 people in an e2e room
    [self createScenario:^(MXSession *aliceSession, MXSession *bobSession, MXSession *samSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSArray *userIds = @[aliceSession.myUserId, bobSession.myUserId, samSession.myUserId];
        
        
        // - Get them from a big chunk request
        MXHTTPOperation *operation = [aliceSession.matrixRestClient downloadKeysByChunkForUsers:userIds token:nil chunkSize:1 success:^(MXKeysQueryResponse * _Nonnull chunkedKeysQueryResponse) {
            XCTFail(@"Operation was cancelled. Completions block must not be called");
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            [expectation fulfill];
        }];
        
        [operation cancel];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [expectation fulfill];
        });
    }];
}

@end
