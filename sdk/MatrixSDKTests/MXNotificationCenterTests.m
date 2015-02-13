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

#import "MatrixSDKTestsData.h"
#import "MXSession.h"

@interface MXNotificationCenterTests : XCTestCase
{
    MXSession *bobSession;
    MXSession *aliceSession;
}

@end

@implementation MXNotificationCenterTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown {
    if (bobSession)
    {
        [[MatrixSDKTestsData sharedData] closeMXSession:bobSession];
        bobSession = nil;
    }
    if (aliceSession)
    {
        [[MatrixSDKTestsData sharedData] closeMXSession:aliceSession];
        aliceSession = nil;
    }
    [super tearDown];
}

- (void)testNotificationCenterRulesReady
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        XCTAssertNotNil(bobSession.notificationCenter);
        XCTAssertNil(bobSession.notificationCenter.rules);

        [bobSession start:^{

            XCTAssertNotNil(bobSession.notificationCenter.rules, @"Notification rules must be ready once MXSession is started");

            XCTAssertGreaterThanOrEqual(bobSession.notificationCenter.rules.count, 3, @"Home server defines 3 default rules (at least)");

            [expectation fulfill];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testNoNotificationsOnUserEvents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        bobSession = mxSession;

        [bobSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {

            XCTFail(@"Events from the user should be notified. event: %@\n rule: %@", event, rule);

        }];

        [room sendTextMessage:@"This message should not generate a notification" success:^(NSString *eventId) {

            // Wait to check that no notification happens
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                [expectation fulfill];

            });

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

// The HS defines a default underride rule asking to notify for all messages of other users.
// As per SYN-267, the HS does not list it when calling GET /pushRules/.
// While this ticket is not fixed, make sure the SDK workrounds it
- (void)testDefaultPushOnAllNonYouMessagesRule
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession2, MXSession *aliceSession2, NSString *roomId, XCTestExpectation *expectation) {

        bobSession = bobSession2;
        aliceSession = aliceSession2;

        [bobSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {

            // We must be alerted by the default content HS rule on "mxBob"
            // XCTAssertEqualObjects(rule.kind, ...) @TODO
            XCTAssert(rule.isDefault, @"The rule must be the server default rule. Rule: %@", rule);

            [expectation fulfill];
        }];

        MXRoom *roomFromAliceSide = [aliceSession roomWithRoomId:roomId];

        [roomFromAliceSide sendTextMessage:@"a message" success:^(NSString *eventId) {

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
};

- (void)testDefaultContentCondition
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession2, MXSession *aliceSession2, NSString *roomId, XCTestExpectation *expectation) {

        bobSession = bobSession2;
        aliceSession = aliceSession2;

        NSString *messageFromAlice = @"mxBob: you should be notified for this message";

        [bobSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {

            // We must be alerted by the default content HS rule on "mxBob"
            // XCTAssertEqualObjects(rule.kind, ...) @TODO
            XCTAssert(rule.isDefault, @"The rule must be the server default rule. Rule: %@", rule);
            XCTAssertEqualObjects(rule.pattern, @"mxBob", @"As content rule, the pattern must be define. Rule: %@", rule);

            // Check the right event has been notified
            XCTAssertEqualObjects(event.content[@"body"], messageFromAlice, @"The wrong messsage has been caught. event: %@", event);

            [expectation fulfill];
        }];

        MXRoom *roomFromAliceSide = [aliceSession roomWithRoomId:roomId];

        [roomFromAliceSide sendTextMessage:messageFromAlice success:^(NSString *eventId) {

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

@end
