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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MXSession.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXNotificationCenterTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}

@end

@implementation MXNotificationCenterTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    
    [super tearDown];
}

- (void)testNotificationCenterRulesReady
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        XCTAssertNotNil(mxSession.notificationCenter);
        XCTAssertNil(mxSession.notificationCenter.rules);
        XCTAssertNil(mxSession.notificationCenter.flatRules);

        [mxSession start:^{

            XCTAssertNotNil(mxSession.notificationCenter.rules, @"Notification rules must be ready once MXSession is started");

            XCTAssertNotNil(mxSession.notificationCenter.flatRules, @"Notification rules must be ready once MXSession is started");

            XCTAssertGreaterThanOrEqual(mxSession.notificationCenter.flatRules.count, 3, @"Home server defines 3 default rules (at least)");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testNoNotificationsOnUserEvents
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [mxSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {

            XCTFail(@"Events from the user should not be notified. event: %@\n rule: %@", event, rule);
            [expectation fulfill];

        }];

        [room sendTextMessage:@"This message should not generate a notification" threadId:nil success:^(NSString *eventId) {

            // Wait to check that no notification happens
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                [expectation fulfill];

            });

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testNoNotificationsOnPresenceOrTypingEvents
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [bobSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {

            XCTFail(@"Presence and typing events should not be notified with default push rules. event: %@\n rule: %@", event, rule);

            [expectation fulfill];
        }];

        [aliceRestClient setPresence:MXPresenceOnline andStatusMessage:nil success:^{

            [aliceRestClient sendTypingNotificationInRoom:roomId typing:YES timeout:30000 success:^{

                // Wait to check that no notification happens
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

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
        
    }];
}

// The HS defines a default underride rule asking to notify for all messages of other users.
// As per SYN-267, the HS does not list it when calling GET /pushRules/.
// While this ticket is not fixed, make sure the SDK workrounds it
- (void)testDefaultPushOnAllNonYouMessagesRule
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *mxSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [mxSession roomWithRoomId:roomId];
        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                [mxSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {

                    // We must be alerted by the default content HS rule on any message
                    XCTAssertEqual(rule.kind, MXPushRuleKindUnderride);
                    XCTAssert(rule.isDefault, @"The rule must be the server default rule. Rule: %@", rule);

                    [expectation fulfill];
                }];

                [aliceRestClient sendTextMessageToRoom:roomId threadId:nil text:@"a message" success:^(NSString *eventId) {

                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];

            }];
        }];

        // Make sure there 3 are peoples in the room to avoid to fire the default "room_member_count == 2" rule
        NSString *carolId = [aliceRestClient.credentials.userId stringByReplacingOccurrencesOfString:@"mxalice" withString:@"@mxcarol"];
        [room inviteUser:carolId success:^{

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
};

// Disabled as it seems that the registration method we use in tests now uses the
// local part of the user id as the default displayname
// Which makes this test reacts on the non expected notification rule (".m.rule.contains_display_name").
//- (void)testDefaultContentCondition
//{
//    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
//
//        mxSession = bobSession;
//
//        MXRoom *room = [mxSession roomWithRoomId:roomId];
//        [room.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
//
//            NSString *messageFromAlice = [NSString stringWithFormat:@"%@: you should be notified for this message", bobSession.matrixRestClient.credentials.userId];
//
//            [bobSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {
//
//                // We must be alerted by the default content HS rule on "mxBob"
//                XCTAssertEqual(rule.kind, MXPushRuleKindContent);
//                XCTAssert(rule.isDefault, @"The rule must be the server default rule. Rule: %@", rule);
//                XCTAssert([rule.pattern hasPrefix:@"mxbob"], @"As content rule, the pattern must be define. Rule: %@", rule);
//
//                // Check the right event has been notified
//                XCTAssertEqualObjects(event.content[kMXMessageBodyKey], messageFromAlice, @"The wrong messsage has been caught. event: %@", event);
//
//                [expectation fulfill];
//            }];
//
//
//            [aliceRestClient sendTextMessageToRoom:roomId text:messageFromAlice success:^(NSString *eventId) {
//
//            } failure:^(NSError *error) {
//                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                [expectation fulfill];
//            }];
//        }];
//
//        // Make sure there 3 are peoples in the room to avoid to fire the default "room_member_count == 2" rule
//        NSString *carolId = [aliceRestClient.credentials.userId stringByReplacingOccurrencesOfString:@"mxalice" withString:@"@mxcarol"];
//        [room inviteUser:carolId success:^{
//
//        } failure:^(NSError *error) {
//            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//            [expectation fulfill];
//        }];
//
//    }];
//}

- (void)testDefaultDisplayNameCondition
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *aliceSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:aliceSession];
        
        [aliceSession start:^{

            // Change alice name
            [aliceSession.myUser setDisplayName:@"AALLIICCEE" success:^{

                NSString *messageFromBob = @"Aalliiccee: where are you?";

                [aliceSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {

                    XCTAssertEqual(rule.kind, MXPushRuleKindOverride);

                    MXPushRuleCondition *condition = rule.conditions[0];

                    XCTAssertEqualObjects(condition.kind, kMXPushRuleConditionStringContainsDisplayName, @"The default content rule with contains_display_name condition must fire first");
                    XCTAssertEqual(condition.kindType, MXPushRuleConditionTypeContainsDisplayName);

                    [aliceSession close];
                    [expectation fulfill];

                }];

                MXRoom *roomBobSide = [bobSession roomWithRoomId:roomId];
                [roomBobSide sendTextMessage:messageFromBob threadId:nil success:^(NSString *eventId) {

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

- (void)testDefaultEventMatchCondition
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"We are two peoples in this room";

        [bobSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {

            // We must be alerted by the default content HS rule on room_member_count == 2
            XCTAssertEqual(rule.kind, MXPushRuleKindUnderride);
            XCTAssert(rule.isDefault, @"The rule must be the server default rule. Rule: %@", rule);

            MXPushRuleCondition *condition = rule.conditions[0];
            XCTAssertEqualObjects(condition.kind, kMXPushRuleConditionStringEventMatch, @"The default content rule with room_member_count condition must fire first");
            XCTAssertEqual(condition.kindType, MXPushRuleConditionTypeEventMatch);

            // Check the right event has been notified
            XCTAssertEqualObjects(event.content[kMXMessageBodyKey], messageFromAlice, @"The wrong messsage has been caught. event: %@", event);

            [expectation fulfill];
        }];

        [aliceRestClient sendTextMessageToRoom:roomId threadId:nil text:messageFromAlice success:^(NSString *eventId) {

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testRemoveListener
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"We are two peoples in this room";

        id listener = [bobSession.notificationCenter listenToNotifications:^(MXEvent *event, MXRoomState *roomState, MXPushRule *rule) {

            XCTFail(@"Listener has been removed. event: %@\n rule: %@", event, rule);

            [expectation fulfill];
        }];

        [bobSession.notificationCenter removeListener:listener];


        [aliceRestClient sendTextMessageToRoom:roomId threadId:nil text:messageFromAlice success:^(NSString *eventId) {

            // Wait to check that no notification happens
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [expectation fulfill];
            });

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testRuleMatchingEvent
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *aliceSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:aliceSession];
        
        [aliceSession start:^{

            // Change alice name
            [aliceSession.myUser setDisplayName:@"AALLIICCEE" success:^{

                NSString *messageFromBob = @"Aalliiccee: where are you?";

                [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

                    if (MXTimelineDirectionForwards == direction)
                    {
                        [[aliceSession roomWithRoomId:event.roomId] state:^(MXRoomState *roomState) {
                            
                            MXPushRule *rule = [aliceSession.notificationCenter ruleMatchingEvent:event roomState:roomState];

                            XCTAssert(rule, @"A push rule must be found for this event: %@", event);

                            // Do the same test as in testDefaultDisplayNameCondition
                            XCTAssertEqual(rule.kind, MXPushRuleKindOverride);

                            MXPushRuleCondition *condition = rule.conditions[0];

                            XCTAssertEqualObjects(condition.kind, kMXPushRuleConditionStringContainsDisplayName, @"The default content rule with contains_display_name condition must fire first");
                            XCTAssertEqual(condition.kindType, MXPushRuleConditionTypeContainsDisplayName);

                            [aliceSession close];
                            [expectation fulfill];
                        }];
                    }
                }];

                MXRoom *roomBobSide = [bobSession roomWithRoomId:roomId];
                [roomBobSide sendTextMessage:messageFromBob threadId:nil success:^(NSString *eventId) {

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


@end

#pragma clang diagnostic pop
