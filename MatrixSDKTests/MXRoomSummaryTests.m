/*
 Copyright 2017 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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
#import "MatrixSDKTestsE2EData.h"

#import "MXMemoryStore.h"
#import "MXFileStore.h"

#import "MXRoomSummaryUpdater.h"

#import "MXCrypto_Private.h"

#import "MXTools.h"


// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"


@interface MXRoomSummaryTests : XCTestCase <MXRoomSummaryUpdating>
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

    id observer;

    // Flags to check the delegate has been called
    BOOL testDelegate;
    BOOL testNoChangeDelegate;
}

@end

NSString *testDelegateLastMessageString = @"The string I decider to render for this event";
NSString *uisiString = @"The sender's device has not sent us the keys for this message.";


@implementation MXRoomSummaryTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
}

- (void)tearDown
{
    if (observer)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        observer = nil;
    }

    matrixSDKTestsData = nil;

    [super tearDown];
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withLastEvent:(MXEvent *)event eventState:(MXRoomState *)eventState roomState:(MXRoomState *)roomState
{
    BOOL updated = NO;

    if (event.isLocalEvent)
    {
        // Do not care about local echo
        return NO;
    }

    if ([self.description containsString:@"testDelegate"])
    {
        XCTAssertNotEqualObjects(summary.lastMessageEventId, event.eventId);

        // Do a classic update
        MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:session];
        updated = [updater session:session updateRoomSummary:summary withLastEvent:event eventState:eventState roomState:roomState];

        summary.lastMessageString = testDelegateLastMessageString;

        XCTAssert(updated);
        XCTAssertEqualObjects(summary.lastMessageEventId, event.eventId);

        testDelegate = YES;
    }
    else if ([self.description containsString:@"testNoChangeDelegate"])
    {
        testNoChangeDelegate = YES;

        // Force a kMXRoomSummaryDidChangeNotification
        [summary save:NO];
    }
    else if ([self.description containsString:@"testGetLastMessageFromSeveralPaginations"])
    {
        if (event.eventType == MXEventTypeRoomMessage)
        {
            updated = NO;
        }
        else
        {
            summary.lastMessageEvent = event;
            updated = YES;
        }
    }
    else if ([self.description containsString:@"testStatePassedToMXRoomSummaryUpdating"])
    {
        XCTAssertNotEqualObjects(eventState.name, @"A room", @"The passed state must be the state of room when the event occured, not the current room state");

        // Do a classic update
        MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:session];
        updated = [updater session:session updateRoomSummary:summary withLastEvent:event eventState:eventState roomState:roomState];
    }
    else if ([self.description containsString:@"testDoNotStoreDecryptedData"]
             || [self.description containsString:@"testEncryptedLastMessageEvent"]
             || [self.description containsString:@"testNotificationCountUpdate"])
    {
        // Do a classic update
        MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:session];
        updated = [updater session:session updateRoomSummary:summary withLastEvent:event eventState:eventState roomState:roomState];

        summary.lastMessageString = event.content[@"body"];
    }
    else if ([self.description containsString:@"testLateRoomKey"])
    {
        // Do a classic update
        MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:session];
        updated = [updater session:session updateRoomSummary:summary withLastEvent:event eventState:eventState roomState:roomState];

        if (event.eventType == MXEventTypeRoomEncrypted)
        {
            summary.lastMessageString = uisiString;
        }
        else
        {
            summary.lastMessageString = event.content[@"body"];
        }
    }
    else
    {
        XCTFail(@"Unexpected delegate call in %@", self);
    }

    return updated;
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withStateEvents:(NSArray<MXEvent *> *)stateEvents roomState:(MXRoomState *)roomState
{
    // Do a classic update
    MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:session];
    return [updater session:session updateRoomSummary:summary withStateEvents:stateEvents roomState:roomState];
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary roomState:(MXRoomState *)roomState
{
    // Do a classic update
    MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:session];
    return [updater session:session updateRoomSummary:summary withServerRoomSummary:serverRoomSummary roomState:roomState];
}

- (void)test
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummary *summary = room.summary;
        XCTAssert(summary);

        XCTAssertEqualObjects(summary.roomId, room.roomId);
        XCTAssert(summary.lastMessageEventId);

        [expectation fulfill];

    }];
}

- (void)testDelegate
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummary *summary = room.summary;
        mxSession.roomSummaryUpdateDelegate = self;

        __block NSString *lastMessageEventId;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            XCTAssert(testDelegate);
            XCTAssertEqualObjects(summary.lastMessageEventId, lastMessageEventId);
            XCTAssertEqualObjects(summary.lastMessageString, testDelegateLastMessageString);

            [expectation fulfill];
        }];

        [room sendTextMessage:@"new message" success:^(NSString *eventId) {
            lastMessageEventId = eventId;
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testNoChangeDelegate
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummary *summary = room.summary;
        mxSession.roomSummaryUpdateDelegate = self;

        MXEvent *lastMessageEvent = summary.lastMessageEvent;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            XCTAssert(testNoChangeDelegate);
            XCTAssertEqualObjects(summary.lastMessageEvent.eventId, lastMessageEvent.eventId);

            [expectation fulfill];
        }];

        [room sendTextMessage:@"new message" success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testGetLastMessageFromPagination
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient = mxSession.matrixRestClient;
        NSString *roomId = room.roomId;

        MXRoomSummary *summary = [mxSession roomSummaryWithRoomId:roomId];
        XCTAssert(summary);
        XCTAssert(summary.lastMessageEventId);

        [mxSession close];

        MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession2 setStore:[[MXMemoryStore alloc] init] success:^{

            // Start a new session by loading no message
            [mxSession2 startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:0] onServerSyncDone:^{

                MXRoomSummary *summary2 = [mxSession2 roomSummaryWithRoomId:roomId];

                XCTAssert(summary2);
                XCTAssertNil(summary2.lastMessageEventId, @"We asked for loading 0 message. So, we cannot know the last message yet");

                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary2 queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    XCTAssert(summary2);
                    XCTAssert(summary2.lastMessageEventId, @"We must have an event now");
                    XCTAssertFalse(summary.isLastMessageEncrypted);

                    MXEvent *event2 = summary2.lastMessageEvent;

                    XCTAssert(event2);
                    XCTAssertEqual(event2.eventType, MXEventTypeRoomMessage);

                    [expectation fulfill];
                }];

                // Force the summary to fetch events from the homeserver to get the last one
                MXHTTPOperation *operation = [summary2 resetLastMessageWithMaxServerPaginationCount:100 onComplete:nil failure:^(NSError *error) {

                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                    
                } commit:YES];

                XCTAssert(operation, @"An HTTP operation is required for that");
                XCTAssert([operation isKindOfClass:MXHTTPOperation.class]);

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

- (void)testGetLastMessageFromSeveralPaginations
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient = mxSession.matrixRestClient;
        NSString *roomId = room.roomId;

        // Add more messages than a single pagination can retrieve
        [matrixSDKTestsData for:bobRestClient andRoom:roomId sendMessages:80 testCase:self success:^{

            MXRoomSummary *summary = [mxSession roomSummaryWithRoomId:roomId];
            XCTAssert(summary);
            XCTAssert(summary.lastMessageEventId);

            [mxSession close];

            MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

            // Configure the updater so that it refuses room messages as last message
            mxSession2.roomSummaryUpdateDelegate = self;

            [mxSession2 setStore:[[MXMemoryStore alloc] init] success:^{

                // Start a new session by loading no message
                [mxSession2 startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:0] onServerSyncDone:^{

                    MXRoomSummary *summary2 = [mxSession2 roomSummaryWithRoomId:roomId];

                    XCTAssert(summary2);
                    XCTAssertNil(summary2.lastMessageEventId, @"We asked for loading 0 message. So, we cannot know the last message yet");


                    // Force the summary to fetch events from the homeserver to get the last one
                    MXHTTPOperation *operation = [summary2 resetLastMessageWithMaxServerPaginationCount:1000 onComplete:nil failure:^(NSError *error) {

                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];

                    } commit:YES];

                    XCTAssert(operation, @"An HTTP operation is required for that");
                    XCTAssert([operation isKindOfClass:MXHTTPOperation.class]);

                    NSURLSessionDataTask *urlSessionDataTask = operation.operation;

                    observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary2 queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                        XCTAssert(summary2);
                        XCTAssert(summary2.lastMessageEventId, @"We must have an event now");

                        MXEvent *event2 = summary2.lastMessageEvent;
                        XCTAssert(event2);

                        XCTAssertNotEqual(urlSessionDataTask, operation.operation, @"operation should have mutated as several http requests are required");
                        
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
    }];
}


- (void)testFixRoomsSummariesLastMessage
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient = mxSession.matrixRestClient;
        NSString *roomId = room.roomId;

        MXRoomSummary *summary = [mxSession roomSummaryWithRoomId:roomId];
        XCTAssert(summary);
        XCTAssert(summary.lastMessageEventId);

        [mxSession close];

        MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession2 setStore:[[MXMemoryStore alloc] init] success:^{

            // Start a new session by loading no message
            [mxSession2 startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:0] onServerSyncDone:^{

                MXRoomSummary *summary2 = [mxSession2 roomSummaryWithRoomId:roomId];

                XCTAssert(summary2);
                XCTAssertNil(summary2.lastMessageEventId, @"We asked for loading 0 message. So, we cannot know the last message yet");

                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary2 queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    XCTAssert(summary2);
                    XCTAssert(summary2.lastMessageEventId, @"We must have an event now");

                    MXEvent *event2 = summary2.lastMessageEvent;

                    XCTAssert(event2);
                    XCTAssertEqual(event2.eventType, MXEventTypeRoomMessage);

                    [expectation fulfill];
                }];

                // Force the summary to fetch events from the homeserver to get the last one
                [mxSession2 fixRoomsSummariesLastMessage];

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

- (void)testDisplaynameUpdate
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummary *summary = room.summary;

        NSString *displayName = @"A room";

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

             XCTAssertEqualObjects(summary.displayname, displayName, @"Room summary must be updated");

             [expectation fulfill];
         }];

        [room setName:displayName success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Check membership when:
//  - the user is in the room
//  - he has left it
- (void)testMembership
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        XCTAssertEqual(room.summary.membership, MXMembershipJoin);

        [room liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if (direction == MXTimelineDirectionForwards)
                {
                    XCTAssertEqual(room.summary.membership, MXMembershipLeave);

                    [expectation fulfill];
                }
            }];
        }];

        [room leave:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Check members count when:
//  - Bob is the only one in a room
//  - Bob has invited Alice
- (void)testMembersCount
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        XCTAssertEqual(room.summary.membersCount.members, 1);
        XCTAssertEqual(room.summary.membersCount.joined, 1);
        XCTAssertEqual(room.summary.membersCount.invited, 0);

        [matrixSDKTestsData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {

            [room liveTimeline:^(MXEventTimeline *liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    if (direction == MXTimelineDirectionForwards)
                    {
                        XCTAssertEqual(room.summary.membersCount.members, 2);
                        XCTAssertEqual(room.summary.membersCount.joined, 1);
                        XCTAssertEqual(room.summary.membersCount.invited, 1);

                        [expectation fulfill];
                    }
                }];
            }];

            [room inviteUser:aliceSession.myUser.userId success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];

    }];
}

// @TODO(summary): It breaks the tests suite :/
//- (void)testResetRoomStateData
//{
//    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
//
//        MXRoomSummary *summary = room.summary;
//
//        NSString *displayName = @"A room";
//
//        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
//
//            dispatch_async(dispatch_get_main_queue(), ^{
//
//                [summary resetRoomStateData];
//
//                XCTAssertEqualObjects(summary.displayname, displayName, @"Room summary must be updated");
//
//                [expectation fulfill];
//                
//            });
//
//        }];
//
//        [room setName:displayName success:nil failure:^(NSError *error) {
//            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//            [expectation fulfill];
//        }];
//    }];
//}

- (void)testMemberProfileChange
{
    // Need a store for this test
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        MXRoomSummary *summary = room.summary;

        NSString *userDisplayName = @"NewBob";

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            MXEvent *event = summary.lastMessageEvent;

            XCTAssert(event);
            XCTAssertFalse(event.isLocalEvent);
            XCTAssertEqual(event.eventType, MXEventTypeRoomMember);

            [expectation fulfill];
        }];

        [mxSession.myUser setDisplayName:userDisplayName success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testIgnoreMemberProfileChanges
{
    // Need a store for this test
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummaryUpdater *defaultUpdater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:mxSession];
        defaultUpdater.ignoreMemberProfileChanges = YES;

        MXRoomSummary *summary = room.summary;

        NSString *userDisplayName = @"NewBob";

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            XCTFail(@"The last message should not change if ignoreMemberProfileChanges == YES");
            [expectation fulfill];
        }];

        // Wait to check that no notification happens
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

            MXEvent *event = summary.lastMessageEvent;

            XCTAssert(event);
            XCTAssertFalse(event.isLocalEvent);
            XCTAssertNotEqual(event.eventType, MXEventTypeRoomMember, @"The last message must not be the change of Bob's displayname");

            [expectation fulfill];

        });

        [mxSession.myUser setDisplayName:userDisplayName success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testOutgoingMessageEcho
{
    // Need a store to manage outgoing events
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummary *summary = room.summary;

        __block NSString *lastMessageEventId;
        MXEvent *localEcho;

        __block NSUInteger notifCount = 0;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            MXEvent *event = summary.lastMessageEvent;

            switch (notifCount++)
            {
                case 0:
                {
                    // First notif is for the echo
                    XCTAssert([summary.lastMessageEventId hasPrefix:kMXEventLocalEventIdPrefix]);

                    XCTAssert(event);
                    XCTAssert(event.isLocalEvent);
                    XCTAssertEqual(event.sentState, MXEventSentStateSending);
                    break;
                }

                case 1:
                {
                    // 2nd notif must be an intermediate state where the event id
                    // changes from a local event id to the final event id
                    XCTAssert(event);
                    XCTAssertFalse(event.isLocalEvent);
                    XCTAssertEqual(event.sentState, MXEventSentStateSending);

                    [expectation fulfill];

                    break;
                }

                case 2:
                {
                    // 3rd notif must be the event sent back by the hs
                    XCTAssert(event);
                    XCTAssertFalse(event.isLocalEvent);
                    XCTAssertEqual(event.sentState, MXEventSentStateSent);

                    XCTAssertEqualObjects(summary.lastMessageEventId, lastMessageEventId);

                    [expectation fulfill];

                    break;
                }
            }
        }];

        [room sendTextMessage:@"new message" formattedText:nil localEcho:&localEcho success:^(NSString *eventId) {
            lastMessageEventId = eventId;
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testFailedOutgoingMessageEcho
{
    // Need a store to manage outgoing events
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummary *summary = room.summary;

        MXEvent *localEcho;

        __block NSUInteger notifCount = 0;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            MXEvent *event = summary.lastMessageEvent;

            switch (notifCount++)
            {
                case 0:
                {
                    // First notif is for the echo
                    XCTAssert([summary.lastMessageEventId hasPrefix:kMXEventLocalEventIdPrefix]);

                    XCTAssert(event);
                    XCTAssert(event.isLocalEvent);
                    XCTAssertEqual(event.sentState, MXEventSentStateSending);
                    break;
                }

                case 1:
                {
                    // 2nd notif must be the event failure notification
                    XCTAssert(event);
                    XCTAssert(event.isLocalEvent);
                    XCTAssertEqual(event.sentState, MXEventSentStateFailed);

                    [expectation fulfill];

                    break;
                }
            }
        }];

        MXHTTPOperation *operation = [room sendTextMessage:@"new message" formattedText:nil localEcho:&localEcho success:^(NSString *eventId) {
            XCTFail(@"Cannot set up intial test conditions");
            [expectation fulfill];
        } failure:nil];

        [operation cancel];
        
    }];
}

- (void)testInvite
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        __block NSString *newRoomId;

        NSString *newRoomName = @"A room name";
        NSString *newRoomTopic = @"An interesting topic";

        // Required to make kMXSessionInvitedRoomsDidChangeNotification work
        MXLogDebug(@"%@", bobSession.invitedRooms);

        [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionInvitedRoomsDidChangeNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            MXRoom *newInvitedRoom = [bobSession roomWithRoomId:note.userInfo[kMXSessionNotificationRoomIdKey]];
            MXEvent *invitationEvent = note.userInfo[kMXSessionNotificationEventKey];

            MXRoomSummary *summary = newInvitedRoom.summary;

            observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                XCTAssertEqualObjects(summary.lastMessageEventId, invitationEvent.eventId);
                
                [expectation fulfill];
            }];

        }];

        // Make Alice invite Bob in a room
        [aliceRestClient createRoom:newRoomName visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:newRoomTopic success:^(MXCreateRoomResponse *response) {

            newRoomId = response.roomId;

            [aliceRestClient inviteUser:bobSession.matrixRestClient.credentials.userId toRoom:newRoomId success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRedaction
{
    // Need a store to roll back the last message when the redaction happens
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummaryUpdater *defaultUpdater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:mxSession];
        defaultUpdater.ignoreRedactedEvent = YES;

        MXRoomSummary *summary = room.summary;

        __block NSString *newEventId;
        NSString *lastMessageEventId = summary.lastMessageEventId;

        XCTAssert(lastMessageEventId);

        __block NSUInteger notifCount = 0;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            switch (notifCount++)
            {
                case 0:
                case 1:
                    // Do not care about the local echo update for MXEventSentStateSending
                    break;

                case 2:
                {
                    XCTAssertEqualObjects(summary.lastMessageEventId, newEventId);

                    // Redact the last event
                    [room redactEvent:newEventId reason:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                    break;
                }

                case 4:
                {
                    XCTAssertEqualObjects(summary.lastMessageEventId, lastMessageEventId, @"We must come back to the previous event");

                    [expectation fulfill];
                    break;
                }

                default:
                    break;
            }
        }];

        [room sendTextMessage:@"new message" success:^(NSString *eventId) {

            newEventId = eventId;

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testStateEventRedaction
{
    // Need a store to roll back the last message when the redaction happens
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummaryUpdater *defaultUpdater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:mxSession];
        defaultUpdater.ignoreRedactedEvent = YES;

        MXRoomSummary *summary = room.summary;

        NSString *lastMessageEventId = summary.lastMessageEventId;
        XCTAssert(lastMessageEventId);

        __block NSUInteger notifCount = 0;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            switch (notifCount++)
            {
                case 0:
                {
                    // This is the display name change
                    XCTAssertEqual(summary.lastMessageEvent.eventType, MXEventTypeRoomMember);

                    // Redact its event
                    [room redactEvent:summary.lastMessageEventId reason:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                    break;
                }

                case 2:
                {
                    XCTAssertEqualObjects(summary.lastMessageEventId, lastMessageEventId, @"We must come back to the previous event");

                    [expectation fulfill];
                    break;
                }

                default:
                    break;
            }
        }];


        [mxSession.myUser setDisplayName:@"NewBob" success:^{

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Check that we have still the right last message after a full initial sync
- (void)testClearCacheAfterStateEventRedaction
{
    // Need a store to roll back the last message when the redaction happens
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummaryUpdater *defaultUpdater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:mxSession];
        defaultUpdater.ignoreRedactedEvent = YES;

        NSString *roomId = room.roomId;

        MXRoomSummary *summary = room.summary;

        NSString *lastMessageEventId = summary.lastMessageEventId;
        XCTAssert(lastMessageEventId);

        __block NSUInteger notifCount = 0;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            switch (notifCount++)
            {
                case 0:
                {
                    // This is the display name change
                    XCTAssertEqual(summary.lastMessageEvent.eventType, MXEventTypeRoomMember);

                    // Redact its event
                    [room redactEvent:summary.lastMessageEventId reason:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                    break;
                }

                case 1:
                {
                    MXRestClient *bobRestClient = mxSession.matrixRestClient;
                    [mxSession close];

                    // Restarting the session with a new MXMemoryStore is equivalent to
                    // clearing the cache of MXFileStore
                    MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                    [mxSession2 setStore:[[MXMemoryStore alloc] init] success:^{

                        MXRoomSummaryUpdater *defaultUpdater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:mxSession2];
                        defaultUpdater.ignoreRedactedEvent = YES;

                        // Start a new session by loading no message
                        [mxSession2 startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:10] onServerSyncDone:^{

                            MXRoomSummary *summary2 = [mxSession2 roomSummaryWithRoomId:roomId];

                            XCTAssert(summary2);
                            XCTAssertEqualObjects(summary2.lastMessageEventId, lastMessageEventId, @"We must come back to the previous event");

                            [expectation fulfill];

                        } failure:^(NSError *error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];
                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                    break;
                }

                default:
                    break;
            }
        }];


        [mxSession.myUser setDisplayName:@"NewBob" success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// A copy of testDisplaynameUpdate but here, we check the state passed in the updater is correct
- (void)testStatePassedToMXRoomSummaryUpdating
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        mxSession.roomSummaryUpdateDelegate = self;

        MXRoomSummary *summary = room.summary;

        NSString *displayName = @"A room";

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            [room state:^(MXRoomState *roomState) {

                XCTAssertEqualObjects(roomState.name, displayName);
                XCTAssertEqualObjects(summary.displayname, displayName, @"Room summary must be updated");

                [expectation fulfill];
            }];
        }];

        [room setName:displayName success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark - Tests with encryption

- (void)testDoNotStoreDecryptedData
{
    // Test it on a permanent store
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self
                                            andStore:[[MXFileStore alloc] init]
                                         readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSession.roomSummaryUpdateDelegate = self;

        NSString *message = @"new message";

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        MXRoomSummary *summary = room.summary;

        __block NSString *lastMessageEventId;
        MXEvent *localEcho;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            MXEvent *event = summary.lastMessageEvent;

            XCTAssert(event);
            XCTAssertFalse(event.isLocalEvent);
            XCTAssertEqual(event.sentState, MXEventSentStateSent);

            XCTAssert(event.isEncrypted);

            XCTAssertEqualObjects(summary.lastMessageEventId, lastMessageEventId);
            XCTAssertEqualObjects(summary.lastMessageString, message);
            XCTAssert(summary.isLastMessageEncrypted);

            XCTAssert(event.isEncrypted);
            XCTAssert(summary.isEncrypted);

            // Use dispatch_async for not closing the session in the middle of stg
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                // Close the session
                MXRestClient *aliceRestClient = aliceSession.matrixRestClient;
                [aliceSession close];

                // And check the store
                id<MXStore> store = [[MXFileStore alloc] init];
                [store openWithCredentials:aliceRestClient.credentials onComplete:^{

                    // A hack to directly read the file built by MXFileStore
                    NSString *roomSummaryFile = [store performSelector:@selector(summaryFileForRoom:forBackup:) withObject:roomId withObject:NSNull.null];
                    XCTAssert(roomSummaryFile.length);
                    XCTAssertGreaterThan(roomSummaryFile.length, 0);
                    [store close];

                    NSData *roomSummaryFileData = [[NSData alloc] initWithContentsOfFile:roomSummaryFile];
                    XCTAssertGreaterThan(roomSummaryFileData.length, 0);

                    NSData *pattern = [lastMessageEventId dataUsingEncoding:NSUTF8StringEncoding];
                    NSRange range = [roomSummaryFileData rangeOfData:pattern options:0 range:NSMakeRange(0, roomSummaryFileData.length)];
                    XCTAssertNotEqual(range.location, NSNotFound, @"We must find the event id in this file. Else this test is not valid");

                    pattern = [message dataUsingEncoding:NSUTF8StringEncoding];
                    range = [roomSummaryFileData rangeOfData:pattern options:0 range:NSMakeRange(0, roomSummaryFileData.length)];
                    XCTAssertEqual(range.location, NSNotFound, @"We must not stored decrypted data");


                    // Then reopen a session on this store
                    MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                    [aliceSession2 setStore:[[MXFileStore alloc] init] success:^{

                        [aliceSession2 start:^{

                            MXRoomSummary *summary2 = [aliceSession2.store summaryOfRoom:roomId];

                            XCTAssert(summary2.isEncrypted);
                            XCTAssertEqualObjects(summary2.lastMessageEventId, lastMessageEventId);
                            XCTAssert(summary.isLastMessageEncrypted);
                            XCTAssertEqualObjects(summary2.lastMessageString, message, @"Once the session is started, the message should be decrypted (in memory)");

                            XCTAssertNil(summary2.lastMessageAttributedString, @"We did not stored an attributed string");
                            XCTAssertEqual(summary2.lastMessageOthers.count, 0, @"We did not stored any others");

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
            });
        }];

        [room sendTextMessage:message formattedText:nil localEcho:&localEcho success:^(NSString *eventId) {
            lastMessageEventId = eventId;
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testEncryptedLastMessageEvent
{
    // Test it on a permanent store
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSession.roomSummaryUpdateDelegate = self;

        NSString *message = @"new message";

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        MXRoomSummary *summary = room.summary;

        __block NSString *lastMessageEventId;
        MXEvent *localEcho;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            MXEvent *event = summary.lastMessageEvent;

            XCTAssert(event);
            XCTAssertEqualObjects(event.eventId, lastMessageEventId);
            XCTAssert(event.clearEvent, @"The event must have been decrypted by MXRoomSummary.lastMessageEvent");
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
            XCTAssertEqualObjects(event.content[@"body"], message);

            // Use dispatch_async for not closing the session in the middle of stg
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                // Close the session
                MXRestClient *aliceRestClient = aliceSession.matrixRestClient;
                [aliceSession close];

                // Then reopen a session
                MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                [aliceSession2 setStore:[[MXFileStore alloc] init] success:^{

                    [aliceSession2 start:^{

                        MXRoomSummary *summary2 = [aliceSession2 roomSummaryWithRoomId:roomId];

                        XCTAssert(summary2.isEncrypted);
                        XCTAssertEqualObjects(summary2.lastMessageString, message, @"Once the session is started, the message should be decrypted (in memory)");

                        MXEvent *event2 = summary2.lastMessageEvent;
                        XCTAssert(event2);
                        XCTAssertEqualObjects(event2.eventId, lastMessageEventId);
                        XCTAssert(event2.clearEvent, @"The event must have been decrypted by MXRoomSummary.lastMessageEvent");
                        XCTAssertEqual(event2.eventType, MXEventTypeRoomMessage);
                        XCTAssertEqualObjects(event2.content[@"body"], message);

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            });
        }];

        [room sendTextMessage:message formattedText:nil localEcho:&localEcho success:^(NSString *eventId) {
            lastMessageEventId = eventId;
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// The same test as MXCryptoTests but dedicated to MXRoomSummary
- (void)testLateRoomKey
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self
                                                cryptedBob:YES
                                       warnOnUnknowDevices:NO
                                                aliceStore:[[MXMemoryStore alloc] init]
                                                  bobStore:[[MXMemoryStore alloc] init]
                                               readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation)
    {
        bobSession.roomSummaryUpdateDelegate = self;

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        // Some hack to set up test conditions
        __block MXEvent *toDeviceEvent;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            toDeviceEvent = notif.userInfo[kMXSessionNotificationEventKey];
        }];

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if (direction == MXTimelineDirectionForwards)
                {
                    // Make crypto forget the inbound group session now
                    // MXRoomSummary will not be able to decrypt it
                    XCTAssert(toDeviceEvent);
                    NSString *sessionId = toDeviceEvent.content[@"session_id"];
                    
                    id<MXCryptoStore> bobCryptoStore = (id<MXCryptoStore>)[bobSession.crypto.olmDevice valueForKey:@"store"];
                    [bobCryptoStore removeInboundGroupSessionWithId:sessionId andSenderKey:toDeviceEvent.senderKey];
                    
                    // So that we cannot decrypt it anymore right now
                    [event setClearData:nil];
                }
            }];
        }];

        MXRoomSummary *roomSummaryFromBobPOV = roomFromBobPOV.summary;

        __block NSString *lastMessageEventId;
        __block NSUInteger notifCount = 0;

        id summaryObserver;
        summaryObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:roomSummaryFromBobPOV queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            switch (notifCount++)
            {
                case 0:
                {
                    XCTAssertEqualObjects(roomSummaryFromBobPOV.lastMessageEventId, lastMessageEventId);
                    XCTAssertEqualObjects(roomSummaryFromBobPOV.lastMessageString, uisiString, @"Without the key, we have a UISI");

                    MXEvent *event = roomSummaryFromBobPOV.lastMessageEvent;
                    XCTAssertNil(event.clearEvent);
                    
                    // Attempt a new decryption
                    [bobSession decryptEvents:@[event] inTimeline:nil onComplete:^(NSArray<MXEvent *> *failedEvents) {
                        // Reinject the m.room_key event. This mimics a room_key event that arrives after message events.
                        [bobSession.crypto handleRoomKeyEvent:toDeviceEvent onComplete:^{}];
                    }];

                    break;
                }

                case 1:
                {
                    // The last message must be decrypted now
                    XCTAssertEqualObjects(roomSummaryFromBobPOV.lastMessageEventId, lastMessageEventId);
                    XCTAssertEqualObjects(roomSummaryFromBobPOV.lastMessageString, messageFromAlice, @"The message must be now decrypted");

                    MXEvent *event = roomSummaryFromBobPOV.lastMessageEvent;
                    XCTAssert(event.clearEvent);

                    [expectation fulfill];
                    break;
                }

                default:
                    break;
            }
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice success:^(NSString *eventId) {
            lastMessageEventId = eventId;
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// https://github.com/matrix-org/matrix-ios-sdk/issues/409
// 1 - Bob creates a room and invite Alice
// 2 - Alice sends a message
// 3 -> From Bob's POV, the room notification count must increase
- (void)testNotificationCountUpdate
{
    // 1 - Bob creates a room and invite Alice
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        bobSession.roomSummaryUpdateDelegate = self;

        MXRoom *room = [bobSession roomWithRoomId:roomId];

        // Set a RR position to get notifications for new incoming messsages
        [room markAllAsRead];

        MXRoomSummary *summary = room.summary;

        NSUInteger notificationCount = room.summary.notificationCount;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            if (room.summary.lastMessageString)
            {
                // 3 -> From Bob's POV, the room notification count must increase
                XCTAssertEqual(room.summary.notificationCount, notificationCount + 1);

                [expectation fulfill];
            }
        }];

        // 2 - Alice sends a message
        NSString *message = [NSString stringWithFormat:@"%@: Hello", bobSession.myUser.userId];
        [aliceRestClient sendTextMessageToRoom:roomId text:message success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop
