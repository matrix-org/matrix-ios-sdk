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

- (void)testFilterInitWithDictionary
{
    MXFilter *filter = [[MXFilter alloc] initWithDictionary:
                                          @{
                                            @"limit": @(30),
                                            @"types": @[@"m.room.message"],
                                            @"not_types": @[@"m.room.not.message"],
                                            @"senders": @[@"@hello:example.com"],
                                            @"not_senders": @[@"@spam:example.com"],

                                            // Not yet specified filter field in matrix spec
                                            @"new_field": @"welcome"
                                            }];

    XCTAssertEqual(filter.limit, 30);
    XCTAssertEqualObjects(filter.types[0], @"m.room.message");
    XCTAssertEqualObjects(filter.notTypes[0], @"m.room.not.message");
    XCTAssertEqualObjects(filter.senders[0], @"@hello:example.com");
    XCTAssertEqualObjects(filter.notSenders[0], @"@spam:example.com");
    XCTAssertEqualObjects(filter.dictionary[@"new_field"], @"welcome");
}

- (void)testFilterInit
{
    MXFilter *filter = [[MXFilter alloc] init];
    filter.limit = 30;
    filter.types = @[@"m.room.message"];
    filter.notTypes = @[@"m.room.not.message"];
    filter.senders = @[@"@hello:example.com"];
    filter.notSenders = @[@"@spam:example.com"];

    NSDictionary *dictionary = @{
                                 @"limit": @(30),
                                 @"types": @[@"m.room.message"],
                                 @"not_types": @[@"m.room.not.message"],
                                 @"senders": @[@"@hello:example.com"],
                                 @"not_senders": @[@"@spam:example.com"]
                                 };

    XCTAssertTrue([filter.dictionary isEqualToDictionary:dictionary], @"%@/%@", filter.dictionary, dictionary);
}


- (void)testRoomEventFilterInitWithDictionary
{
    MXRoomEventFilter *filter = [[MXRoomEventFilter alloc] initWithDictionary:
                                          @{
                                            @"limit": @(30),
                                            @"types": @[@"m.room.message"],
                                            @"not_types": @[@"m.room.not.message"],
                                            @"rooms": @[@"!726s6s6q:example.com"],
                                            @"not_rooms": @[@"!not726s6s6q:example.com"],
                                            @"senders": @[@"@hello:example.com"],
                                            @"not_senders": @[@"@spam:example.com"],
                                            @"contains_url": @(YES),

                                            // Not yet specified filter field in matrix spec
                                             @"new_field": @"welcome"
                                            }];

    XCTAssertEqual(filter.limit, 30);
    XCTAssertEqualObjects(filter.types[0], @"m.room.message");
    XCTAssertEqualObjects(filter.notTypes[0], @"m.room.not.message");
    XCTAssertEqualObjects(filter.rooms[0], @"!726s6s6q:example.com");
    XCTAssertEqualObjects(filter.notRooms[0], @"!not726s6s6q:example.com");
    XCTAssertEqualObjects(filter.senders[0], @"@hello:example.com");
    XCTAssertEqualObjects(filter.notSenders[0], @"@spam:example.com");
    XCTAssertTrue(filter.containsURL);
    XCTAssertEqualObjects(filter.dictionary[@"new_field"], @"welcome");
}

- (void)testRoomEventFilterInit
{
    MXRoomEventFilter *filter = [[MXRoomEventFilter alloc] init];
    filter.limit = 30;
    filter.types = @[@"m.room.message"];
    filter.notTypes = @[@"m.room.not.message"];
    filter.rooms = @[@"!726s6s6q:example.com"];
    filter.notRooms = @[@"!not726s6s6q:example.com"];
    filter.senders = @[@"@hello:example.com"];
    filter.notSenders = @[@"@spam:example.com"];
    filter.containsURL = YES;

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

    XCTAssertTrue([filter.dictionary isEqualToDictionary:dictionary], @"%@/%@", filter.dictionary, dictionary);
}


