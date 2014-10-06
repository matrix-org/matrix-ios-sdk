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

#import "MXRestClient.h"
#import "MXError.h"

#define MX_HOMESERVER_URL @"http://matrix.org"
#define MX_NOT_A_HOMESERVER_URL @"http://matrix.org/non-existing-path"

@interface MXRestClientTests : XCTestCase

@end

@implementation MXRestClientTests

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

- (void)testMXError {
    
    MXRestClient *hsClient = [[MXRestClient alloc] initWithHomeServer:MX_HOMESERVER_URL];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [hsClient requestWithMethod:@"GET"
                           path:@"notExistingAPI"
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         XCTAssert(NO, @"The request must fail as the API path does not exist");
         [expectation fulfill];
     }
                        failure:^(NSError *error)
     {
         XCTAssert([MXError isMXError:error], @"The HTTP client must have detected a Home Server error");
         
         [expectation fulfill];
     }];
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)testNSError {
    
    MXRestClient *hsClient = [[MXRestClient alloc] initWithHomeServer:MX_NOT_A_HOMESERVER_URL];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [hsClient requestWithMethod:@"GET"
                           path:@"publicRooms"
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         XCTAssert(NO, @"The request must fail as we are not targetting a home server");
         [expectation fulfill];
     }
                        failure:^(NSError *error)
     {
         XCTAssert(NO == [MXError isMXError:error], @"The HTTP client must not have detected a Home Server error");
         
         [expectation fulfill];
     }];
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

@end
