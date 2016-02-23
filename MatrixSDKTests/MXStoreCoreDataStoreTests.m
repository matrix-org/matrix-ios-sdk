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

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MXCoreDataStore.h"
#import "MXStoreTests.h"

#ifdef MXCOREDATA_STORE

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXStoreCoreDataStoreTests : MXStoreTests
@end

@implementation MXStoreCoreDataStoreTests

- (void)doTestWithMXCoreDataStore:(void (^)(MXRoom *room))readyToTest
{
    MXCoreDataStore *store = [[MXCoreDataStore alloc] init];
    [self doTestWithStore:store readyToTest:readyToTest];
}

- (void)doTestWithTwoUsersAndMXCoreDataStore:(void (^)(MXRoom *room))readyToTest
{
    MXCoreDataStore *store = [[MXCoreDataStore alloc] init];
    [self doTestWithTwoUsersAndStore:store readyToTest:readyToTest];
}

- (void)doTestWithMXCoreDataStoreAndMessagesLimit:(NSUInteger)messagesLimit readyToTest:(void (^)(MXRoom *room))readyToTest
{
    MXCoreDataStore *store = [[MXCoreDataStore alloc] init];
    [self doTestWithStore:store andMessagesLimit:messagesLimit readyToTest:readyToTest];
}


#pragma mark - MXCoreDataStore
- (void)testMXCoreDataStoreEventExistsWithEventId
{
    MXCoreDataStore *store = [[MXCoreDataStore alloc] init];
    [self checkEventExistsWithEventIdOfStore:store];
}

- (void)testMXCoreDataStoreEventWithEventId
{
    MXCoreDataStore *store = [[MXCoreDataStore alloc] init];
    [self checkEventWithEventIdOfStore:store];
}

- (void)testMXCoreDataStorePaginateBack
{
    [self doTestWithMXCoreDataStore:^(MXRoom *room) {
        [self checkPaginateBack:room];
    }];
}

- (void)testMXCoreDataStorePaginateBackFilter
{
    [self doTestWithMXCoreDataStore:^(MXRoom *room) {
        [self checkPaginateBackFilter:room];
    }];
}

- (void)testMXCoreDataStorePaginateBackOrder
{
    [self doTestWithMXCoreDataStore:^(MXRoom *room) {
        [self checkPaginateBackOrder:room];
    }];
}

- (void)testMXCoreDataStorePaginateBackDuplicates
{
    [self doTestWithMXCoreDataStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

// This test illustrates bug SYIOS-9
- (void)testMXCoreDataStorePaginateBackDuplicatesInRoomWithTwoUsers
{
    [self doTestWithTwoUsersAndMXCoreDataStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

- (void)testMXCoreDataStoreSeveralPaginateBacks
{
    [self doTestWithMXCoreDataStore:^(MXRoom *room) {
        [self checkSeveralPaginateBacks:room];
    }];
}

- (void)testMXCoreDataStorePaginateWithLiveEvents
{
    [self doTestWithMXCoreDataStore:^(MXRoom *room) {
        [self checkPaginateWithLiveEvents:room];
    }];
}

- (void)testMXCoreDataStoreCanPaginateFromHomeServer
{
    // Preload less messages than the room history counts so that there are still requests to the HS to do
    [self doTestWithMXCoreDataStoreAndMessagesLimit:1 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromHomeServer:room];
    }];
}

- (void)testMXCoreDataStoreCanPaginateFromMXStore
{
    // Preload more messages than the room history counts so that all messages are already loaded
    // room.liveTimeline.canPaginate will use [MXStore canPaginateInRoom]
    [self doTestWithMXCoreDataStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromMXStore:room];
    }];
}

- (void)testMXCoreDataStoreLastMessageAfterPaginate
{
    [self doTestWithMXCoreDataStore:^(MXRoom *room) {
        [self checkLastMessageAfterPaginate:room];
    }];
}

- (void)testMXCoreDataStorePaginateWhenJoiningAgainAfterLeft
{
    [self doTestWithMXCoreDataStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkPaginateWhenJoiningAgainAfterLeft:room];
    }];
}

- (void)testMXCoreDataStoreAndHomeServerPaginateWhenJoiningAgainAfterLeft
{
    // Not preloading all messages of the room causes a duplicated event issue with MXCoreDataStore
    // See `testMXCoreDataStorePaginateBackDuplicatesInRoomWithTwoUsers`.
    // Check here if MXCoreDataStore is able to filter this duplicate
    [self doTestWithMXCoreDataStoreAndMessagesLimit:10 readyToTest:^(MXRoom *room) {
        [self checkPaginateWhenJoiningAgainAfterLeft:room];
    }];
}

- (void)testMXCoreDataStorePaginateWhenReachingTheExactBeginningOfTheRoom
{
    [self doTestWithMXCoreDataStore:^(MXRoom *room) {
        [self checkPaginateWhenReachingTheExactBeginningOfTheRoom:room];
    }];
}

- (void)testMXCoreDataStoreRedactEvent
{
    [self doTestWithMXCoreDataStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkRedactEvent:room];
    }];
}


#pragma mark - MXCoreDataStore specific tests
- (void)testMXCoreDataStoreUserDisplaynameAndAvatarUrl
{
    [MXCoreDataStore flush];
    [self checkUserDisplaynameAndAvatarUrl:MXCoreDataStore.class];
}

- (void)testMXCoreDataStoreMXSessionOnStoreDataReady
{
    [self checkMXSessionOnStoreDataReady:MXCoreDataStore.class];
}

- (void)testMXCoreDataStoreRoomDeletion
{
    [self checkRoomDeletion:MXCoreDataStore.class];
}

- (void)testMXCoreDataStoreAge
{
    [self checkEventAge:MXCoreDataStore.class];
}

- (void)testMXCoreDataStoreMXRoomPaginationToken
{
    [self checkMXRoomPaginationToken:MXCoreDataStore.class];
}

- (void)testMXCoreDataStoreMultiAccount
{
    [self checkMultiAccount:MXCoreDataStore.class];
}

@end

#pragma clang diagnostic pop

#endif // MXCOREDATA_STORE
