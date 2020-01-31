/*
 * Copyright 2019 New Vector Ltd
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXCrypto_Private.h"
#import "MXDeviceVerificationManager_Private.h"
#import "MXFileStore.h"

#import "MXKeyVerificationRequestJSONModel.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXDeviceVerificationManager (Testing)

- (MXDeviceVerificationTransaction*)transactionWithTransactionId:(NSString*)transactionId;

@end

@interface MXCryptoDeviceVerificationTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

    NSMutableArray<id> *observers;
}
@end

@implementation MXCryptoDeviceVerificationTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];

    observers = [NSMutableArray array];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;

    for (id observer in observers)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }

    [super tearDown];
}

- (void)observeSASIncomingTransactionInSession:(MXSession*)session block:(void (^)(MXIncomingSASTransaction * _Nullable transaction))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXDeviceVerificationManagerNewTransactionNotification object:session.crypto.deviceVerificationManager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

        MXDeviceVerificationTransaction *transaction = notif.userInfo[MXDeviceVerificationManagerNotificationTransactionKey];
        if (transaction.isIncoming && [transaction isKindOfClass:MXIncomingSASTransaction.class])
        {
            block((MXIncomingSASTransaction*)transaction);
        }
        else
        {
            XCTFail(@"We support only SAS. transaction: %@", transaction);
        }
    }];

    [observers addObject:observer];
}

- (void)observeTransactionUpdate:(MXDeviceVerificationTransaction*)transaction block:(void (^)(void))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXDeviceVerificationTransactionDidChangeNotification object:transaction queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
            block();
    }];

    [observers addObject:observer];
}

- (void)observeKeyVerificationRequestInSession:(MXSession*)session block:(void (^)(MXKeyVerificationRequest * _Nullable request))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXDeviceVerificationManagerNewRequestNotification object:session.crypto.deviceVerificationManager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

        MXKeyVerificationRequest *request = notif.userInfo[MXDeviceVerificationManagerNotificationRequestKey];
        if ([request isKindOfClass:MXKeyVerificationRequest.class])
        {
            block((MXKeyVerificationRequest*)request);
        }
        else
        {
            XCTFail(@"We support only SAS. transaction: %@", request);
        }
    }];

    [observers addObject:observer];
}



/**
 Nomical case: The full flow:

 - Alice and Bob are in a room
 - Alice begins SAS verification of Bob's device
 - Bob accepts it
 -> 1. Transaction on Bob side must be WaitForPartnerKey (Alice is WaitForPartnerToAccept)
 -> 2. Transaction on Alice side must then move to WaitForPartnerKey
 -> 3. Transaction on Bob side must then move to ShowSAS
 -> 4. Transaction on Alice side must then move to ShowSAS
 -> 5. SASs must be the same
 -  Alice confirms SAS
 -> 6. Transaction on Alice side must then move to WaitForPartnerToConfirm
 -  Bob confirms SAS
 -> 7. Transaction on Bob side must then move to Verified
 -> 7. Transaction on Alice side must then move to Verified
 -> Devices must be really verified
 -> Transaction must not be listed anymore
 */
