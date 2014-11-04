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
#import "MXHTTPClient.h"

#import "MXJSONModel.h"


// Class for tests
@interface MXJSONModelTestClass : MXJSONModel

@end
@implementation MXJSONModelTestClass

@end



@interface MXJSONModelTests : XCTestCase
{
    MXHTTPClient *httpClient;
}
@end

@implementation MXJSONModelTests

- (void)setUp
{
    [super setUp];

    httpClient = [[MXHTTPClient alloc] initWithHomeServer:kMXTestsHomeServerURL];
}

- (void)tearDown
{
    httpClient = nil;
    
    [super tearDown];
}

- (void)testModelFromJSON
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        // Use publicRooms JSON response to check modelFromJSON
        [httpClient requestWithMethod:@"GET"
                                 path:@"publicRooms"
                           parameters:nil
                              success:^(NSDictionary *JSONResponse)
         {
             NSArray *chunk = JSONResponse[@"chunk"];
             
             MXPublicRoom *publicRoom = [MXPublicRoom modelFromJSON:chunk[0]];
             
             XCTAssert([publicRoom isKindOfClass:[MXPublicRoom class]]);
             XCTAssertNotNil(publicRoom.room_id);
             
             [expectation fulfill];
             
         } failure:^(NSError *error) {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];
    }];
}

- (void)testModelsFromJSON
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        // Use publicRooms JSON response to check modelFromJSON
        [httpClient requestWithMethod:@"GET"
                                 path:@"publicRooms"
                           parameters:nil
                              success:^(NSDictionary *JSONResponse)
         {
             NSArray *publicRooms = [MXPublicRoom modelsFromJSON:JSONResponse[@"chunk"]];
             XCTAssertNotNil(publicRooms);
             XCTAssertGreaterThanOrEqual(publicRooms.count, 1);
             
             MXPublicRoom *publicRoom = publicRooms[0];
             XCTAssert([publicRoom isKindOfClass:[MXPublicRoom class]]);
             XCTAssertNotNil(publicRoom.room_id);
             
             [expectation fulfill];
             
         } failure:^(NSError *error) {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];
    }];
}

- (void)testOthers
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        [httpClient requestWithMethod:@"GET"
                                 path:@"publicRooms"
                           parameters:nil
                              success:^(NSDictionary *JSONResponse)
         {
             NSArray *chunk = JSONResponse[@"chunk"];
             
             // Convert the JSON in a MXJSONModel class with no property
             // All values in the JSON must go into the MXJSONModel.others dictionary
             MXJSONModelTestClass *nonTypedObject = [MXJSONModelTestClass modelFromJSON:chunk[0]];
             XCTAssertNotNil(nonTypedObject.others);
             
             // Check expected keys for a MXPublicRoom JSON
             NSDictionary *others = nonTypedObject.others;
             XCTAssertNotNil(others[@"room_id"]);
             XCTAssertNotNil(others[@"name"]);
             XCTAssertNotNil(others[@"aliases"]);
             
             MXPublicRoom *publicRoom = [MXPublicRoom modelFromJSON:chunk[0]];
             XCTAssertNil(publicRoom.others, @"Each field of a publicRooms JSON response should be declared as property in MXPublicRoom.");
             
             [expectation fulfill];
             
         } failure:^(NSError *error) {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];
    }];

}


@end
