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

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

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
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXDeviceVerificationManagerNewTransactionNotification object:session.crypto.deviceVerificationManager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

        MXDeviceVerificationTransaction *transaction = notif.userInfo[kMXDeviceVerificationManagerNotificationTransactionKey];
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
 -> 8. Transaction on Alice side must then move to Verified
 */
- (void)testAliceAndBobShowSAS
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Alice begins SAS verification of Bob's device
        MXCredentials *bob = bobSession.matrixRestClient.credentials;
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:bob.userId andDeviceId:bob.deviceId method:kMXKeyVerificationMethodSAS complete:^(MXDeviceVerificationTransaction * _Nullable transactionFromAlicePOV) {

            MXOutgoingSASTransaction *sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;

            [self observeSASIncomingTransactionInSession:bobSession block:^(MXIncomingSASTransaction * _Nullable transactionFromBobPOV) {

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
                        // -> 7. Transaction on Bob side must then move to Verified
                        case MXSASTransactionStateVerified:
                            XCTAssertEqual(transactionFromBobPOV.state, MXSASTransactionStateVerified);

                            [expectation fulfill];
                            break;
                        default:
                            XCTAssert(NO, @"Unexpected alice transation state: %@", @(sasTransactionFromAlicePOV.state));
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
                            // -> 8. Transaction on Alice side must then move to Verified
                        case MXSASTransactionStateVerified:
                            break;
                        default:
                            XCTAssert(NO, @"Unexpected alice transation state: %@", @(sasTransactionFromAlicePOV.state));
                            break;
                    }
                }];
            }];
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
 */
- (void)testAliceStartThenAliceCancel
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Alice begins SAS verification of Bob's device
        MXCredentials *bob = bobSession.matrixRestClient.credentials;
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:bob.userId andDeviceId:bob.deviceId method:kMXKeyVerificationMethodSAS complete:^(MXDeviceVerificationTransaction * _Nullable transactionFromAlicePOV) {

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

                    XCTAssertNotNil(transactionFromBobPOV.cancelCode);
                    XCTAssertEqualObjects(transactionFromBobPOV.cancelCode.value, MXTransactionCancelCode.user.value);
                    [expectation fulfill];
                }];

            }];
        }];
    }];
}


/**
 - Alice and Bob are in a room
 - Alice begins SAS verification of Bob's device
 - Bob cancels the incoming transaction
 -> Alice must be notified by the cancellation
 */
- (void)testAliceStartThenBobCancel
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Alice begins SAS verification of Bob's device
        MXCredentials *bob = bobSession.matrixRestClient.credentials;
        [aliceSession.crypto.deviceVerificationManager beginKeyVerificationWithUserId:bob.userId andDeviceId:bob.deviceId method:kMXKeyVerificationMethodSAS complete:^(MXDeviceVerificationTransaction * _Nullable transactionFromAlicePOV) {

            MXOutgoingSASTransaction *sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;

            [self observeSASIncomingTransactionInSession:bobSession block:^(MXIncomingSASTransaction * _Nullable transactionFromBobPOV) {

                // - Bob cancels the transaction
                [transactionFromBobPOV cancelWithCancelCode:MXTransactionCancelCode.user];

                // -> Alice must be notified by the cancellation
                [self observeTransactionUpdate:sasTransactionFromAlicePOV block:^{

                    XCTAssertEqual(sasTransactionFromAlicePOV.state, MXSASTransactionStateCancelled);

                    XCTAssertNotNil(sasTransactionFromAlicePOV.cancelCode);
                    XCTAssertEqualObjects(sasTransactionFromAlicePOV.cancelCode.value, MXTransactionCancelCode.user.value);
                    [expectation fulfill];
                }];
            }];
        }];
    }];
}


// TODO: more tests

@end
