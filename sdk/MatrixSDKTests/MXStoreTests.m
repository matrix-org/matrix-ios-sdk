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

#import "MXNoStore.h"
#import "MXMemoryStore.h"
#import "MXFileStore.h"

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXStoreTests : XCTestCase
{
    MXSession *mxSession;

    // The current test expectation
    XCTestExpectation *expectation;
}
@end

@implementation MXStoreTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    if (mxSession)
    {
        [[MatrixSDKTestsData sharedData] closeMXSession:mxSession];
        mxSession = nil;
    }
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

    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:testCase readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        if (!expectation)
        {
            expectation = expectation2;
        }

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession setStore:store success:^{

            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                readyToTest(room);

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
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

    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    [sharedData doMXRestClientTestWithBobAndAliceInARoom:testCase readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        [sharedData for:bobRestClient andRoom:roomId sendMessages:5 success:^{

            if (!expectation)
            {
                expectation = expectation2;
            }

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

            [mxSession setStore:store success:^{
                [mxSession start:^{

                    MXRoom *room = [mxSession roomWithRoomId:roomId];

                    readyToTest(room);

                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];

    }];
}

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

- (void)doTestWithMXMemoryStore:(void (^)(MXRoom *room))readyToTest
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self doTestWithStore:store readyToTest:readyToTest];
}

- (void)doTestWithTwoUsersAndMXMemoryStore:(void (^)(MXRoom *room))readyToTest
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self doTestWithTwoUsersAndStore:store readyToTest:readyToTest];
}

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

    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:testCase readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

        if (!expectation)
        {
            expectation = expectation2;
        }

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [mxSession setStore:store success:^{

            [mxSession startWithMessagesLimit:messagesLimit onServerSyncDone:^{
                MXRoom *room = [mxSession roomWithRoomId:roomId];

                readyToTest(room);

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];


    }];
}

- (void)doTestWithMXNoStoreAndMessagesLimit:(NSUInteger)messagesLimit readyToTest:(void (^)(MXRoom *room))readyToTest
{
    MXNoStore *store = [[MXNoStore alloc] init];
    [self doTestWithStore:store andMessagesLimit:messagesLimit readyToTest:readyToTest];
}

- (void)doTestWithMXMemoryStoreAndMessagesLimit:(NSUInteger)messagesLimit readyToTest:(void (^)(MXRoom *room))readyToTest
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self doTestWithStore:store andMessagesLimit:messagesLimit readyToTest:readyToTest];
}

