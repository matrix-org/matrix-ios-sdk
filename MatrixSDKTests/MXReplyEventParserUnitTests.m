/*
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

#import "MXReplyEventParser.h"
#import "MXEnumConstants.h"

@interface MXReplyEventParserUnitTests : XCTestCase

@end

@implementation MXReplyEventParserUnitTests

- (MXEvent*)fakeReplyEventWithBody:(NSString*)body andFormattedBody:(NSString*)formattedBody
{
    NSDictionary *replyEventDict = @{
        @"content": @{
            kMXMessageBodyKey: body,
            @"formatted_body": formattedBody,
            @"format": kMXRoomMessageFormatHTML,
            kMXEventRelationRelatesToKey: @{
                kMXEventContentRelatesToKeyInReplyTo: @{
                    kMXEventContentRelatesToKeyEventId: @"$1561994860861855MtlYo:matrix.org"
                }
            },
            kMXMessageTypeKey: kMXMessageTypeText
        },
        @"event_id": @"$eventid:matrix.org",
        @"origin_server_ts": @(1560254175300),
        @"sender": @"@user:matrix.org",
        @"type": kMXEventTypeStringRoomMessage,
        @"unsigned": @{
            @"age": @(5328779)
        },
        @"room_id": @"!roomid:matrix.org"
    };
    
    MXEvent *replyEvent = [MXEvent modelFromJSON:replyEventDict];
    return replyEvent;
}

- (void)testReplyEventParser
{
    NSString *expectedBodyPrefix = @"> <@user:matrix.org> Test\n\n";
    NSString *expectedReplyText = @"\n\nReply";
    NSString *body = [NSString stringWithFormat:@"%@%@", expectedBodyPrefix, expectedReplyText];
    
    NSString *expectedFormattedBodyPrefix = @"<mx-reply><blockquote><a href=\"https://matrix.to/#/!IaGDumUyKyFkJzddqp:matrix.org/$1561994860861855MtlYo:matrix.org?via=matrix.org\">In reply to</a> <a href=\"https://matrix.to/#/@user:matrix.org\">@user:matrix.org</a><br><p>Test</p>\n<blockquote>\n</blockquote>\n<p>Test<br />\\n<br />\\n</p>\n</blockquote></mx-reply>";
    NSString *expectedFormattedReplyText = @"<blockquote>\n</blockquote>\n<p>Test</p>\n";
    NSString *formattedBody = [NSString stringWithFormat:@"%@%@", expectedFormattedBodyPrefix, expectedFormattedReplyText];
    
    MXEvent *replyEvent = [self fakeReplyEventWithBody:body andFormattedBody:formattedBody];
    
    MXReplyEventParser *replyEventParser = [MXReplyEventParser new];
    MXReplyEventParts *eventParts = [replyEventParser parse:replyEvent];
    
    XCTAssertNotNil(eventParts);
    
    XCTAssertEqualObjects(eventParts.bodyParts.replyTextPrefix, expectedBodyPrefix);
    XCTAssertEqualObjects(eventParts.bodyParts.replyText, expectedReplyText);
    
    XCTAssertEqualObjects(eventParts.formattedBodyParts.replyTextPrefix, expectedFormattedBodyPrefix);
    XCTAssertEqualObjects(eventParts.formattedBodyParts.replyText, expectedFormattedReplyText);
}

- (void)testReplyEventParser2
{
    NSString *expectedBodyPrefix = @"> <@user:matrix.org> Test\n> >\n> Test\n> \\n\n> \\n\n\n";
    NSString *expectedReplyText = @"\n>\nTest";
    NSString *body = [NSString stringWithFormat:@"%@%@", expectedBodyPrefix, expectedReplyText];

    NSString *expectedFormattedBodyPrefix = @"<mx-reply><blockquote><a href=\"https://matrix.to/#/!IaGDumUyKyFkJzddqp:matrix.org/$1561994984862328mxQdo:matrix.org?via=matrix.org\">In reply to</a> <a href=\"https://matrix.to/#/@user:matrix.org\">@user:matrix.org</a><br>Test</blockquote></mx-reply>";
    NSString *expectedFormattedReplyText = @"Reply";
    NSString *formattedBody = [NSString stringWithFormat:@"%@%@", expectedFormattedBodyPrefix, expectedFormattedReplyText];
    
    MXEvent *replyEvent = [self fakeReplyEventWithBody:body andFormattedBody:formattedBody];
    
    MXReplyEventParser *replyEventParser = [MXReplyEventParser new];
    MXReplyEventParts *eventParts = [replyEventParser parse:replyEvent];
    
    XCTAssertNotNil(eventParts);
    
    XCTAssertEqualObjects(eventParts.bodyParts.replyTextPrefix, expectedBodyPrefix);
    XCTAssertEqualObjects(eventParts.bodyParts.replyText, expectedReplyText);
    
    XCTAssertEqualObjects(eventParts.formattedBodyParts.replyTextPrefix, expectedFormattedBodyPrefix);
    XCTAssertEqualObjects(eventParts.formattedBodyParts.replyText, expectedFormattedReplyText);
}

- (void)testReplyEventParser3
{
    NSString *expectedBodyPrefix = @"> <@user:matrix.org> **Testo**\n\n";
    NSString *expectedReplyText = @"<>*Test*<>\n\n";
    NSString *body = [NSString stringWithFormat:@"%@%@", expectedBodyPrefix, expectedReplyText];
    
    NSString *expectedFormattedBodyPrefix = @"<mx-reply><blockquote><a href=\"https://matrix.to/#/!udRWDmubDtEheLCChL%3Amatrix.org/%24la6cTVc2ln_4uN5QndQOpFlLGlMP1f5nAIUk6JUhtHQ\">In reply to</a> <a href=\"https://matrix.to/#/@user:matrix.org\">@user:matrix.org</a><br><strong>Testo</strong></blockquote></mx-reply>";
    NSString *expectedFormattedReplyText = @"&lt;&gt;<em>Test</em>&lt;&gt;";
    NSString *formattedBody = [NSString stringWithFormat:@"%@%@", expectedFormattedBodyPrefix, expectedFormattedReplyText];
    
    MXEvent *replyEvent = [self fakeReplyEventWithBody:body andFormattedBody:formattedBody];
    
    MXReplyEventParser *replyEventParser = [MXReplyEventParser new];
    MXReplyEventParts *eventParts = [replyEventParser parse:replyEvent];
    
    XCTAssertNotNil(eventParts);
    
    XCTAssertEqualObjects(eventParts.bodyParts.replyTextPrefix, expectedBodyPrefix);
    XCTAssertEqualObjects(eventParts.bodyParts.replyText, expectedReplyText);
    
    XCTAssertEqualObjects(eventParts.formattedBodyParts.replyTextPrefix, expectedFormattedBodyPrefix);
    XCTAssertEqualObjects(eventParts.formattedBodyParts.replyText, expectedFormattedReplyText);
}

@end
