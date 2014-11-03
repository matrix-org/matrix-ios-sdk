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

#import <Foundation/Foundation.h>

#import <XCTest/XCTest.h>

#import "MXRestClient.h"

// The URL of your test home server
FOUNDATION_EXPORT NSString * const kMXTestsHomeServerURL;

@interface MatrixSDKTestsData : NSObject

+ (id)sharedData;

#pragma mark - mxBob
// Credentials for the user mxBob on the home server located at kMXTestsHomeServerURL
@property (nonatomic, readonly) MXCredentials *bobCredentials;

// Get credentials asynchronously
// The user will be created if needed
- (void)getBobCredentials:(void (^)())success;

// Prepare a test with a MXRestClient for mxBob so that we can make test on it
- (void)doMXRestClientTestWithBob:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXRestClient *bobRestClient, XCTestExpectation *expectation))readyToTest;

// Prepare a test with a a MXRestClient for mxBob so that we can make test on it
- (void)doMXRestClientTestWithBobAndARoom:(XCTestCase*)testCase
                           readyToTest:(void (^)(MXRestClient *bobRestClient, NSString* room_id, XCTestExpectation *expectation))readyToTest;

- (void)doMXRestClientTestWithBobAndThePublicRoom:(XCTestCase*)testCase
                           readyToTest:(void (^)(MXRestClient *bobRestClient, NSString* room_id, XCTestExpectation *expectation))readyToTest;

- (void)doMXRestClientTestInABobRoomAndANewTextMessage:(XCTestCase*)testCase
                                     newTextMessage:(NSString*)newTextMessage
                                      onReadyToTest:(void (^)(MXRestClient *bobRestClient, NSString* room_id, NSString* new_text_message_event_id, XCTestExpectation *expectation))readyToTest;

- (void)doMXRestClientTestWithBobAndARoomWithMessages:(XCTestCase*)testCase
                                       readyToTest:(void (^)(MXRestClient *bobRestClient, NSString* room_id, XCTestExpectation *expectation))readyToTest;

- (void)doMXRestClientTestWihBobAndSeveralRoomsAndMessages:(XCTestCase*)testCase
                                            readyToTest:(void (^)(MXRestClient *bobRestClient, XCTestExpectation *expectation))readyToTest;

#pragma mark - mxAlice
@property (nonatomic, readonly) MXCredentials *aliceCredentials;

- (void)getAliceCredentials:(void (^)())success;

- (void)doMXRestClientTestWithAlice:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXRestClient *aliceRestClient, XCTestExpectation *expectation))readyToTest;

//- (void)randomCredentials:(void (^)(MXCredentials *randomCredentials))success;

#pragma mark - both
- (void)doMXSessionTestWithBobAndAliceInARoom:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString* room_id, XCTestExpectation *expectation))readyToTest;


@end