- (void)testRoomFilterInitWithDictionary
{
    NSMutableArray<NSDictionary*> *roomEventFiltersDict = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4; i++)
    {
        [roomEventFiltersDict addObject:@{
                                          @"limit": @(i),
                                          @"types": @[@"m.room.message"],
                                          @"not_types": @[@"m.room.not.message"],
                                          @"rooms": @[@"!726s6s6q:example.com"],
                                          @"not_rooms": @[@"!not726s6s6q:example.com"],
                                          @"senders": @[@"@hello:example.com"],
                                          @"not_senders": @[@"@spam:example.com"],
                                          @"contains_url": @(YES)
                                          }];
    }

    MXRoomFilter *filter = [[MXRoomFilter alloc] initWithDictionary:
                                 @{
                                   @"rooms": @[@"!726s6s6q:example.com"],
                                   @"not_rooms": @[@"!not726s6s6q:example.com"],
                                   @"ephemeral": roomEventFiltersDict[0],
                                   @"include_leave": @(YES),
                                   @"state": roomEventFiltersDict[1],
                                   @"timeline": roomEventFiltersDict[2],
                                   @"account_data": roomEventFiltersDict[3],

                                   // Not yet specified filter field in matrix spec
                                   @"new_field": @"welcome"
                                   }];

    XCTAssertEqualObjects(filter.rooms[0], @"!726s6s6q:example.com");
    XCTAssertEqualObjects(filter.notRooms[0], @"!not726s6s6q:example.com");
    XCTAssertTrue([filter.ephemeral.dictionary isEqualToDictionary:roomEventFiltersDict[0]]);
    XCTAssertTrue(filter.includeLeave);
    XCTAssertTrue([filter.state.dictionary isEqualToDictionary:roomEventFiltersDict[1]]);
    XCTAssertTrue([filter.timeline.dictionary isEqualToDictionary:roomEventFiltersDict[2]]);
    XCTAssertTrue([filter.accountData.dictionary isEqualToDictionary:roomEventFiltersDict[3]]);
    XCTAssertEqualObjects(filter.dictionary[@"new_field"], @"welcome");
}

- (void)testEventFilterInit
{
    NSMutableArray<MXRoomEventFilter*> *roomEventFilters = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4; i++)
    {
        [roomEventFilters addObject:[[MXRoomEventFilter alloc] initWithDictionary:@{
                                                                                    @"limit": @(i),
                                                                                    @"types": @[@"m.room.message"],
                                                                                    @"not_types": @[@"m.room.not.message"],
                                                                                    @"rooms": @[@"!726s6s6q:example.com"],
                                                                                    @"not_rooms": @[@"!not726s6s6q:example.com"],
                                                                                    @"senders": @[@"@hello:example.com"],
                                                                                    @"not_senders": @[@"@spam:example.com"],
                                                                                    @"contains_url": @(YES)
                                                                                    }]];
    }

    MXRoomFilter *filter = [[MXRoomFilter alloc] init];
    filter.rooms = @[@"!726s6s6q:example.com"];
    filter.notRooms = @[@"!not726s6s6q:example.com"];
    filter.ephemeral = roomEventFilters[0];
    filter.includeLeave = YES;
    filter.state = roomEventFilters[1];
    filter.timeline = roomEventFilters[2];
    filter.accountData = roomEventFilters[3];

    NSDictionary *dictionary = @{
                                 @"rooms": @[@"!726s6s6q:example.com"],
                                 @"not_rooms": @[@"!not726s6s6q:example.com"],
                                 @"ephemeral": roomEventFilters[0].dictionary,
                                 @"include_leave": @(YES),
                                 @"state": roomEventFilters[1].dictionary,
                                 @"timeline": roomEventFilters[2].dictionary,
                                 @"account_data": roomEventFilters[3].dictionary
                                 };

    XCTAssertTrue([filter.dictionary isEqualToDictionary:dictionary], @"%@/%@", filter.dictionary, dictionary);
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

            XCTAssertNil(mxSession.syncFilterId);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop

