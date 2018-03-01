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

#import "MXTools.h"

@interface MXToolsTests : XCTestCase

@end

@implementation MXToolsTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

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
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:matrix.org:8480"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:localhost"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:localhost:8480"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:127.0.0.1"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob:127.0.0.1:8480"]);
    XCTAssertFalse([MXTools isMatrixUserIdentifier:@"@bob:matrix+25.org"]);
    XCTAssertFalse([MXTools isMatrixUserIdentifier:@"@bob:matrix[].org"]);

    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@Bob:matrix.org"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@bob1234:matrix.org"]);
    XCTAssertTrue([MXTools isMatrixUserIdentifier:@"@+33012:matrix.org"]);

    XCTAssertTrue([MXTools isMatrixEventIdentifier:@"$123456EventId:matrix.org"]);

    XCTAssertTrue([MXTools isMatrixRoomIdentifier:@"!an1234Room:matrix.org"]);

    XCTAssertTrue([MXTools isMatrixRoomAlias:@"#matrix:matrix.org"]);

    XCTAssertTrue([MXTools isMatrixGroupIdentifier:@"+matrix:matrix.org"]);
}

@end
