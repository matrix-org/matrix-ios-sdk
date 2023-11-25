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

#import "MXTools.h"
#import "MatrixSDKTestsSwiftHeader.h"
#import "MatrixSDKSwiftHeader.h"

@interface MXToolsUnitTests : XCTestCase

@end

@implementation MXToolsUnitTests

- (void)testGenerateSecret
{
    NSString *secret = [MXTools generateSecret];

    XCTAssertNotNil(secret);
}

- (void)testMatrixIdentifiers
{
    // Tests on homeserver domain (https://matrix.org/docs/spec/legacy/#users)
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:matrix.org"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:chat1234.matrix.org"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:chat-1234.matrix.org"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:chat-1234.aa.bbbb.matrix.org"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:matrix.org:8480"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:localhost"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:localhost:8480"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:127.0.0.1"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:127.0.0.1:8480"]);
    
    XCTAssertFalse([MXTools isMatrixUserIdentifier:@"@bob:matrix+25.org"]);
    XCTAssertFalse([MXTools isMatrixUserIdentifier:@"@bob:matrix[].org"]);
    XCTAssertFalse([MXTools isMatrixUserIdentifier:@"@bob:matrix.org."]);
    XCTAssertFalse([MXTools isMatrixUserIdentifier:@"@bob:matrix.org-"]);
    XCTAssertFalse([MXTools isMatrixUserIdentifier:@"@bob:matrix-.org"]);
    XCTAssertFalse([MXTools isMatrixUserIdentifier:@"@bob:matrix.&aaz.org"]);
    
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@Bob:matrix.org"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob1234:matrix.org"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@+33012:matrix.org"]);

    XCTAssertTrue([MXTools isMatrixEventIdentifier:@"$123456EventId:matrix.org"]);
    XCTAssertTrue([MXTools isMatrixEventIdentifier:@"$pmOSN/DognfuSfhdW/qivXT19lfCWpdSfaPFKDBTJUk+"]);

    XCTAssertTrue([MXTools isMatrixRoomIdentifier:@"!an1234Room:matrix.org"]);

    XCTAssertTrue([MXTools isMatrixRoomAlias:@"#matrix:matrix.org"]);
    XCTAssertTrue([MXTools isMatrixRoomAlias:@"#matrix:matrix.org:1234"]);

    XCTAssertTrue([MXTools isMatrixGroupIdentifier:@"+matrix:matrix.org"]);
}

