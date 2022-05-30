/*
 Copyright 2015 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import "MXFileStore.h"
#import "MXStoreTests.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXStoreFileStoreTests : MXStoreTests
@end

@implementation MXStoreFileStoreTests

- (void)doTestWithMXFileStore:(void (^)(MXRoom *room))readyToTest
{
    MXFileStore *store = [[MXFileStore alloc] init];
    [self doTestWithStore:store readyToTest:readyToTest];
}

- (void)doTestWithTwoUsersAndMXFileStore:(void (^)(MXRoom *room))readyToTest
{
    MXFileStore *store = [[MXFileStore alloc] init];
    [self doTestWithTwoUsersAndStore:store readyToTest:readyToTest];
}

- (void)doTestWithMXFileStoreAndMessagesLimit:(NSUInteger)messagesLimit readyToTest:(void (^)(MXRoom *room))readyToTest
{
    MXFileStore *store = [[MXFileStore alloc] init];
    [self doTestWithStore:store andMessagesLimit:messagesLimit readyToTest:readyToTest];
}


#pragma mark - MXFileStore
- (void)testMXFileStoreEventExistsWithEventId
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self checkEventExistsWithEventIdOfStore:store];
}

- (void)testMXFileStoreEventWithEventId
{
    MXFileStore *store = [[MXFileStore alloc] init];
    [self checkEventWithEventIdOfStore:store];
}

- (void)testMXFileStorePaginateBack
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkPaginateBack:room];
    }];
}

- (void)testMXFileStorePaginateBackFilter
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkPaginateBackFilter:room];
    }];
}

- (void)testMXFileStorePaginateBackOrder
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkPaginateBackOrder:room];
    }];
}

- (void)testMXFileStorePaginateBackDuplicates
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

// This test illustrates bug SYIOS-9
- (void)testMXFileStorePaginateBackDuplicatesInRoomWithTwoUsers
{
    [self doTestWithTwoUsersAndMXFileStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

- (void)testMXFileStoreSeveralPaginateBacks
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkSeveralPaginateBacks:room];
    }];
}

- (void)testMXFileStorePaginateWithLiveEvents
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkPaginateWithLiveEvents:room];
    }];
}

- (void)testMXFileStoreCanPaginateFromHomeServer
{
    // Preload less messages than the room history counts so that there are still requests to the HS to do
    [self doTestWithMXFileStoreAndMessagesLimit:1 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromHomeServer:room];
    }];
}

- (void)testMXFileStoreCanPaginateFromMXStore
{
    // Preload more messages than the room history counts so that all messages are already loaded
    // room.liveTimeline.canPaginate will use [MXStore canPaginateInRoom]
    [self doTestWithMXFileStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromMXStore:room];
    }];
}

- (void)testMXFileStoreLastMessageAfterPaginate
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkLastMessageAfterPaginate:room];
    }];
}

- (void)testMXFileStoreLastMessageProfileChange
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkLastMessageProfileChange:room];
    }];
}

- (void)testMXMFileStoreLastMessageIgnoreProfileChange
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkLastMessageIgnoreProfileChange:room];
    }];
}

- (void)testMXFileStorePaginateWhenJoiningAgainAfterLeft
{
    [self doTestWithMXFileStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkPaginateWhenJoiningAgainAfterLeft:room];
    }];
}

- (void)testMXFileStoreAndHomeServerPaginateWhenJoiningAgainAfterLeft
{
    // Not preloading all messages of the room causes a duplicated event issue with MXFileStore
    // See `testMXFileStorePaginateBackDuplicatesInRoomWithTwoUsers`.
    // Check here if MXFileStore is able to filter this duplicate
    [self doTestWithMXFileStoreAndMessagesLimit:10 readyToTest:^(MXRoom *room) {
        [self checkPaginateWhenJoiningAgainAfterLeft:room];
    }];
}

- (void)testMXFileStorePaginateWhenReachingTheExactBeginningOfTheRoom
{
    [self doTestWithMXFileStore:^(MXRoom *room) {
        [self checkPaginateWhenReachingTheExactBeginningOfTheRoom:room];
    }];
}

- (void)testMXFileStoreRedactEvent
{
    [self doTestWithMXFileStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkRedactEvent:room];
    }];
}


#pragma mark - MXFileStore specific tests
- (void)testDiskUsage
{
    [self doTestWithMXFileStore:^(MXRoom *room) {

        MXFileStore *fileStore = mxSession.store;

        [fileStore diskUsageWithBlock:^(NSUInteger diskUsage1) {

            XCTAssertTrue([NSThread isMainThread], @"The block must be called from the main thread");

            [mxSession createRoom:nil visibility:nil roomAlias:nil topic:nil success:^(MXRoom *room) {

                [fileStore diskUsageWithBlock:^(NSUInteger diskUsage2) {

                    XCTAssertGreaterThan(diskUsage2, diskUsage1);

                    [fileStore deleteAllData];

                    [fileStore diskUsageWithBlock:^(NSUInteger diskUsage3) {

                        XCTAssertLessThan(diskUsage3, diskUsage2);

                        [expectation fulfill];
                    }];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];


    }];
}

- (void)testMXFileStoreUserDisplaynameAndAvatarUrl
{
    [self checkUserDisplaynameAndAvatarUrl:MXFileStore.class];
}

- (void)testMXFileStoreUpdateUserDisplaynameAndAvatarUrl
{
    [self checkUpdateUserDisplaynameAndAvatarUrl:MXFileStore.class];
}

- (void)testMXFileStoreMXSessionOnStoreDataReady
{
    [self checkMXSessionOnStoreDataReady:MXFileStore.class];
}

- (void)testMXFileStoreRoomDeletion
{
    [self checkRoomDeletion:MXFileStore.class];
}

- (void)testMXFileStoreAge
{
    [self checkEventAge:MXFileStore.class];
}

- (void)testMXFileStoreMXRoomPaginationToken
{
    [self checkMXRoomPaginationToken:MXFileStore.class];
}

- (void)testMXFileStoreMultiAccount
{
    [self checkMultiAccount:MXFileStore.class];
}

- (void)testMXFileStoreRoomAccountDataTags
{
    [self checkRoomAccountDataTags:MXFileStore.class];
}

- (void)testMXFileStoreRoomSummary
{
    [self checkRoomSummary:MXFileStore.class];
}

- (void)testMXFileStoreFilterId
{
    NSUInteger messagesLimit = 13;
    [self doTestWithMXFileStoreAndMessagesLimit:messagesLimit readyToTest:^(MXRoom *room) {
        MXFileStore *fileStore = mxSession.store;
        
        NSString *syncFilterId = fileStore.syncFilterId;
        
        XCTAssertNotNil(syncFilterId, @"Sync filter id must be stored");
        
        //  find filter by id in store
        [fileStore filterWithFilterId:syncFilterId success:^(MXFilterJSONModel * _Nullable filter) {
            
            XCTAssertEqual(filter.room.timeline.limit, messagesLimit, @"Timeline limits should match for filter");
            
            //  find id back from filter
            [fileStore filterIdForFilter:filter success:^(NSString * _Nullable filterId) {
                
                XCTAssertNotNil(filterId, @"Sync filter id must be found from the filter");
                XCTAssertEqual(filterId, syncFilterId, @"Sync filter ids must match");
                
                [expectation fulfill];
                
            } failure:^(NSError * _Nullable error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError * _Nullable error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testRoomStateIsStoredAndRestored
{
    [self doTestWithMXFileStoreAndMessagesLimit:10 readyToTest:^(MXRoom *room) {
        MXFileStore *fileStore = mxSession.store;
        
        // Load pre-existing room state
        [fileStore stateOfRoom:room.roomId success:^(NSArray<MXEvent *> * _Nonnull originalEvents) {
            
            MXEvent *name = [MXEvent modelFromJSON:@{
                @"type": kMXEventTypeStringRoomName,
                @"content": @{
                    @"name": @"Room 1"
                }
            }];
            NSArray *extendedEvents = [originalEvents arrayByAddingObject:name];

            // Save all existing events plus one additional
            [fileStore storeStateForRoom:room.roomId stateEvents:extendedEvents];
            [fileStore commitWithCompletion:^{
                
                // Need to fetch state of room twice due to a caching issue
                [fileStore stateOfRoom:room.roomId success:^(NSArray<MXEvent *> * _Nonnull _stateEvents) {
                    [fileStore stateOfRoom:room.roomId success:^(NSArray<MXEvent *> * _Nonnull stateEvents) {
                        
                        // Loaded state should include an extra event that was archived and unarchived
                        XCTAssertTrue(stateEvents.count);
                        XCTAssertEqual(stateEvents.count, extendedEvents.count);
                        XCTAssertNotEqual(stateEvents.count, originalEvents.count);
                        [expectation fulfill];
                        
                    } failure:^(NSError * _Nonnull error) {
                        XCTFail(@"Cannot load state - error: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError * _Nonnull error) {
                    XCTFail(@"Cannot load state - error: %@", error);
                    [expectation fulfill];
                }];
            }];
            
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot load state - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop
