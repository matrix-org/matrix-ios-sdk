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

@interface MXFileStore (RetentionTesting)
- (NSString *)messagesFileForRoom:(NSString *)roomId forBackup:(BOOL)backup;
@end

@interface MXFileStore (AccountDataTesting)
- (MXRoomAccountData *)loadAccountDataFromFileForRoom:(NSString *)roomId;
@end

@interface MXRetentionTestFileStore : MXFileStore
@property (nonatomic, copy) void (^nextMessagesFileAccessHook)(NSString *roomId);
- (void)unloadRoomForTesting:(NSString *)roomId;
- (BOOL)isRoomLoadedForTesting:(NSString *)roomId;
- (NSString *)messagesFileForRoomForTesting:(NSString *)roomId;
@end

@interface MXAccountDataTestFileStore : MXFileStore
@property (atomic) NSUInteger accountDataFileLoadCount;
@property (atomic) BOOL loadedAccountDataOnMainThread;
@end

@implementation MXAccountDataTestFileStore
- (MXRoomAccountData *)loadAccountDataFromFileForRoom:(NSString *)roomId
{
    self.accountDataFileLoadCount += 1;
    self.loadedAccountDataOnMainThread |= NSThread.isMainThread;
    return [super loadAccountDataFromFileForRoom:roomId];
}
@end

@implementation MXRetentionTestFileStore
- (NSString *)messagesFileForRoom:(NSString *)roomId forBackup:(BOOL)backup
{
    NSString *path = [super messagesFileForRoom:roomId forBackup:backup];
    void (^hook)(NSString *) = self.nextMessagesFileAccessHook;
    if (!backup && hook)
    {
        self.nextMessagesFileAccessHook = nil;
        hook(roomId);
    }
    return path;
}

- (void)unloadRoomForTesting:(NSString *)roomId
{
    @synchronized (roomStores)
    {
        [roomStores removeObjectForKey:roomId];
    }
}

- (BOOL)isRoomLoadedForTesting:(NSString *)roomId
{
    @synchronized (roomStores)
    {
        return roomStores[roomId] != nil;
    }
}

