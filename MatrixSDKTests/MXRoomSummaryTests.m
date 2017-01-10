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

#import "MXRoomSummaryUpdater.h"

@interface MXRoomSummaryTests : XCTestCase <MXRoomSummaryUpdating>
{
    MatrixSDKTestsData *matrixSDKTestsData;

    // Flags to check the delegate has been called
    BOOL testDelegate;
    BOOL testNoChangeDelegate;
}

@end

NSString *testDelegateLastEventString = @"The string I decider to render for this event";

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

    if ([self.description containsString:@"testDelegate"])
    {
        XCTAssertNotEqualObjects(summary.lastEvent.eventId, event.eventId);

        // Do a classic update
        MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:session];
        updated = [updater session:session updateRoomSummary:summary withLastEvent:event oldState:oldState];

        summary.lastEventString = testDelegateLastEventString;

        XCTAssert(updated);
        XCTAssertEqualObjects(summary.lastEvent.eventId, event.eventId);

        testDelegate = YES;
    }
    else if ([self.description containsString:@"testNoChangeDelegate"])
    {
        testNoChangeDelegate = YES;

        // Force a kMXRoomSummaryDidChangeNotification
        [summary save];
    }
    else
    {
        XCTFail(@"Unexpected delegate call in %@", self);
    }

    return updated;
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withStateEvent:(MXEvent *)event
{
    // Do a classic update
    MXRoomSummaryUpdater *updater = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:session];
    return [updater session:session updateRoomSummary:summary withStateEvent:event];
}

- (void)test
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummary *summary = room.summary;
        XCTAssert(summary);

        XCTAssertEqualObjects(summary.roomId, room.roomId);
        XCTAssert(summary.lastEvent);

        [expectation fulfill];

    }];
}

- (void)testDelegate
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXRoomSummary *summary = room.summary;
        mxSession.roomSummaryUpdateDelegate = self;

        __block NSString *lastEventId;

        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

            XCTAssert(testDelegate);
            XCTAssertEqualObjects(summary.lastEvent.eventId, lastEventId);
            XCTAssertEqualObjects(summary.lastEventString, testDelegateLastEventString);

            [expectation fulfill];
        }];

        [room sendTextMessage:@"new message" success:^(NSString *eventId) {
            lastEventId = eventId;
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

        MXEvent *lastEvent = summary.lastEvent;


        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomSummaryDidChangeNotification object:summary queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

            [[NSNotificationCenter defaultCenter] removeObserver:observer];

            XCTAssert(testNoChangeDelegate);
            XCTAssertEqualObjects(summary.lastEvent.eventId, lastEvent.eventId);

            [expectation fulfill];
        }];

        [room sendTextMessage:@"new message" success:nil failure:^(NSError *error) {
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

- (void)testOutgoingMessage
{
    XCTFail(@"@TODO: To implement...");
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

                XCTAssertEqualObjects(summary.lastEvent.eventId, invitationEvent.eventId);
                XCTAssertEqual(summary.lastEvent.eventType, MXEventTypeRoomMember);

                // @TODO: Fix it (or fix the test) (is it testable?)
                //XCTAssertEqualObjects(summary.displayname, newRoomName);
                //XCTAssertEqualObjects(summary.topic, newRoomTopic);
                
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

@end
