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

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

@interface MXUserTests : XCTestCase
{
    MXSession *mxSession;
}
@end

@implementation MXUserTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    if (mxSession)
    {
        [mxSession close];
        mxSession = nil;
    }
    [super tearDown];
}

- (void)doTestWithBobAndAliceActiveInARoom:(void (^)(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString* room_id, XCTestExpectation *expectation))readyToTest
{
    // Make sure Alice and Bob have activities
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {

        [bobRestClient postTextMessageToRoom:room_id text:@"Hi Alice!" success:^(NSString *event_id) {

            [aliceRestClient postTextMessageToRoom:room_id text:@"Hi Bob!" success:^(NSString *event_id) {

                mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

                // Start the session
                [mxSession start:^{

                    readyToTest(bobRestClient, aliceRestClient, room_id, expectation);

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

- (void)testLastActiveAgo
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {

        NSArray *users = mxSession.users;

        XCTAssertNotNil(users);
        XCTAssertGreaterThanOrEqual(users.count, 2, "mxBob must know at least mxBob and mxAlice");

        MXUser *mxAlice;
        NSUInteger lastAliceActivity = -1;
        for (MXUser *user in users)
        {
            if ([user.userId isEqualToString:bobRestClient.credentials.userId])
            {
                XCTAssertLessThan(user.lastActiveAgo, 5000, @"mxBob has just posted a message. lastActiveAgo should not exceeds 5s. Found: %ld", user.lastActiveAgo);
            }
            if ([user.userId isEqualToString:aliceRestClient.credentials.userId])
            {
                mxAlice = user;
                lastAliceActivity = user.lastActiveAgo;
                XCTAssertLessThan(user.lastActiveAgo, 1000, @"mxAlice has just posted a message. lastActiveAgo should not exceeds 1s. Found: %ld", user.lastActiveAgo);

                // mxAlice has a displayname and avatar defined. They should be found in the presence event
                XCTAssert([user.displayname isEqualToString:kMXTestsAliceDisplayName]);
                XCTAssert([user.avatarUrl isEqualToString:kMXTestsAliceAvatarURL]);
            }
        }

        // Wait a bit before getting lastActiveAgo again
        [NSThread sleepForTimeInterval:1.0];

        NSUInteger newLastAliceActivity = mxAlice.lastActiveAgo;
        XCTAssertGreaterThanOrEqual(newLastAliceActivity, lastAliceActivity + 1000, @"MXUser.lastActiveAgo should auto increase");

        [expectation fulfill];

    }];
}

- (void)testOtherUserLastActiveUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {

        MXUser *mxAlice = [mxSession userWithUserId:aliceRestClient.credentials.userId];

        [mxAlice listenToUserUpdate:^(MXEvent *event) {

            XCTAssertEqual(event.eventType, MXEventTypePresence);
            [expectation fulfill];

        }];

        [aliceRestClient postTextMessageToRoom:room_id text:@"A message to update my last active ago" success:^(NSString *event_id) {

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testOtherUserProfileUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {

        MXUser *mxAlice = [mxSession userWithUserId:aliceRestClient.credentials.userId];

        [mxAlice listenToUserUpdate:^(MXEvent *event) {

            XCTAssertEqual(event.eventType, MXEventTypePresence);

            XCTAssert([mxAlice.displayname isEqualToString:@"ALICE"]);
            XCTAssert([mxAlice.avatarUrl isEqualToString:kMXTestsAliceAvatarURL]);

            [expectation fulfill];

        }];

        [aliceRestClient setDisplayName:@"ALICE" success:^{

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}


- (void)testOtherUserPresenceUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {

        MXUser *mxAlice = [mxSession userWithUserId:aliceRestClient.credentials.userId];

        [mxAlice listenToUserUpdate:^(MXEvent *event) {

            XCTAssertEqual(event.eventType, MXEventTypePresence);

            XCTAssert([mxAlice.displayname isEqualToString:kMXTestsAliceDisplayName]);
            XCTAssert([mxAlice.avatarUrl isEqualToString:kMXTestsAliceAvatarURL]);

            XCTAssertEqual(mxAlice.presence, MXPresenceUnavailable);
            XCTAssert([mxAlice.statusMsg isEqualToString:@"in Wonderland"]);

            [expectation fulfill];

        }];

        [aliceRestClient setPresence:MXPresenceUnavailable andStatusMessage:@"in Wonderland" success:^{

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testMyUserAvailability
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];

        XCTAssertNil(mxSession.myUser);

        [mxSession start:^{

            XCTAssertNotNil(mxSession.myUser);

            XCTAssert([mxSession.myUser.displayname isEqualToString:kMXTestsAliceDisplayName]);
            XCTAssert([mxSession.myUser.avatarUrl isEqualToString:kMXTestsAliceAvatarURL]);

            [expectation fulfill];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testMyUserLastActiveUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {

        [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {

            XCTAssertEqual(event.eventType, MXEventTypePresence);
            [expectation fulfill];

        }];

        [bobRestClient postTextMessageToRoom:room_id text:@"A message to update my last active ago" success:^(NSString *event_id) {

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testMyUserProfileUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {

        // Do tests with Alice since tests are not supposed to change Bob's profile
        [mxSession close];

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [mxSession start:^{

            [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {

                XCTAssertEqual(event.eventType, MXEventTypePresence);

                XCTAssert([mxSession.myUser.displayname isEqualToString:@"ALICE"]);
                XCTAssert([mxSession.myUser.avatarUrl isEqualToString:kMXTestsAliceAvatarURL]);

                [expectation fulfill];

            }];

            [aliceRestClient setDisplayName:@"ALICE" success:^{

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}


- (void)testMyUserPresenceUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {

        // Do tests with Alice since tests are not supposed to change Bob's profile
        [mxSession close];

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [mxSession start:^{

            [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {

                XCTAssertEqual(event.eventType, MXEventTypePresence);

                XCTAssert([mxSession.myUser.displayname isEqualToString:kMXTestsAliceDisplayName]);
                XCTAssert([mxSession.myUser.avatarUrl isEqualToString:kMXTestsAliceAvatarURL]);

                XCTAssertEqual(mxSession.myUser.presence, MXPresenceUnavailable);
                XCTAssert([mxSession.myUser.statusMsg isEqualToString:@"in Wonderland"]);

                [expectation fulfill];

            }];

            [aliceRestClient setPresence:MXPresenceUnavailable andStatusMessage:@"in Wonderland" success:^{

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
}

@end