- (void)doTestWithMXFileStoreAndMessagesLimit:(NSUInteger)messagesLimit readyToTest:(void (^)(MXRoom *room))readyToTest
{
    MXFileStore *store = [[MXFileStore alloc] init];
    [self doTestWithStore:store andMessagesLimit:messagesLimit readyToTest:readyToTest];
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

- (void)checkEventWithEventIdOfStore:(id<MXStore>)store
{
    MXEvent *event = [MXEvent modelFromJSON:@{@"event_id" : @"anID"}];

    [store storeEventForRoom:@"roomId" event:event direction:MXEventDirectionForwards];

    MXEvent *storedEvent = [store eventWithEventId:@"anID" inRoom:@"roomId"];

    XCTAssertEqualObjects(storedEvent, event);

    [expectation fulfill];
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
    [room listenToEventsOfTypes:eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        eventCount++;
    }];

    [room resetBackState];
    [room paginateBackMessages:5 complete:^() {

        XCTAssertEqual(eventCount, 5, @"We should get as many messages as requested");

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
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
    [room listenToEventsOfTypes:eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        eventCount++;

        // Only events with a type declared in `eventsFilterForMessages`
        // must appear in messages
        XCTAssertNotEqual([eventsFilterForMessages indexOfObject:event.type], NSNotFound, "Event of this type must not be in messages. Event: %@", event);

    }];

    [room resetBackState];
    [room paginateBackMessages:100 complete:^() {

        XCTAssert(eventCount, "We should have received events in registerEventListenerForTypes");

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
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
    [room listenToEventsOfTypes:eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        XCTAssert(event.originServerTs, @"The event should have an attempt: %@", event);

        XCTAssertLessThanOrEqual(event.originServerTs, prev_ts, @"Events in messages must be listed  one by one in antichronological order");
        prev_ts = event.originServerTs;

    }];

    [room resetBackState];
    [room paginateBackMessages:100 complete:^() {

        XCTAssertNotEqual(prev_ts, -1, "We should have received events in registerEventListenerForTypes");

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}

- (void)checkPaginateBackDuplicates:(MXRoom*)room
{
    __block NSUInteger eventCount = 0;
    __block NSMutableArray *events = [NSMutableArray array];
    [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        eventCount++;

        [events addObject:event];
    }];

    [room resetBackState];
    [room paginateBackMessages:100 complete:^() {

        XCTAssert(eventCount, "We should have received events in registerEventListenerForTypes");

        [self assertNoDuplicate:events text:@"events got one by one with paginateBackMessages"];

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];

}

- (void)checkSeveralPaginateBacks:(MXRoom*)room
{
    __block NSMutableArray *roomEvents = [NSMutableArray array];
    [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        [roomEvents addObject:event];
    }];

    [room resetBackState];
    [room paginateBackMessages:100 complete:^() {

        // Use another MXRoom instance to do pagination in several times
        MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.state.roomId andMatrixSession:mxSession];

        __block NSMutableArray *room2Events = [NSMutableArray array];
        [room2 listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

            [room2Events addObject:event];
        }];

        // The several paginations
        [room2 resetBackState];

        if ([mxSession.store isKindOfClass:[MXMemoryStore class]])
        {
            XCTAssertGreaterThanOrEqual(room2.remainingMessagesForPaginationInStore, 7);
        }

        [room2 paginateBackMessages:2 complete:^() {

            if ([mxSession.store isKindOfClass:[MXMemoryStore class]])
            {
                XCTAssertGreaterThanOrEqual(room2.remainingMessagesForPaginationInStore, 5);
            }

            [room2 paginateBackMessages:5 complete:^() {

                [room2 paginateBackMessages:100 complete:^() {

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
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}

- (void)checkPaginateWithLiveEvents:(MXRoom*)room
{
    __block NSMutableArray *roomEvents = [NSMutableArray array];

    // Use another MXRoom instance to paginate while receiving live events
    MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.state.roomId andMatrixSession:mxSession];

    __block NSMutableArray *room2Events = [NSMutableArray array];
    [room2 listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        if (MXEventDirectionForwards != direction)
        {
            [room2Events addObject:event];
        }
    }];

    __block NSUInteger liveEvents = 0;
    [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        if (MXEventDirectionForwards == direction)
        {
            // Do some paginations after receiving live events
            liveEvents++;
            if (1 == liveEvents)
            {
                if ([mxSession.store isKindOfClass:[MXMemoryStore class]])
                {
                    XCTAssertGreaterThanOrEqual(room2.remainingMessagesForPaginationInStore, 7);
                }

                [room2 paginateBackMessages:2 complete:^() {

                    if ([mxSession.store isKindOfClass:[MXMemoryStore class]])
                    {
                        XCTAssertGreaterThanOrEqual(room2.remainingMessagesForPaginationInStore, 5);
                    }

                    // Try with 2 more live events
                    [room sendTextMessage:@"How is the pagination #2?" success:nil failure:nil];
                    [room sendTextMessage:@"How is the pagination #3?" success:nil failure:nil];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }
            else if (3 == liveEvents)

                [room2 paginateBackMessages:5 complete:^() {

                    [room2 paginateBackMessages:100 complete:^() {

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
        else
        {
            [roomEvents addObject:event];
        }
    }];

    // Take a snapshot of all room history
    [room resetBackState];
    [room paginateBackMessages:100 complete:^{

        // Messages are now in the cache
        // Start checking pagination from the cache
        [room2 resetBackState];

        [room sendTextMessage:@"How is the pagination #1?" success:nil failure:nil];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}


- (void)checkCanPaginateFromHomeServer:(MXRoom*)room
{
    [room resetBackState];
    XCTAssertTrue(room.canPaginate, @"We can always paginate at the beginning");

    [room paginateBackMessages:100 complete:^() {

        XCTAssertFalse(room.canPaginate, @"We must have reached the end of the pagination");

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}

- (void)checkCanPaginateFromMXStore:(MXRoom*)room
{
    [room resetBackState];
    XCTAssertTrue(room.canPaginate, @"We can always paginate at the beginning");

    [room paginateBackMessages:100 complete:^() {

        XCTAssertFalse(room.canPaginate, @"We must have reached the end of the pagination");

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}

- (void)checkLastMessageAfterPaginate:(MXRoom*)room
{
    MXEvent *lastMessage = [room lastMessageWithTypeIn:nil];
    XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMessage);

    [room resetBackState];
    XCTAssertEqual([room lastMessageWithTypeIn:nil], lastMessage, @"The last message should stay the same");

    [room paginateBackMessages:100 complete:^() {

        XCTAssertEqual([room lastMessageWithTypeIn:nil], lastMessage, @"The last message should stay the same");

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}

- (void)checkPaginateWhenJoiningAgainAfterLeft:(MXRoom*)room
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

        [mxSession.matrixRestClient inviteUser:aliceRestClient.credentials.userId toRoom:room.state.roomId success:^{

            NSString *roomId = room.state.roomId;

            // Leave the room
            [room leave:^{

                __block NSString *aliceTextEventId;

                // Listen for the invitation by Alice
                [mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXEventDirection direction, id customObject) {

                    // Join the room again
                    MXRoom *room2 = [mxSession roomWithRoomId:roomId];

                    XCTAssertNotNil(room2);

                    if (direction == MXEventDirectionForwards && MXMembershipInvite == room2.state.membership)
                    {
                        // Join the room on the invitation and check we can paginate all expected text messages
                        [room2 join:^{

                            NSMutableArray *events = [NSMutableArray array];
                            [room2 listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                                if (0 == events.count)
                                {
                                    // The most recent message must be "Hi bob" sent by Alice
                                    XCTAssertEqualObjects(aliceTextEventId, event.eventId);
                                }

                                [events addObject:event];

                            }];

                            [room2 resetBackState];
                            [room2 paginateBackMessages:100 complete:^{

                                XCTAssertEqual(events.count, 6, "The room should contain 5 + 1 messages");
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
                }];

                // Make Alice send text message while Bob is not in the room.
                // Then, invite him.
                [aliceRestClient joinRoom:roomId success:^(NSString *roomName){

                    [aliceRestClient sendTextMessageToRoom:roomId text:@"Hi bob"  success:^(NSString *eventId) {

                        aliceTextEventId = eventId;

                        [aliceRestClient inviteUser:mxSession.matrixRestClient.credentials.userId toRoom:roomId success:^{

                        } failure:^(NSError *error) {
                            NSAssert(NO, @"Cannot set up intial test conditions");
                        }];

                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions");
                    }];

                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions");
                }];

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions");
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions");
        }];
    }];
}

// Test for https://matrix.org/jira/browse/SYN-162
- (void)checkPaginateWhenReachingTheExactBeginningOfTheRoom:(MXRoom*)room
{
    __block NSUInteger eventCount = 0;
    [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        eventCount++;
    }];

    // First count how many messages to retrieve
    [room resetBackState];
    [room paginateBackMessages:100 complete:^() {

        // Paginate for the exact number of events in the room
        NSUInteger pagEnd = eventCount;
        eventCount = 0;
        [room resetBackState];
        [room paginateBackMessages:pagEnd complete:^{

            XCTAssertEqual(eventCount, pagEnd, @"We should get as many messages as requested");

            XCTAssert(room.canPaginate, @"At this point the SDK cannot know it reaches the beginning of the history");

            // Try to load more messages
            eventCount = 0;
            [room paginateBackMessages:1 complete:^{

                XCTAssertEqual(eventCount, 0, @"There must be no more event");
                XCTAssertFalse(room.canPaginate, @"SDK must now indicate there is no more event to paginate");

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - see SYN-162 - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    } failure:^(NSError *error) {
        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        [expectation fulfill];
    }];
}

- (void)checkRedactEvent:(MXRoom*)room
{
    __block NSString *messageEventId;

    [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

        if (MXEventTypeRoomMessage == event.eventType)
        {
            // Manage the case where message comes down the stream before the call of the success
            // callback of [room sendTextMessage:...]
            if (nil == messageEventId)
            {
                messageEventId = event.eventId;
            }

            MXEvent *notYetRedactedEvent = [mxSession.store eventWithEventId:messageEventId inRoom:room.state.roomId];

            XCTAssertGreaterThan(notYetRedactedEvent.content.count, 0);
            XCTAssertNil(notYetRedactedEvent.redacts);
            XCTAssertNil(notYetRedactedEvent.redactedBecause);

            // Redact this event
            [room redactEvent:messageEventId reason:@"No reason" success:^{

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }
        else if (MXEventTypeRoomRedaction == event.eventType)
        {
            MXEvent *redactedEvent = [mxSession.store eventWithEventId:messageEventId inRoom:room.state.roomId];

            XCTAssertEqual(redactedEvent.content.count, 0, @"Redacted event content must be now empty");
            XCTAssertEqualObjects(event.eventId, redactedEvent.redactedBecause[@"event_id"], @"It must contain the event that redacted it");

            // Tests more related to redaction (could be moved to a dedicated section somewhere else)
            XCTAssertEqualObjects(event.redacts, messageEventId, @"");

            [expectation fulfill];
        }

    }];

    [room sendTextMessage:@"This is text message" success:^(NSString *eventId) {

        messageEventId = eventId;

    } failure:^(NSError *error) {
        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        [expectation fulfill];
    }];
}


#pragma mark - MXNoStore tests
/* This feature is not available with MXNoStore
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
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
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
    // room.canPaginate will use [MXStore canPaginateInRoom]
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

/* Disabled while SYN-162 is not fixed
 - (void)testMXNoStorePaginateWhenReachingTheExactBeginningOfTheRoom
 {
     [self doTestWithMXNoStore:^(MXRoom *room) {
         [self checkPaginateWhenReachingTheExactBeginningOfTheRoom:room];
     }];
 }
 */


#pragma mark - MXMemoryStore
- (void)testMXMemoryEventWithEventId
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self checkEventWithEventIdOfStore:store];
}

- (void)testMXMemoryStorePaginateBack
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBack:room];
    }];
}

- (void)testMXMemoryStorePaginateBackFilter
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBackFilter:room];
    }];
}

- (void)testMXMemoryStorePaginateBackOrder
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBackOrder:room];
    }];
}

- (void)testMXMemoryStorePaginateBackDuplicates
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

// This test illustrates bug SYIOS-9
- (void)testMXMemoryStorePaginateBackDuplicatesInRoomWithTwoUsers
{
    [self doTestWithTwoUsersAndMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

- (void)testMXMemoryStoreSeveralPaginateBacks
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkSeveralPaginateBacks:room];
    }];
}

- (void)testMXMemoryStorePaginateWithLiveEvents
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateWithLiveEvents:room];
    }];
}

- (void)testMXMemoryStoreCanPaginateFromHomeServer
{
    // Preload less messages than the room history counts so that there are still requests to the HS to do
    [self doTestWithMXMemoryStoreAndMessagesLimit:1 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromHomeServer:room];
    }];
}

- (void)testMXMemoryStoreCanPaginateFromMXStore
{
    // Preload more messages than the room history counts so that all messages are already loaded
    // room.canPaginate will use [MXStore canPaginateInRoom]
    [self doTestWithMXMemoryStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromMXStore:room];
    }];
}

- (void)testMXMemoryStoreLastMessageAfterPaginate
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkLastMessageAfterPaginate:room];
    }];
}

