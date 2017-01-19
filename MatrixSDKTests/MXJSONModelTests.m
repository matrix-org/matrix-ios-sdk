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


@interface MXJSONModelTestClass64Bits : MXJSONModel

@property (nonatomic) uint64_t ts;

@end
@implementation MXJSONModelTestClass64Bits

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXJSONModelTestClass64Bits *o = [[MXJSONModelTestClass64Bits alloc] init];
    if (o)
    {
        MXJSONModelSetUInt64(o.ts, JSONDictionary[@"ts"]);
    }

    return o;
}

@end

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

- (void)testRemoveNullValuesInJSON
{
    NSDictionary *JSONDict = @{@"foo" : [NSNull null],
                               @"John" : @"Doe",
                               @"toons" : @{@"Mickey" : @"Mouse",
                                             @"Donald" : @"Duck",
                                             @"Pluto" : [NSNull null]},
                               @"dict1" : @{@"dict2" : @{@"key" : [NSNull null]}}
                               };

    NSDictionary *cleanDict = [MXJSONModel removeNullValuesInJSON:JSONDict];
    XCTAssertNil(cleanDict[@"foo"], @"JSON null value must be removed. Found: %@", cleanDict[@"foo"]);
    XCTAssertNotNil(cleanDict[@"John"], @"JSON null value must be removed. Found: %@", cleanDict[@"John"]);
    XCTAssertNil(cleanDict[@"toons"][@"Pluto"], @"JSON null value must be removed. Found: %@", cleanDict[@"toons"][@"Pluto"]);
    XCTAssert(((NSDictionary*)cleanDict[@"dict1"][@"dict2"]).count == 0, @"JSON null value must be removed. Found: %@", cleanDict[@"dict1"][@"dict2"]);
}

- (void)test64BitsValue
{
    NSDictionary *JSONDict = @{
                               @"ts" : [NSNumber numberWithLongLong:1414159014100]
                               };
    
    MXJSONModelTestClass64Bits *model = [MXJSONModelTestClass64Bits modelFromJSON:JSONDict];
    
    XCTAssertEqual(model.ts, 1414159014100, @"The 64bits value must be 1414159014100. Found: %lld", model.ts);
}

@end
