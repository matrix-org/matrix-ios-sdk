/*
 Copyright 2014 OpenMarket Ltd
 
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

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MXHTTPClient.h"
#import "MXError.h"

#import "MatrixSDKTestsData.h"

@interface MXHTTPClientTests : XCTestCase

@end

@implementation MXHTTPClientTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}


- (void)testMainThread {

    MXHTTPClient *hsClient = [[MXHTTPClient alloc] initWithHomeServer:kMXTestsHomeServerURL];

    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [hsClient requestWithMethod:@"GET"
                           path:@"publicRooms"
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         XCTAssertTrue([NSThread isMainThread], @"The block callback must be called from the main thread");
         [expectation fulfill];
     }
                        failure:^(NSError *error)
     {
         XCTFail(@"The request should not fail - NSError: %@", error);
         [expectation fulfill];
     }];

    [self waitForExpectationsWithTimeout:10000 handler:nil];
}


- (void)testMXError {
    
    MXHTTPClient *hsClient = [[MXHTTPClient alloc] initWithHomeServer:kMXTestsHomeServerURL];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [hsClient requestWithMethod:@"GET"
                           path:@"notExistingAPI"
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         XCTFail(@"The request must fail as the API path does not exist");
         [expectation fulfill];
     }
                        failure:^(NSError *error)
     {
         XCTAssertTrue([MXError isMXError:error], @"The HTTP client must have detected a Home Server error");
   
         XCTAssertTrue([NSThread isMainThread], @"The block callback must be called from the main thread");
         
         [expectation fulfill];
     }];
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)testNSError {
    
    MXHTTPClient *hsClient = [[MXHTTPClient alloc] initWithHomeServer:[NSString stringWithFormat:@"%@/non-existing-path", kMXTestsHomeServerURL]];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [hsClient requestWithMethod:@"GET"
                           path:@"publicRooms"
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         XCTFail(@"The request must fail as we are not targetting a home server");
         [expectation fulfill];
     }
                        failure:^(NSError *error)
     {
         XCTAssertFalse([MXError isMXError:error], @"The HTTP client must not have detected a Home Server error");
         
         XCTAssertTrue([NSThread isMainThread], @"The block callback must be called from the main thread");

         [expectation fulfill];
     }];
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

@end