- (void)testFullFlowWithAliceAndBob
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXCredentials *alice = aliceSession.matrixRestClient.credentials;
        MXCredentials *bob = bobSession.matrixRestClient.credentials;

        // - Alice begins SAS verification of Bob's device
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:bob.userId andDeviceId:bob.deviceId method:MXKeyVerificationMethodSAS success:^(MXDeviceVerificationTransaction * _Nonnull transactionFromAlicePOV) {

            MXOutgoingSASTransaction *sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;

            [self observeSASIncomingTransactionInSession:bobSession block:^(MXIncomingSASTransaction * _Nullable transactionFromBobPOV) {

                // Final checks
                void (^checkBothDeviceVerified)(void) = ^ void ()
                {
                    if (sasTransactionFromAlicePOV.state == MXSASTransactionStateVerified
                        && transactionFromBobPOV.state == MXSASTransactionStateVerified)
                    {
                        // -> Devices must be really verified
                        MXDeviceInfo *bobDeviceFromAlicePOV = [aliceSession.crypto.store deviceWithDeviceId:bob.deviceId forUser:bob.userId];
                        MXDeviceInfo *aliceDeviceFromBobPOV = [bobSession.crypto.store deviceWithDeviceId:alice.deviceId forUser:alice.userId];

                        XCTAssertEqual(bobDeviceFromAlicePOV.trustLevel.localVerificationStatus, MXDeviceVerified);
                        XCTAssertEqual(aliceDeviceFromBobPOV.trustLevel.localVerificationStatus, MXDeviceVerified);

                        // -> Transaction must not be listed anymore
                        XCTAssertNil([aliceSession.crypto.deviceVerificationManager transactionWithTransactionId:transactionFromAlicePOV.transactionId]);
                        XCTAssertNil([bobSession.crypto.deviceVerificationManager transactionWithTransactionId:transactionFromBobPOV.transactionId]);

                        [expectation fulfill];
                    }
                };

                // - Bob accepts it
                [transactionFromBobPOV accept];

                // -> Transaction on Alice side must be WaitForPartnerKey, then ShowSAS
                [self observeTransactionUpdate:sasTransactionFromAlicePOV block:^{

                    switch (sasTransactionFromAlicePOV.state)
                    {
                        // -> 2. Transaction on Alice side must then move to WaitForPartnerKey
                        case MXSASTransactionStateWaitForPartnerKey:
                            XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateWaitForPartnerKey);
                            break;
                        // -> 4. Transaction on Alice side must then move to ShowSAS
                        case MXSASTransactionStateShowSAS:
                            XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateShowSAS);

                            // -> 5. SASs must be the same
                            XCTAssertEqualObjects(sasTransactionFromAlicePOV.sasBytes, transactionFromBobPOV.sasBytes);
                            XCTAssertEqualObjects(sasTransactionFromAlicePOV.sasDecimal, transactionFromBobPOV.sasDecimal);
                            XCTAssertEqualObjects(sasTransactionFromAlicePOV.sasEmoji, transactionFromBobPOV.sasEmoji);

                            // -  Alice confirms SAS
                            [sasTransactionFromAlicePOV confirmSASMatch];
                            break;
                        // -> 6. Transaction on Alice side must then move to WaitForPartnerToConfirm
                        case MXSASTransactionStateWaitForPartnerToConfirm:
                            // -  Bob confirms SAS
                            [transactionFromBobPOV confirmSASMatch];
                            break;
                        // -> 7. Transaction on Alice side must then move to Verified
                        case MXSASTransactionStateVerified:
                            checkBothDeviceVerified();
                            break;
                        default:
                            XCTAssert(NO, @"Unexpected Alice transation state: %@", @(sasTransactionFromAlicePOV.state));
                            break;
                    }
                }];

                // -> Transaction on Bob side must be WaitForPartnerKey, then ShowSAS
                [self observeTransactionUpdate:transactionFromBobPOV block:^{

                    switch (transactionFromBobPOV.state)
                    {
                        // -> 1. Transaction on Bob side must be WaitForPartnerKey (Alice is WaitForPartnerToAccept)
                        case MXSASTransactionStateWaitForPartnerKey:
                            XCTAssertEqual(sasTransactionFromAlicePOV.state, MXSASTransactionStateOutgoingWaitForPartnerToAccept);
                            break;
                        // -> 3. Transaction on Bob side must then move to ShowSAS
                        case MXSASTransactionStateShowSAS:
                            break;
                        case MXSASTransactionStateWaitForPartnerToConfirm:
                            break;
                        // 7. Transaction on Bob side must then move to Verified
                        case MXSASTransactionStateVerified:
                            checkBothDeviceVerified();
                            break;
                        default:
                            XCTAssert(NO, @"Unexpected Bob transation state: %@", @(sasTransactionFromAlicePOV.state));
                            break;
                    }
                }];
            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Alice begins SAS verification of a non-existing device
 -> The request should fail
 */
- (void)testAliceDoingVerificationOnANonExistingDevice
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Alice begins SAS verification of a non-existing device
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:@"@bob:foo.bar" andDeviceId:@"DEVICEID" method:MXKeyVerificationMethodSAS success:^(MXDeviceVerificationTransaction * _Nonnull transaction) {

            // -> The request should fail
            XCTFail(@"The request should fail");
            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {
            [expectation fulfill];
        }];
    }];
}

