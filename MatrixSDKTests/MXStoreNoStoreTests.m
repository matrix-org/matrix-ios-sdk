/*
 Copyright 2015 OpenMarket Ltd

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

#import "MXNoStore.h"
#import "MXStoreTests.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXStoreNoStoreTests : MXStoreTests
@end

@implementation MXStoreNoStoreTests

- (void)doTestWithMXNoStore:(void (^)(MXRoom *room))readyToTest
{
    MXNoStore *store = [[MXNoStore alloc] init];
    [self doTestWithStore:store readyToTest:readyToTest];
}

- (void)doTestWithTwoUsersAndMXNoStore:(void (^)(MXRoom *room))readyToTest
{
    MXNoStore *store = [[MXNoStore alloc] init];
    [self doTestWithTwoUsersAndStore:store readyToTest:readyToTest];
}

- (void)doTestWithMXNoStoreAndMessagesLimit:(NSUInteger)messagesLimit readyToTest:(void (^)(MXRoom *room))readyToTest
{
    MXNoStore *store = [[MXNoStore alloc] init];
    [self doTestWithStore:store andMessagesLimit:messagesLimit readyToTest:readyToTest];
}


#pragma mark - MXNoStore tests
/* This feature is not available with MXNoStore
- (void)testMXNoStoreEventExistsWithEventId
{
    MXNoStore *store = [[MXNoStore alloc] init];
    [self checkEventExistsWithEventIdOfStore:store];
}

- (void)testMXNoStoreEventWithEventId
{
    MXNoStore *store = [[MXNoStore alloc] init];
    [self checkEventWithEventIdOfStore:store];
}
*/

- (void)testMXNoStorePaginateBack
{
    [self doTestWithMXNoStore:^(MXRoom *room) {
        [self checkPaginateBack:room];
    }];
}

- (void)testMXNoStorePaginateBackFilter
{
    [self doTestWithMXNoStore:^(MXRoom *room) {
        [self checkPaginateBackFilter:room];
    }];
}

- (void)testMXNoStorePaginateBackOrder
{
    [self doTestWithMXNoStore:^(MXRoom *room) {
        [self checkPaginateBackOrder:room];
    }];
}

- (void)testMXNoStorePaginateBackDuplicates
{
    [self doTestWithMXNoStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

- (void)testMXNoStorePaginateBackDuplicatesInRoomWithTwoUsers
{
    [self doTestWithMXNoStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

- (void)testMXNoStoreSeveralPaginateBacks
{
    [self doTestWithMXNoStore:^(MXRoom *room) {
        [self checkSeveralPaginateBacks:room];
    }];
}

- (void)testMXNoStoreCanPaginateFromHomeServer
{
    // Preload less messages than the room history counts so that there are still requests to the HS to do
    [self doTestWithMXNoStoreAndMessagesLimit:1 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromHomeServer:room];
    }];
}

- (void)testMXNoStoreCanPaginateFromMXStore
{
    // Preload more messages than the room history counts so that all messages are already loaded
    // room.liveTimeline.canPaginate will use [MXStore canPaginateInRoom]
    [self doTestWithMXNoStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromMXStore:room];
    }];
}

- (void)testMXNoStoreLastMessageAfterPaginate
{
    [self doTestWithMXNoStore:^(MXRoom *room) {
        [self checkLastMessageAfterPaginate:room];
    }];
}

- (void)testMXNoStorePaginateWhenJoiningAgainAfterLeft
{
    [self doTestWithMXNoStoreAndMessagesLimit:10 readyToTest:^(MXRoom *room) {
        [self checkPaginateWhenJoiningAgainAfterLeft:room];
    }];
}

- (void)testMXNoStorePaginateWhenReachingTheExactBeginningOfTheRoom
{
    [self doTestWithMXNoStore:^(MXRoom *room) {
        [self checkPaginateWhenReachingTheExactBeginningOfTheRoom:room];
    }];
}

@end

#pragma clang diagnostic pop
