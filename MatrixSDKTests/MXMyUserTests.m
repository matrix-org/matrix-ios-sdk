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
#import <XCTest/XCTest.h>

@interface MXMyUserTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}
@end

@implementation MXMyUserTests

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

- (void)testMXSessionMyUser
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        XCTAssertNotNil(mxSession.myUser);

        MXUser *myUser = [mxSession userWithUserId:mxSession.matrixRestClient.credentials.userId];
        XCTAssertEqual(mxSession.myUser, myUser);

        [expectation fulfill];
    }];
}

- (void)testSetDisplayName
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:mxSession];

        XCTAssertNil(mxSession.myUser, @"There should be no myUser while initialSync is not done");

        [mxSession start:^{

            // Listen to my profile changes
            [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {
                
                XCTAssertEqual(event.eventType, MXEventTypePresence);
                XCTAssert([mxSession.myUser.displayname isEqualToString:@"ALICE"], @"Wrong displayname. Found: %@", mxSession.myUser.displayname);

            }];

            // Update the profile
            [mxSession.myUser setDisplayName:@"ALICE" success:^{

                XCTAssert([mxSession.myUser.displayname isEqualToString:@"ALICE"], @"Wrong displayname. Found: %@", mxSession.myUser.displayname);
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testSetAvatarURL
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession start:^{

            // Listen to my profile changes
            [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {

                XCTAssertEqual(event.eventType, MXEventTypePresence);
                XCTAssert([mxSession.myUser.avatarUrl isEqualToString:@"mxc://matrix.org/rQkrOoaFIRgiACATXUdQIuNJ"], @"Wrong avatar. Found: %@", mxSession.myUser.avatarUrl);

            }];

            // Update the profile with a mxc URL (non mxc url are ignored)
            [mxSession.myUser setAvatarUrl:@"mxc://matrix.org/rQkrOoaFIRgiACATXUdQIuNJ" success:^{

                XCTAssert([mxSession.myUser.avatarUrl isEqualToString:@"mxc://matrix.org/rQkrOoaFIRgiACATXUdQIuNJ"], @"Wrong avatar. Found: %@", mxSession.myUser.avatarUrl);
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}


- (void)testSetPresence
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession start:^{

            // Listen to my profile changes
            [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {

                XCTAssertEqual(event.eventType, MXEventTypePresence);
                XCTAssertEqual(mxSession.myUser.presence, MXPresenceUnavailable);
                XCTAssert([mxSession.myUser.statusMsg isEqualToString:@"In Wonderland"], @"Wrong status message. Found: %@", mxSession.myUser.statusMsg);

            }];

            // Update the profile
            [mxSession.myUser setPresence:MXPresenceUnavailable andStatusMessage:@"In Wonderland" success:^{

                XCTAssertEqual(mxSession.myUser.presence, MXPresenceUnavailable);
                XCTAssert([mxSession.myUser.statusMsg isEqualToString:@"In Wonderland"], @"Wrong status message. Found: %@", mxSession.myUser.statusMsg);
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testIdenticon
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        MXUser *myUser = [mxSession userWithUserId:mxSession.matrixRestClient.credentials.userId];

        NSString *identiconURL = [mxSession.mediaManager urlOfIdenticon:myUser.userId];
        XCTAssert([identiconURL hasPrefix:@"http://localhost:8080/_matrix/media/v1/identicon/%40mxbob"]);

        [expectation fulfill];
    }];
}


@end