/**
 - Alice begins SAS verification of a device she has never talked too
 -> The request should succeed
 -> Transaction must exist in both side
 */
- (void)testAliceDoingVerificationOnANotYetKnownDevice
{
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        MXCredentials *bob = bobSession.matrixRestClient.credentials;

        // - Alice begins SAS verification of a device she has never talked too
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:bob.userId andDeviceId:bob.deviceId method:MXKeyVerificationMethodSAS success:^(MXDeviceVerificationTransaction * _Nonnull transactionFromAlicePOV) {

            // -> The request should succeed
            MXOutgoingSASTransaction *sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;

            [self observeSASIncomingTransactionInSession:bobSession block:^(MXIncomingSASTransaction * _Nullable transactionFromBobPOV) {

                // -> Transaction must exist in both side
                XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateIncomingShowAccept);
                XCTAssertEqual(sasTransactionFromAlicePOV.state, MXSASTransactionStateOutgoingWaitForPartnerToAccept);

                [expectation fulfill];
            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Alice and Bob are in a room
 - Alice begins SAS verification of Bob's device
 -> Alice must see the transaction as a MXOutgoingSASTransaction
 -> In the WaitForPartnerToAccept state
 -> Bob must receive an incoming transaction notification
 -> Transaction ids must be the same
 -> The transaction must be in ShowAccept state
 - Alice cancels the transaction
 -> Bob must be notified by the cancellation
 -> Transaction on Alice side must then move to CancelledByMe
 */
- (void)testAliceStartThenAliceCancel
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Alice begins SAS verification of Bob's device
        MXCredentials *bob = bobSession.matrixRestClient.credentials;
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:bob.userId andDeviceId:bob.deviceId method:MXKeyVerificationMethodSAS success:^(MXDeviceVerificationTransaction * _Nonnull transactionFromAlicePOV) {

            // -> Alice must see the transaction as a MXOutgoingSASTransaction
            XCTAssert(transactionFromAlicePOV);
            XCTAssertTrue([transactionFromAlicePOV isKindOfClass:MXOutgoingSASTransaction.class]);
            MXOutgoingSASTransaction *sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;

            // -> In the WaitForPartnerToAccept state
            XCTAssertEqual(sasTransactionFromAlicePOV.state, MXSASTransactionStateOutgoingWaitForPartnerToAccept);


            //  -> Bob must receive an incoming transaction notification
            [self observeSASIncomingTransactionInSession:bobSession block:^(MXIncomingSASTransaction * _Nullable transactionFromBobPOV) {

                // -> Transaction ids must be the same
                XCTAssertEqualObjects(transactionFromBobPOV.transactionId, transactionFromAlicePOV.transactionId);

                // -> The transaction must be in ShowAccept state
                XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateIncomingShowAccept);

                // - Alice cancels the transaction
                [sasTransactionFromAlicePOV cancelWithCancelCode:MXTransactionCancelCode.user];

                // -> Bob must be notified by the cancellation
                [self observeTransactionUpdate:transactionFromBobPOV block:^{

                    XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateCancelled);

                    XCTAssertNotNil(transactionFromBobPOV.reasonCancelCode);
                    XCTAssertEqualObjects(transactionFromBobPOV.reasonCancelCode.value, MXTransactionCancelCode.user.value);

                    // -> Transaction on Alice side must then move to CancelledByMe
                    XCTAssertEqual(sasTransactionFromAlicePOV.state, MXSASTransactionStateCancelledByMe);
                    XCTAssertEqualObjects(sasTransactionFromAlicePOV.reasonCancelCode.value, MXTransactionCancelCode.user.value);

                    [expectation fulfill];
                }];

            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


/**
 - Alice and Bob are in a room
 - Alice begins SAS verification of Bob's device
 - Bob cancels the incoming transaction
 -> Alice must be notified by the cancellation
 -> Transaction on Bob side must then move to CancelledByMe
 */
- (void)testAliceStartThenBobCancel
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Alice begins SAS verification of Bob's device
        MXCredentials *bob = bobSession.matrixRestClient.credentials;
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:bob.userId andDeviceId:bob.deviceId method:MXKeyVerificationMethodSAS success:^(MXDeviceVerificationTransaction * _Nonnull transactionFromAlicePOV) {

            MXOutgoingSASTransaction *sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;

            [self observeSASIncomingTransactionInSession:bobSession block:^(MXIncomingSASTransaction * _Nullable transactionFromBobPOV) {

                // - Bob cancels the transaction
                [transactionFromBobPOV cancelWithCancelCode:MXTransactionCancelCode.user];

                // -> Alice must be notified by the cancellation
                [self observeTransactionUpdate:sasTransactionFromAlicePOV block:^{

                    XCTAssertEqual(sasTransactionFromAlicePOV.state, MXSASTransactionStateCancelled);

                    XCTAssertNotNil(sasTransactionFromAlicePOV.reasonCancelCode);
                    XCTAssertEqualObjects(sasTransactionFromAlicePOV.reasonCancelCode.value, MXTransactionCancelCode.user.value);

                    // -> Transaction on Bob side must then move to CancelledByMe
                    XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateCancelledByMe);
                    XCTAssertEqualObjects(transactionFromBobPOV.reasonCancelCode.value, MXTransactionCancelCode.user.value);

                    [expectation fulfill];
                }];
            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Alice and Bob are in a room
 - Alice begins SAS verification of Bob's device
 - Alice starts another SAS verification of Bob's device
 -> Alice must see all her requests cancelled
 */
- (void)testAliceStartTwoVerificationsAtSameTime
{
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        MXCredentials *bob = bobSession.matrixRestClient.credentials;

        // - Alice begins SAS verification of Bob's device
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:bob.userId andDeviceId:bob.deviceId method:MXKeyVerificationMethodSAS success:^(MXDeviceVerificationTransaction * _Nonnull transactionFromAlicePOV) {

            MXOutgoingSASTransaction *sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;

            // - Alice must see all her requests cancelled
            [self observeTransactionUpdate:sasTransactionFromAlicePOV block:^{

                XCTAssertEqual(sasTransactionFromAlicePOV.state, MXSASTransactionStateCancelled);

                [expectation fulfill];
            }];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

        // - Alice starts another SAS verification of Bob's device
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:bob.userId andDeviceId:bob.deviceId method:MXKeyVerificationMethodSAS success:^(MXDeviceVerificationTransaction * _Nonnull transaction2FromAlicePOV) {

            MXOutgoingSASTransaction *sasTransaction2FromAlicePOV = (MXOutgoingSASTransaction*)transaction2FromAlicePOV;

            // -> Alice must see all her requests cancelled
            [self observeTransactionUpdate:sasTransaction2FromAlicePOV block:^{

                XCTAssertEqual(sasTransaction2FromAlicePOV.state, MXSASTransactionStateCancelled);

                [expectation fulfill];
            }];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];


        // - Alice starts another SAS verification of Bob's device
        [self observeSASIncomingTransactionInSession:bobSession block:^(MXIncomingSASTransaction * _Nullable transactionFromBobPOV) {

            // -> Alice must see all her requests cancelled
            [self observeTransactionUpdate:transactionFromBobPOV block:^{

                XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateCancelledByMe);

                [expectation fulfill];
            }];
        }];
    }];
}


#pragma mark - Verification by DM requests -
/**
 Test new requests

 - Alice and Bob are in a room
 - Bob requests a verification of Alice in this Room
 -> Alice gets the requests notification
 -> They both have it in their pending requests
 */
- (void)testVerificationByDMRequests
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *fallbackText = @"fallbackText";
        __block NSString *requestId;

        MXCredentials *alice = aliceSession.matrixRestClient.credentials;
        MXCredentials *bob = bobSession.matrixRestClient.credentials;

        // - Bob requests a verification of Alice in this Room
        [bobSession.crypto.deviceVerificationManager requestVerificationByDMWithUserId:alice.userId
                                                                                roomId:roomId
                                                                          fallbackText:fallbackText
                                                                               methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                               success:^(MXKeyVerificationRequest *request)
         {
             requestId = request.requestId;
         }
                                                                               failure:^(NSError * _Nonnull error)
         {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];


        // -> Alice gets the requests notification
        [self observeKeyVerificationRequestInSession:aliceSession block:^(MXKeyVerificationRequest * _Nullable request) {
            XCTAssertEqualObjects(request.requestId, requestId);
            XCTAssertFalse(request.isFromMyUser);

            MXKeyVerificationRequest *requestFromAlicePOV = aliceSession.crypto.deviceVerificationManager.pendingRequests.firstObject;
            MXKeyVerificationRequest *requestFromBobPOV = bobSession.crypto.deviceVerificationManager.pendingRequests.firstObject;

            XCTAssertNotNil(requestFromAlicePOV);
            XCTAssertNotNil(requestFromBobPOV);


            [expectation fulfill];
        }];
    }];
}


#pragma mark - Verification by DM -

/**
 Nomical case: The full flow
 It reuses code from testFullFlowWithAliceAndBob.

 - Alice and Bob are in a room
 - Bob requests a verification of Alice in this Room
 - Alice gets the request in the timeline
 - Alice accepts it and begins a SAS verification
 -> 1. Transaction on Bob side must be WaitForPartnerKey (Alice is WaitForPartnerToAccept)
 -> 2. Transaction on Alice side must then move to WaitForPartnerKey
 -> 3. Transaction on Bob side must then move to ShowSAS
 -> 4. Transaction on Alice side must then move to ShowSAS
 -> 5. SASs must be the same
 -  Alice confirms SAS
 -> 6. Transaction on Alice side must then move to WaitForPartnerToConfirm
 -  Bob confirms SAS
 -> 7. Transaction on Bob side must then move to Verified
 -> 7. Transaction on Alice side must then move to Verified
 -> Devices must be really verified
 -> Transaction must not be listed anymore
 -> Both ends must get a done message
 - Then, test MXKeyVerification
 */
- (void)testVerificationByDMFullFlow
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:YES aliceStore:[[MXMemoryStore alloc] init] bobStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *fallbackText = @"fallbackText";
        __block NSString *requestId;

        MXCredentials *alice = aliceSession.matrixRestClient.credentials;
        MXCredentials *bob = bobSession.matrixRestClient.credentials;

        // - Bob requests a verification of Alice in this Room
        [bobSession.crypto.deviceVerificationManager requestVerificationByDMWithUserId:alice.userId
                                                                                roomId:roomId
                                                                          fallbackText:fallbackText
                                                                               methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                               success:^(MXKeyVerificationRequest *request)
         {
             requestId = request.requestId;
         }
                                                                               failure:^(NSError * _Nonnull error)
         {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];


        __block MXOutgoingSASTransaction *sasTransactionFromAlicePOV;


        // Alice gets the request in the timeline
        [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                  onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject)
         {
             if ([event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
             {
                 XCTAssertEqualObjects(event.eventId, requestId);

                 // Check verification by DM request format
                 MXKeyVerificationRequestJSONModel *requestJSON;
                 MXJSONModelSetMXJSONModel(requestJSON, MXKeyVerificationRequestJSONModel.class, event.content);
                 XCTAssertNotNil(requestJSON);

                 // - Alice accepts it and begins a SAS verification

                 // Wait a bit
                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                     // - Alice rejects the incoming request
                     MXKeyVerificationRequest *requestFromAlicePOV = aliceSession.crypto.deviceVerificationManager.pendingRequests.firstObject;
                     XCTAssertNotNil(requestFromAlicePOV);

                     [requestFromAlicePOV acceptWithMethod:MXKeyVerificationMethodSAS success:^(MXDeviceVerificationTransaction * _Nonnull transactionFromAlicePOV) {

                         XCTAssertEqualObjects(transactionFromAlicePOV.transactionId, event.eventId);

                         XCTAssert(transactionFromAlicePOV);
                         XCTAssertTrue([transactionFromAlicePOV isKindOfClass:MXOutgoingSASTransaction.class]);
                         sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;

                     } failure:^(NSError * _Nonnull error) {
                         XCTFail(@"The request should not fail - NSError: %@", error);
                         [expectation fulfill];
                     }];
                 });
             }
         }];


        [self observeSASIncomingTransactionInSession:bobSession block:^(MXIncomingSASTransaction * _Nullable transactionFromBobPOV) {

            // Final checks
            void (^checkBothDeviceVerified)(void) = ^ void ()
            {
                if (sasTransactionFromAlicePOV.state == MXSASTransactionStateVerified
                    && transactionFromBobPOV.state == MXSASTransactionStateVerified)
                {
                    // -> Devices must be really verified
                    MXDeviceInfo *bobDeviceFromAlicePOV = [aliceSession.crypto.store deviceWithDeviceId:bob.deviceId forUser:bob.userId];
                    MXDeviceInfo *aliceDeviceFromBobPOV = [bobSession.crypto.store deviceWithDeviceId:alice.deviceId forUser:alice.userId];

                    XCTAssertEqual(bobDeviceFromAlicePOV.trustLevel.localVerificationStatus, MXDeviceVerified);
                    XCTAssertEqual(aliceDeviceFromBobPOV.trustLevel.localVerificationStatus, MXDeviceVerified);

                    // -> Transaction must not be listed anymore
                    XCTAssertNil([aliceSession.crypto.deviceVerificationManager transactionWithTransactionId:sasTransactionFromAlicePOV.transactionId]);
                    XCTAssertNil([bobSession.crypto.deviceVerificationManager transactionWithTransactionId:transactionFromBobPOV.transactionId]);
                }
            };

            // -> Transaction on Alice side must be WaitForPartnerKey, then ShowSAS
            [self observeTransactionUpdate:sasTransactionFromAlicePOV block:^{

                switch (sasTransactionFromAlicePOV.state)
                {
                        // -> 2. Transaction on Alice side must then move to WaitForPartnerKey
                    case MXSASTransactionStateWaitForPartnerKey:
                        XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateWaitForPartnerKey);
                        break;
                        // -> 4. Transaction on Alice side must then move to ShowSAS
                    case MXSASTransactionStateShowSAS:
                        XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateShowSAS);

                        // -> 5. SASs must be the same
                        XCTAssertEqualObjects(sasTransactionFromAlicePOV.sasBytes, transactionFromBobPOV.sasBytes);
                        XCTAssertEqualObjects(sasTransactionFromAlicePOV.sasDecimal, transactionFromBobPOV.sasDecimal);
                        XCTAssertEqualObjects(sasTransactionFromAlicePOV.sasEmoji, transactionFromBobPOV.sasEmoji);

                        // -  Alice confirms SAS
                        [sasTransactionFromAlicePOV confirmSASMatch];
                        break;
                        // -> 6. Transaction on Alice side must then move to WaitForPartnerToConfirm
                    case MXSASTransactionStateWaitForPartnerToConfirm:
                        // -  Bob confirms SAS
                        [transactionFromBobPOV confirmSASMatch];
                        break;
                        // -> 7. Transaction on Alice side must then move to Verified
                    case MXSASTransactionStateVerified:
                        checkBothDeviceVerified();
                        break;
                    default:
                        XCTAssert(NO, @"Unexpected Alice transation state: %@", @(sasTransactionFromAlicePOV.state));
                        break;
                }
            }];

            // -> Transaction on Bob side must be WaitForPartnerKey, then ShowSAS
            [self observeTransactionUpdate:transactionFromBobPOV block:^{

                switch (transactionFromBobPOV.state)
                {
                        // -> 1. Transaction on Bob side must be WaitForPartnerKey (Alice is WaitForPartnerToAccept)
                    case MXSASTransactionStateWaitForPartnerKey:
                        XCTAssertEqual(sasTransactionFromAlicePOV.state, MXSASTransactionStateOutgoingWaitForPartnerToAccept);
                        break;
                        // -> 3. Transaction on Bob side must then move to ShowSAS
                    case MXSASTransactionStateShowSAS:
                        break;
                    case MXSASTransactionStateWaitForPartnerToConfirm:
                        break;
                        // 7. Transaction on Bob side must then move to Verified
                    case MXSASTransactionStateVerified:
                        checkBothDeviceVerified();
                        break;
                    default:
                        XCTAssert(NO, @"Unexpected Bob transation state: %@", @(sasTransactionFromAlicePOV.state));
                        break;
                }
            }];
        }];

        // -> Both ends must get a done message
        NSMutableArray<MXKeyVerificationDone*> *doneDone = [NSMutableArray new];
        void (^checkDoneDone)(MXEvent *event, MXTimelineDirection direction, id customObject) = ^ void (MXEvent *event, MXTimelineDirection direction, id customObject)
        {
            XCTAssertEqual(event.eventType, MXEventTypeKeyVerificationDone);

            // Check done format
            MXKeyVerificationDone *done;
            MXJSONModelSetMXJSONModel(done, MXKeyVerificationDone.class, event.content);
            XCTAssertNotNil(done);

            [doneDone addObject:done];
            if (doneDone.count == 2)
            {
                // Then, test MXKeyVerification
                MXEvent *event = [aliceSession.store eventWithEventId:requestId inRoom:roomId];
                [aliceSession.crypto.deviceVerificationManager keyVerificationFromKeyVerificationEvent:event success:^(MXKeyVerification * _Nonnull verificationFromAlicePOV) {

                    XCTAssertEqual(verificationFromAlicePOV.state, MXKeyVerificationStateVerified);

                    [expectation fulfill];
                } failure:^(NSError * _Nonnull error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }
        };

        [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringKeyVerificationDone]
                                    onEvent:checkDoneDone];
        [bobSession listenToEventsOfTypes:@[kMXEventTypeStringKeyVerificationDone]
                                    onEvent:checkDoneDone];
    }];
}


