/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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
#import "MatrixSDKTestsE2EData.h"

#import "MXCrypto_Private.h"
#import "MXKeyVerificationManager_Private.h"
#import "MXFileStore.h"

#import "MXKeyVerificationRequestJSONModel.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXKeyVerificationManager (Testing)

- (MXKeyVerificationTransaction*)transactionWithTransactionId:(NSString*)transactionId;

@end

@interface MXCrossSigningVerificationTests : XCTestCase <MXCrossSigningKeysStorageDelegate>
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
    
    NSMutableArray<id> *observers;
    
    MXUsersDevicesMap<NSData*> *userPrivateKeys;
}
@end

@implementation MXCrossSigningVerificationTests

- (void)setUp
{
    [super setUp];
    
    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
    
    observers = [NSMutableArray array];
    userPrivateKeys = [MXUsersDevicesMap new];
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
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationManagerNewTransactionNotification object:session.crypto.keyVerificationManager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        
        MXKeyVerificationTransaction *transaction = notif.userInfo[MXKeyVerificationManagerNotificationTransactionKey];
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

- (void)observeTransactionUpdate:(MXKeyVerificationTransaction*)transaction block:(void (^)(void))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationTransactionDidChangeNotification object:transaction queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        block();
    }];
    
    [observers addObject:observer];
}

- (void)observeKeyVerificationRequestInSession:(MXSession*)session block:(void (^)(MXKeyVerificationRequest * _Nullable request))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationManagerNewRequestNotification object:session.crypto.keyVerificationManager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        
        MXKeyVerificationRequest *request = notif.userInfo[MXKeyVerificationManagerNotificationRequestKey];
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


#pragma mark - MXCrossSigningKeysStorageDelegate

- (void)getCrossSigningKey:(nonnull MXCrossSigning *)crossSigning
                    userId:(nonnull NSString*)userId
                  deviceId:(nonnull NSString*)deviceId
               withKeyType:(nonnull NSString *)keyType
         expectedPublicKey:(nonnull NSString *)expectedPublicKey
                   success:(nonnull void (^)(NSData * _Nonnull))success
                   failure:(nonnull void (^)(NSError * _Nonnull))failure
{
    NSData *privateKey = [userPrivateKeys objectForDevice:keyType forUser:userId];
    if (privateKey)
    {
        success(privateKey);
    }
    else
    {
        failure([NSError errorWithDomain:@"MXCrossSigningTests: Unknown keys" code:0 userInfo:nil]);
    }
}

- (void)saveCrossSigningKeys:(nonnull MXCrossSigning *)crossSigning
                      userId:(nonnull NSString*)userId
                    deviceId:(nonnull NSString*)deviceId
                 privateKeys:(nonnull NSDictionary<NSString *,NSData *> *)privateKeys
                     success:(nonnull void (^)(void))success
                     failure:(nonnull void (^)(NSError * _Nonnull))failure
{
    [userPrivateKeys setObjects:privateKeys forUser:userId];
    success();
}

- (void)bootstrapCrossSigningOnSession:(MXSession*)session
                              password:(NSString*)password
                              completion:(void (^)(void))completionBlock
{
    session.crypto.crossSigning.keysStorageDelegate = self;
    [session.crypto.crossSigning bootstrapWithPassword:password success:^{
        completionBlock();
    } failure:^(NSError *error) {
        XCTAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
    }];
}


#pragma mark - Verification by DM -

/**
 Nomical case: The full flow
 It reuses code from testVerificationByDMFullFlow from MXCryptoKeyVerificationTests.
 
 - Alice and Bob are in a room
 - Alice and Bob bootstrap cross-signing (This is the single difference with original testVerificationByDMFullFlow).
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
        
        // - Alice and Bob bootstrap cross-signing 
        [self bootstrapCrossSigningOnSession:aliceSession password:MXTESTS_ALICE_PWD completion:^{
            [self bootstrapCrossSigningOnSession:bobSession password:MXTESTS_BOB_PWD completion:^{
                
                NSString *fallbackText = @"fallbackText";
                __block NSString *requestId;
                
                MXCredentials *alice = aliceSession.matrixRestClient.credentials;
                MXCredentials *bob = bobSession.matrixRestClient.credentials;
                
                // - Bob requests a verification of Alice in this Room
                [bobSession.crypto.keyVerificationManager requestVerificationByDMWithUserId:alice.userId
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
                             MXKeyVerificationRequest *requestFromAlicePOV = aliceSession.crypto.keyVerificationManager.pendingRequests.firstObject;
                             XCTAssertNotNil(requestFromAlicePOV);
                             
                             [requestFromAlicePOV acceptWithMethods:@[MXKeyVerificationMethodSAS] success:^{
                                 
                                 [aliceSession.crypto.keyVerificationManager beginKeyVerificationFromRequest:requestFromAlicePOV method:MXKeyVerificationMethodSAS success:^(MXKeyVerificationTransaction * _Nonnull transactionFromAlicePOV) {

                                     XCTAssertEqualObjects(transactionFromAlicePOV.transactionId, event.eventId);
                                     
                                     XCTAssert(transactionFromAlicePOV);
                                     XCTAssertTrue([transactionFromAlicePOV isKindOfClass:MXOutgoingSASTransaction.class]);
                                     sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;
                                     
                                 } failure:^(NSError * _Nonnull error) {
                                     XCTFail(@"The request should not fail - NSError: %@", error);
                                     [expectation fulfill];
                                 }];
                                 
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
                            XCTAssertNil([aliceSession.crypto.keyVerificationManager transactionWithTransactionId:sasTransactionFromAlicePOV.transactionId]);
                            XCTAssertNil([bobSession.crypto.keyVerificationManager transactionWithTransactionId:transactionFromBobPOV.transactionId]);
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
                    if (doneDone.count == 4)
                    {
                        // Then, test MXKeyVerification
                        MXEvent *event = [aliceSession.store eventWithEventId:requestId inRoom:roomId];
                        [aliceSession.crypto.keyVerificationManager keyVerificationFromKeyVerificationEvent:event success:^(MXKeyVerification * _Nonnull verificationFromAlicePOV) {
                            
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
        }];
    }];
}

@end

#pragma clang diagnostic pop