- (NSString *)messagesFileForRoomForTesting:(NSString *)roomId
{
    NSString *roomsPath = [self valueForKey:@"storeRoomsPath"];
    return [[roomsPath stringByAppendingPathComponent:roomId] stringByAppendingPathComponent:@"messages"];
}
@end

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
- (void)testRoomAccountDataPreloadCachesExistingMissingAndCorruptFiles
{
    XCTestExpectation *done = [self expectationWithDescription:@"account data preload"];
    NSString *suffix = NSUUID.UUID.UUIDString;
    MXCredentials *credentials = [[MXCredentials alloc] initWithHomeServer:@"https://example.org"
                                                                    userId:[@"@account-data-" stringByAppendingString:suffix]
                                                               accessToken:@"token"];
    MXFileStore *initialStore = [[MXFileStore alloc] init];

    [initialStore openWithCredentials:credentials onComplete:^{
        initialStore.eventStreamToken = @"initial-token";
        NSString *existingRoomId = [@"existing-" stringByAppendingString:suffix];
        NSString *missingRoomId = [@"missing-" stringByAppendingString:suffix];
        NSString *corruptRoomId = [@"corrupt-" stringByAppendingString:suffix];
        MXRoomAccountData *existingAccountData = [[MXRoomAccountData alloc] init];
        [initialStore storeAccountDataForRoom:existingRoomId userData:existingAccountData];

        [initialStore commitWithCompletion:^{
            NSString *roomsPath = [initialStore valueForKey:@"storeRoomsPath"];
            NSString *missingRoomPath = [roomsPath stringByAppendingPathComponent:missingRoomId];
            NSString *corruptRoomPath = [roomsPath stringByAppendingPathComponent:corruptRoomId];
            [NSFileManager.defaultManager createDirectoryAtPath:missingRoomPath
                                    withIntermediateDirectories:YES attributes:nil error:nil];
            [NSFileManager.defaultManager createDirectoryAtPath:corruptRoomPath
                                    withIntermediateDirectories:YES attributes:nil error:nil];
            [[@"not an archive" dataUsingEncoding:NSUTF8StringEncoding]
             writeToFile:[corruptRoomPath stringByAppendingPathComponent:@"accountData"]
             options:NSDataWritingAtomic
             error:nil];

            MXAccountDataTestFileStore *reopenedStore = [[MXAccountDataTestFileStore alloc] init];
            [reopenedStore openWithCredentials:credentials onComplete:^{
                XCTAssertTrue(NSThread.isMainThread);
                XCTAssertEqual(reopenedStore.accountDataFileLoadCount, 3u);
                XCTAssertFalse(reopenedStore.loadedAccountDataOnMainThread);

                XCTAssertNotNil([reopenedStore accountDataOfRoom:existingRoomId]);
                XCTAssertNil([reopenedStore accountDataOfRoom:missingRoomId]);
                XCTAssertNil([reopenedStore accountDataOfRoom:corruptRoomId]);
                XCTAssertNotNil([reopenedStore accountDataOfRoom:existingRoomId]);
                XCTAssertNil([reopenedStore accountDataOfRoom:missingRoomId]);
                XCTAssertNil([reopenedStore accountDataOfRoom:corruptRoomId]);
                XCTAssertEqual(reopenedStore.accountDataFileLoadCount, 3u,
                               @"Main-thread reads must use positive and negative preload cache entries");

                MXRoomAccountData *replacement = [[MXRoomAccountData alloc] init];
                [reopenedStore storeAccountDataForRoom:missingRoomId userData:replacement];
                XCTAssertEqual([reopenedStore accountDataOfRoom:missingRoomId], replacement);
                XCTAssertEqual(reopenedStore.accountDataFileLoadCount, 3u);

                [reopenedStore deleteAllData];
                [done fulfill];
            } failure:^(NSError *error) {
                XCTFail(@"Cannot reopen account data test store: %@", error);
                [done fulfill];
            }];
        }];
    } failure:^(NSError *error) {
        XCTFail(@"Cannot open account data test store: %@", error);
        [done fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testRetentionCleanupProcessesUnloadedFilesAtomicallyAndSkipsCorruption
{
    XCTestExpectation *done = [self expectationWithDescription:@"retention cleanup"];
    NSString *suffix = NSUUID.UUID.UUIDString;
    MXCredentials *credentials = [[MXCredentials alloc] initWithHomeServer:@"https://example.org"
                                                                    userId:[@"@retention-" stringByAppendingString:suffix]
                                                               accessToken:@"token"];
    MXRetentionTestFileStore *store = [[MXRetentionTestFileStore alloc] init];

    [store openWithCredentials:credentials onComplete:^{
        NSString *validRoomId = [@"valid-" stringByAppendingString:suffix];
        NSString *corruptRoomId = [@"corrupt-" stringByAppendingString:suffix];
        MXEvent *oldEvent = [MXEvent modelFromJSON:@{
            @"event_id": @"old", @"room_id": validRoomId,
            @"sender": @"@alice:example.org", @"type": kMXEventTypeStringRoomMessage,
            @"origin_server_ts": @100, @"content": @{@"msgtype": @"m.text", @"body": @"old"}
        }];
        MXEvent *newEvent = [MXEvent modelFromJSON:@{
            @"event_id": @"new", @"room_id": validRoomId,
            @"sender": @"@alice:example.org", @"type": kMXEventTypeStringRoomMessage,
            @"origin_server_ts": @300, @"content": @{@"msgtype": @"m.text", @"body": @"new"}
        }];
        [store storeEventForRoom:validRoomId event:oldEvent direction:MXTimelineDirectionForwards];
        [store storeEventForRoom:validRoomId event:newEvent direction:MXTimelineDirectionForwards];

        [store commitWithCompletion:^{
            [store unloadRoomForTesting:validRoomId];
            NSString *validFile = [store messagesFileForRoomForTesting:validRoomId];
            NSNumber *oldFileNumber = [[NSFileManager.defaultManager attributesOfItemAtPath:validFile error:nil]
                                       objectForKey:NSFileSystemFileNumber];

            NSString *corruptFile = [store messagesFileForRoomForTesting:corruptRoomId];
            [NSFileManager.defaultManager createDirectoryAtPath:corruptFile.stringByDeletingLastPathComponent
                                    withIntermediateDirectories:YES attributes:nil error:nil];
            NSData *corruptBytes = [@"not an archive" dataUsingEncoding:NSUTF8StringEncoding];
            [corruptBytes writeToFile:corruptFile options:NSDataWritingAtomic error:nil];

            [store removeExpiredMessagesWithRoomMinimumTimestamps:@{
                validRoomId: @200,
                corruptRoomId: @200
            } completion:^(NSUInteger cleanedRoomCount, NSUInteger failedRoomCount, BOOL cancelled) {
                XCTAssertTrue(NSThread.isMainThread);
                XCTAssertEqual(cleanedRoomCount, 1u);
                XCTAssertEqual(failedRoomCount, 1u);
                XCTAssertFalse(cancelled);
                XCTAssertFalse([store isRoomLoadedForTesting:validRoomId]);
                XCTAssertFalse([store isRoomLoadedForTesting:corruptRoomId]);
                XCTAssertEqualObjects([NSData dataWithContentsOfFile:corruptFile], corruptBytes);

                NSNumber *newFileNumber = [[NSFileManager.defaultManager attributesOfItemAtPath:validFile error:nil]
                                           objectForKey:NSFileSystemFileNumber];
                XCTAssertNotEqualObjects(oldFileNumber, newFileNumber, @"NSDataWritingAtomic must replace the file");
                XCTAssertNil([store eventWithEventId:@"old" inRoom:validRoomId]);
                XCTAssertNotNil([store eventWithEventId:@"new" inRoom:validRoomId]);
                [store deleteAllData];
                [done fulfill];
            }];
        }];
    } failure:^(NSError *error) {
        XCTFail(@"Cannot open retention test store: %@", error);
        [done fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testRetentionCleanupDoesNotOverwriteRoomLoadedAfterInitialCheck
{
    XCTestExpectation *done = [self expectationWithDescription:@"retention cleanup room load race"];
    NSString *suffix = NSUUID.UUID.UUIDString;
    NSString *roomId = [@"race-" stringByAppendingString:suffix];
    MXCredentials *credentials = [[MXCredentials alloc] initWithHomeServer:@"https://example.org"
                                                                    userId:[@"@retention-race-" stringByAppendingString:suffix]
                                                               accessToken:@"token"];
    MXRetentionTestFileStore *store = [[MXRetentionTestFileStore alloc] init];

    [store openWithCredentials:credentials onComplete:^{
        MXEvent *oldEvent = [MXEvent modelFromJSON:@{
            @"event_id": @"old", @"room_id": roomId,
            @"sender": @"@alice:example.org", @"type": kMXEventTypeStringRoomMessage,
            @"origin_server_ts": @100, @"content": @{@"msgtype": @"m.text", @"body": @"old"}
        }];
        MXEvent *newEvent = [MXEvent modelFromJSON:@{
            @"event_id": @"new", @"room_id": roomId,
            @"sender": @"@alice:example.org", @"type": kMXEventTypeStringRoomMessage,
            @"origin_server_ts": @300, @"content": @{@"msgtype": @"m.text", @"body": @"new"}
        }];
        [store storeEventForRoom:roomId event:oldEvent direction:MXTimelineDirectionForwards];

        [store commitWithCompletion:^{
            [store unloadRoomForTesting:roomId];
            store.nextMessagesFileAccessHook = ^(NSString *accessedRoomId) {
                XCTAssertEqualObjects(accessedRoomId, roomId);
                [store storeEventForRoom:roomId event:newEvent direction:MXTimelineDirectionForwards];
            };

            [store removeExpiredMessagesWithRoomMinimumTimestamps:@{roomId: @200}
                                                       completion:^(NSUInteger cleanedRoomCount,
                                                                    NSUInteger failedRoomCount,
                                                                    BOOL cancelled) {
                XCTAssertEqual(cleanedRoomCount, 0u);
                XCTAssertEqual(failedRoomCount, 0u);
                XCTAssertFalse(cancelled);
                XCTAssertTrue([store isRoomLoadedForTesting:roomId]);

                [store commitWithCompletion:^{
                    [store unloadRoomForTesting:roomId];
                    XCTAssertNotNil([store eventWithEventId:@"new" inRoom:roomId],
                                    @"Retention must not overwrite events from a room mounted during cleanup");
                    [store deleteAllData];
                    [done fulfill];
                }];
            }];
        }];
    } failure:^(NSError *error) {
        XCTFail(@"Cannot open retention race test store: %@", error);
        [done fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

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
