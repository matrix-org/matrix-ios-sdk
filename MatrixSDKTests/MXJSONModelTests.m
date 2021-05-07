/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2021 The Matrix.org Foundation C.I.C
 
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
#import "MXHTTPClient.h"

#import "MXJSONModel.h"


@interface MXJSONModelTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    
    MXHTTPClient *httpClient;
}
@end

@implementation MXJSONModelTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];

    httpClient = [[MXHTTPClient alloc] initWithBaseURL:kMXTestsHomeServerURL
                     andOnUnrecognizedCertificateBlock:nil];
}

- (void)tearDown
{
    httpClient = nil;
    matrixSDKTestsData = nil;
    
    [super tearDown];
}

- (void)testModelFromJSON
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        // Use publicRooms JSON response to check modelFromJSON
        [httpClient requestWithMethod:@"GET"
                                 path:[NSString stringWithFormat:@"%@/publicRooms", kMXAPIPrefixPathR0]
                           parameters:nil
                              success:^(NSDictionary *JSONResponse)
         {
             NSArray *chunk = JSONResponse[@"chunk"];
             
             MXPublicRoom *publicRoom = [MXPublicRoom modelFromJSON:chunk[0]];
             
             XCTAssert([publicRoom isKindOfClass:[MXPublicRoom class]]);
             XCTAssertNotNil(publicRoom.roomId);
             
             [expectation fulfill];
             
         } failure:^(NSError *error) {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];
    }];
}

- (void)testModelsFromJSON
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        // Use publicRooms JSON response to check modelFromJSON
        [httpClient requestWithMethod:@"GET"
                                 path:[NSString stringWithFormat:@"%@/publicRooms", kMXAPIPrefixPathR0]
                           parameters:nil
                              success:^(NSDictionary *JSONResponse)
         {
             NSArray *publicRooms = [MXPublicRoom modelsFromJSON:JSONResponse[@"chunk"]];
             XCTAssertNotNil(publicRooms);
             XCTAssertGreaterThanOrEqual(publicRooms.count, 1);
             
             MXPublicRoom *publicRoom = publicRooms[0];
             XCTAssert([publicRoom isKindOfClass:[MXPublicRoom class]]);
             XCTAssertNotNil(publicRoom.roomId);
             
             [expectation fulfill];
             
         } failure:^(NSError *error) {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];
    }];
}

@end
