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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

@interface MXUserTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;

    MXSession *mxSession;
}
@end

@implementation MXUserTests

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

    matrixSDKTestsData = nil;
    
    [super tearDown];
}

- (void)doTestWithBobAndAliceActiveInARoom:(void (^)(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    // Make sure Alice and Bob have activities
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [bobRestClient sendTextMessageToRoom:roomId threadId:nil text:@"Hi Alice!" success:^(NSString *eventId) {

            [aliceRestClient sendTextMessageToRoom:roomId threadId:nil text:@"Hi Bob!" success:^(NSString *eventId) {

                mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                [matrixSDKTestsData retain:mxSession];

                // Start the session
                [mxSession start:^{

                    readyToTest(bobRestClient, aliceRestClient, roomId, expectation);

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

/* Disabled as lastActiveAgo events sent by the HS are less accurate than before
- (void)testLastActiveAgo
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        NSArray *users = mxSession.users;

        XCTAssertNotNil(users);
        XCTAssertGreaterThanOrEqual(users.count, 2, "mxBob must know at least mxBob and mxAlice");

        MXUser *mxAlice;
        NSUInteger lastAliceActivity = -1;
        for (MXUser *user in users)
        {
            if ([user.userId isEqualToString:bobRestClient.credentials.userId])
            {
                // @TODO: Decrease the 30s value when SYN-157 is fixed
                XCTAssertLessThan(user.lastActiveAgo, 30000, @"mxBob has just sent a message. lastActiveAgo should not exceeds 5s. Found: %tu", user.lastActiveAgo);
            }
            if ([user.userId isEqualToString:aliceRestClient.credentials.userId])
            {
                mxAlice = user;
                lastAliceActivity = user.lastActiveAgo;
                // @TODO: Decrease the 30s value when SYN-157 is fixed
                XCTAssertLessThan(user.lastActiveAgo, 30000, @"mxAlice has just sent a message. lastActiveAgo should not exceeds 1s. Found: %tu", user.lastActiveAgo);

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
*/

- (void)testOtherUserLastActiveUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXUser *mxAlice = [mxSession userWithUserId:aliceRestClient.credentials.userId];
        XCTAssert(mxAlice);

        [mxAlice listenToUserUpdate:^(MXEvent *event) {

            XCTAssertEqual(event.eventType, MXEventTypePresence);
            [expectation fulfill];

        }];

        [aliceRestClient setPresence:MXPresenceOnline andStatusMessage:@"" success:^{

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testOtherUserProfileUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXUser *mxAlice = [mxSession userWithUserId:aliceRestClient.credentials.userId];
        XCTAssert(mxAlice);

        [mxAlice listenToUserUpdate:^(MXEvent *event) {

            XCTAssert(event.eventType == MXEventTypePresence || event.eventType == MXEventTypeRoomMember, @"%@", event);

            if (event.eventType == MXEventTypePresence)
            {
                XCTAssert([mxAlice.displayname isEqualToString:@"ALICE"]);
                XCTAssert([mxAlice.avatarUrl isEqualToString:kMXTestsAliceAvatarURL]);

                [expectation fulfill];
            }

        }];

        [aliceRestClient setDisplayName:@"ALICE" success:^{

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


- (void)testOtherUserPresenceUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXUser *mxAlice = [mxSession userWithUserId:aliceRestClient.credentials.userId];
        XCTAssert(mxAlice);

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
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMyUserAvailability
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:mxSession];

        XCTAssertNil(mxSession.myUser);

        [mxSession start:^{

            XCTAssertNotNil(mxSession.myUser);

            XCTAssertEqualObjects(mxSession.myUser.displayname, kMXTestsAliceDisplayName);
            //XCTAssertEqualObjects(mxSession.myUser.avatarUrl, kMXTestsAliceAvatarURL);    // Disabled because setting avatar does not work anymore with local test homeserver

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

/* Disabled as lastActiveAgo events sent by the HS are less accurate than before
- (void)testMyUserLastActiveUpdate
{
    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {

            XCTAssertEqual(event.eventType, MXEventTypePresence);
            [expectation fulfill];

        }];

        [bobRestClient sendTextMessageToRoom:roomId text:@"A message to update my last active ago" success:^(NSString *eventId) {

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}
 */

// Disabled because presence is currently disabled on hs side
//- (void)testMyUserProfileUpdate
//{
//    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
//
//        // Do tests with Alice since tests are not supposed to change Bob's profile
//        [mxSession close];
//
//        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
//        [matrixSDKTestsData retain:mxSession];
//
//        [mxSession start:^{
//
//            [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {
//
//                XCTAssert(event.eventType == MXEventTypePresence || event.eventType == MXEventTypeRoomMember, @"%@", event);
//
//                XCTAssertEqualObjects(mxSession.myUser.displayname, @"ALICE");
//                XCTAssertEqualObjects(mxSession.myUser.avatarUrl, kMXTestsAliceAvatarURL);
//
//                [expectation fulfill];
//
//            }];
//
//            [aliceRestClient setDisplayName:@"ALICE" success:^{
//
//            } failure:^(NSError *error) {
//                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                [expectation fulfill];
//            }];
//
//        } failure:^(NSError *error) {
//            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//            [expectation fulfill];
//        }];
//    }];
//}
//
//
//- (void)testMyUserPresenceUpdate
//{
//    [self doTestWithBobAndAliceActiveInARoom:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
//
//        // Do tests with Alice since tests are not supposed to change Bob's profile
//        [mxSession close];
//
//        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
//        [matrixSDKTestsData retain:mxSession];
//
//        [mxSession start:^{
//
//            [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {
//
//                // Filter first presence events for online
//                if (MXPresenceOnline != mxSession.myUser.presence)
//                {
//                    XCTAssertEqual(event.eventType, MXEventTypePresence);
//
//                    XCTAssert([mxSession.myUser.displayname isEqualToString:kMXTestsAliceDisplayName]);
//                    XCTAssert([mxSession.myUser.avatarUrl isEqualToString:kMXTestsAliceAvatarURL]);
//
//                    XCTAssertEqual(mxSession.myUser.presence, MXPresenceUnavailable);
//                    XCTAssertEqualObjects(mxSession.myUser.statusMsg, @"in Wonderland");
//
//                    [expectation fulfill];
//                }
//            }];
//
//            [aliceRestClient setPresence:MXPresenceUnavailable andStatusMessage:@"in Wonderland" success:^{
//
//            } failure:^(NSError *error) {
//                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                [expectation fulfill];
//            }];
//
//        } failure:^(NSError *error) {
//            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//            [expectation fulfill];
//        }];
//
//    }];
//}

@end
