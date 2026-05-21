/*
 Copyright 2017 Vector Creations Ltd

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

#import "MXSDKOptions.h"

#ifdef MX_CRYPTO

#import "MatrixSDKTestsData.h"

@class MXOutgoingRoomKeyRequest;

/**
 Class helper to create reusable initial conditions for e2e.
 */
@interface MatrixSDKTestsE2EData : NSObject

- (instancetype)initWithMatrixSDKTestsData:(MatrixSDKTestsData*)matrixSDKTestsData;

// Messages exchanged by Alice and Bob in doE2ETestWithAliceAndBobInARoomWithCryptedMessages
@property (readonly) NSArray<NSString*> *messagesFromAlice;
@property (readonly) NSArray<NSString*> *messagesFromBob;


#pragma mark - Scenarii
- (void)doE2ETestWithBobAndAlice:(XCTestCase*)testCase
                     readyToTest:(void (^)(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation))readyToTest;

- (void)doE2ETestWithAliceInARoom:(XCTestCase*)testCase
                      readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest;

- (void)doE2ETestWithAliceInARoom:(XCTestCase*)testCase andStore:(id<MXStore>)store
                      readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest;

- (void)doE2ETestWithAliceAndBobInARoom:(XCTestCase*)testCase
                             cryptedBob:(BOOL)cryptedBob
                    warnOnUnknowDevices:(BOOL)warnOnUnknowDevices
                            readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest;

- (void)doE2ETestWithAliceAndBobInARoom:(XCTestCase*)testCase
                             cryptedBob:(BOOL)cryptedBob
                    warnOnUnknowDevices:(BOOL)warnOnUnknowDevices
                             aliceStore:(id<MXStore>)aliceStore
                               bobStore:(id<MXStore>)bobStore
                            readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest;

- (void)doE2ETestWithAliceByInvitingBobInARoom:(XCTestCase*)testCase
                                    cryptedBob:(BOOL)cryptedBob
                           warnOnUnknowDevices:(BOOL)warnOnUnknowDevices
                                   readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest;

- (void)doE2ETestWithAliceByInvitingBobInARoom:(XCTestCase*)testCase
                                    cryptedBob:(BOOL)cryptedBob
                           warnOnUnknowDevices:(BOOL)warnOnUnknowDevices
                                    aliceStore:(id<MXStore>)aliceStore
                                      bobStore:(id<MXStore>)bobStore
                                   readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest;

- (void)doE2ETestWithAliceAndBobInARoomWithCryptedMessages:(XCTestCase*)testCase
                                                cryptedBob:(BOOL)cryptedBob
                                               readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest;

- (void)doE2ETestWithAliceAndBobAndSamInARoom:(XCTestCase*)testCase
                                   cryptedBob:(BOOL)cryptedBob
                                   cryptedSam:(BOOL)cryptedSam
                          warnOnUnknowDevices:(BOOL)warnOnUnknowDevices
                                  readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, MXSession *samSession, NSString *roomId, XCTestExpectation *expectation))readyToTest;

- (void)loginUserOnANewDevice:(XCTestCase*)testCase
                  credentials:(MXCredentials*)credentials
                 withPassword:(NSString*)password
                   onComplete:(void (^)(MXSession *newSession))onComplete;

- (void)loginUserOnANewDevice:(XCTestCase*)testCase
                  credentials:(MXCredentials*)credentials
                 withPassword:(NSString*)password
                        store:(id<MXStore>)store
                   onComplete:(void (^)(MXSession *newSession))onComplete;


#pragma mark - Cross-signing

// Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
// - Create Alice & Bob accounts
// - Bootstrap cross-signing x2
// - Make Alice2 aware of Bob
// - Make each Alice devices trust each other
// - Make Alice & Bob trust each other
- (void)doTestWithBobAndAliceWithTwoDevicesAllTrusted:(XCTestCase*)testCase
                                          readyToTest:(void (^)(MXSession *bobSession, MXSession *aliceSession1, MXSession *aliceSession2, NSString *roomId, XCTestExpectation *expectation))readyToTest;


#pragma mark - Tools

- (void)outgoingRoomKeyRequestInSession:(MXSession*)session complete:(void (^)(MXOutgoingRoomKeyRequest*))complete;

@end

#endif // MX_CRYPTO
