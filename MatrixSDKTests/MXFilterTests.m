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

#import "MXRoomEventFilter.h"

@interface MXFilterTests : XCTestCase

@end

@implementation MXFilterTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testRoomEventFilterInitWithDictionary
{
    MXRoomEventFilter *roomEventFilter = [[MXRoomEventFilter alloc] initWithDictionary:
                                          @{
                                            @"limit": @(30),
                                            @"types": @[@"m.room.message"],
                                            @"not_types": @[@"m.room.not.message"],
                                            @"rooms": @[@"!726s6s6q:example.com"],
                                            @"not_rooms": @[@"!not726s6s6q:example.com"],
                                            @"senders": @[@"@hello:example.com"],
                                            @"not_senders": @[@"@spam:example.com"],
                                            @"contains_url": @(YES),

                                            // Not yet specified filter fiedld in matrix spec
                                             @"new_field": @"welcome"
                                            }];

    XCTAssertEqual(roomEventFilter.limit, 30);
    XCTAssertEqualObjects(roomEventFilter.types[0], @"m.room.message");
    XCTAssertEqualObjects(roomEventFilter.notTypes[0], @"m.room.not.message");
    XCTAssertEqualObjects(roomEventFilter.rooms[0], @"!726s6s6q:example.com");
    XCTAssertEqualObjects(roomEventFilter.notRooms[0], @"!not726s6s6q:example.com");
    XCTAssertEqualObjects(roomEventFilter.senders[0], @"@hello:example.com");
    XCTAssertEqualObjects(roomEventFilter.notSenders[0], @"@spam:example.com");
    XCTAssertTrue(roomEventFilter.containsURL);
    XCTAssertEqualObjects(roomEventFilter.dictionary[@"new_field"], @"welcome");
}

- (void)testRoomEventFilterInit
{
    MXRoomEventFilter *roomEventFilter = [[MXRoomEventFilter alloc] init];
    roomEventFilter.limit = 30;
    roomEventFilter.types = @[@"m.room.message"];
    roomEventFilter.notTypes = @[@"m.room.not.message"];
    roomEventFilter.rooms = @[@"!726s6s6q:example.com"];
    roomEventFilter.notRooms = @[@"!not726s6s6q:example.com"];
    roomEventFilter.senders = @[@"@hello:example.com"];
    roomEventFilter.notSenders = @[@"@spam:example.com"];
    roomEventFilter.containsURL = YES;

    NSDictionary *dictionary = @{
                                 @"limit": @(30),
                                 @"types": @[@"m.room.message"],
                                 @"not_types": @[@"m.room.not.message"],
                                 @"rooms": @[@"!726s6s6q:example.com"],
                                 @"not_rooms": @[@"!not726s6s6q:example.com"],
                                 @"senders": @[@"@hello:example.com"],
                                 @"not_senders": @[@"@spam:example.com"],
                                 @"contains_url": @(YES)
                                 };


    XCTAssertTrue([roomEventFilter.dictionary isEqualToDictionary:dictionary], @"%@/%@", roomEventFilter.dictionary, dictionary);
}

@end