- (void)testMXMemoryStorePaginateWhenJoiningAgainAfterLeft
{
    [self doTestWithMXMemoryStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkPaginateWhenJoiningAgainAfterLeft:room];
    }];
}

- (void)testMXMemoryStoreAndHomeServerPaginateWhenJoiningAgainAfterLeft
{
    // Not preloading all messages of the room causes a duplicated event issue with MXMemoryStore
    // See `testMXMemoryStorePaginateBackDuplicatesInRoomWithTwoUsers`.
    // Check here if MXMemoryStore is able to filter this duplicate
    [self doTestWithMXMemoryStoreAndMessagesLimit:10 readyToTest:^(MXRoom *room) {
        [self checkPaginateWhenJoiningAgainAfterLeft:room];
    }];
}

/* Disabled while SYN-162 is not fixed
 - (void)testMXMemoryStorePaginateWhenReachingTheExactBeginningOfTheRoom
 {
     [self doTestWithMXMemoryStore:^(MXRoom *room) {
         [self checkPaginateWhenReachingTheExactBeginningOfTheRoom:room];
     }];
 }
 */

- (void)testMXMemoryStoreRedactEvent
{
    [self doTestWithMXMemoryStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkRedactEvent:room];
    }];
}


#pragma mark - MXMemoryStore specific tests
- (void)testMXMemoryStorePaginate
{
    [self doTestWithMXMemoryStoreAndMessagesLimit:0 readyToTest:^(MXRoom *room) {

        __block NSUInteger eventCount = 0;
        __block MXEvent *firstEventInTheRoom;
        [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

            eventCount++;

            firstEventInTheRoom = event;
        }];

        // First make a call to paginateBackMessages that will make a request to the server
        [room resetBackState];
        [room paginateBackMessages:100 complete:^{

            XCTAssertEqual(firstEventInTheRoom.eventType, MXEventTypeRoomCreate, @"First event in a room is always m.room.create");

            [room removeAllListeners];

            __block NSUInteger eventCount2 = 0;
            __block MXEvent *firstEventInTheRoom2;
            [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                eventCount2++;

                firstEventInTheRoom2 = event;
            }];

            [room resetBackState];
            [room paginateBackMessages:100 complete:^{

                XCTAssertEqual(eventCount, eventCount2);
                XCTAssertEqual(firstEventInTheRoom2.eventType, MXEventTypeRoomCreate, @"First event in a room is always m.room.create");
                XCTAssertEqualObjects(firstEventInTheRoom, firstEventInTheRoom2);

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


- (void)testMXMemoryStorePaginateAgain
{
    [self doTestWithMXMemoryStoreAndMessagesLimit:0 readyToTest:^(MXRoom *room) {

        __block NSInteger paginateBackMessagesCallCount = 0;

        __block NSMutableArray *roomEvents = [NSMutableArray array];
        [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

            XCTAssertEqual(paginateBackMessagesCallCount, 1, @"Messages must asynchronously come");

            [roomEvents addObject:event];
        }];

        [room resetBackState];
        [room paginateBackMessages:8 complete:^() {

            [room removeAllListeners];

            __block NSMutableArray *room2Events = [NSMutableArray array];
            [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                [room2Events addObject:event];

                if (room2Events.count <=2)
                {
                    XCTAssertEqual(paginateBackMessagesCallCount, 1, @"Messages for 'paginateBackMessages:2' must synchronously come");
                }
                else if (room2Events.count <=7)
                {
                    XCTAssertEqual(paginateBackMessagesCallCount, 1, @"Messages for 'paginateBackMessages:5' must synchronously come");
                }
                else if (room2Events.count <=8)
                {
                    XCTAssertEqual(paginateBackMessagesCallCount, 1, @"The first messages for 'paginateBackMessages:100' must synchronously come");
                }
                else
                {
                    XCTAssertEqual(paginateBackMessagesCallCount, 4, @"Other Messages for 'paginateBackMessages:100' must ssynchronously come");
                }
            }];

            XCTAssertTrue(room.canPaginate, @"There is still at least one event to retrieve from the server");

            // The several paginations
            [room resetBackState];
            [room paginateBackMessages:2 complete:^() {

                [room paginateBackMessages:5 complete:^() {

                    [room paginateBackMessages:100 complete:^() {

                        // Now, compare the result with the reference
                        XCTAssertEqual(roomEvents.count, 8);
                        XCTAssertGreaterThan(room2Events.count, roomEvents.count);

                        // Compare events one by one
                        for (NSUInteger i = 0; i < roomEvents.count; i++)
                        {
                            MXEvent *event = roomEvents[i];
                            MXEvent *event2 = room2Events[i];

                            XCTAssertTrue([event2.eventId isEqualToString:event.eventId], @"Events mismatch: %@ - %@", event, event2);
                        }

                        XCTAssertFalse(room.canPaginate, @"We reach the beginning of the history");

                        [room resetBackState];
                        XCTAssertTrue(room.canPaginate, @"We must be able to paginate again");

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                    paginateBackMessagesCallCount++;

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

                paginateBackMessagesCallCount++;

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            paginateBackMessagesCallCount++;

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
        paginateBackMessagesCallCount++;

    }];
}

- (void)testMXMemoryStoreLastMessage
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {

        [room resetBackState];
        [room paginateBackMessages:8 complete:^() {

            MXEvent *lastMessage = [room lastMessageWithTypeIn:nil];
            XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMessage);

            lastMessage = [room lastMessageWithTypeIn:@[kMXEventTypeStringRoomMessage]];
            XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMessage);

            lastMessage = [room lastMessageWithTypeIn:@[kMXEventTypeStringRoomMember]];
            XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMember);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];

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

/* Disabled while SYN-162 is not fixed
 - (void)testMXFileStorePaginateWhenReachingTheExactBeginningOfTheRoom
 {
     [self doTestWithMXFileStore:^(MXRoom *room) {
         [self checkPaginateWhenReachingTheExactBeginningOfTheRoom:room];
     }];
 }
 */

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

@end

#pragma clang diagnostic pop
