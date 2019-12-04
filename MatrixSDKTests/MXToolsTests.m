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
    XCTAssertTrue([MXTools isMatrixEventIdentifier:@"$pmOSN/DognfuSfhdW/qivXT19lfCWpdSfaPFKDBTJUk+"]);

    XCTAssertTrue([MXTools isMatrixRoomIdentifier:@"!an1234Room:matrix.org"]);

    XCTAssertTrue([MXTools isMatrixRoomAlias:@"#matrix:matrix.org"]);

    XCTAssertTrue([MXTools isMatrixGroupIdentifier:@"+matrix:matrix.org"]);
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

@end
