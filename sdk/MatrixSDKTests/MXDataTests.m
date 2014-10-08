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

#import "MatrixSDKTestsData.h"

#import "MXData.h"


// @TODO: Find an automatic way to test with an user account
#define MX_USER_ID @"@your_name:matrig.org"
#define MX_ACCESS_TOKEN @"your_access_token"

@interface MXDataTests : XCTestCase
{
    MXData *matrixData;
}
@end

@implementation MXDataTests

- (void)setUp
{
    [super setUp];

    MXSession *matrixSession = [[MXSession alloc] initWithHomeServer:kMXTestsHomeServerURL
                                                              userId:MX_USER_ID
                                                         accessToken:MX_ACCESS_TOKEN];
    
    matrixData = [[MXData alloc] initWithMatrixSession:matrixSession];
}

- (void)tearDown
{
    [matrixData close];
    matrixData = nil;
    
    [super tearDown];
}

- (void)testRecents
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [matrixData start:^{
        
        NSArray *recents = [matrixData recents];
        
        XCTAssert(0 < recents.count, @"There must be recents");
        
        for (MXEvent *event in recents)
        {
            XCTAssertNotNil(event.event_id, @"The event must have an event_id to be valid");
        }
        
        [expectation fulfill];
        
    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

@end
