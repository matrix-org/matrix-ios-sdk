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

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

#import "MXMemoryStore.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXSessionTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;

    MXSession *mxSession;
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
    if (mxSession)
    {
        [matrixSDKTestsData closeMXSession:mxSession];
        mxSession = nil;
    }
    [super tearDown];
}


- (void)testRoomWithAlias
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        NSString *alias = [[NSProcessInfo processInfo] globallyUniqueString];

        // Room with a tag with "oranges" order
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:alias topic:nil success:^(MXCreateRoomResponse *response) {

            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithAlias:response.roomAlias];

                XCTAssertNotNil(room);
                XCTAssertEqual(room.state.aliases.count, 1);
                XCTAssertEqualObjects(room.state.aliases[0], response.roomAlias);

                [expectation fulfill];

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
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
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
        [mxSession startWithMessagesLimit:0 onServerSyncDone:^{
            
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
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
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
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
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

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [mxSession start:^{

            [mxSession listenToEvents:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                XCTFail(@"We should not receive events after closing the session. Received: %@", event);
                [expectation fulfill];
            }];

            MXRoom *room = [mxSession roomWithRoomId:roomId];
            XCTAssert(room);
            [room.liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                XCTFail(@"We should not receive events after closing the session. Received: %@", event);
                [expectation fulfill];
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
            [bobRestClient sendTextMessageToRoom:roomId text:@"A message" success:^(NSString *eventId) {

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

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [mxSession setStore:store success:^{

            [mxSession start:^{

                NSUInteger storeRoomsCount = store.rooms.count;

                XCTAssertGreaterThan(storeRoomsCount, 0);

                [mxSession close];
                mxSession = nil;

                // Create another random room to create more data server side
                [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

                    // Check the stream has been correctly shutdowned. Checking that the store has not changed is one way to verify it
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                        XCTAssertEqual(store.rooms.count, storeRoomsCount, @"There must still the same number of stored rooms");
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

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

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
                [room.liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    eventCount++;
                    XCTAssertFalse(paused, @"We should not receive events when paused. Received: %@", event);
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
                [bobRestClient sendTextMessageToRoom:roomId text:@"A message" success:^(NSString *eventId) {

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

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

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
                [room.liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    eventCount++;
                    XCTAssertFalse(paused, @"We should not receive events when paused. Received: %@", event);
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

                    mxSession = nil;
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
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession2, XCTestExpectation *expectation) {

        mxSession = mxSession2;

        // Create a random room with no params
        [mxSession createRoom:nil visibility:nil roomAlias:nil topic:nil success:^(MXRoom *room) {

            XCTAssertNotNil(room);
            
            BOOL isSync = (room.state.membership != MXMembershipInvite && room.state.membership != MXMembershipUnknown);
            XCTAssertTrue(isSync, @"The callback must be called once the room has been initialSynced");

            XCTAssertEqual(1, room.state.members.count, @"Bob must be the only one. members: %@", room.state.members);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testDidSyncNotification
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        mxSession = mxSession2;

        id observer;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionDidSyncNotification object:mxSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            MXSyncResponse *syncResponse = (MXSyncResponse*)notif.userInfo[kMXSessionNotificationSyncResponseKey];

            XCTAssert([syncResponse isKindOfClass:MXSyncResponse.class]);
            XCTAssert(syncResponse.rooms.join[room.roomId], @"We should receive back the 'Hello' sent in this room");

            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            [expectation fulfill];
        }];

        [room sendTextMessage:@"Hello" success:nil failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testCreateRoomWithInvite
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession2, XCTestExpectation *expectation) {
        
        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            mxSession = mxSession2;
            
            // Create a random room with no params
            [mxSession createRoom:nil visibility:nil roomAlias:nil topic:nil invite:@[matrixSDKTestsData.aliceCredentials.userId] invite3PID:nil isDirect:NO preset:nil success:^(MXRoom *room) {
                
                XCTAssertNotNil(room);
                
                BOOL isSync = (room.state.membership != MXMembershipInvite && room.state.membership != MXMembershipUnknown);
                XCTAssertTrue(isSync, @"The callback must be called once the room has been initialSynced");
                
                [mxSession.matrixRestClient membersOfRoom:room.roomId success:^(NSArray *roomMemberEvents) {
                    
                    XCTAssertEqual(roomMemberEvents.count, 2);
                    
                    MXEvent *roomMemberEvent1 = roomMemberEvents[0];
                    MXEvent *roomMemberEvent2 = roomMemberEvents[1];
                    
                    BOOL succeed;
                    if ([roomMemberEvent1.stateKey isEqualToString:mxSession.myUser.userId])
                    {
                        succeed = [roomMemberEvent2.stateKey isEqualToString:matrixSDKTestsData.aliceCredentials.userId];
                    }
                    else if ([roomMemberEvent1.stateKey isEqualToString:matrixSDKTestsData.aliceCredentials.userId])
                    {
                        succeed = [roomMemberEvent2.stateKey isEqualToString:mxSession.myUser.userId];
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
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession2, XCTestExpectation *expectation) {
        
        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            mxSession = mxSession2;
            
            // Create a random room with no params
            [mxSession createRoom:nil visibility:nil roomAlias:nil topic:nil invite:@[matrixSDKTestsData.aliceCredentials.userId] invite3PID:nil isDirect:YES preset:kMXRoomPresetTrustedPrivateChat success:^(MXRoom *room) {
                
                XCTAssertNotNil(room);
                
                BOOL isSync = (room.state.membership != MXMembershipInvite && room.state.membership != MXMembershipUnknown);
                XCTAssertTrue(isSync, @"The callback must be called once the room has been initialSynced");
                
                [mxSession.matrixRestClient membersOfRoom:room.roomId success:^(NSArray *roomMemberEvents) {
                    
                    XCTAssertEqual(roomMemberEvents.count, 2);
                    
                    MXEvent *roomMemberEvent1 = roomMemberEvents[0];
                    MXEvent *roomMemberEvent2 = roomMemberEvents[1];
                    
                    BOOL succeed;
                    if ([roomMemberEvent1.stateKey isEqualToString:mxSession.myUser.userId])
                    {
                        succeed = [roomMemberEvent2.stateKey isEqualToString:matrixSDKTestsData.aliceCredentials.userId];
                    }
                    else if ([roomMemberEvent1.stateKey isEqualToString:matrixSDKTestsData.aliceCredentials.userId])
                    {
                        succeed = [roomMemberEvent2.stateKey isEqualToString:mxSession.myUser.userId];
                    }
                    
                    XCTAssertTrue(succeed);
                    
                    // Force sync to get direct rooms list
                    [mxSession startWithMessagesLimit:0 onServerSyncDone:^{
                        
                        XCTAssertTrue(room.isDirect);
                        
                        // Check whether both members have the same power level (trusted_private_chat preset)
                        MXRoomPowerLevels *roomPowerLevels = room.state.powerLevels;
                        
                        XCTAssertNotNil(roomPowerLevels);
                        NSUInteger powerlLevel1 = [roomPowerLevels powerLevelOfUserWithUserID:mxSession.myUser.userId];
                        NSUInteger powerlLevel2 = [roomPowerLevels powerLevelOfUserWithUserID:matrixSDKTestsData.aliceCredentials.userId];
                        XCTAssertEqual(powerlLevel1, powerlLevel2, @"The members must have the same power level");
                        
                        [expectation fulfill];
                        
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
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        mxSession = bobSession;
        
        MXRoom *mxRoom1 = [mxSession directJoinedRoomWithUserId:aliceRestClient.credentials.userId];
        XCTAssertEqualObjects(mxRoom1.state.roomId, roomId, @"We should retrieve the last created room");
        
        [mxSession leaveRoom:roomId success:^{
            MXRoom *mxRoom2 = [mxSession directJoinedRoomWithUserId:aliceRestClient.credentials.userId];
            if (mxRoom2) {
                XCTAssertNotEqualObjects(mxRoom2.state.roomId, roomId, @"We should not retrieve the left room");
            }
            
            [expectation fulfill];
            
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
        }];
    }];
}


#pragma mark MXSessionNewRoomNotification tests
- (void)testNewRoomNotificationOnInvite
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

            mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            [mxSession start:^{

                // Listen to Alice's MXSessionNewRoomNotification event
                __block __weak id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    XCTAssertEqual(mxSession, note.object, @"The MXSessionNewRoomNotification sender must be the current MXSession");

                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
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

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession start:^{

            __block __weak id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                XCTAssertEqual(mxSession, note.object, @"The MXSessionNewRoomNotification sender must be the current MXSession");

                MXRoom *publicRoom = [mxSession roomWithRoomId:note.userInfo[kMXSessionNotificationRoomIdKey]];
                XCTAssertNotNil(publicRoom);

                [[NSNotificationCenter defaultCenter] removeObserver:observer];
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

            mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            [mxSession start:^{

                // Listen to Alice's MXSessionNewRoomNotification event
                __block __weak id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    XCTAssertEqual(mxSession, note.object, @"The MXSessionNewRoomNotification sender must be the current MXSession");

                    MXRoom *publicRoom = [mxSession roomWithRoomId:note.userInfo[kMXSessionNotificationRoomIdKey]];
                    XCTAssertNotNil(publicRoom);

                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                    [expectation fulfill];
                }];

                [mxSession joinRoom:roomId success:nil failure:^(NSError *error) {
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

            mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            [mxSession start:^{

                // Listen to Alice's kMXRoomInitialSyncNotification event
                __block __weak id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    MXRoom *publicRoom = (MXRoom*)note.object;
                    XCTAssertNotNil(publicRoom);

                    BOOL isSync = (publicRoom.state.membership != MXMembershipInvite && publicRoom.state.membership != MXMembershipUnknown);
                    XCTAssert(isSync, @"kMXRoomInitialSyncNotification must inform when the room state is fully known");

                    XCTAssertEqual(mxSession, publicRoom.mxSession, @"The session of the sent MXRoom must be the right one");

                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                    [expectation fulfill];
                }];

                [mxSession joinRoom:roomId success:nil failure:^(NSError *error) {
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
                                mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
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

                                    XCTAssertEqualObjects(room1.state.topic, @"1", "The order is wrong");
                                    XCTAssertEqualObjects(room2.state.topic, @"2", "The order is wrong");
                                    XCTAssertEqualObjects(room3.state.topic, @"3", "The order is wrong");


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
                        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                        [mxSession start:^{

                            NSArray<MXRoom*> *roomsWithTag = [mxSession roomsWithTag:tag];

                            // If the order is the same, the room must be sorted by their last event
                            XCTAssertEqualObjects(roomsWithTag[0].state.topic, @"newest");
                            XCTAssertEqualObjects(roomsWithTag[1].state.topic, @"oldest");

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
                    mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
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
                                mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
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
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        mxSession = bobSession;

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

            [aliceRestClient inviteUser:bobSession.matrixRestClient.credentials.userId toRoom:testRoomId success:^{

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
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        mxSession = bobSession;

        id observer;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            XCTAssertEqual(notif.object, mxSession);

            MXEvent *toDeviceEvent = notif.userInfo[kMXSessionNotificationEventKey];
            XCTAssert(toDeviceEvent);

            XCTAssertEqualObjects(toDeviceEvent.sender, aliceRestClient.credentials.userId);
            XCTAssertEqual(toDeviceEvent.eventType, MXEventTypeRoomKeyRequest);

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

            [expectation fulfill];
        }];

        MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
        [contentMap setObjects:@{
                                 @"*": @{
                                         @"device_id": @"AliceDevice",
                                         @"rooms": @[roomId]
                                         }
                                 } forUser:mxSession.myUser.userId];

        [aliceRestClient sendToDevice:kMXEventTypeStringRoomKeyRequest contentMap:contentMap txnId:nil success:^{

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}


@end

#pragma clang diagnostic pop
