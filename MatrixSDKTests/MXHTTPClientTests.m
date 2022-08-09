/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MXHTTPClient.h"
#import "MXError.h"

#import "MatrixSDKTestsData.h"

@interface MXHTTPClientTests : XCTestCase

@end

@implementation MXHTTPClientTests


- (void)testMainThread
{
    MXHTTPClient *httpClient = [[MXHTTPClient alloc] initWithBaseURL:kMXTestsHomeServerURL
                                   andOnUnrecognizedCertificateBlock:nil];

    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [httpClient requestWithMethod:@"GET"
                             path:[NSString stringWithFormat:@"%@/publicRooms", kMXAPIPrefixPathR0]
                       parameters:nil
                          success:^(NSDictionary *JSONResponse) {
                              XCTAssertTrue([NSThread isMainThread], @"The block callback must be called from the main thread");
                              [expectation fulfill];
                          }
                          failure:^(NSError *error) {
                              XCTFail(@"The request should not fail - NSError: %@", error);
                              [expectation fulfill];
                          }];
    
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testCancel
{
    MXHTTPClient *httpClient = [[MXHTTPClient alloc] initWithBaseURL:kMXTestsHomeServerURL
                                   andOnUnrecognizedCertificateBlock:nil];

    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    MXHTTPOperation *operation = [httpClient requestWithMethod:@"GET"
                             path:@"publicRooms"
                       parameters:nil
                          success:^(NSDictionary *JSONResponse) {
                              XCTFail(@"A canceled request should not complete");
                              [expectation fulfill];
                          }
                          failure:^(NSError *error) {
                              [expectation fulfill];
                          }];

    [operation cancel];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testMXError
{
    MXHTTPClient *httpClient = [[MXHTTPClient alloc] initWithBaseURL:kMXTestsHomeServerURL
                                   andOnUnrecognizedCertificateBlock:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [httpClient requestWithMethod:@"GET"
                             path:[NSString stringWithFormat:@"%@/notExistingAPI", kMXAPIPrefixPathR0]
                       parameters:nil
                          success:^(NSDictionary *JSONResponse) {
                              XCTFail(@"The request must fail as the API path does not exist");
                              [expectation fulfill];
                          }
                          failure:^(NSError *error) {
                              XCTAssertTrue([MXError isMXError:error], @"The HTTP client must have detected a Home Server error");
                              XCTAssertTrue([NSThread isMainThread], @"The block callback must be called from the main thread");

                              MXError *mxError = [[MXError alloc] initWithNSError:error];
                              XCTAssertNotNil(mxError.httpResponse);
                              XCTAssertEqual(mxError.httpResponse.statusCode, 400);

                              [expectation fulfill];
                          }];
    
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testNSError
{
    MXHTTPClient *httpClient = [[MXHTTPClient alloc] initWithBaseURL:[NSString stringWithFormat:@"%@/non-existing-path", kMXTestsHomeServerURL]
                                   andOnUnrecognizedCertificateBlock:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [httpClient requestWithMethod:@"GET"
                             path:@"publicRooms"
                       parameters:nil
                          success:^(NSDictionary *JSONResponse) {
                              XCTFail(@"The request must fail as we are not targetting a home server");
                              [expectation fulfill];
                          }
                          failure:^(NSError *error) {
                              XCTAssertFalse([MXError isMXError:error], @"The HTTP client must not have detected a Home Server error");
                              
                              XCTAssertTrue([NSThread isMainThread], @"The block callback must be called from the main thread");
                              
                              [expectation fulfill];
                          }];
    
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testTimeForRetry
{
    XCTAssertNotEqual([MXHTTPClient timeForRetry:nil], [MXHTTPClient timeForRetry:nil], @"[MXHTTPClient timeForRetry] cannot return the same value twice");
}

@end