- (void)testEmailAddresses
{
    XCTAssertTrue([MXTools isEmailAddress:@"alice@matrix.org"]);
    XCTAssertTrue([MXTools isEmailAddress:@"alice@matrix"]);
    XCTAssertTrue([MXTools isEmailAddress:@"al-i_ce@matrix"]);
    XCTAssertTrue([MXTools isEmailAddress:@"al+ice@matrix.org"]);
    XCTAssertTrue([MXTools isEmailAddress:@"al=ice@matrix.org"]);
    XCTAssertTrue([MXTools isEmailAddress:@"*@example.net"]);
    XCTAssertTrue([MXTools isEmailAddress:@"fred&barny@example.com"]);
    XCTAssertTrue([MXTools isEmailAddress:@"---@example.com"]);
    XCTAssertTrue([MXTools isEmailAddress:@"foo-bar@example.net"]);
    XCTAssertTrue([MXTools isEmailAddress:@"mailbox.sub1.sub2@this-domain"]);
    XCTAssertTrue([MXTools isEmailAddress:@"prettyandsimple@example.com"]);
    XCTAssertTrue([MXTools isEmailAddress:@"very.common@example.com"]);
    XCTAssertTrue([MXTools isEmailAddress:@"disposable.style.email.with+symbol@example.com"]);
    XCTAssertTrue([MXTools isEmailAddress:@"other.email-with-dash@example.com"]);
    XCTAssertTrue([MXTools isEmailAddress:@"x@example.com"]);
    XCTAssertTrue([MXTools isEmailAddress:@"example-indeed@strange-example.com"]);
    XCTAssertTrue([MXTools isEmailAddress:@"admin@mailserver1"]);
    XCTAssertTrue([MXTools isEmailAddress:@"#!$%&'*+-/=?^_`{}|~@example.org"]);
    XCTAssertTrue([MXTools isEmailAddress:@"example@localhost"]);
    XCTAssertTrue([MXTools isEmailAddress:@"example@s.solutions"]);
    XCTAssertTrue([MXTools isEmailAddress:@"user@localserver"]);
    XCTAssertTrue([MXTools isEmailAddress:@"user@tt"]);
    XCTAssertTrue([MXTools isEmailAddress:@"xn--80ahgue5b@xn--p-8sbkgc5ag7bhce.xn--ba-lmcq"]);
    XCTAssertTrue([MXTools isEmailAddress:@"nothing@xn--fken-gra.no"]);
    
    XCTAssertFalse([MXTools isEmailAddress:@"alice.matrix.org"]);
    XCTAssertFalse([MXTools isEmailAddress:@"al ice@matrix.org"]);
    XCTAssertFalse([MXTools isEmailAddress:@"al(ice@matrix.org"]);
    XCTAssertFalse([MXTools isEmailAddress:@"alice@"]);
    XCTAssertFalse([MXTools isEmailAddress:@"al\nice@matrix.org"]);
    XCTAssertFalse([MXTools isEmailAddress:@"al@ice@matrix.org"]);
    XCTAssertFalse([MXTools isEmailAddress:@"al@ice@.matrix.org"]);
    XCTAssertFalse([MXTools isEmailAddress:@"Just a string"]);
    XCTAssertFalse([MXTools isEmailAddress:@"string"]);
    XCTAssertFalse([MXTools isEmailAddress:@"me@"]);
    XCTAssertFalse([MXTools isEmailAddress:@"@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"me.@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@".me@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"me@example..com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"me\\@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"Abc.example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"A@b@c@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"a\"b(c)d,e:f;g<h>i[j\\k]l@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"just\"not\"right@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"this is\"not\\allowed@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"this\\ still\\\"not\\\\allowed@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"john..doe@example.com"]);
    XCTAssertFalse([MXTools isEmailAddress:@"john.doe@example..com"]);
}


#pragma mark - Strings encoding

// Matrix identifiers can be found at https://matrix.org/docs/spec/appendices.html#common-identifier-format
- (void)testRoomIdEscaping
{
    NSString *string = @"!tDRGDwZwQnlkowsjsm:matrix.org";
    XCTAssertEqualObjects([MXTools encodeURIComponent:string], @"!tDRGDwZwQnlkowsjsm%3Amatrix.org");
}

- (void)testRoomAliasEscaping
{
    NSString *string = @"#riot-ios:matrix.org";
    XCTAssertEqualObjects([MXTools encodeURIComponent:string], @"%23riot-ios%3Amatrix.org");
}

- (void)testEventIdEscaping
{
    NSString *string = @"$155006612045UiBxj:matrix.org";
    XCTAssertEqualObjects([MXTools encodeURIComponent:string], @"%24155006612045UiBxj%3Amatrix.org");
}

- (void)testV3EventIdEscaping
{
    NSString *string = @"$pmOSN/DognfuSfhdW/qivXT19lfCWpdSfaPFKDBTJUk+";
    XCTAssertEqualObjects([MXTools encodeURIComponent:string], @"%24pmOSN%2FDognfuSfhdW%2FqivXT19lfCWpdSfaPFKDBTJUk%2B");
}

- (void)testGroupIdEscaping
{
    NSString *string = @"+matrix:matrix.org";
    XCTAssertEqualObjects([MXTools encodeURIComponent:string], @"%2Bmatrix%3Amatrix.org");
}


#pragma mark - File extensions

- (void)testFileExtensionFromImageJPEGContentType
{
    XCTAssertEqualObjects([MXTools fileExtensionFromContentType:@"image/jpeg"], @".jpeg");
}

#pragma mark - URL creation

- (void)testUrlGeneration
{
    NSString *base = @"https://www.domain.org";
    NSString *parameter = @"parameter_name=parameter_value";
    NSString *currentResult = base;
    NSString *url = [NSString stringWithFormat:@"%@?%@", base, parameter];
    while (url.length < [MXTools kMXUrlMaxLength]) {
        currentResult = [MXTools urlStringWithBase:currentResult queryParameters:@[parameter]];
        // if the url is shorter than kMXUrlMaxLength, the result shouldn't be truncated
        XCTAssertEqualObjects(url, currentResult);
        url = [NSString stringWithFormat:@"%@&%@", url, parameter];
    }
    
    // if the URL is longer than kMXUrlMaxLength, no more parameter should be added
    XCTAssertEqualObjects(currentResult, [MXTools urlStringWithBase:currentResult queryParameters:@[parameter]]);
    XCTAssertNotEqualObjects(url, [MXTools urlStringWithBase:currentResult queryParameters:@[parameter]]);
}

#pragma mark - Supported To-Device events

- (void)testSupportedToDeviceEvents
{
    MXEvent *event1 = [MXEvent modelFromJSON:@{
        @"type": @"m.room.encrypted",
        @"content": @{
            @"algorithm": kMXCryptoOlmAlgorithm
        }
    }];
    XCTAssertTrue([MXTools isSupportedToDeviceEvent:event1]);
    
    MXEvent *event2 = [MXEvent modelFromJSON:@{
        @"type": @"m.room.message",
    }];
    XCTAssertTrue([MXTools isSupportedToDeviceEvent:event2]);
    
    MXEvent *event3 = [MXEvent modelFromJSON:@{
        @"type": @"random",
    }];
    XCTAssertTrue([MXTools isSupportedToDeviceEvent:event3]);
}

- (void)testUnsupportedToDeviceEvents
{
    MXEvent *event1 = [MXEvent modelFromJSON:@{
        @"type": @"m.room.encrypted",
        @"content": @{
            @"algorithm": kMXCryptoMegolmAlgorithm
        }
    }];
    XCTAssertFalse([MXTools isSupportedToDeviceEvent:event1]);
    
    MXEvent *event2 = [MXEvent modelFromJSON:@{
        @"type": @"m.room_key",
    }];
    XCTAssertFalse([MXTools isSupportedToDeviceEvent:event2]);
    
    MXEvent *event3 = [MXEvent modelFromJSON:@{
        @"type": @"m.forwarded_room_key",
    }];
    XCTAssertFalse([MXTools isSupportedToDeviceEvent:event3]);
    
    MXEvent *event4 = [MXEvent modelFromJSON:@{
        @"type": @"m.secret.send",
    }];
    XCTAssertFalse([MXTools isSupportedToDeviceEvent:event4]);
}


@end
