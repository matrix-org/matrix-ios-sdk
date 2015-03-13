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
#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

@interface MXMyUserTests : XCTestCase
{
    MXSession *mxSession;
}
@end

@implementation MXMyUserTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    if (mxSession)
    {
        [[MatrixSDKTestsData sharedData] closeMXSession:mxSession];
        mxSession = nil;
    }
    [super tearDown];
}

- (void)testMXSessionMyUser
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        mxSession = mxSession2;

        XCTAssertNotNil(mxSession.myUser);

        MXUser *myUser = [mxSession userWithUserId:mxSession.matrixRestClient.credentials.userId];
        XCTAssertEqual(mxSession.myUser, myUser);

        [expectation fulfill];
    }];
}

- (void)testSetDisplayName
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];

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
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
}

- (void)testSetAvatarURL
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];

        [mxSession start:^{

            // Listen to my profile changes
            [mxSession.myUser listenToUserUpdate:^(MXEvent *event) {

                XCTAssertEqual(event.eventType, MXEventTypePresence);
                XCTAssert([mxSession.myUser.avatarUrl isEqualToString:@"http://matrix.org/matrix2.png"], @"Wrong avatar. Found: %@", mxSession.myUser.avatarUrl);

            }];

            // Update the profile
            [mxSession.myUser setAvatarUrl:@"http://matrix.org/matrix2.png" success:^{

                XCTAssert([mxSession.myUser.avatarUrl isEqualToString:@"http://matrix.org/matrix2.png"], @"Wrong avatar. Found: %@", mxSession.myUser.avatarUrl);
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
        
    }];
}


- (void)testSetPresence
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];

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
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
        
    }];
}

- (void)testIdenticon
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        mxSession = mxSession2;

        MXUser *myUser = [mxSession userWithUserId:mxSession.matrixRestClient.credentials.userId];

        NSString *identiconURL = [mxSession.matrixRestClient urlOfIdenticon:myUser.userId];
        XCTAssertEqualObjects(identiconURL, @"http://localhost:8080/_matrix/media/v1/identicon/%40mxBob%3Alocalhost%3A8480");

        [expectation fulfill];
    }];
}


@end
