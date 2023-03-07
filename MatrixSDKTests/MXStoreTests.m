/*
 Copyright 2014 OpenMarket Ltd
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

#import "MXStoreTests.h"

#import "MXMemoryStore.h"
#import "MXFileStore.h"

#import "MXRoomSummaryUpdater.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXStoreTests ()
{
    MatrixSDKTestsData *matrixSDKTestsData;

    id observer;
}

@end

@implementation MXStoreTests

- (void)setUp
{
    [super setUp];
    
    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    if (mxSession)
    {
        [mxSession close];
        mxSession = nil;
    }

    if (observer)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        observer = nil;
    }

    matrixSDKTestsData = nil;

    [super tearDown];
}

- (void)doTestWithStore:(id<MXStore>)store
   readyToTest:(void (^)(MXRoom *room))readyToTest
{
    // Do not generate an expectation if we already have one
    XCTestCase *testCase = self;
    if (expectation)
    {
        testCase = nil;
    }

    [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:testCase readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        if (!expectation)
        {
            expectation = expectation2;
        }

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession setStore:store success:^{

            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                readyToTest(room);

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

- (void)doTestWithTwoUsersAndStore:(id<MXStore>)store
            readyToTest:(void (^)(MXRoom *room))readyToTest
{
    // Do not generate an expectation if we already have one
    XCTestCase *testCase = self;
    if (expectation)
    {
        testCase = nil;
    }

    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:testCase readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        [matrixSDKTestsData for:bobRestClient andRoom:roomId sendMessages:5 testCase:testCase success:^{

            if (!expectation)
            {
                expectation = expectation2;
            }

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            [matrixSDKTestsData retain:mxSession];

            [mxSession setStore:store success:^{
                [mxSession start:^{

                    MXRoom *room = [mxSession roomWithRoomId:roomId];

                    readyToTest(room);

                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];

    }];
}

- (void)doTestWithStore:(id<MXStore>)store
       andMessagesLimit:(NSUInteger)messagesLimit
            readyToTest:(void (^)(MXRoom *room))readyToTest
{
    // Do not generate an expectation if we already have one
    XCTestCase *testCase = self;
    if (expectation)
    {
        testCase = nil;
    }

    [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:testCase readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        if (!expectation)
        {
            expectation = expectation2;
        }

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession setStore:store success:^{

            [mxSession startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:messagesLimit] onServerSyncDone:^{
                MXRoom *room = [mxSession roomWithRoomId:roomId];

                readyToTest(room);

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


- (void)assertNoDuplicate:(NSArray*)events text:(NSString*)text
{
    NSMutableDictionary *eventIDs = [NSMutableDictionary dictionary];

    for (MXEvent *event in events)
    {
        if ([eventIDs objectForKey:event.eventId])
        {
            XCTAssert(NO, @"Duplicated event in %@ - MXEvent: %@", text, event);
        }
        eventIDs[event.eventId] = event;
    }
}


#pragma mark - MXStore generic tests

- (void)checkEventExistsWithEventIdOfStore:(id<MXStore>)store
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation2) {

        expectation = expectation2;

        [store openWithCredentials:bobRestClient.credentials onComplete:^{
            MXEvent *event = [MXEvent modelFromJSON:@{
                                                      @"event_id": @"anID",
                                                      @"type": @"type",
                                                      @"room_id": @"roomId",
                                                      @"user_id": @"userId:"
                                                      }];

            [store storeEventForRoom:@"roomId" event:event direction:MXTimelineDirectionForwards];

            BOOL exists = [store eventExistsWithEventId:@"anID" inRoom:@"roomId"];

            XCTAssertEqual(exists, YES);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)checkEventWithEventIdOfStore:(id<MXStore>)store
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation2) {

        expectation = expectation2;

        [store openWithCredentials:bobRestClient.credentials onComplete:^{
            MXEvent *event = [MXEvent modelFromJSON:@{
                                                      @"event_id": @"anID",
                                                      @"type": @"type",
                                                      @"room_id": @"roomId",
                                                      @"user_id": @"userId:"
                                                      }];

            [store storeEventForRoom:@"roomId" event:event direction:MXTimelineDirectionForwards];

            MXEvent *storedEvent = [store eventWithEventId:@"anID" inRoom:@"roomId"];

            XCTAssertEqualObjects(storedEvent, event);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)checkPaginateBack:(MXRoom*)room
{
    NSArray *eventsFilterForMessages = @[
                                         kMXEventTypeStringRoomName,
                                         kMXEventTypeStringRoomTopic,
                                         kMXEventTypeStringRoomMember,
                                         kMXEventTypeStringRoomMessage
                                         ];

    __block NSUInteger eventCount = 0;

    [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

        [liveTimeline listenToEventsOfTypes:eventsFilterForMessages onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            eventCount++;
        }];

        [liveTimeline resetPagination];
        [liveTimeline paginate:5 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

            XCTAssertEqual(eventCount, 5, @"We should get as many messages as requested");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)checkPaginateBackFilter:(MXRoom*)room
{
    NSArray *eventsFilterForMessages = @[
                                         kMXEventTypeStringRoomName,
                                         kMXEventTypeStringRoomTopic,
                                         kMXEventTypeStringRoomMember,
                                         kMXEventTypeStringRoomMessage
                                         ];

    __block NSUInteger eventCount = 0;

    [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

        [liveTimeline listenToEventsOfTypes:eventsFilterForMessages onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            eventCount++;

            // Only events with a type declared in `eventsFilterForMessages`
            // must appear in messages
            XCTAssertNotEqual([eventsFilterForMessages indexOfObject:event.type], NSNotFound, "Event of this type must not be in messages. Event: %@", event);

        }];

        [liveTimeline resetPagination];
        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

            XCTAssert(eventCount, "We should have received events in registerEventListenerForTypes");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)checkPaginateBackOrder:(MXRoom*)room
{
    NSArray *eventsFilterForMessages = @[
                                         kMXEventTypeStringRoomName,
                                         kMXEventTypeStringRoomTopic,
                                         kMXEventTypeStringRoomMember,
                                         kMXEventTypeStringRoomMessage
                                         ];

    __block uint64_t prev_ts = -1;

    [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

        [liveTimeline listenToEventsOfTypes:eventsFilterForMessages onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            XCTAssert(event.originServerTs, @"The event should have an attempt: %@", event);

            XCTAssertLessThanOrEqual(event.originServerTs, prev_ts, @"Events in messages must be listed  one by one in antichronological order");
            prev_ts = event.originServerTs;

        }];

        [liveTimeline resetPagination];
        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

            XCTAssertNotEqual(prev_ts, -1, "We should have received events in registerEventListenerForTypes");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)checkPaginateBackDuplicates:(MXRoom*)room
{
    __block NSUInteger eventCount = 0;
    __block NSMutableArray *events = [NSMutableArray array];
    [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

        [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            eventCount++;

            [events addObject:event];
        }];

        [liveTimeline resetPagination];
        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

            XCTAssert(eventCount, "We should have received events in registerEventListenerForTypes");

            [self assertNoDuplicate:events text:@"events got one by one with paginateBackMessages"];

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];

}

- (void)checkSeveralPaginateBacks:(MXRoom*)room
{
    __block NSMutableArray *roomEvents = [NSMutableArray array];
    [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
        [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            [roomEvents addObject:event];
        }];

        [liveTimeline resetPagination];
        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

            // Use another MXRoom instance to do pagination in several times
            MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.roomId andMatrixSession:mxSession];

            __block NSMutableArray *room2Events = [NSMutableArray array];

            [room2 liveTimeline:^(id<MXEventTimeline> room2LiveTimeline) {

                [room2LiveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    [room2Events addObject:event];
                }];

                // The several paginations
                [room2LiveTimeline resetPagination];

                if (mxSession.store.isPermanent)
                {
                    XCTAssertGreaterThanOrEqual(room2LiveTimeline.remainingMessagesForBackPaginationInStore, 7);
                }

                [room2LiveTimeline paginate:2 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                    if (mxSession.store.isPermanent)
                    {
                        XCTAssertGreaterThanOrEqual(room2LiveTimeline.remainingMessagesForBackPaginationInStore, 5);
                    }

                    [room2LiveTimeline paginate:5 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                        // Log room2 to keep a ref on it up to here
                        MXLogDebug(@"%@", room2);

                        [room2LiveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                            [self assertNoDuplicate:room2Events text:@"events got one by one with testSeveralPaginateBacks"];

                            // Now, compare the result with the reference
                            XCTAssertEqual(roomEvents.count, room2Events.count);

                            if (roomEvents.count == room2Events.count)
                            {
                                // Compare events one by one
                                for (NSUInteger i = 0; i < room2Events.count; i++)
                                {
                                    MXEvent *event = roomEvents[i];
                                    MXEvent *event2 = room2Events[i];

                                    XCTAssertTrue([event2.eventId isEqualToString:event.eventId], @"Events mismatch: %@ - %@", event, event2);
                                }
                            }

                            [expectation fulfill];

                        } failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)checkPaginateWithLiveEvents:(MXRoom*)room
{
    __block NSMutableArray *roomEvents = [NSMutableArray array];

    // Use another MXRoom instance to paginate while receiving live events
    MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.roomId andMatrixSession:mxSession];

    __block NSMutableArray *room2Events = [NSMutableArray array];
    [room2 liveTimeline:^(id<MXEventTimeline> room2liveTimeline) {

        [room2liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if (MXTimelineDirectionForwards != direction)
            {
                [room2Events addObject:event];
            }
        }];

        __block NSUInteger liveEvents = 0;

        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if (MXTimelineDirectionForwards == direction)
                {
                    // Do some paginations after receiving live events
                    liveEvents++;
                    if (1 == liveEvents)
                    {
                        if (mxSession.store.isPermanent)
                        {
                            XCTAssertGreaterThanOrEqual(room2liveTimeline.remainingMessagesForBackPaginationInStore, 7);
                        }

                        [room2liveTimeline paginate:2 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                            if (mxSession.store.isPermanent)
                            {
                                XCTAssertGreaterThanOrEqual(room2liveTimeline.remainingMessagesForBackPaginationInStore, 5);
                            }

                            // Try with 2 more live events
                            [room sendTextMessage:@"How is the pagination #2?" threadId:nil success:nil failure:nil];
                            [room sendTextMessage:@"How is the pagination #3?" threadId:nil success:nil failure:nil];

                        } failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                    }
                    else if (3 == liveEvents)
                    {
                        [room2liveTimeline paginate:5 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                            // Log room2 to keep a ref on it up to here
                            MXLogDebug(@"%@", room2);
                            
                            [room2liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                                [self assertNoDuplicate:room2Events text:@"events got one by one with testSeveralPaginateBacks"];

                                // Now, compare the result with the reference
                                XCTAssertEqual(roomEvents.count, room2Events.count);

                                // Compare events one by one
                                for (NSUInteger i = 0; i < room2Events.count; i++)
                                {
                                    MXEvent *event = roomEvents[i];
                                    MXEvent *event2 = room2Events[i];

                                    XCTAssertTrue([event2.eventId isEqualToString:event.eventId], @"Events mismatch: %@ - %@", event, event2);
                                }

                                [expectation fulfill];

                            } failure:^(NSError *error) {
                                XCTFail(@"The request should not fail - NSError: %@", error);
                                [expectation fulfill];
                            }];
                        } failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                    }
                }
                else
                {
                    [roomEvents addObject:event];
                }
            }];

            // Take a snapshot of all room history
            [liveTimeline resetPagination];
            [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                // Messages are now in the cache
                // Start checking pagination from the cache
                [room2liveTimeline resetPagination];

                [room sendTextMessage:@"How is the pagination #1?" threadId:nil success:nil failure:nil];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}


- (void)checkCanPaginateFromHomeServer:(MXRoom*)room
{
    [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
        [liveTimeline resetPagination];
        XCTAssertTrue([liveTimeline canPaginate:MXTimelineDirectionBackwards], @"We can always paginate at the beginning");

        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

            // Due to SPEC-319, we need to paginate twice to be sure to hit the limit
            [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                XCTAssertFalse([liveTimeline canPaginate:MXTimelineDirectionBackwards], @"We must have reached the end of the pagination");

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)checkCanPaginateFromMXStore:(MXRoom*)room
{
    [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

        [liveTimeline resetPagination];
        XCTAssertTrue([liveTimeline canPaginate:MXTimelineDirectionBackwards], @"We can always paginate at the beginning");

        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

            // Do one more round trip so that SDK detect the limit
            [liveTimeline paginate:1 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                XCTAssertFalse([liveTimeline canPaginate:MXTimelineDirectionBackwards], @"We must have reached the end of the pagination");

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)checkLastMessageAfterPaginate:(MXRoom*)room
{
    [room.mxSession eventWithEventId:room.summary.lastMessage.eventId
                              inRoom:room.roomId
                             success:^(MXEvent *lastMessage) {
        
        XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMessage);

        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline resetPagination];
            XCTAssertEqualObjects(room.summary.lastMessage.eventId, lastMessage.eventId,  @"The last message should stay the same");

            [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                XCTAssertEqualObjects(room.summary.lastMessage.eventId, lastMessage.eventId,  @"The last message should stay the same");

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];
        
    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}

- (void)checkLastMessageProfileChange:(MXRoom*)room
{
    [room.mxSession eventWithEventId:room.summary.lastMessage.eventId
                              inRoom:room.roomId
                             success:^(MXEvent *lastMessage) {
        
        XCTAssertNotNil(lastMessage);
        XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMessage);

        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                // The room summary is handled afterwards
                if (!observer)
                {
                    observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:room.summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                        [room.mxSession eventWithEventId:room.summary.lastMessage.eventId
                                                  inRoom:room.roomId
                                                 success:^(MXEvent *lastMessage2) {
                            
                            XCTAssertNotNil(lastMessage2);
                            XCTAssertEqual(lastMessage2.eventType, MXEventTypeRoomMember);
                            XCTAssertNotEqualObjects(room.summary.lastMessage.eventId, lastMessage.eventId);

                            [expectation fulfill];
                            
                        } failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                        
                    }];
                }
            }];
        }];

        [room.mxSession.myUser setDisplayName:@"Toto" success:nil failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
    
}

- (void)checkLastMessageEventTypesAllowList:(MXRoom*)room
{
    [room.mxSession eventWithEventId:room.summary.lastMessage.eventId
                              inRoom:room.roomId
                             success:^(MXEvent *lastMessage) {
        
        XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMessage);

        // Only allow message events to become the last message.
        MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:room.mxSession];
        updater.lastMessageEventTypesAllowList = @[kMXEventTypeStringRoomMessage];

        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                [room.mxSession eventWithEventId:room.summary.lastMessage.eventId
                                          inRoom:room.roomId
                                         success:^(MXEvent *lastMessage2) {
                    
                    XCTAssertNotNil(lastMessage2);
                    XCTAssertEqual(lastMessage2.eventType, MXEventTypeRoomMessage);
                    XCTAssertEqualObjects(lastMessage2.eventId, lastMessage.eventId);

                    // The room.summary.lastMessageEvent must no be updated in this case
                    [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:room.summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                        XCTFail(@"The room.summary.lastMessageEvent must no be updated in this case");

                    }];

                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            }];
        }];

        [room.mxSession.myUser setDisplayName:@"Toto" success:nil failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}

- (void)checkLastMessageIgnoreProfileChange:(MXRoom *)room
{
    // Not implemented
}

- (void)checkPaginateWhenJoiningAgainAfterLeft:(MXRoom*)room
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

        [mxSession.matrixRestClient inviteUser:aliceRestClient.credentials.userId toRoom:room.roomId success:^{

            NSString *roomId = room.roomId;

            __block NSString *aliceTextEventId;

            // Make sure bob joins back the room only once
            __block BOOL joinedRequestMade = NO;

            // Listen for the invitation by Alice
            [mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

                // Join the room again
                MXRoom *room2 = [mxSession roomWithRoomId:roomId];

                XCTAssertNotNil(room2);

                if (direction == MXTimelineDirectionForwards && MXMembershipInvite == room2.summary.membership && !joinedRequestMade)
                {
                    // Join the room on the invitation and check we can paginate all expected text messages
                    // By default the last Alice's message (sent while Bob is not in the room) must be visible.
                    joinedRequestMade = YES;
                    [room2 join:^{

                        NSMutableArray *events = [NSMutableArray array];
                        [room2 liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                                if (direction == MXTimelineDirectionBackwards)
                                {
                                    if (0 == events.count)
                                    {
                                        // The most recent message must be "Hi bob" sent by Alice
                                        XCTAssertEqualObjects(aliceTextEventId, event.eventId);
                                    }

                                    [events addObject:event];
                                }

                            }];

                            [liveTimeline resetPagination];
                            [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                                XCTAssertEqual(events.count, 6, "The room should contain only 6 messages (the last message sent while the user is not in the room must be visible)");

                                [mxSession close];
                                [expectation fulfill];

                            } failure:^(NSError *error) {
                                XCTFail(@"The request should not fail - NSError: %@", error);
                                [mxSession close];
                                [expectation fulfill];
                            }];
                        }];

                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [mxSession close];
                        [expectation fulfill];
                    }];
                }
            }];

            // Make Alice send text message while Bob is not in the room.
            // Then, invite him.
            [aliceRestClient joinRoom:roomId viaServers:nil withThirdPartySigned:nil success:^(NSString *roomName){

                // Make Bob the room
                [room leave:^{

                    [aliceRestClient sendTextMessageToRoom:roomId threadId:nil text:@"Hi bob" success:^(NSString *eventId) {

                        aliceTextEventId = eventId;

                        [aliceRestClient inviteUser:mxSession.matrixRestClient.credentials.userId toRoom:roomId success:^{

                        } failure:^(NSError *error) {
                            XCTFail(@"Cannot set up intial test conditions");
                            [expectation fulfill];
                        }];

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions");
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions");
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions");
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions");
            [expectation fulfill];
        }];
    }];
}

// Test for https://matrix.org/jira/browse/SYN-162
- (void)checkPaginateWhenReachingTheExactBeginningOfTheRoom:(MXRoom*)room
{
    __block NSUInteger eventCount = 0;
    [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
        [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if (direction == MXTimelineDirectionBackwards)
            {
                eventCount++;
            }
        }];

        // First count how many messages to retrieve
        [liveTimeline resetPagination];
        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

            // Paginate for the exact number of events in the room
            NSUInteger pagEnd = eventCount;
            eventCount = 0;
            [mxSession.store deleteRoom:room.roomId];
            [liveTimeline resetPagination];

            [liveTimeline paginate:pagEnd direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                XCTAssertEqual(eventCount, pagEnd, @"We should get as many messages as requested");

                XCTAssert([liveTimeline canPaginate:MXTimelineDirectionBackwards], @"At this point the SDK cannot know it reaches the beginning of the history");

                // Try to load more messages
                eventCount = 0;
                [liveTimeline paginate:1 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                    XCTAssertEqual(eventCount, 0, @"There must be no more event");
                    XCTAssertFalse([liveTimeline canPaginate:MXTimelineDirectionBackwards], @"SDK must now indicate there is no more event to paginate");

                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - see SYN-162 - NSError: %@", error);
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

- (void)checkRedactEvent:(MXRoom*)room
{
    __block NSString *messageEventId;

    [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
        [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if (MXEventTypeRoomMessage == event.eventType)
            {
                // Manage the case where message comes down the stream before the call of the success
                // callback of [room sendTextMessage:...]
                if (nil == messageEventId)
                {
                    messageEventId = event.eventId;
                }

                MXEvent *notYetRedactedEvent = [mxSession.store eventWithEventId:messageEventId inRoom:room.roomId];

                XCTAssertGreaterThan(notYetRedactedEvent.content.count, 0);
                XCTAssertNil(notYetRedactedEvent.redacts);
                XCTAssertNil(notYetRedactedEvent.redactedBecause);

                // Redact this event
                [room redactEvent:messageEventId reason:@"No reason" success:^{

                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            }
            else if (MXEventTypeRoomRedaction == event.eventType)
            {
                MXEvent *redactedEvent = [mxSession.store eventWithEventId:messageEventId inRoom:room.roomId];

                XCTAssertEqual(redactedEvent.content.count, 0, @"Redacted event content must be now empty");
                XCTAssertEqualObjects(event.eventId, redactedEvent.redactedBecause[@"event_id"], @"It must contain the event that redacted it");

                // Tests more related to redaction (could be moved to a dedicated section somewhere else)
                XCTAssertEqualObjects(event.redacts, messageEventId, @"");

                [expectation fulfill];
            }

        }];
    }];

    [room sendTextMessage:@"This is text message" threadId:nil success:^(NSString *eventId) {

        messageEventId = eventId;

    } failure:^(NSError *error) {
        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
        [expectation fulfill];
    }];
}


#pragma mark - Tests on MXStore optional methods
- (void)checkUserDisplaynameAndAvatarUrl:(Class)mxStoreClass
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

        expectation = expectation2;

        id<MXStore> store = [[mxStoreClass alloc] init];
        [store openWithCredentials:matrixSDKTestsData.aliceCredentials onComplete:^{

            [store deleteAllData];

            XCTAssertNil([store userWithUserId:aliceRestClient.credentials.userId]);

            if ([store respondsToSelector:@selector(close)])
            {
                [store close];
            }

            XCTAssertNil([store userWithUserId:aliceRestClient.credentials.userId]);

            // Let's (and verify) MXSession start update the store with user information
            mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            [matrixSDKTestsData retain:mxSession];

            [mxSession setStore:store success:^{

                [mxSession start:^{

                    MXUser *myUser = [mxSession userWithUserId:aliceRestClient.credentials.userId];
                    XCTAssertEqual(myUser, mxSession.myUser);
                    XCTAssertEqualObjects(myUser.displayname, kMXTestsAliceDisplayName);
                    //XCTAssertEqualObjects(myUser.avatarUrl, kMXTestsAliceAvatarURL);    // Disabled because setting avatar does not work anymore with local test homeserver

                    [mxSession close];
                    mxSession = nil;

                    // Check user information is permanent
                    id<MXStore> store2 = [[mxStoreClass alloc] init];
                    [store2 openWithCredentials:matrixSDKTestsData.aliceCredentials onComplete:^{

                        MXUser *myUser = [store2 userWithUserId:aliceRestClient.credentials.userId];
                        XCTAssert([myUser isKindOfClass:MXMyUser.class]);
                        XCTAssertEqualObjects(myUser.displayname, kMXTestsAliceDisplayName);
                        //XCTAssertEqualObjects(myUser.avatarUrl, kMXTestsAliceAvatarURL);    // Disabled because setting avatar does not work anymore with local test homeserver

                        if ([store2 respondsToSelector:@selector(close)])
                        {
                            [store2 close];
                        }
                        [expectation fulfill];

                    } failure:^(NSError *error) {
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
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)checkUpdateUserDisplaynameAndAvatarUrl:(Class)mxStoreClass
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

        expectation = expectation2;

        id<MXStore> store = [[mxStoreClass alloc] init];
        [store openWithCredentials:matrixSDKTestsData.aliceCredentials onComplete:^{

            [store deleteAllData];

            XCTAssertNil([store userWithUserId:aliceRestClient.credentials.userId]);

            if ([store respondsToSelector:@selector(close)])
            {
                [store close];
            }

            XCTAssertNil([store userWithUserId:aliceRestClient.credentials.userId]);

            // Let's (and verify) MXSession start update the store with user information
            mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            [matrixSDKTestsData retain:mxSession];

            [mxSession setStore:store success:^{

                [mxSession start:^{

                    MXUser *myUser = [mxSession userWithUserId:aliceRestClient.credentials.userId];
                    XCTAssertEqual(myUser, mxSession.myUser);
                    XCTAssertEqualObjects(myUser.displayname, kMXTestsAliceDisplayName);
                    //XCTAssertEqualObjects(myUser.avatarUrl, kMXTestsAliceAvatarURL);    // Disabled because setting avatar does not work anymore with local test homeserver

                    [mxSession.myUser setDisplayName:@"Alicia" success:^{

                        XCTAssertEqualObjects(myUser.displayname, @"Alicia");

                        [mxSession.myUser setAvatarUrl:@"http://matrix.org/matrix.png" success:^{

                            XCTAssertEqualObjects(myUser.avatarUrl, @"http://matrix.org/matrix.png");

                            [mxSession close];
                            mxSession = nil;

                            // Check user information is permanent
                            id<MXStore> store2 = [[mxStoreClass alloc] init];
                            [store2 openWithCredentials:matrixSDKTestsData.aliceCredentials onComplete:^{

                                MXUser *myUser = [store2 userWithUserId:aliceRestClient.credentials.userId];
                                XCTAssertEqualObjects(myUser.displayname, @"Alicia");
                                XCTAssertEqualObjects(myUser.avatarUrl, @"http://matrix.org/matrix.png");

                                if ([store2 respondsToSelector:@selector(close)])
                                {
                                    [store2 close];
                                }
                                [expectation fulfill];

                            } failure:^(NSError *error) {
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
                } failure:^(NSError *error) {
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

- (void)checkMXSessionOnStoreDataReady:(Class)mxStoreClass
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;


        id<MXStore> store = [[mxStoreClass alloc] init];
        [store openWithCredentials:matrixSDKTestsData.bobCredentials onComplete:^{

            // Make sure to start from an empty store
            [store deleteAllData];

            MXUser *myUser = [store userWithUserId:matrixSDKTestsData.bobCredentials.userId];

            XCTAssertNil(myUser);
            XCTAssertEqual(store.roomSummaryStore.rooms.count, 0);

            if ([store respondsToSelector:@selector(close)])
            {
                [store close];
            }

            // Do a 1st [mxSession start] to fill the store
            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            [matrixSDKTestsData retain:mxSession];
            
            [mxSession setStore:store success:^{

                [mxSession start:^{

                    NSString *eventStreamToken = [store.eventStreamToken copy];
                    NSUInteger storeRoomsCount = store.roomSummaryStore.rooms.count;

                    [mxSession close];
                    mxSession = nil;

                    // Create another random room to create more data server side
                    [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

                        [bobRestClient sendTextMessageToRoom:response.roomId threadId:nil text:@"A Message" success:^(NSString *eventId) {

                            // Do a 2nd [mxSession start] with the filled store
                            id<MXStore> store2 = [[mxStoreClass alloc] init];

                            __block BOOL onStoreDataReadyCalled;

                            MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                            [matrixSDKTestsData retain:mxSession2];

                            [mxSession2 setStore:store2 success:^{
                                onStoreDataReadyCalled = YES;

                                XCTAssertEqual(mxSession2.rooms.count, storeRoomsCount, @"MXSessionOnStoreDataReady must have loaded as many MXRooms as room stored");
                                XCTAssertEqual(store2.roomSummaryStore.rooms.count, storeRoomsCount, @"There must still the same number of stored rooms");
                                XCTAssertEqualObjects(eventStreamToken, store2.eventStreamToken, @"The event stream token must not have changed yet");

                                [mxSession2 start:^{

                                    XCTAssert(onStoreDataReadyCalled, @"onStoreDataReady must alway be called before onServerSyncDone");

                                    XCTAssertEqual(mxSession2.rooms.count, storeRoomsCount + 1, @"MXSessionOnStoreDataReady must have loaded as many MXRooms as room stored");
                                    XCTAssertEqual(store2.roomSummaryStore.rooms.count, storeRoomsCount + 1, @"There must still the same number of stored rooms");
                                    XCTAssertNotEqualObjects(eventStreamToken, store2.eventStreamToken, @"The event stream token must not have changed yet");

                                    [mxSession2 close];

                                    [expectation fulfill];

                                } failure:^(NSError *error) {
                                    XCTFail(@"The request should not fail - NSError: %@", error);
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

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
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

- (void)checkRoomDeletion:(Class)mxStoreClass
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;

        id<MXStore> store = [[mxStoreClass alloc] init];

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession setStore:store success:^{

            [mxSession start:^{

                // Quit the newly created room
                MXRoom *room = [mxSession roomWithRoomId:roomId];
                [room leave:^{

                    XCTAssertEqual(NSNotFound, [store.roomSummaryStore.rooms indexOfObject:roomId], @"The room %@ must be no more in the store", roomId);

                    [mxSession close];
                    mxSession = nil;

                    // Reload the store, to be sure the room is no more here
                    id<MXStore> store2 = [[mxStoreClass alloc] init];
                    [store2 openWithCredentials:matrixSDKTestsData.bobCredentials onComplete:^{

                        XCTAssertEqual(NSNotFound, [store2.roomSummaryStore.rooms indexOfObject:roomId], @"The room %@ must be no more in the store", roomId);

                        if ([store2 respondsToSelector:@selector(close)])
                        {
                            [store2 close];
                        }

                        [expectation fulfill];

                    } failure:^(NSError *error) {
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

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Check that MXEvent.age and MXEvent.ageLocalTs are consistent after being stored.
- (void)checkEventAge:(Class)mxStoreClass
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;

        id<MXStore> store = [[mxStoreClass alloc] init];

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession setStore:store success:^{
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];
                
                [room.mxSession eventWithEventId:room.summary.lastMessage.eventId
                                          inRoom:room.roomId
                                         success:^(MXEvent *event) {
                    
                    NSUInteger age = event.age;
                    uint64_t ageLocalTs = event.ageLocalTs;

                    if ([store respondsToSelector:@selector(close)])
                    {
                        [store close];
                    }

                    [store openWithCredentials:matrixSDKTestsData.bobCredentials onComplete:^{

                        MXEvent *sameEvent = [store eventWithEventId:event.eventId inRoom:roomId];
                        XCTAssertNotNil(sameEvent);

                        NSUInteger sameEventAge = sameEvent.age;
                        uint64_t sameEventAgeLocalTs = sameEvent.ageLocalTs;

                        XCTAssertGreaterThan(sameEventAge, 0, @"MXEvent.age should strictly positive");
                        XCTAssertLessThanOrEqual(age, sameEventAge, @"MXEvent.age should auto increase");
                        XCTAssertLessThanOrEqual(sameEventAge - age, 1000, @"sameEventAge and age should be almost the same");

                        XCTAssertEqual(ageLocalTs, sameEventAgeLocalTs, @"MXEvent.ageLocalTs must still be the same");

                        [expectation fulfill];
                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
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

// Check the pagination token is valid after reloading the store
- (void)checkMXRoomPaginationToken:(Class)mxStoreClass
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;

        id<MXStore> store = [[mxStoreClass alloc] init];

        // Do a 1st [mxSession start] to fill the store
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession setStore:store success:^{
            [mxSession startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:5] onServerSyncDone:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                    [liveTimeline resetPagination];
                    [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                        NSString *roomPaginationToken = [store paginationTokenOfRoom:roomId];
                        XCTAssert(roomPaginationToken, @"The room must have a pagination after a pagination");

                        [mxSession close];
                        mxSession = nil;

                        // Reopen a session and check roomPaginationToken
                        id<MXStore> store2 = [[mxStoreClass alloc] init];

                        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                        [matrixSDKTestsData retain:mxSession];
                        [mxSession setStore:store2 success:^{

                            XCTAssertEqualObjects(roomPaginationToken, [store2 paginationTokenOfRoom:roomId], @"The store must keep the pagination token");

                            [mxSession start:^{

                                XCTAssertEqualObjects(roomPaginationToken, [store2 paginationTokenOfRoom:roomId], @"The store must keep the pagination token even after [MXSession start]");

                                [expectation fulfill];

                            } failure:^(NSError *error) {
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

- (void)checkMultiAccount:(Class)mxStoreClass
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        expectation = expectation2;

        id<MXStore> bobStore1 = [[mxStoreClass alloc] init];

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession setStore:bobStore1 success:^{
            [mxSession start:^{

                [mxSession close];
                mxSession = nil;

                id<MXStore> bobStore2 = [[mxStoreClass alloc] init];
                [bobStore2 openWithCredentials:matrixSDKTestsData.bobCredentials onComplete:^{

                    id<MXStore> aliceStore = [[mxStoreClass alloc] init];
                    [matrixSDKTestsData retain:aliceStore];

                    [aliceStore openWithCredentials:matrixSDKTestsData.aliceCredentials onComplete:^{

                        id<MXStore> bobStore3 = [[mxStoreClass alloc] init];
                        [bobStore3 openWithCredentials:matrixSDKTestsData.bobCredentials onComplete:^{

                            XCTAssertEqual(bobStore2.roomSummaryStore.rooms.count, bobStore3.roomSummaryStore.rooms.count);

                            if ([bobStore2 isKindOfClass:[MXFileStore class]])
                            {
                                [((MXFileStore*)bobStore2) diskUsageWithBlock:^(NSUInteger diskUsage2) {
                                    [((MXFileStore*)bobStore3) diskUsageWithBlock:^(NSUInteger diskUsage3) {

                                        XCTAssertEqual(diskUsage2, diskUsage3, @"Bob's store must still have the same content");
                                    }];
                                }];
                            }

                            [expectation fulfill];

                        } failure:^(NSError *error) {
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

- (void)checkRoomAccountDataTags:(Class)mxStoreClass
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation2) {

        expectation = expectation2;

        // Create 2 rooms with the same tag and one with another
        NSString *tag1 = [[NSProcessInfo processInfo] globallyUniqueString];
        NSString *tag2 = [[NSProcessInfo processInfo] globallyUniqueString];

        // Room #1
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"2" success:^(MXCreateRoomResponse *response) {
            [bobRestClient addTag:tag1 withOrder:@"0.2"  toRoom:response.roomId success:^{

                // Room #2
                [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"1" success:^(MXCreateRoomResponse *response) {
                    [bobRestClient addTag:tag1 withOrder:@"0.1" toRoom:response.roomId success:^{

                        // Room #3
                        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"the only one" success:^(MXCreateRoomResponse *response) {
                            [bobRestClient addTag:tag2 withOrder:@"0.1" toRoom:response.roomId success:^{


                                // Do the test
                                id<MXStore> store = [[mxStoreClass alloc] init];
                                [store openWithCredentials:matrixSDKTestsData.bobCredentials onComplete:^{

                                    // Make sure to start from an empty store
                                    [store deleteAllData];

                                    if ([store respondsToSelector:@selector(close)])
                                    {
                                        [store close];
                                    }

                                    // Do a 1st [mxSession start] to fill the store
                                    mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                                    [matrixSDKTestsData retain:mxSession];
                                    
                                    [mxSession setStore:store success:^{
                                        [mxSession start:^{

                                            [mxSession close];
                                            mxSession = nil;

                                            // Reopen a session and check roomAccountData
                                            id<MXStore> store2 = [[mxStoreClass alloc] init];

                                            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                                            [matrixSDKTestsData retain:mxSession];
                                            
                                            [mxSession setStore:store2 success:^{

                                                NSArray<MXRoom*> *roomsWithTagTag1 = [mxSession roomsWithTag:tag1];
                                                XCTAssertEqual(roomsWithTagTag1.count, 2);
                                                if (roomsWithTagTag1.count >= 2)
                                                {
                                                    XCTAssertEqualObjects(roomsWithTagTag1[0].accountData.tags[tag1].order, @"0.1");
                                                    XCTAssertEqualObjects(roomsWithTagTag1[1].accountData.tags[tag1].order, @"0.2");
                                                }

                                                NSArray<MXRoom*> *roomsWithTagTag2 = [mxSession roomsWithTag:tag2];
                                                XCTAssertEqual(roomsWithTagTag2.count, 1);
                                                if (roomsWithTagTag2.count >= 1)
                                                {
                                                    XCTAssertEqualObjects(roomsWithTagTag2[0].accountData.tags[tag2].order, @"0.1");
                                                }

                                                [expectation fulfill];

                                            } failure:^(NSError *error) {
                                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                                [expectation fulfill];
                                            }];

                                        } failure:^(NSError *error) {
                                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                            [expectation fulfill];
                                        }];

                                    } failure:^(NSError *error) {
                                        XCTFail(@"The request should not fail - NSError: %@", error);
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
                        } failure:^(NSError *error) {
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

- (void)checkRoomSummary:(Class)mxStoreClass
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation2) {

        expectation = expectation2;

        // Create a random room
        [bobRestClient createRoom:@"A name" visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"A topic" success:^(MXCreateRoomResponse *response) {

            // Do the test
            id<MXStore> store = [[mxStoreClass alloc] init];
            [store openWithCredentials:matrixSDKTestsData.bobCredentials onComplete:^{

                // Make sure to start from an empty store
                [store deleteAllData];

                if ([store respondsToSelector:@selector(close)])
                {
                    [store close];
                }

                // Do a 1st [mxSession start] to fill the store
                mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                [matrixSDKTestsData retain:mxSession];
                
                [mxSession setStore:store success:^{
                    [mxSession start:^{

                        [mxSession close];
                        mxSession = nil;

                        // Reopen a session and check roomSummary
                        id<MXStore> store2 = [[mxStoreClass alloc] init];

                        [store2 openWithCredentials:bobRestClient.credentials onComplete:^{
                            id<MXRoomSummaryProtocol> summary = [store2.roomSummaryStore summaryOfRoom:response.roomId];

                            XCTAssert(summary);

                            XCTAssertEqualObjects(summary.displayName, @"A name");
                            XCTAssertEqualObjects(summary.topic, @"A topic");

                            [expectation fulfill];

                        } failure:^(NSError *error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
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

@end

#pragma clang diagnostic pop
