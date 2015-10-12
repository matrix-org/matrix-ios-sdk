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
- (void)testMXFileEventWithEventId
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
    // room.canPaginate will use [MXStore canPaginateInRoom]
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

- (void)testMXFileStoreUserDisplaynameAndAvatarUrl
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];

    [sharedData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

        expectation = expectation2;

        MXFileStore *store = [[MXFileStore alloc] init];
        [store openWithCredentials:sharedData.aliceCredentials onComplete:^{

            [store deleteAllData];

            XCTAssertNil(store.userDisplayname);
            XCTAssertNil(store.userAvatarUrl);

            [store close];

            [store openWithCredentials:sharedData.aliceCredentials onComplete:^{

                XCTAssertNil(store.userDisplayname);
                XCTAssertNil(store.userAvatarUrl);

                // Let's (and verify) MXSession start update the store with user information
                mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];

                [mxSession setStore:store success:^{

                    [mxSession start:^{

                        [mxSession close];
                        mxSession = nil;

                        // Check user information is permanent
                        MXFileStore *store2 = [[MXFileStore alloc] init];
                        [store2 openWithCredentials:sharedData.aliceCredentials onComplete:^{

                            XCTAssertEqualObjects(store2.userDisplayname, kMXTestsAliceDisplayName);
                            XCTAssertEqualObjects(store2.userAvatarUrl, kMXTestsAliceAvatarURL);

                            [store2 close];
                            [expectation fulfill];

                        } failure:^(NSError *error) {
                            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                        }];
                        
                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];

                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testMXFileStoreMXSessionOnStoreDataReady
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];

    [sharedData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;


        MXFileStore *store = [[MXFileStore alloc] init];
        [store openWithCredentials:sharedData.bobCredentials onComplete:^{

            // Make sure to start from an empty store
            [store deleteAllData];

            XCTAssertNil(store.userDisplayname);
            XCTAssertNil(store.userAvatarUrl);
            XCTAssertEqual(store.rooms.count, 0);

            [store close];

            [store openWithCredentials:sharedData.bobCredentials onComplete:^{

                // Do a 1st [mxSession start] to fill the store
                mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

                [mxSession setStore:store success:^{

                    [mxSession start:^{

                        [mxSession close];
                        mxSession = nil;

                        // Create another random room to create more data server side
                        [bobRestClient createRoom:nil visibility:kMXRoomVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

                            [bobRestClient sendTextMessageToRoom:response.roomId text:@"A Message" success:^(NSString *eventId) {

                                // Do a 2nd [mxSession start] with the filled store
                                MXFileStore *store2 = [[MXFileStore alloc] init];
                                [store2 openWithCredentials:sharedData.bobCredentials onComplete:^{

                                    __block BOOL onStoreDataReadyCalled;
                                    NSString *eventStreamToken = [store2.eventStreamToken copy];
                                    NSUInteger storeRoomsCount = store2.rooms.count;

                                    MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

                                    [mxSession2 setStore:store2 success:^{
                                        onStoreDataReadyCalled = YES;

                                        XCTAssertEqual(mxSession2.rooms.count, storeRoomsCount, @"MXSessionOnStoreDataReady must have loaded as many MXRooms as room stored");
                                        XCTAssertEqual(store2.rooms.count, storeRoomsCount, @"There must still the same number of stored rooms");
                                        XCTAssertEqualObjects(eventStreamToken, store2.eventStreamToken, @"The event stream token must not have changed yet");

                                        [mxSession2 start:^{

                                            XCTAssert(onStoreDataReadyCalled, @"onStoreDataReady must alway be called before onServerSyncDone");

                                            XCTAssertEqual(mxSession2.rooms.count, storeRoomsCount + 1, @"MXSessionOnStoreDataReady must have loaded as many MXRooms as room stored");
                                            XCTAssertEqual(store2.rooms.count, storeRoomsCount + 1, @"There must still the same number of stored rooms");
                                            XCTAssertNotEqualObjects(eventStreamToken, store2.eventStreamToken, @"The event stream token must not have changed yet");

                                            [mxSession2 close];

                                            [expectation fulfill];

                                        } failure:^(NSError *error) {
                                            XCTFail(@"The request should not fail - NSError: %@", error);
                                            [expectation fulfill];
                                        }];

                                    } failure:^(NSError *error) {
                                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                                    }];

                                } failure:^(NSError *error) {
                                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                                }];
                                
                            } failure:^(NSError *error) {
                                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                            }];
                            
                        } failure:^(NSError *error) {
                            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                        }];
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
}

- (void)testMXFileStoreRoomDeletion
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];

    [sharedData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;

        MXFileStore *store = [[MXFileStore alloc] init];
        [store openWithCredentials:sharedData.bobCredentials onComplete:^{

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

            [mxSession setStore:store success:^{

                [mxSession start:^{

                    // Quit the newly created room
                    MXRoom *room = [mxSession roomWithRoomId:roomId];
                    [room leave:^{

                        XCTAssertEqual(NSNotFound, [store.rooms indexOfObject:roomId], @"The room %@ must be no more in the store", roomId);

                        [mxSession close];
                        mxSession = nil;

                        // Reload the store, to be sure the room is no more here
                        MXFileStore *store2 = [[MXFileStore alloc] init];
                        [store2 openWithCredentials:sharedData.bobCredentials onComplete:^{

                            XCTAssertEqual(NSNotFound, [store2.rooms indexOfObject:roomId], @"The room %@ must be no more in the store", roomId);

                            [store2 close];

                            [expectation fulfill];

                        } failure:^(NSError *error) {
                            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                        }];

                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

// Check that MXEvent.age and MXEvent.ageLocalTs are consistent after being stored.
- (void)testMXFileStoreAge
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];

    [sharedData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;

        MXFileStore *store = [[MXFileStore alloc] init];
        [store openWithCredentials:sharedData.bobCredentials onComplete:^{

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

            [mxSession setStore:store success:^{
                [mxSession start:^{

                    MXRoom *room = [mxSession roomWithRoomId:roomId];

                    MXEvent *event = [room lastMessageWithTypeIn:nil];

                    NSUInteger age = event.age;
                    uint64_t ageLocalTs = event.ageLocalTs;

                    [store close];
                    [store openWithCredentials:sharedData.bobCredentials onComplete:^{

                        MXEvent *sameEvent = [store eventWithEventId:event.eventId inRoom:roomId];

                        NSUInteger sameEventAge = sameEvent.age;
                        uint64_t sameEventAgeLocalTs = sameEvent.ageLocalTs;

                        XCTAssertGreaterThan(sameEventAge, 0, @"MXEvent.age should strictly positive");
                        XCTAssertLessThanOrEqual(age, sameEventAge, @"MXEvent.age should auto increase");
                        XCTAssertLessThanOrEqual(sameEventAge - age, 1000, @"sameEventAge and age should be almost the same");

                        XCTAssertEqual(ageLocalTs, sameEventAgeLocalTs, @"MXEvent.ageLocalTs must still be the same");

                        [expectation fulfill];
                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];

                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
}

// Check the pagination token is valid after reloading the store
- (void)testMXFileStoreMXSessionPaginationToken
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];

    [sharedData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;

        MXFileStore *store = [[MXFileStore alloc] init];
        [store openWithCredentials:sharedData.bobCredentials onComplete:^{

            // Do a 1st [mxSession start] to fill the store
            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            [mxSession setStore:store success:^{
                [mxSession start:^{

                    MXRoom *room = [mxSession roomWithRoomId:roomId];
                    [room resetBackState];
                    [room paginateBackMessages:10 complete:^{

                        NSString *roomPaginationToken = [store paginationTokenOfRoom:roomId];
                        XCTAssert(roomPaginationToken, @"The room must have a pagination after a pagination");

                        [mxSession close];
                        mxSession = nil;

                        // Reopen a session and check roomPaginationToken
                        MXFileStore *store2 = [[MXFileStore alloc] init];
                        [store2 openWithCredentials:sharedData.bobCredentials onComplete:^{

                            XCTAssertEqualObjects(roomPaginationToken, [store2 paginationTokenOfRoom:roomId], @"The store must keep the pagination token");

                            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                            [mxSession setStore:store2 success:^{
                                [mxSession start:^{

                                    XCTAssertEqualObjects(roomPaginationToken, [store2 paginationTokenOfRoom:roomId], @"The store must keep the pagination token even after [MXSession start]");

                                    [expectation fulfill];

                                } failure:^(NSError *error) {
                                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                                }];
                            } failure:^(NSError *error) {
                                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                            }];
                        } failure:^(NSError *error) {
                            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                        }];
                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testMXFileStoreMultiAccount
{
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];

    [sharedData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;

        MXFileStore *bobStore1 = [[MXFileStore alloc] init];
        [bobStore1 openWithCredentials:sharedData.bobCredentials onComplete:^{

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            [mxSession setStore:bobStore1 success:^{
                [mxSession start:^{

                    [mxSession close];
                    mxSession = nil;

                    MXFileStore *bobStore2 = [[MXFileStore alloc] init];
                    [bobStore2 openWithCredentials:sharedData.bobCredentials onComplete:^{

                        MXFileStore *aliceStore = [[MXFileStore alloc] init];
                        [aliceStore openWithCredentials:sharedData.aliceCredentials onComplete:^{

                            MXFileStore *bobStore3 = [[MXFileStore alloc] init];
                            [bobStore3 openWithCredentials:sharedData.bobCredentials onComplete:^{

                                XCTAssertEqual(bobStore2.diskUsage, bobStore3.diskUsage, @"Bob's store must still have the same content");
                                XCTAssertEqual(bobStore2.rooms.count, bobStore3.rooms.count);

                                [expectation fulfill];

                            } failure:^(NSError *error) {
                                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                            }];
                        } failure:^(NSError *error) {
                            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                        }];
                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
}

@end

#pragma clang diagnostic pop
