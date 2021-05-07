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


@interface MXJSONModelUnitTests : XCTestCase
@end

@implementation MXJSONModelUnitTests

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