/**
 Nomical case: The full flow
 It reuses code from testFullFlowWithAliceAndBob.

 - Alice and Bob are in a room
 - Bob requests a verification of Alice in this Room
 - Alice gets the request in the timeline
 - Alice rejects the incoming request
 -> Both ends must see a cancel message
 - Then, test MXKeyVerification
 */
- (void)testVerificationByDMCancelledByAlice
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *fallbackText = @"fallbackText";
        __block NSString *requestId;

        MXCredentials *alice = aliceSession.matrixRestClient.credentials;

        // - Bob requests a verification of Alice in this Room
        [bobSession.crypto.deviceVerificationManager requestVerificationByDMWithUserId:alice.userId
                                                                                roomId:roomId
                                                                          fallbackText:fallbackText
                                                                               methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                               success:^(MXKeyVerificationRequest *request)
         {
             requestId = request.requestId;
         }
                                                                               failure:^(NSError * _Nonnull error)
         {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];

        // Alice gets the request in the timeline
        [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                    onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject)
         {
             if ([event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
             {
                 MXKeyVerificationRequestJSONModel *requestJSON;
                 MXJSONModelSetMXJSONModel(requestJSON, MXKeyVerificationRequestJSONModel.class, event.content);
                 XCTAssertNotNil(requestJSON);

                 // Wait a bit
                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                     // - Alice rejects the incoming request
                     MXKeyVerificationRequest *requestFromAlicePOV = aliceSession.crypto.deviceVerificationManager.pendingRequests.firstObject;
                     XCTAssertNotNil(requestFromAlicePOV);

                     [requestFromAlicePOV cancelWithCancelCode:MXTransactionCancelCode.user success:^{
                     } failure:^(NSError * _Nonnull error) {
                     }];
                 });
             }
         }];

        // -> Both ends must see a cancel message
        NSMutableArray<MXKeyVerificationCancel*> *cancelCancel = [NSMutableArray new];
        void (^checkCancelCancel)(MXEvent *event, MXTimelineDirection direction, id customObject) = ^ void (MXEvent *event, MXTimelineDirection direction, id customObject)
        {
            XCTAssertEqual(event.eventType, MXEventTypeKeyVerificationCancel);

            // Check cancel format
            MXKeyVerificationCancel *cancel;
            MXJSONModelSetMXJSONModel(cancel, MXKeyVerificationCancel.class, event.content);
            XCTAssertNotNil(cancel);

            [cancelCancel addObject:cancel];
            if (cancelCancel.count == 2)
            {
                // Then, test MXKeyVerification
                [aliceSession.crypto.deviceVerificationManager keyVerificationFromKeyVerificationEvent:event success:^(MXKeyVerification * _Nonnull verificationFromAlicePOV) {

                    XCTAssertEqual(verificationFromAlicePOV.state, MXKeyVerificationStateRequestCancelledByMe);

                    [expectation fulfill];
                } failure:^(NSError * _Nonnull error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }
        };

        [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringKeyVerificationCancel]
                                    onEvent:checkCancelCancel];
        [bobSession listenToEventsOfTypes:@[kMXEventTypeStringKeyVerificationCancel]
                                  onEvent:checkCancelCancel];

    }];
}

