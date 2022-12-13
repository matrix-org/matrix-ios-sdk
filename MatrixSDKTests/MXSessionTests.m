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

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

#import "MXMemoryStore.h"
#import "MXFileStore.h"
#import "MatrixSDKSwiftHeader.h"
#import "MXSyncResponse.h"

#import <OHHTTPStubs/HTTPStubs.h>

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXSessionTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;

    id observer;
}
@end

@implementation MXSessionTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    if (observer)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        observer = nil;
    }
    
    matrixSDKTestsData = nil;
    
    [HTTPStubs removeAllStubs];
    [MXSDKOptions sharedInstance].wellknownDomainUrl = nil;

    [super tearDown];
}

// Check MXSession clears initial sync cache after handling sync response.
//
// - Have Bob start a new session
// - Run initial sync on Bob's session
// -> The initial sync cache must be used
- (void)testInitialSyncSuccess
{
    id<MXStore> store = [[MXFileStore alloc] init];
    [matrixSDKTestsData doMXSessionTestWithBob:self andStore:store readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        MXCredentials *credentials = [MXCredentials initialSyncCacheCredentialsFrom:matrixSDKTestsData.bobCredentials];
        id<MXSyncResponseStore> cache = [[MXSyncResponseFileStore alloc] initWithCredentials:credentials];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            [NSThread sleepForTimeInterval:1.0];
            
            XCTAssertEqual(cache.syncResponseIds.count,
                           0,
                           @"Initial sync cache must be reset after successful initialization");

            [expectation fulfill];
        });
    }];
}

