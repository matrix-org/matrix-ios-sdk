/*
 Copyright 2017 OpenMarket Ltd

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

#import "MXMemoryStore.h"
#import "MXFileStore.h"

#import "MXRoomSummaryUpdater.h"

#import "MXTools.h"


// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"


@interface MXRoomSummaryTests : XCTestCase <MXRoomSummaryUpdating>
{
    MatrixSDKTestsData *matrixSDKTestsData;

    // Flags to check the delegate has been called
    BOOL testDelegate;
    BOOL testNoChangeDelegate;
}

@end

NSString *testDelegateLastMessageString = @"The string I decider to render for this event";

@implementation MXRoomSummaryTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}


- (void)tearDown
{
     [super tearDown];
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withLastEvent:(MXEvent *)event oldState:(MXRoomState *)oldState
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
        updated = [updater session:session updateRoomSummary:summary withLastEvent:event oldState:oldState];

        summary.lastMessageString = testDelegateLastMessageString;

        XCTAssert(updated);
        XCTAssertEqualObjects(summary.lastMessageEventId, event.eventId);

        testDelegate = YES;
    }
    else if ([self.description containsString:@"testNoChangeDelegate"])
    {
        testNoChangeDelegate = YES;

        // Force a kMXRoomSummaryDidChangeNotification
        [summary save];
    }
    else if ([self.description containsString:@"testGetLastMessageFromSeveralPaginations"])
    {
        if (event.eventType == MXEventTypeRoomMessage)
        {
            updated = NO;
        }
        else
        {
            summary.lastMessageEventId = event.eventId;
            updated = YES;
        }
    }
    else
    {
        XCTFail(@"Unexpected delegate call in %@", self);
    }

    return updated;
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withStateEvents:(NSArray<MXEvent *> *)stateEvents
{
    // Do a classic update
    MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:session];
    return [updater session:session updateRoomSummary:summary withStateEvents:stateEvents];
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

        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

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


        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

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
            [mxSession2 startWithMessagesLimit:0 onServerSyncDone:^{

                MXRoomSummary *summary2 = [mxSession2 roomSummaryWithRoomId:roomId];

                XCTAssert(summary2);
                XCTAssertNil(summary2.lastMessageEventId, @"We asked for loading 0 message. So, we cannot know the last message yet");

                id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary2 queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    [[NSNotificationCenter defaultCenter] removeObserver:observer];

                    XCTAssert(summary2);
                    XCTAssert(summary2.lastMessageEventId, @"We must have an event now");

                    MXEvent *event2 = summary2.lastMessageEvent;

                    XCTAssert(event2);
                    XCTAssertEqual(event2.eventType, MXEventTypeRoomMessage);

                    [expectation fulfill];
                }];

                // Force the summary to fetch events from the homeserver to get the last one
                MXHTTPOperation *operation = [summary2 resetLastMessage:nil failure:^(NSError *error) {

                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                    
                }];

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
        [matrixSDKTestsData for:bobRestClient andRoom:roomId sendMessages:80 success:^{

            MXRoomSummary *summary = [mxSession roomSummaryWithRoomId:roomId];
            XCTAssert(summary);
            XCTAssert(summary.lastMessageEventId);

            [mxSession close];

            MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

            // Configure the updater so that it refuses room messages as last message
            mxSession2.roomSummaryUpdateDelegate = self;

            [mxSession2 setStore:[[MXMemoryStore alloc] init] success:^{

                // Start a new session by loading no message
                [mxSession2 startWithMessagesLimit:0 onServerSyncDone:^{

                    MXRoomSummary *summary2 = [mxSession2 roomSummaryWithRoomId:roomId];

                    XCTAssert(summary2);
                    XCTAssertNil(summary2.lastMessageEventId, @"We asked for loading 0 message. So, we cannot know the last message yet");


                    // Force the summary to fetch events from the homeserver to get the last one
                    MXHTTPOperation *operation = [summary2 resetLastMessage:nil failure:^(NSError *error) {

                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];

                    }];

                    XCTAssert(operation, @"An HTTP operation is required for that");
                    XCTAssert([operation isKindOfClass:MXHTTPOperation.class]);

                    NSURLSessionDataTask *urlSessionDataTask = operation.operation;

                    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary2 queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                        [[NSNotificationCenter defaultCenter] removeObserver:observer];

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
            [mxSession2 startWithMessagesLimit:0 onServerSyncDone:^{

                MXRoomSummary *summary2 = [mxSession2 roomSummaryWithRoomId:roomId];

                XCTAssert(summary2);
                XCTAssertNil(summary2.lastMessageEventId, @"We asked for loading 0 message. So, we cannot know the last message yet");

                id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary2 queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    [[NSNotificationCenter defaultCenter] removeObserver:observer];

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

        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

             XCTAssertEqualObjects(room.state.displayname, displayName);
             XCTAssertEqualObjects(summary.displayname, displayName, @"Room summary must be updated");

             [expectation fulfill];
         }];

        [room setName:displayName success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testResetRoomStateData
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummary *summary = room.summary;

        NSString *displayName = @"A room";

        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

            dispatch_async(dispatch_get_main_queue(), ^{

                [summary resetRoomStateData];

                XCTAssertEqualObjects(summary.displayname, displayName, @"Room summary must be updated");

                [expectation fulfill];
                
            });

        }];

        [room setName:displayName success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMemberProfileChange
{
    // Need a store for this test
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        MXRoomSummary *summary = room.summary;

        NSString *userDisplayName = @"NewBob";

        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

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

        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

            XCTFail(@"The last message should not change if ignoreMemberProfileChanges == YES");
            [expectation fulfill];
        }];

        // Wait to check that no notification happens
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

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
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

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
                    // 2nd notif must be the event sent back by the hs
                    XCTAssert(event);
                    XCTAssertFalse(event.isLocalEvent);
                    XCTAssertEqual(event.sentState, MXEventSentStateSent);

                    XCTAssertEqualObjects(summary.lastMessageEventId, lastMessageEventId);

                    [[NSNotificationCenter defaultCenter] removeObserver:observer];

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
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

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

                    [[NSNotificationCenter defaultCenter] removeObserver:observer];

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
        bobSession.invitedRooms;

        [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionInvitedRoomsDidChangeNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            MXRoom *newInvitedRoom = [bobSession roomWithRoomId:note.userInfo[kMXSessionNotificationRoomIdKey]];
            MXEvent *invitationEvent = note.userInfo[kMXSessionNotificationEventKey];

            MXRoomSummary *summary = newInvitedRoom.summary;

            id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                [[NSNotificationCenter defaultCenter] removeObserver:observer];

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
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            switch (notifCount++)
            {
                case 0:
                    // Do not care about the local echo
                    break;

                case 1:
                {
                    XCTAssertEqualObjects(summary.lastMessageEventId, newEventId);

                    // Redact the last event
                    [room redactEvent:newEventId reason:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                    break;
                }

                case 2:
                {
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];

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

@end

#pragma clang diagnostic pop
