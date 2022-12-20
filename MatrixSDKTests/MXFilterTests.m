/*
 Copyright 2018 New Vector Ltd

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

#import "MXFilter.h"
#import "MXRoomEventFilter.h"
#import "MXRoomFilter.h"

#import "MXNoStore.h"
#import "MXFileStore.h"


// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXFilterTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}

@end

@implementation MXFilterTests

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

// - Create a session with MXNoStore
// - Create a filter
// - Get it back
// - Compare them
- (void)testFilterAPI
{
    [matrixSDKTestsData doMXSessionTestWithBob:self andStore:[MXNoStore new] readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        MXFilterJSONModel *filter = [MXFilterJSONModel syncFilterWithMessageLimit:0];

        MXHTTPOperation *operation = [mxSession setFilter:filter success:^(NSString *filterId) {

            XCTAssertNotNil(filterId);

            MXHTTPOperation *operation2 = [mxSession filterWithFilterId:filterId success:^(MXFilterJSONModel *filter2) {

                XCTAssertEqualObjects(filter, filter2);
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            XCTAssertNotNil(operation2.operation, @"An HTTP request should have been made");

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        XCTAssert(operation.operation, @"An HTTP request should have been made");
    }];
}

// - Create a session with MXNFileStore
// - Create a filter
// - Get it back (no HTTP should have been done)
// - Create it again (no HTTP should have been done)
// - Compare them
- (void)testFilterCache
{
    MXFileStore *store = [MXFileStore new];

    [matrixSDKTestsData doMXSessionTestWithBob:self andStore:store readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        // Make a random request to wake up the store so that next requests will be
        // more synchronousish and easier to test
        [mxSession filterWithFilterId:@"aFakeFilterId" success:nil failure:^(NSError *error) {

            MXFilterJSONModel *filter = [MXFilterJSONModel syncFilterWithMessageLimit:0];

            MXHTTPOperation *operation = [mxSession setFilter:filter success:^(NSString *filterId) {

                XCTAssertNotNil(filterId);

                MXHTTPOperation *operation2 = [mxSession setFilter:filter success:^(NSString *filterId2) {

                    XCTAssertNotNil(filterId);
                    XCTAssertEqualObjects(filterId, filterId2);

                    MXHTTPOperation *operation3 = [mxSession filterWithFilterId:filterId success:^(MXFilterJSONModel *filter2) {

                        XCTAssertEqualObjects(filter, filter2);
                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                    XCTAssertNil(operation3.operation, @"No HTTP request is required for filter already created");

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

                XCTAssertNil(operation2.operation, @"No HTTP request is required for filter already created");

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            XCTAssert(operation.operation, @"An HTTP request should have been made");

        }];
    }];
}

// Check that filter data is permanent
- (void)testFilterPermanentStorage
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession setStore:[MXFileStore new] success:^{

            MXFilterJSONModel *filter = [MXFilterJSONModel syncFilterWithMessageLimit:12];

            [mxSession startWithSyncFilter:filter onServerSyncDone:^{

                NSString *syncFilterId = mxSession.syncFilterId;
                XCTAssertNotNil(syncFilterId);

                [mxSession close];

                // Check data directly in the store
                MXFileStore *fileStore = [MXFileStore new];
                [fileStore openWithCredentials:bobRestClient.credentials onComplete:^{

                    NSString *filterId = fileStore.syncFilterId;
                    XCTAssertNotNil(filterId);
                    XCTAssertEqualObjects(syncFilterId, filterId);

                    [fileStore filterWithFilterId:syncFilterId success:^(MXFilterJSONModel * _Nullable filter2) {

                        XCTAssertNotNil(filter2);
                        XCTAssertEqualObjects(filter, filter2);
                        XCTAssertEqualObjects(fileStore.allFilterIds, @[syncFilterId]);

                        [expectation fulfill];

                    } failure:^(NSError * _Nullable error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError * _Nullable error) {
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

// Check MXSession start if the passed filter is not supported by the homeserver
- (void)testUnsupportedSyncFilter
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        MXFilterJSONModel *badFilter = [MXFilterJSONModel modelFromJSON:@{
                                                                          @"room": @{
                                                                                  @"say": @"hello"
                                                                                  }
                                                                          }];

        [mxSession startWithSyncFilter:badFilter onServerSyncDone:^{

            // https://github.com/matrix-org/synapse/pull/14369
            XCTAssertTrue([mxSession.syncFilterId isEqualToString:@"0"]);
            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop

