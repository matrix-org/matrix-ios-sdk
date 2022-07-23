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

#import "MXNotificationCenter.h"

#pragma mark - MXNotificationCenter overide for tests
@interface MXNotificationCenterTests: MXNotificationCenter

// Force MXNotificationCenter to use custom push rules
- (void)setFlatRules:(NSArray *)flatRules;

@end


@implementation MXNotificationCenter (MXPushRuleConditionCheckerTests)

- (void)setFlatRules:(NSArray *)newFlatRules
{
    flatRules = [NSMutableArray arrayWithArray:newFlatRules];
}

@end


@interface MXPushRuleUnitTests : XCTestCase
{
}

@end


#pragma mark - MXPushRuleTests helper methods
@implementation MXPushRuleUnitTests


- (MXPushRule *)contentRuleWithPattern:(NSString*)pattern
{
    MXPushRule *rule = [MXPushRule modelFromJSON:@{
                                       @"pattern": pattern,
                                       @"enabled": @YES,
                                       @"rule_id": @"aRuleId",
                                       @"actions": @[
                                               @"notify",
                                               @{
                                                   @"set_tweak": @"sound",
                                                   @"value": @"default"
                                                   },
                                               @{
                                                   @"set_tweak": @"highlight",
                                                   @"value": @YES
                                                   }
                                               ]
                                       }];

    rule.kind = MXPushRuleKindContent;
    
    return rule;
}

- (MXEvent*)messageTextEventWithContent:(NSString*)content
{
    return [MXEvent modelFromJSON:@{
        @"type": kMXEventTypeStringRoomMessage,
        @"event_id": @"anID",
        @"room_id": @"roomId",
        @"user_id": @"userId",
        @"content": @{
                kMXMessageBodyKey: content,
                kMXMessageTypeKey: kMXMessageTypeText
        }
    }];
}

#pragma mark - The tests
// Test per-word notification with pattern: "foo"
- (void)testEventContentMatchFoo
{
    MXEvent *event;
    MXPushRule *matchingRule;

    // Set up a minimalist MXNotificationCenter with only one rule
    MXNotificationCenter *notificationCenter = [[MXNotificationCenter alloc] initWithMatrixSession:nil];
    MXPushRule *rule = [self contentRuleWithPattern:@"foo"];
    notificationCenter.flatRules = @[rule];

    event = [self messageTextEventWithContent:@"foo bar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"foo,bar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"bar.foo"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"bar.foo!bar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"foobar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNil(matchingRule, @"'In this test, foo must be surrounded by word delimiters (e.g. punctuation and whitespace or start/end of line)");

    event = [self messageTextEventWithContent:@"barfoo"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNil(matchingRule, @"'In this test, foo must be surrounded by word delimiters (e.g. punctuation and whitespace or start/end of line)");

}

// Test per-word notification with pattern: "foo*"
- (void)testEventContentMatchFooStar
{
    MXEvent *event;
    MXPushRule *matchingRule;

    // Set up a minimalist MXNotificationCenter with only one rule
    MXNotificationCenter *notificationCenter = [[MXNotificationCenter alloc] initWithMatrixSession:nil];
    MXPushRule *rule = [self contentRuleWithPattern:@"foo*"];
    notificationCenter.flatRules = @[rule];

    event = [self messageTextEventWithContent:@"foo bar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"foo,bar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"bar.foo"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"bar.foo!bar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"foobar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"barfoo"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNil(matchingRule, @"'In this test, only words starting with foo must match");
}

// Test per-word notification with pattern: "*foo*"
- (void)testEventContentMatchStarFooStar
{
    MXEvent *event;
    MXPushRule *matchingRule;

    // Set up a minimalist MXNotificationCenter with only one rule
    MXNotificationCenter *notificationCenter = [[MXNotificationCenter alloc] initWithMatrixSession:nil];
    MXPushRule *rule = [self contentRuleWithPattern:@"*foo*"];
    notificationCenter.flatRules = @[rule];

    event = [self messageTextEventWithContent:@"foo bar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"foobar"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"barfoo"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);

    event = [self messageTextEventWithContent:@"foobarfoo"];
    matchingRule = [notificationCenter ruleMatchingEvent:event roomState:nil];
    XCTAssertNotNil(matchingRule);
    XCTAssertEqual(matchingRule, rule);
}

@end