/**
 Test new requests without indicating a room to use
 
 - Alice and Bob are in a room
 - Make sure this room is direct
 - Bob requests a verification of Alice without indicating a room to use
 -> Alice gets the requests notification
 -> They both have it in their pending requests
 */
- (void)testVerificationWithRoomDetection
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *fallbackText = @"fallbackText";
        __block NSString *requestId;
        
        MXCredentials *alice = aliceSession.matrixRestClient.credentials;
        
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        [roomFromBobPOV setIsDirect:YES withUserId:alice.userId success:^{
            
            // - Bob requests a verification of Alice without indicating a room to use
            [bobSession.crypto.deviceVerificationManager requestVerificationByDMWithUserId:alice.userId
                                                                                    roomId:nil
                                                                              fallbackText:fallbackText
                                                                                   methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                                   success:^(MXKeyVerificationRequest *request)
             {
                 requestId = request.requestId;
             } failure:^(NSError * _Nonnull error) {
                 XCTFail(@"The request should not fail - NSError: %@", error);
                 [expectation fulfill];
             }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
        // -> Alice gets the requests notification
        [self observeKeyVerificationRequestInSession:aliceSession block:^(MXKeyVerificationRequest * _Nullable request) {
            XCTAssertEqualObjects(request.requestId, requestId);
            XCTAssertFalse(request.isFromMyUser);
            
            MXKeyVerificationRequest *requestFromAlicePOV = aliceSession.crypto.deviceVerificationManager.pendingRequests.firstObject;
            MXKeyVerificationRequest *requestFromBobPOV = bobSession.crypto.deviceVerificationManager.pendingRequests.firstObject;
            
            XCTAssertNotNil(requestFromAlicePOV);
            XCTAssertNotNil(requestFromBobPOV);
            
            
            [expectation fulfill];
        }];
    }];
}