// Check MXSession updates initial sync cache when an error occurs handling the sync response.
//
// - Have Bob start a new session
// - Run initial sync on Bob's session
// - In the middle of the process, close the session to simulate a crash
// -> The initial sync cache must be updated
// - Restart the session
// -> The initial sync cache must be used
- (void)testInitialSyncFailure
{
    id<MXStore> store = [[MXFileStore alloc] init];
    
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        MXCredentials *credentials = [MXCredentials initialSyncCacheCredentialsFrom:matrixSDKTestsData.bobCredentials];
        id<MXSyncResponseStore> cache = [[MXSyncResponseFileStore alloc] initWithCredentials:credentials];
        __block MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        //  listen for session state change notification
        __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionStateDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            
            if (mxSession.state == MXSessionStateRunning)
            {
                //  stop observing
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                
                //  2. simulate an unexpected session close (like a crash)
                [mxSession close];
                
                XCTAssertGreaterThan(cache.syncResponseIds.count,
                                     0,
                                     @"Session must cache initial sync responses in case of a failure");
                
                //  3. recreate the session
                mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                [matrixSDKTestsData retain:mxSession];

                [mxSession setStore:store success:^{
                    [mxSession start:^{
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

                            [NSThread sleepForTimeInterval:1.0];

                            XCTAssertEqual(cache.syncResponseIds.count,
                                           0,
                                           @"Initial sync cache must be used after successful restart");

                            [expectation fulfill];
                        });
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
        
        [mxSession setStore:store success:^{
            //  start with a fresh store
            [store deleteAllData];
            
            //  1. start the session
            [mxSession start:^{

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

- (void)testRoomWithAlias
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        NSString *alias = [[NSProcessInfo processInfo] globallyUniqueString];

        // Room with a tag with "oranges" order
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:alias topic:nil success:^(MXCreateRoomResponse *response) {

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            [matrixSDKTestsData retain:mxSession];
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:response.roomId];
                
                XCTAssertNotNil(room);
                
                //  fetch room alias from the room
                NSString *roomAlias = room.summary.aliases.firstObject;
                XCTAssertNotNil(roomAlias);
                
                //  fetch the room by the alias
                MXRoom *room2 = [mxSession roomWithAlias:roomAlias];

                XCTAssertNotNil(room2);
                
                [room2 state:^(MXRoomState *roomState) {
                    XCTAssertEqual(roomState.aliases.count, 1);
                    XCTAssertEqualObjects(roomState.aliases[0], roomAlias);

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
    }];
}


- (void)testListenerForAllLiveEvents
{
    [matrixSDKTestsData doMXRestClientTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        // The listener must catch at least these events
        __block NSMutableArray *expectedEvents =
        [NSMutableArray arrayWithArray:@[
                                         //kMXEventTypeStringRoomCreate,    // TODO: To fix. Why we do not receive it in the timeline?
                                         kMXEventTypeStringRoomMember,
                                         
                                         // Expect the 5 text messages created by doMXRestClientTestWithBobAndARoomWithMessages
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         ]];

        __block NSString *theRoomId;
        __block NSString *eventsRoomId;
        __block BOOL testDone = NO;

        [mxSession listenToEvents:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            if (MXTimelineDirectionForwards == direction)
            {
                if (event.roomId && event.eventId)
                {
                    // Make sure we test events coming from the same room
                    if (nil == eventsRoomId)
                    {
                        eventsRoomId = event.roomId;
                    }
                    XCTAssertEqualObjects(event.roomId, eventsRoomId, @"We should receive events from the current room only");

                    [expectedEvents removeObject:event.type];
                }

                if (!testDone && 0 == expectedEvents.count && theRoomId)
                {
                    XCTAssertEqualObjects(theRoomId, eventsRoomId, @"We must have received live events from the expected room");

                    testDone = YES;
                    [expectation fulfill];
                }
            }
        }];
        
        
        // Create a room with messages in parallel
        // Use a 0 limit to avoid to get older messages from /sync 
        [mxSession startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:0]
                      onServerSyncDone:^{
            
            [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:nil readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {

                theRoomId = roomId;

                if (!testDone && 0 == expectedEvents.count)
                {
                    XCTAssertEqualObjects(theRoomId, eventsRoomId, @"We must have received live events from the expected room");

                    testDone = YES;
                    [expectation fulfill];
                }
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testListenerForRoomMessageOnly
{
    [matrixSDKTestsData doMXRestClientTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        // Listen to m.room.message only
        // We should not see events coming before (m.room.create, and all state events)
        __block NSInteger messagesCount = 0;
        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                            onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
            
            if (MXTimelineDirectionForwards == direction)
            {
                XCTAssertEqual(event.eventType, MXEventTypeRoomMessage, @"We must receive only m.room.message event - Event: %@", event);

                if (++messagesCount == 5)
                {
                    [expectation fulfill];
                }
            }
            
        }];
        
        
        // Create a room with messages in parallel
        [mxSession start:^{
            
            [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:nil readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


/* Disabled as lastActiveAgo events sent by the HS are less accurate than before
- (void)testListenerForPresence
{
    // Make sure Alice and Bob have activities
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        __block MXSession *mxSession2 = mxSession;
        __block NSUInteger lastAliceActivity = -1;
        
        // Listen to m.presence only
        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringPresence] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            if (MXTimelineDirectionForwards == direction)
            {
                XCTAssertEqual(event.eventType, MXEventTypePresence, @"We must receive only m.presence - Event: %@", event);

                MXPresenceEventContent *eventContent = [MXPresenceEventContent modelFromJSON:event.content];

                // Filter out Bob own presence events
                if (NO == [eventContent.userId isEqualToString:mxSession.matrixRestClient.credentials.userId])
                {
                    XCTAssertEqualObjects(eventContent.userId, aliceRestClient.credentials.userId);

                    MXUser *mxAlice = [mxSession2 userWithUserId:eventContent.userId];

                    NSUInteger newLastAliceActivity = mxAlice.lastActiveAgo;
                    XCTAssertLessThan(newLastAliceActivity, lastAliceActivity, @"alice activity must be updated");
                    
                    [expectation fulfill];
                }
            }
        }];

        // Start the session
        [mxSession start:^{

            // Get the last Alice activity before making her active again
            lastAliceActivity = [mxSession2 userWithUserId:aliceRestClient.credentials.userId].lastActiveAgo;

            // Wait a bit before making her active again
            [NSThread sleepForTimeInterval:5.0];

            [aliceRestClient sendTextMessageToRoom:roomId text:@"Hi Bob!" success:^(NSString *eventId) {

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }
         failure:^(NSError *error) {
             XCTFail(@"Cannot set up intial test conditions - error: %@", error);
             [expectation fulfill];
         }];
    }];
}
*/

- (void)testClose
{
    // Make sure Alice and Bob have activities
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession start:^{

            [mxSession listenToEvents:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                XCTFail(@"We should not receive events after closing the session. Received: %@", event);
                [expectation fulfill];
            }];

            MXRoom *room = [mxSession roomWithRoomId:roomId];
            XCTAssert(room);
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    XCTFail(@"We should not receive events after closing the session. Received: %@", event);
                    [expectation fulfill];
                }];
            }];

            MXUser *bob = [mxSession userWithUserId:bobRestClient.credentials.userId];
            XCTAssert(bob);
            [bob listenToUserUpdate:^(MXEvent *event) {
                XCTFail(@"We should not receive events after closing the session. Received: %@", event);
                [expectation fulfill];
            }];


            // Now close the session
            [mxSession close];

            MXRoom *room2 = [mxSession roomWithRoomId:roomId];
            XCTAssertNil(room2);

            MXUser *bob2 = [mxSession userWithUserId:bobRestClient.credentials.userId];
            XCTAssertNil(bob2);

            XCTAssertNil(mxSession.myUser);

            // Do some activity to check nothing comes through mxSession, room and bob
            [bobRestClient sendTextMessageToRoom:roomId threadId:nil text:@"A message" success:^(NSString *eventId) {

                [expectation performSelector:@selector(fulfill) withObject:nil afterDelay:5];

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

- (void)testCloseWithMXMemoryStore
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXMemoryStore *store = [[MXMemoryStore alloc] init];

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession setStore:store success:^{

            [mxSession start:^{

                NSUInteger storeRoomsCount = store.roomSummaryStore.rooms.count;

                XCTAssertGreaterThan(storeRoomsCount, 0);

                [mxSession close];

                // Create another random room to create more data server side
                [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

                    // Check the stream has been correctly shutdowned. Checking that the store has not changed is one way to verify it
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                        XCTAssertEqual(store.roomSummaryStore.rooms.count, storeRoomsCount, @"There must still the same number of stored rooms");
                        [expectation fulfill];

                    });

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

- (void)testPauseResume
{
    // Make sure Alice and Bob have activities
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession start:^{

            // Delay the test as the event stream is actually launched by the sdk after the call of the block passed in [MXSession start]
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

                __block BOOL paused = NO;
                __block NSInteger eventCount = 0;

                [mxSession listenToEvents:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                    eventCount++;
                    XCTAssertFalse(paused, @"We should not receive events when paused. Received: %@", event);
                }];

                MXRoom *room = [mxSession roomWithRoomId:roomId];
                [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                    [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                        eventCount++;
                        XCTAssertFalse(paused, @"We should not receive events when paused. Received: %@", event);
                    }];
                }];

                MXUser *bob = [mxSession userWithUserId:bobRestClient.credentials.userId];
                [bob listenToUserUpdate:^(MXEvent *event) {
                    eventCount++;
                    XCTAssertFalse(paused, @"We should not receive events when paused. Received: %@", event);
                }];


                // Pause the session
                [mxSession pause];
                paused = YES;

                // Do some activity while MXSession is paused
                // We should not receive events while paused
                [bobRestClient sendTextMessageToRoom:roomId threadId:nil text:@"A message" success:^(NSString *eventId) {

                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];

                // Resume the MXSession in 3 secs
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                    paused = NO;
                    [mxSession resume:^{

                        // We should receive these events now
                        XCTAssertGreaterThan(eventCount, 0, @"We should have received events");
                        [expectation fulfill];

                    }];
                    
                });
                
            });
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPauseResumeOnNothingNew
{
    // Make sure Alice and Bob have activities
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession start:^{

            // Delay the test as the event stream is actually launched by the sdk after the call of the block passed in [MXSession start]
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

                __block BOOL paused = NO;
                __block NSInteger eventCount = 0;

                [mxSession listenToEvents:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                    eventCount++;
                    XCTAssertFalse(paused, @"We should not receive events when paused. Received: %@", event);
                }];

                MXRoom *room = [mxSession roomWithRoomId:roomId];
                [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                    [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                        eventCount++;
                        XCTAssertFalse(paused, @"We should not receive events when paused. Received: %@", event);
                    }];
                }];

                MXUser *bob = [mxSession userWithUserId:bobRestClient.credentials.userId];
                [bob listenToUserUpdate:^(MXEvent *event) {
                    eventCount++;
                    XCTAssertFalse(paused, @"We should not receive events when paused. Received: %@", event);
                }];


                // Pause the session
                [mxSession pause];
                paused = YES;

                // Resume the MXSession in 3 secs
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                    paused = NO;

                    NSDate *refDate = [NSDate date];
                    [mxSession resume:^{

                        XCTAssertEqual(eventCount, 0, @"This test tests resuming when there were no new events");

                        NSDate *now  = [NSDate date];
                        XCTAssertLessThanOrEqual([now timeIntervalSinceDate:refDate], 1, @"The resume must be quick if there is no new event");
                        [expectation fulfill];

                    }];
                    
                });
                
            });
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testState
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXSession *mxSession;
        __block MXSessionState previousSessionState = MXSessionStateInitialised;
        [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionStateDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            if (mxSession)
            {
                XCTAssertEqual(note.object, mxSession, @"The notification must embed the MXSession sender");
                XCTAssertNotEqual(mxSession.state, previousSessionState, @"The state must have changed");
                previousSessionState = mxSession.state;
            }
        }];

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        XCTAssertEqual(MXSessionStateInitialised, mxSession.state);

        [mxSession start:^{

            XCTAssertEqual(MXSessionStateRunning, mxSession.state);

            [mxSession pause];
            XCTAssertEqual(MXSessionStatePaused, mxSession.state);

            [mxSession resume:^{

                // As advertised the session state will be updated after the call of this block
                dispatch_async(dispatch_get_main_queue(), ^{

                    XCTAssertEqual(MXSessionStateRunning, mxSession.state);

                    [mxSession close];
                    XCTAssertEqual(MXSessionStateClosed, mxSession.state);

                    [expectation fulfill];
                });

            }];

            XCTAssertEqual(MXSessionStateSyncInProgress, mxSession.state);

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        // Since crypto, we do start syncing immediately but there is
        // an intermediate true asynchronous step where crypto is checked
        // XCTAssertEqual(MXSessionStateSyncInProgress, mxSession.state);
    }];
}


- (void)testCreateRoom
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        // Create a random room with no params
        [mxSession createRoom:nil visibility:nil roomAlias:nil topic:nil success:^(MXRoom *room) {

            XCTAssertNotNil(room);
            
            BOOL isSync = (room.summary.membership != MXMembershipInvite && room.summary.membership != MXMembershipUnknown);
            XCTAssertTrue(isSync, @"The callback must be called once the room has been initialSynced");

            XCTAssertEqual(1, room.summary.membersCount.members, @"Bob must be the only one");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testDidSyncNotification
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionDidSyncNotification object:mxSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            MXSyncResponse *syncResponse = (MXSyncResponse*)notif.userInfo[kMXSessionNotificationSyncResponseKey];

            XCTAssert([syncResponse isKindOfClass:MXSyncResponse.class]);
            XCTAssert(syncResponse.rooms.join[room.roomId], @"We should receive back the 'Hello' sent in this room");

            [expectation fulfill];
        }];

        [room sendTextMessage:@"Hello" threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

// Check sync response does not contain empty objects.
//
// - Have Bob start a new session
// - Run initial sync on Bob's session
// - Run another sync on Bob's session
// -> Check latter sync response does not contain anything but the event stream token
- (void)testEmptySyncResponse
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        
        __block BOOL isFirst = YES;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionDidSyncNotification object:mxSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            if (isFirst)
            {
                isFirst = NO;
                //  wait for another sync response, which should be completely empty
                return;
            }
            MXSyncResponse *syncResponse = (MXSyncResponse*)notif.userInfo[kMXSessionNotificationSyncResponseKey];

            XCTAssert([syncResponse isKindOfClass:MXSyncResponse.class]);
            XCTAssertNil(syncResponse.accountData, @"Account data should be nil");
            XCTAssertNotNil(syncResponse.nextBatch, @"Event stream token must be provided");
            XCTAssertNil(syncResponse.presence, @"Presence should be nil");
            XCTAssertNil(syncResponse.toDevice, @"To device events should be nil");
            XCTAssertNil(syncResponse.deviceLists, @"Device lists should be nil");
            XCTAssertNil(syncResponse.rooms, @"Rooms should be nil");
            XCTAssertNil(syncResponse.groups, @"Groups should be nil");
            XCTAssertEqual(syncResponse.unusedFallbackKeys.count, 0, @"Device shouldn't have any fallback keys");
            for (NSNumber *numberOfKeys in syncResponse.deviceOneTimeKeysCount.allKeys) {
                XCTAssertEqual(numberOfKeys.unsignedIntValue, 0, @"Device shouldn't have any one time keys");
            }

            [expectation fulfill];
        }];
    }];
}

- (void)testCreateRoomWithInvite
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        
        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            // Create a random room with no params
            MXRoomCreationParameters *parameters = [MXRoomCreationParameters new];
            parameters.inviteArray = @[matrixSDKTestsData.aliceCredentials.userId];

            [mxSession createRoomWithParameters:parameters success:^(MXRoom *room) {
                
                XCTAssertNotNil(room);
                
                BOOL isSync = (room.summary.membership != MXMembershipInvite && room.summary.membership != MXMembershipUnknown);
                XCTAssertTrue(isSync, @"The callback must be called once the room has been initialSynced");
                
                [mxSession.matrixRestClient membersOfRoom:room.roomId success:^(NSArray *roomMemberEvents) {
                    
                    XCTAssertEqual(roomMemberEvents.count, 2);
                    
                    MXEvent *roomMemberEvent1 = roomMemberEvents[0];
                    MXEvent *roomMemberEvent2 = roomMemberEvents[1];
                    
                    BOOL succeed;
                    if ([roomMemberEvent1.stateKey isEqualToString:mxSession.myUserId])
                    {
                        succeed = [roomMemberEvent2.stateKey isEqualToString:matrixSDKTestsData.aliceCredentials.userId];
                    }
                    else if ([roomMemberEvent1.stateKey isEqualToString:matrixSDKTestsData.aliceCredentials.userId])
                    {
                        succeed = [roomMemberEvent2.stateKey isEqualToString:mxSession.myUserId];
                    }
                    
                    XCTAssertTrue(succeed);
                    
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
        
    }];
}

- (void)testCreateDirectRoom
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        
        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            // Create a random room with no params
            MXRoomCreationParameters *parameters = [MXRoomCreationParameters parametersForDirectRoomWithUser:matrixSDKTestsData.aliceCredentials.userId];
            [mxSession createRoomWithParameters:parameters success:^(MXRoom *room) {
                
                XCTAssertNotNil(room);
                
                BOOL isSync = (room.summary.membership != MXMembershipInvite && room.summary.membership != MXMembershipUnknown);
                XCTAssertTrue(isSync, @"The callback must be called once the room has been initialSynced");
                
                [mxSession.matrixRestClient membersOfRoom:room.roomId success:^(NSArray *roomMemberEvents) {
                    
                    XCTAssertEqual(roomMemberEvents.count, 2);
                    
                    MXEvent *roomMemberEvent1 = roomMemberEvents[0];
                    MXEvent *roomMemberEvent2 = roomMemberEvents[1];
                    
                    BOOL succeed;
                    if ([roomMemberEvent1.stateKey isEqualToString:mxSession.myUserId])
                    {
                        succeed = [roomMemberEvent2.stateKey isEqualToString:matrixSDKTestsData.aliceCredentials.userId];
                    }
                    else if ([roomMemberEvent1.stateKey isEqualToString:matrixSDKTestsData.aliceCredentials.userId])
                    {
                        succeed = [roomMemberEvent2.stateKey isEqualToString:mxSession.myUserId];
                    }
                    
                    XCTAssertTrue(succeed);
                    
                    // Force sync to get direct rooms list
                    // CRASH
                    [mxSession startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:0]
                                  onServerSyncDone:^{
                        
                        XCTAssertTrue(room.isDirect);

                        [room state:^(MXRoomState *roomState) {

                            // Check whether both members have the same power level (trusted_private_chat preset)
                            MXRoomPowerLevels *roomPowerLevels = roomState.powerLevels;

                            XCTAssertNotNil(roomPowerLevels);
                            NSUInteger powerlLevel1 = [roomPowerLevels powerLevelOfUserWithUserID:mxSession.myUserId];
                            NSUInteger powerlLevel2 = [roomPowerLevels powerLevelOfUserWithUserID:matrixSDKTestsData.aliceCredentials.userId];
                            XCTAssertEqual(powerlLevel1, powerlLevel2, @"The members must have the same power level");

                            [expectation fulfill];
                        }];
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot sync direct rooms - error: %@", error);
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
        
    }];
}

- (void)testPrivateDirectRoomWithUserId
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *mxSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [mxSession roomWithRoomId:roomId];
        [room setIsDirect:YES withUserId:aliceRestClient.credentials.userId success:^{

            MXRoom *mxRoom1 = [mxSession directJoinedRoomWithUserId:aliceRestClient.credentials.userId];
            XCTAssertEqualObjects(mxRoom1.roomId, roomId, @"We should retrieve the last created room");

            [mxSession leaveRoom:roomId success:^{
                MXRoom *mxRoom2 = [mxSession directJoinedRoomWithUserId:aliceRestClient.credentials.userId];
                if (mxRoom2)
                {
                    XCTAssertNotEqualObjects(mxRoom2.roomId, roomId, @"We should not retrieve the left room");
                }

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark MXSessionNewRoomNotification tests
- (void)testNewRoomNotificationOnInvite
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            [matrixSDKTestsData retain:mxSession];
            [mxSession start:^{

                // Listen to Alice's MXSessionNewRoomNotification event
                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    XCTAssertEqual(mxSession, note.object, @"The MXSessionNewRoomNotification sender must be the current MXSession");

                    [expectation fulfill];
                }];

                [bobRestClient inviteUser:aliceRestClient.credentials.userId toRoom:roomId success:nil failure:nil];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];

    }];
}

- (void)testNewRoomNotificationOnCreatingPublicRoom
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        [mxSession start:^{

            observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                XCTAssertEqual(mxSession, note.object, @"The MXSessionNewRoomNotification sender must be the current MXSession");

                MXRoom *publicRoom = [mxSession roomWithRoomId:note.userInfo[kMXSessionNotificationRoomIdKey]];
                XCTAssertNotNil(publicRoom);

                [expectation fulfill];
            }];

            [mxSession.matrixRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPublic roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

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

- (void)testNewRoomNotificationOnJoiningPublicRoom
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndAPublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            [matrixSDKTestsData retain:mxSession];
            [mxSession start:^{

                // Listen to Alice's MXSessionNewRoomNotification event
                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    XCTAssertEqual(mxSession, note.object, @"The MXSessionNewRoomNotification sender must be the current MXSession");

                    MXRoom *publicRoom = [mxSession roomWithRoomId:note.userInfo[kMXSessionNotificationRoomIdKey]];
                    XCTAssertNotNil(publicRoom);

                    [expectation fulfill];
                }];

                [mxSession joinRoom:roomId viaServers:nil success:nil failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
        
    }];
}


#pragma mark kMXRoomInitialSyncNotification tests
- (void)testMXRoomInitialSyncNotificationOnJoiningPublicRoom
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndAPublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            [matrixSDKTestsData retain:mxSession];
            [mxSession start:^{

                // Listen to Alice's kMXRoomInitialSyncNotification event
                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    MXRoom *publicRoom = (MXRoom*)note.object;
                    XCTAssertNotNil(publicRoom);

                    BOOL isSync = (publicRoom.summary.membership != MXMembershipInvite && publicRoom.summary.membership != MXMembershipUnknown);
                    XCTAssert(isSync, @"kMXRoomInitialSyncNotification must inform when the room state is fully known");

                    XCTAssertEqual(mxSession, publicRoom.mxSession, @"The session of the sent MXRoom must be the right one");

                    [expectation fulfill];
                }];

                [mxSession joinRoom:roomId viaServers:nil success:nil failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
        
    }];
}


#pragma mark rooms tags
- (void)doRoomByTagsOrderTest:(XCTestCase*)testCase withOrder1:(NSString*)order1 order2:(NSString*)order2 order3:(NSString*)order3
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        // Create rooms with the same tag but with the passed orders
        // Use the room topic to define the expected order
        NSString *tag = [[NSProcessInfo processInfo] globallyUniqueString];

        // Room with a tag with "oranges" order
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"2" success:^(MXCreateRoomResponse *response) {
            [bobRestClient addTag:tag withOrder:order2  toRoom:response.roomId success:^{

                // Room with a tag with no order
                [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"3" success:^(MXCreateRoomResponse *response) {
                    [bobRestClient addTag:tag withOrder:order3 toRoom:response.roomId success:^{

                        // Room with a tag with "apples" order
                        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"1" success:^(MXCreateRoomResponse *response) {
                            [bobRestClient addTag:tag withOrder:order1 toRoom:response.roomId success:^{


                                // Do the test
                                MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                                [matrixSDKTestsData retain:mxSession];
                                [mxSession start:^{

                                    NSDictionary<NSString*, NSArray<MXRoom*>*> *roomByTags = [mxSession roomsByTags];

                                    XCTAssertGreaterThanOrEqual(roomByTags.count, 1);

                                    XCTAssertNotNil(roomByTags[tag]);
                                    XCTAssertEqual(roomByTags[tag].count, 3);

                                    MXRoom *room1 = roomByTags[tag][0];
                                    MXRoom *room2 = roomByTags[tag][1];
                                    MXRoom *room3 = roomByTags[tag][2];

                                    // Room ordering: a tagged room with no order value must have higher priority
                                    // than the tagged rooms with order value.

                                    XCTAssertEqualObjects(room1.summary.topic, @"1", "The order is wrong");
                                    XCTAssertEqualObjects(room2.summary.topic, @"2", "The order is wrong");
                                    XCTAssertEqualObjects(room3.summary.topic, @"3", "The order is wrong");


                                    // By the way, check roomsWithTag
                                    NSArray<MXRoom*> *roomsWithTag = [mxSession roomsWithTag:tag];
                                    XCTAssertEqualObjects(roomsWithTag, roomByTags[tag], "[MXSession roomsWithTag:] must return the same list");

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

- (void)testRoomByTagsOrderWithStringTagOrder
{
    [self doRoomByTagsOrderTest:self withOrder1:nil order2:@"apples" order3:@"oranges"];
}

- (void)testRoomByTagsOrderWithFloatTagOrder
{
    [self doRoomByTagsOrderTest:self withOrder1:nil order2:@"0.2" order3:@"0.9"];
}

- (void)testRoomByTagsOrderWithFloatAndStringTagOrder
{
    [self doRoomByTagsOrderTest:self withOrder1:nil order2:@"0.9" order3:@"apples"];
}

- (void)testTagRoomsWithSameOrder
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        // Create 2 rooms with the same tag and same order
        NSString *tag = [[NSProcessInfo processInfo] globallyUniqueString];

        // Room at position
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"oldest" success:^(MXCreateRoomResponse *response) {
            [bobRestClient addTag:tag withOrder:@"0.2"  toRoom:response.roomId success:^{

                // Room at position
                [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"newest" success:^(MXCreateRoomResponse *response) {
                    [bobRestClient addTag:tag withOrder:@"0.2" toRoom:response.roomId success:^{

                        // Do the tests
                        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                        [matrixSDKTestsData retain:mxSession];
                        [mxSession start:^{

                            NSArray<MXRoom*> *roomsWithTag = [mxSession roomsWithTag:tag];

                            // If the order is the same, the room must be sorted by their last event
                            XCTAssertEqualObjects(roomsWithTag[0].summary.topic, @"newest");
                            XCTAssertEqualObjects(roomsWithTag[1].summary.topic, @"oldest");

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
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomByTagsAndNoRoomTag
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        // Create a tagged room
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"Tagged" success:^(MXCreateRoomResponse *response) {
            [bobRestClient addTag:@"aTag" withOrder:nil  toRoom:response.roomId success:^{

                // And a not tagged room
                [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:@"Not tagged" success:^(MXCreateRoomResponse *response) {

                    // Do the test
                    MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                    [matrixSDKTestsData retain:mxSession];
                    [mxSession start:^{

                        NSDictionary<NSString*, NSArray<MXRoom*>*> *roomByTags = [mxSession roomsByTags];

                        XCTAssertGreaterThanOrEqual(roomByTags.count, 2, "There must be at least 2 tags ('aTag' and kMXSessionNoRoomTag)");

                        // By the way, check roomsWithTag
                        NSArray *roomsWithNoTags = [mxSession roomsWithTag:kMXSessionNoRoomTag];
                        XCTAssertEqualObjects(roomsWithNoTags, roomByTags[kMXSessionNoRoomTag], "[MXSession roomsWithTag:] must return the same list");

                        MXRoom *theNonTaggedRoom = [mxSession roomWithRoomId:response.roomId];

                        XCTAssertNotEqual([roomsWithNoTags indexOfObject:theNonTaggedRoom], NSNotFound);

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
    }];
}

- (void)testTagOrderToBeAtIndex
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        // Create 2 rooms with the same tag but different order
        NSString *tag = [[NSProcessInfo processInfo] globallyUniqueString];

        // Room at position #1
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {
            [bobRestClient addTag:tag withOrder:@"0.1"  toRoom:response.roomId success:^{

                // Room at position #2
                [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {
                    [bobRestClient addTag:tag withOrder:@"0.2" toRoom:response.roomId success:^{

                        // Room at position #3
                        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {
                            [bobRestClient addTag:tag withOrder:@"0.3" toRoom:response.roomId success:^{

                                // Do the tests
                                MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                                [matrixSDKTestsData retain:mxSession];
                                [mxSession start:^{

                                    NSString *orderForFirstPosition = [mxSession tagOrderToBeAtIndex:0 from:NSNotFound withTag:tag];
                                    XCTAssertLessThan(orderForFirstPosition.floatValue, 0.1);

                                    NSString *orderForThirdPosition = [mxSession tagOrderToBeAtIndex:2 from:NSNotFound withTag:tag];
                                    XCTAssertGreaterThan(orderForThirdPosition.floatValue, 0.2);
                                    XCTAssertLessThan(orderForThirdPosition.floatValue, 0.3);

                                    NSString *orderForLastPosition = [mxSession tagOrderToBeAtIndex:3 from:NSNotFound withTag:tag];
                                    XCTAssertGreaterThan(orderForLastPosition.floatValue, 0.3);

                                    orderForLastPosition = [mxSession tagOrderToBeAtIndex:10 from:NSNotFound withTag:tag];
                                    XCTAssertGreaterThan(orderForLastPosition.floatValue, 0.3);

                                    NSString *orderForSecondPositionWhenComingFromFirst = [mxSession tagOrderToBeAtIndex:1 from:0 withTag:tag];
                                    XCTAssertGreaterThan(orderForSecondPositionWhenComingFromFirst.floatValue, 0.2);
                                    XCTAssertLessThan(orderForSecondPositionWhenComingFromFirst.floatValue, 0.3);


                                    // Test the method on a fresh new tag
                                    NSString *newTag = [[NSProcessInfo processInfo] globallyUniqueString];

                                    NSString *orderForFirstTaggedRoom = [mxSession tagOrderToBeAtIndex:2 from:NSNotFound withTag:newTag];
                                    XCTAssertGreaterThan(orderForFirstTaggedRoom.floatValue, 0);
                                    XCTAssertLessThan(orderForFirstTaggedRoom.floatValue, 1);

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

- (void)testInvitedRooms
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *mxSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        NSUInteger prevInviteCount = mxSession.invitedRooms.count;

        __block NSString *testRoomId;
        __block NSUInteger testState = 0;

        [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionInvitedRoomsDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            MXRoom *impactedRoom = [mxSession roomWithRoomId:note.userInfo[kMXSessionNotificationRoomIdKey]];
            MXEvent *event = note.userInfo[kMXSessionNotificationEventKey];

            NSArray *invitedRooms = mxSession.invitedRooms;

            switch (testState)
            {
                case 0:
                    // First notif is for the invite
                    // The room must be in the invitedRooms list
                    XCTAssertEqual(invitedRooms.count, prevInviteCount + 1);

                    XCTAssertNotEqual([invitedRooms indexOfObject:impactedRoom], NSNotFound, @"The room must be in the invitation list");

                    testState++;

                    // Join the room now
                    //[impactedRoom join:nil failure:nil];
                    [impactedRoom leave:nil failure:nil];

                    break;

                case 1:
                    // 2nd notif comes when the user has accepted the invitation
                    XCTAssertEqual(invitedRooms.count, prevInviteCount );

                    XCTAssertEqual([invitedRooms indexOfObject:impactedRoom], NSNotFound, @"The room must be no more in the invitation list");
                    XCTAssertNil(event.inviteRoomState, @"The event must not be an invite");

                    [expectation fulfill];
                    
                default:
                    break;
            }

        }];

        // Make Alice invite Bob in a room
        [aliceRestClient createRoom:@"A room name" visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

            testRoomId = response.roomId;

            [aliceRestClient inviteUser:mxSession.matrixRestClient.credentials.userId toRoom:testRoomId success:^{

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

- (void)testToDeviceEvents
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *mxSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            XCTAssertEqual(notif.object, mxSession);

            MXEvent *toDeviceEvent = notif.userInfo[kMXSessionNotificationEventKey];
            XCTAssert(toDeviceEvent);

            XCTAssertEqualObjects(toDeviceEvent.sender, aliceRestClient.credentials.userId);
            XCTAssertEqual(toDeviceEvent.eventType, MXEventTypeRoomKeyRequest);

            [expectation fulfill];
        }];

        MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
        [contentMap setObjects:@{
                                 @"*": @{
                                         @"device_id": @"AliceDevice",
                                         @"rooms": @[roomId]
                                         }
                                 } forUser:mxSession.myUserId];

        MXToDevicePayload *payload = [[MXToDevicePayload alloc] initWithEventType:kMXEventTypeStringRoomKeyRequest
                                                                       contentMap:contentMap];
        [aliceRestClient sendToDevice:payload success:^{

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

// Check MXSDKOptions.wellknownDomainUrl
//
// - Customise the wellknown domain
// - Set up a MXSession
// - Catch the wellknown request
// -> The wellknown request must be done on the custom domain
- (void)testMXSDKOptionsWellknownDomainUrl
{
    __block BOOL testDone = NO;
    __block XCTestExpectation *expectation;
    
    // - Customise the wellknown domain
    NSString *wellknownDomainUrl = @"https://anotherWellknownDomain";
    [MXSDKOptions sharedInstance].wellknownDomainUrl = wellknownDomainUrl;

    // - Catch the wellknown request
    [HTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest *request) {
        if ([request.URL.absoluteString containsString:@".well-known/matrix/client"])
        {
            // -> The wellknown request must be done on the custom domain
            XCTAssertTrue([request.URL.absoluteString hasPrefix:wellknownDomainUrl],
                          @"The wellknown request (%@) must contain the customised wellknown domain (%@)",
                          request.URL.absoluteString, wellknownDomainUrl);
            
            testDone = YES;
            [expectation fulfill];
        }
        return NO;
    } withStubResponse:^HTTPStubsResponse*(NSURLRequest *request) {
        return nil;
    }];
    
    // - Set up a MXSession
    [matrixSDKTestsData doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *theExpectation) {
        expectation = theExpectation;
        
        if (testDone)
        {
            [expectation fulfill];
        }
    }];
}

#pragma mark Account Data tests

-(void)testAccountDataIsDeletedLocally
{
    id<MXStore> store = MXFileStore.new;
    [matrixSDKTestsData doMXSessionTestWithBob:self andStore:store readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        NSString* accountDataType = @"foo";
        [mxSession.accountData updateDataWithType:accountDataType data:NSDictionary.new];
        XCTAssertNotNil([mxSession.accountData accountDataForEventType:accountDataType]);
        [mxSession deleteAccountDataWithType:accountDataType
                                     success:^{ XCTAssertNil([mxSession.accountData accountDataForEventType:accountDataType]); [expectation fulfill]; }
                                     failure:^(NSError *error) { }
        ];
    }];
}

@end

#pragma clang diagnostic pop