/**
 Test new requests without indicating a room to use
 
 - Alice and Bob are in a room
 - Bob requests a verification of Alice
 - Alice gets a room invite and join
 -> Alice gets the requests notification
 -> They both have it in their pending requests
 */
- (void)testVerificationWithNoRoom
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *aliceSession, MXSession *bobSession, XCTestExpectation *expectation) {
        
        NSString *fallbackText = @"fallbackText";
        __block NSString *requestId;
        
        MXCredentials *alice = aliceSession.matrixRestClient.credentials;
            
        // - Bob requests a verification of Alice without indicating a room to use
        [bobSession.crypto.deviceVerificationManager requestVerificationByDMWithUserId:alice.userId
                                                                                roomId:nil
                                                                          fallbackText:fallbackText
                                                                               methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                               success:^(MXKeyVerificationRequest *request)
         {
             requestId = request.requestId;
         } failure:^(NSError * _Nonnull error) {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];
        
         // - Alice gets a room invite and join
        __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:aliceSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            
            [aliceSession joinRoom:note.userInfo[kMXSessionNotificationRoomIdKey] viaServers:nil success:^(MXRoom *room) {
                XCTAssertTrue(room.summary.isEncrypted);
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
        
        // -> Alice gets the requests notification
        [self observeKeyVerificationRequestInSession:aliceSession block:^(MXKeyVerificationRequest * _Nullable request) {
        
            
            XCTAssertEqualObjects(request.requestId, requestId);
            XCTAssertFalse(request.isFromMyUser);
            
            MXKeyVerificationRequest *requestFromAlicePOV = aliceSession.crypto.deviceVerificationManager.pendingRequests.firstObject;
            MXKeyVerificationRequest *requestFromBobPOV = bobSession.crypto.deviceVerificationManager.pendingRequests.firstObject;
            
            XCTAssertNotNil(requestFromAlicePOV);
            XCTAssertNotNil(requestFromBobPOV);
            
            
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop
