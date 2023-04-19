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

#import "MXKeyVerificationRequestByDMJSONModel.h"

#import "MXQRCodeTransaction_Private.h"
#import "MatrixSDKTestsSwiftHeader.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXLegacyKeyVerificationManager (Testing)

- (id<MXKeyVerificationTransaction>)transactionWithTransactionId:(NSString*)transactionId;
- (MXLegacyQRCodeTransaction*)qrCodeTransactionWithTransactionId:(NSString*)transactionId;

@end

@interface MXCrossSigningVerificationTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
    
    NSMutableArray<id> *observers;
}
@end

@implementation MXCrossSigningVerificationTests

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
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationManagerNewTransactionNotification object:session.crypto.keyVerificationManager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        
        id<MXKeyVerificationTransaction>transaction = notif.userInfo[MXKeyVerificationManagerNotificationTransactionKey];
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

- (void)observeNewQRCodeTransactionInSession:(MXSession*)session block:(void (^)(MXLegacyQRCodeTransaction * _Nullable transaction))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationManagerNewTransactionNotification object:session.crypto.keyVerificationManager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        
        id<MXKeyVerificationTransaction>transaction = notif.userInfo[MXKeyVerificationManagerNotificationTransactionKey];
        if ([transaction isKindOfClass:MXLegacyQRCodeTransaction.class])
        {
            block((MXLegacyQRCodeTransaction*)transaction);
        }
        else
        {
            XCTFail(@"We support only QR code. transaction: %@", transaction);
        }
    }];
    
    [observers addObject:observer];
}

- (void)observeTransactionUpdate:(id<MXKeyVerificationTransaction>)transaction block:(void (^)(void))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationTransactionDidChangeNotification object:transaction queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        block();
    }];
    
    [observers addObject:observer];
}

- (void)observeKeyVerificationRequestChangeWithBlock:(void (^)(id<MXKeyVerificationRequest> _Nullable request))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationRequestDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        
        id<MXKeyVerificationRequest>request = notif.object;
        
        if ([request conformsToProtocol:@protocol(MXKeyVerificationRequest)])
        {
            block((id<MXKeyVerificationRequest>)request);
        }
        else
        {
            XCTFail(@"We support only MXKeyVerificationRequest. request: %@", request);
        }
    }];
    
    [observers addObject:observer];
}

- (void)bootstrapCrossSigningOnSession:(MXSession*)session
                              password:(NSString*)password
                              completion:(void (^)(void))completionBlock
{
    [session.crypto.crossSigning setupWithPassword:password success:^{
        completionBlock();
    } failure:^(NSError *error) {
        XCTAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
    }];
}


- (void)observeKeyVerificationRequestInSession:(MXSession*)session block:(void (^)(id<MXKeyVerificationRequest> _Nullable request))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationManagerNewRequestNotification object:session.crypto.keyVerificationManager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        
        id<MXKeyVerificationRequest> request = notif.userInfo[MXKeyVerificationManagerNotificationRequestKey];
        if ([request conformsToProtocol:@protocol(MXKeyVerificationRequest)])
        {
            block((id<MXKeyVerificationRequest>)request);
        }
        else
        {
            XCTFail(@"We support only SAS. transaction: %@", request);
        }
    }];
    
    [observers addObject:observer];
}


#pragma mark - Self Verification (by to_device) -

// After verifying a signin with cross-signing enabled, check that cross-signing is up on both side.
// This is the exact same code as testVerificationByToDeviceSelfVerificationFullFlow but we cross-signing on.
// Check tests in checkBothVerified():
// -> Devices must be really verified
// -> My user must be really verified
- (void)testSelfVerificationWithSAS
{
    // - Have Alice
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:YES aliceStore:[[MXMemoryStore alloc] init] bobStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *aliceSession1, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Alice bootstrap cross-signing
        [self bootstrapCrossSigningOnSession:aliceSession1 password:MXTESTS_ALICE_PWD completion:^{
          
            // - Alice has a second sign-in
            [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                __block NSString *requestId;
                
                MXCredentials *alice = aliceSession1.matrixRestClient.credentials;
                MXCredentials *alice2 = aliceSession2.matrixRestClient.credentials;
                
                NSArray *methods = @[MXKeyVerificationMethodSAS, @"toto"];
                
                // - Bob requests a verification of Alice in this Room
                [aliceSession2.crypto.keyVerificationManager requestVerificationByToDeviceWithUserId:alice.userId
                                                                                        deviceIds:@[alice.deviceId]
                                                                                          methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                                          success:^(id<MXKeyVerificationRequest> requestFromBobPOV)
                 {
                     requestId = requestFromBobPOV.requestId;
                     
                     XCTAssertEqualObjects(requestFromBobPOV.otherUser, alice.userId);
                     XCTAssertNil(requestFromBobPOV.otherDevice);
                 }
                                                                                          failure:^(NSError * _Nonnull error)
                 {
                     XCTFail(@"The request should not fail - NSError: %@", error);
                     [expectation fulfill];
                 }];
                
                
                __block MXOutgoingSASTransaction *sasTransactionFromAlicePOV;
                
                // - Alice gets the requests notification
                [self observeKeyVerificationRequestInSession:aliceSession1 block:^(id<MXKeyVerificationRequest> _Nullable requestFromAlicePOV) {
                    XCTAssertEqualObjects(requestFromAlicePOV.requestId, requestId);
                    
                    // Wait a bit
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        
                        XCTAssertEqualObjects(requestFromAlicePOV.methods, methods);
                        XCTAssertEqualObjects(requestFromAlicePOV.otherMethods, methods);
                        XCTAssertNil(requestFromAlicePOV.myMethods);
                        
                        XCTAssertEqualObjects(requestFromAlicePOV.otherUser, alice2.userId);
                        XCTAssertEqualObjects(requestFromAlicePOV.otherDevice, alice2.deviceId);
                        
                        // - Alice accepts it
                        [requestFromAlicePOV acceptWithMethods:@[MXKeyVerificationMethodSAS] success:^{
                            
                            id<MXKeyVerificationRequest> requestFromAlicePOV2 = aliceSession1.crypto.keyVerificationManager.pendingRequests.firstObject;
                            XCTAssertNotNil(requestFromAlicePOV2);
                            XCTAssertEqualObjects(requestFromAlicePOV2.myMethods, @[MXKeyVerificationMethodSAS]);
                            
                            // - Alice begins a SAS verification
                            [aliceSession1.crypto.keyVerificationManager beginKeyVerificationFromRequest:requestFromAlicePOV2 method:MXKeyVerificationMethodSAS success:^(id<MXKeyVerificationTransaction> _Nonnull transactionFromAlicePOV) {
                                
                                XCTAssertEqualObjects(transactionFromAlicePOV.transactionId, requestFromAlicePOV.requestId);
                                
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
                }];
                
                
                [self observeSASIncomingTransactionInSession:aliceSession2 block:^(MXIncomingSASTransaction * _Nullable transactionFromAlice2POV) {
                    
                    // Final checks
                    void (^checkBothVerified)(void) = ^ void ()
                    {
                        if (sasTransactionFromAlicePOV.state == MXSASTransactionStateVerified
                            && transactionFromAlice2POV.state == MXSASTransactionStateVerified)
                        {
                            // -> Devices must be really verified
                            MXDeviceInfo *aliceDevice2FromAlice1POV = [aliceSession1.legacyCrypto.store deviceWithDeviceId:alice2.deviceId forUser:alice2.userId];
                            MXDeviceInfo *aliceDevice1FromAlice2POV = [aliceSession2.legacyCrypto.store deviceWithDeviceId:alice.deviceId forUser:alice.userId];
                            
                            XCTAssertEqual(aliceDevice2FromAlice1POV.trustLevel.localVerificationStatus, MXDeviceVerified);
                            XCTAssertTrue(aliceDevice2FromAlice1POV.trustLevel.isCrossSigningVerified);
                            XCTAssertEqual(aliceDevice1FromAlice2POV.trustLevel.localVerificationStatus, MXDeviceVerified);
                            XCTAssertTrue(aliceDevice1FromAlice2POV.trustLevel.isCrossSigningVerified);

                            // -> My user must be really verified
                            MXCrossSigningInfo *aliceFromAlice1POV = [aliceSession1.legacyCrypto.store crossSigningKeysForUser:alice.userId];
                            MXCrossSigningInfo *aliceFromAlice2POV = [aliceSession2.legacyCrypto.store crossSigningKeysForUser:alice.userId];

                            XCTAssertTrue(aliceFromAlice1POV.trustLevel.isCrossSigningVerified);
                            XCTAssertTrue(aliceFromAlice1POV.trustLevel.isLocallyVerified);
                            XCTAssertTrue(aliceFromAlice2POV.trustLevel.isCrossSigningVerified);
                            XCTAssertTrue(aliceFromAlice2POV.trustLevel.isLocallyVerified);
                            
                            // -> Transaction must not be listed anymore
                            XCTAssertNil([(MXLegacyKeyVerificationManager *)aliceSession1.crypto.keyVerificationManager transactionWithTransactionId:sasTransactionFromAlicePOV.transactionId]);
                            XCTAssertNil([(MXLegacyKeyVerificationManager *)aliceSession2.crypto.keyVerificationManager transactionWithTransactionId:transactionFromAlice2POV.transactionId]);
                            
                            [expectation fulfill];
                        }
                    };
                    
                    // -> Transaction on Alice side must be WaitForPartnerKey, then ShowSAS
                    [self observeTransactionUpdate:sasTransactionFromAlicePOV block:^{
                        
                        switch (sasTransactionFromAlicePOV.state)
                        {
                                // -> 2. Transaction on Alice side must then move to WaitForPartnerKey
                            case MXSASTransactionStateWaitForPartnerKey:
                                XCTAssertEqual(transactionFromAlice2POV.state, MXSASTransactionStateWaitForPartnerKey);
                                break;
                                // -> 4. Transaction on Alice side must then move to ShowSAS
                            case MXSASTransactionStateShowSAS:
                                XCTAssertEqual(transactionFromAlice2POV.state, MXSASTransactionStateShowSAS);
                                
                                // -> 5. SASs must be the same
                                XCTAssertEqualObjects(sasTransactionFromAlicePOV.sasBytes, transactionFromAlice2POV.sasBytes);
                                XCTAssertEqualObjects(sasTransactionFromAlicePOV.sasDecimal, transactionFromAlice2POV.sasDecimal);
                                XCTAssertEqualObjects(sasTransactionFromAlicePOV.sasEmoji, transactionFromAlice2POV.sasEmoji);
                                
                                // -  Alice confirms SAS
                                [sasTransactionFromAlicePOV confirmSASMatch];
                                break;
                                // -> 6. Transaction on Alice side must then move to WaitForPartnerToConfirm
                            case MXSASTransactionStateWaitForPartnerToConfirm:
                                // -  Bob confirms SAS
                                [transactionFromAlice2POV confirmSASMatch];
                                break;
                                // -> 7. Transaction on Alice side must then move to Verified
                            case MXSASTransactionStateVerified:
                                checkBothVerified();
                                break;
                            default:
                                XCTAssert(NO, @"Unexpected Alice transation state: %@", @(sasTransactionFromAlicePOV.state));
                                break;
                        }
                    }];
                    
                    // -> Transaction on Bob side must be WaitForPartnerKey, then ShowSAS
                    [self observeTransactionUpdate:transactionFromAlice2POV block:^{
                        
                        switch (transactionFromAlice2POV.state)
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
                                checkBothVerified();
                                break;
                            default:
                                XCTAssert(NO, @"Unexpected Bob transation state: %@", @(sasTransactionFromAlicePOV.state));
                                break;
                        }
                    }];
                }];
            }];
        }];
    
    }];
}

#pragma mark - Verification of others (by DM) -

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
 -> Users must be really verified
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
                                                                                       success:^(id<MXKeyVerificationRequest> request)
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
                     if ([event.content[kMXMessageTypeKey] isEqualToString:kMXMessageTypeKeyVerificationRequest])
                     {
                         XCTAssertEqualObjects(event.eventId, requestId);
                         
                         // Check verification by DM request format
                         MXKeyVerificationRequestByDMJSONModel *requestJSON;
                         MXJSONModelSetMXJSONModel(requestJSON, MXKeyVerificationRequestByDMJSONModel.class, event.content);
                         XCTAssertNotNil(requestJSON);
                         
                         // - Alice accepts it and begins a SAS verification
                         
                         // Wait a bit
                         dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                             // - Alice rejects the incoming request
                             id<MXKeyVerificationRequest> requestFromAlicePOV = aliceSession.crypto.keyVerificationManager.pendingRequests.firstObject;
                             XCTAssertNotNil(requestFromAlicePOV);
                             
                             [requestFromAlicePOV acceptWithMethods:@[MXKeyVerificationMethodSAS] success:^{
                                 
                                 [aliceSession.crypto.keyVerificationManager beginKeyVerificationFromRequest:requestFromAlicePOV method:MXKeyVerificationMethodSAS success:^(id<MXKeyVerificationTransaction> _Nonnull transactionFromAlicePOV) {

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
                            MXDeviceInfo *bobDeviceFromAlicePOV = [aliceSession.legacyCrypto.store deviceWithDeviceId:bob.deviceId forUser:bob.userId];
                            MXDeviceInfo *aliceDeviceFromBobPOV = [bobSession.legacyCrypto.store deviceWithDeviceId:alice.deviceId forUser:alice.userId];
                            
                            XCTAssertEqual(bobDeviceFromAlicePOV.trustLevel.localVerificationStatus, MXDeviceVerified);
                            XCTAssertTrue(bobDeviceFromAlicePOV.trustLevel.isCrossSigningVerified);
                            XCTAssertEqual(aliceDeviceFromBobPOV.trustLevel.localVerificationStatus, MXDeviceVerified);
                            XCTAssertTrue(aliceDeviceFromBobPOV.trustLevel.isCrossSigningVerified);

                            // -> Users must be really verified
                            MXCrossSigningInfo *bobFromAlicePOV = [aliceSession.legacyCrypto.store crossSigningKeysForUser:bob.userId];
                            MXCrossSigningInfo *aliceFromBobPOV = [bobSession.legacyCrypto.store crossSigningKeysForUser:alice.userId];
                            
                            XCTAssertTrue(bobFromAlicePOV.trustLevel.isCrossSigningVerified);
                            XCTAssertTrue(bobFromAlicePOV.trustLevel.isLocallyVerified);
                            XCTAssertTrue(aliceFromBobPOV.trustLevel.isCrossSigningVerified);
                            XCTAssertTrue(aliceFromBobPOV.trustLevel.isLocallyVerified);
                            
                            // -> Transaction must not be listed anymore
                            XCTAssertNil([(MXLegacyKeyVerificationManager *)aliceSession.crypto.keyVerificationManager transactionWithTransactionId:sasTransactionFromAlicePOV.transactionId]);
                            XCTAssertNil([(MXLegacyKeyVerificationManager *)bobSession.crypto.keyVerificationManager transactionWithTransactionId:transactionFromBobPOV.transactionId]);
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
                        [aliceSession.crypto.keyVerificationManager keyVerificationFromKeyVerificationEvent:event roomId:roomId success:^(MXKeyVerification * _Nonnull verificationFromAlicePOV) {
                            
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

/**
 Verify another user by QR code
 It reuses code from testVerificationByDMFullFlow from MXCryptoKeyVerificationTests.
 
 - Alice and Bob are in a room
 - Alice and Bob bootstrap cross-signing (This is the single difference with original testVerificationByDMFullFlow).
 - Bob requests a verification of Alice in this Room
 - Alice gets the request in the timeline
 - Alice accepts it and wait for Bob to scan her QR code
 -> 1. Transaction on Bob side must be Unknown
 -> 2. Transaction on Alice side must be Unknown
 -  Bob scans Alice QR code
 -> 3. Transaction on Bob side must then move to ScannedOtherQR
 -> 4. Transaction on Bob side must then move to WaitingOtherConfirm, if the start request succeed
 -> 5. Transaction on Alice side must then move to QRScannedByOther
 -  Alice confirms that Bob has scanned her QR code
 -> 6. Transaction on Alice side must then move to Verified
 -> 7. Transaction on Bob side must then move to Verified
 -> Users must be verified
 -> Transaction must not be listed anymore
 -> Both ends must get a done message
 - Then, test MXKeyVerification
 */
- (void)testVerifyingAnotherUserQRCodeVerificationFullFlow
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:YES aliceStore:[[MXMemoryStore alloc] init] bobStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Alice and Bob bootstrap cross-signing
        [self bootstrapCrossSigningOnSession:aliceSession password:MXTESTS_ALICE_PWD completion:^{
            [self bootstrapCrossSigningOnSession:bobSession password:MXTESTS_BOB_PWD completion:^{
                
                NSString *fallbackText = @"fallbackText";
                __block NSString *requestId;
                
                __block MXQRCodeData *aliceQRCodeData;
                
                MXCredentials *alice = aliceSession.matrixRestClient.credentials;
                MXCredentials *bob = bobSession.matrixRestClient.credentials;
                
                // - Bob requests a verification of Alice in this Room
                [bobSession.crypto.keyVerificationManager requestVerificationByDMWithUserId:alice.userId
                                                                                     roomId:roomId
                                                                               fallbackText:fallbackText
                                                                                    methods:@[MXKeyVerificationMethodQRCodeShow, MXKeyVerificationMethodQRCodeScan, MXKeyVerificationMethodReciprocate]
                                                                                    success:^(id<MXKeyVerificationRequest> request)
                 {
                     requestId = request.requestId;
                 }
                                                                                    failure:^(NSError * _Nonnull error)
                 {
                     XCTFail(@"The request should not fail - NSError: %@", error);
                     [expectation fulfill];
                 }];
                
                __block MXLegacyQRCodeTransaction *qrCodeTransactionFromAlicePOV;
                
                // Alice gets the request in the timeline
                [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                            onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject)
                 {
                     if ([event.content[kMXMessageTypeKey] isEqualToString:kMXMessageTypeKeyVerificationRequest])
                     {
                         XCTAssertEqualObjects(event.eventId, requestId);
                         
                         // Check verification by DM request format
                         MXKeyVerificationRequestByDMJSONModel *requestJSON;
                         MXJSONModelSetMXJSONModel(requestJSON, MXKeyVerificationRequestByDMJSONModel.class, event.content);
                         XCTAssertNotNil(requestJSON);
                         
                         // - Alice accepts it and creates a QR code transaction
                         [self observeKeyVerificationRequestInSession:aliceSession block:^(id<MXKeyVerificationRequest>  _Nullable request) {

                             // - Alice accepts the incoming request
                             id<MXKeyVerificationRequest> requestFromAlicePOV = aliceSession.crypto.keyVerificationManager.pendingRequests.firstObject;
                             XCTAssertNotNil(requestFromAlicePOV);
                             
                             [requestFromAlicePOV acceptWithMethods:@[MXKeyVerificationMethodQRCodeShow, MXKeyVerificationMethodReciprocate] success:^{
                                 
                                 qrCodeTransactionFromAlicePOV = [aliceSession.crypto.keyVerificationManager qrCodeTransactionWithTransactionId:requestFromAlicePOV.requestId];
                                 
                                 aliceQRCodeData = qrCodeTransactionFromAlicePOV.qrCodeData;
                                 
                                 XCTAssertEqual(requestFromAlicePOV.state, MXKeyVerificationRequestStateReady);
                                 XCTAssertNotNil(aliceQRCodeData);
                                 XCTAssertEqual(aliceQRCodeData.verificationMode, MXQRCodeVerificationModeVerifyingAnotherUser);                                                                                                   
                                 
                             } failure:^(NSError * _Nonnull error) {
                                 XCTFail(@"The request should not fail - NSError: %@", error);
                                 [expectation fulfill];
                             }];
                         }];
                     }
                 }];
                
                
                [self observeNewQRCodeTransactionInSession:bobSession block:^(MXLegacyQRCodeTransaction * _Nullable qrCodeTransactionFromBobPOV) {
                    
                    // Final checks
                    void (^checkBothDeviceVerified)(void) = ^ void ()
                    {
                        if (qrCodeTransactionFromAlicePOV.state == MXQRCodeTransactionStateVerified
                            && qrCodeTransactionFromBobPOV.state == MXQRCodeTransactionStateVerified)
                        {
                            // -> Devices must be really verified
                            MXDeviceInfo *bobDeviceFromAlicePOV = [aliceSession.legacyCrypto.store deviceWithDeviceId:bob.deviceId forUser:bob.userId];
                            MXDeviceInfo *aliceDeviceFromBobPOV = [bobSession.legacyCrypto.store deviceWithDeviceId:alice.deviceId forUser:alice.userId];
                            
                            XCTAssertEqual(bobDeviceFromAlicePOV.trustLevel.localVerificationStatus, MXDeviceVerified);
                            XCTAssertTrue(bobDeviceFromAlicePOV.trustLevel.isCrossSigningVerified);
                            XCTAssertEqual(aliceDeviceFromBobPOV.trustLevel.localVerificationStatus, MXDeviceVerified);
                            XCTAssertTrue(aliceDeviceFromBobPOV.trustLevel.isCrossSigningVerified);
                            
                            // -> Users must be really verified
                            MXCrossSigningInfo *bobFromAlicePOV = [aliceSession.legacyCrypto.store crossSigningKeysForUser:bob.userId];
                            MXCrossSigningInfo *aliceFromBobPOV = [bobSession.legacyCrypto.store crossSigningKeysForUser:alice.userId];
                            
                            XCTAssertTrue(bobFromAlicePOV.trustLevel.isCrossSigningVerified);
                            XCTAssertTrue(bobFromAlicePOV.trustLevel.isLocallyVerified);
                            XCTAssertTrue(aliceFromBobPOV.trustLevel.isCrossSigningVerified);
                            XCTAssertTrue(aliceFromBobPOV.trustLevel.isLocallyVerified);
                            
                            // -> Transaction must not be listed anymore
                            XCTAssertNil([(MXLegacyKeyVerificationManager *)aliceSession.crypto.keyVerificationManager transactionWithTransactionId:qrCodeTransactionFromAlicePOV.transactionId]);
                            XCTAssertNil([(MXLegacyKeyVerificationManager *)bobSession.crypto.keyVerificationManager transactionWithTransactionId:qrCodeTransactionFromBobPOV.transactionId]);
                        }
                    };
                    
                    // -> Transaction on Alice side must be Unknown, then QRScannedByOther
                    [self observeTransactionUpdate:qrCodeTransactionFromAlicePOV block:^{
                        
                        switch (qrCodeTransactionFromAlicePOV.state)
                        {
                                // -> 2. Transaction on Alice side must be Unknown
                            case MXQRCodeTransactionStateUnknown:
                                XCTAssertEqual(qrCodeTransactionFromBobPOV.state, MXQRCodeTransactionStateUnknown);
                                break;
                                // -> 5. Transaction on Alice side must then move to QRScannedByOther
                            case MXQRCodeTransactionStateQRScannedByOther:
                                XCTAssertEqual(qrCodeTransactionFromBobPOV.state, MXQRCodeTransactionStateWaitingOtherConfirm);
                                
                                // Alice confirms that Bob has scanned her QR code
                                [qrCodeTransactionFromAlicePOV otherUserScannedMyQrCode:YES];
                                break;
                                // -> 6. Transaction on Alice side must then move to Verified
                            case MXQRCodeTransactionStateVerified:
                                checkBothDeviceVerified();
                                break;
                            default:
                                XCTAssert(NO, @"Unexpected Alice transation state: %@", @(qrCodeTransactionFromAlicePOV.state));
                                break;
                        }
                    }];
                    
                    // -> Transaction on Bob side must be Unknown, then ScannedOtherQR
                    [self observeTransactionUpdate:qrCodeTransactionFromBobPOV block:^{
                        
                        switch (qrCodeTransactionFromBobPOV.state)
                        {
                            // -> 1. Transaction on Bob side must be Unknown (Alice is Unknown)
                            case MXQRCodeTransactionStateUnknown:
                                XCTAssertEqual(qrCodeTransactionFromAlicePOV.state, MXQRCodeTransactionStateUnknown);
                                break;
                            // -> 3. Transaction on Bob side must then move to ScannedOtherQR
                            case MXQRCodeTransactionStateScannedOtherQR:
                                XCTAssertEqual(qrCodeTransactionFromAlicePOV.state, MXQRCodeTransactionStateUnknown);
                                break;
                            // -> 4. Transaction on Bob side must then move to WaitingOtherConfirm
                            case MXQRCodeTransactionStateWaitingOtherConfirm:
                                XCTAssertEqual(qrCodeTransactionFromAlicePOV.state, MXQRCodeTransactionStateUnknown);
                                break;
                            // -> 7. Transaction on Bob side must then move to Verified
                            case MXQRCodeTransactionStateVerified:
                                checkBothDeviceVerified();
                                break;
                            default:
                                XCTAssert(NO, @"Unexpected Bob transation state: %@", @(qrCodeTransactionFromAlicePOV.state));
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
                        // Then, to test MXKeyVerification
                        MXEvent *event = [aliceSession.store eventWithEventId:requestId inRoom:roomId];
                        [aliceSession.crypto.keyVerificationManager keyVerificationFromKeyVerificationEvent:event roomId:roomId success:^(MXKeyVerification * _Nonnull verificationFromAlicePOV) {

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
                
                // -> Bob gets the requests notification
                [self observeKeyVerificationRequestChangeWithBlock:^(id<MXKeyVerificationRequest> _Nullable request) {
                    
                    if (!request.isFromMyUser)
                    {
                        return;
                    }
                    
                    XCTAssertEqualObjects(request.requestId, requestId);
                    XCTAssertTrue(request.isFromMyUser);
                    
                    id<MXKeyVerificationRequest> requestFromAlicePOV = aliceSession.crypto.keyVerificationManager.pendingRequests.firstObject;
                    id<MXKeyVerificationRequest> requestFromBobPOV = bobSession.crypto.keyVerificationManager.pendingRequests.firstObject;
                    
                    XCTAssertNotNil(requestFromAlicePOV);
                    XCTAssertEqual(requestFromAlicePOV.transport, MXKeyVerificationTransportDirectMessage);
                    XCTAssertNotNil(requestFromBobPOV);
                    XCTAssertEqual(requestFromBobPOV.transport, MXKeyVerificationTransportDirectMessage);
                    
                    switch (request.state)
                    {
                        case MXKeyVerificationRequestStateReady:
                        {
                            MXLegacyQRCodeTransaction *qrCodeTransactionFromBobPOV = [bobSession.crypto.keyVerificationManager qrCodeTransactionWithTransactionId:request.requestId];
                            XCTAssertNotNil(qrCodeTransactionFromBobPOV);
                            XCTAssertNil(qrCodeTransactionFromBobPOV.qrCodeData); // Bob cannot show QR code
                            
                            // Bob scan Alice QR code
                            [qrCodeTransactionFromBobPOV userHasScannedOtherQrCodeData:aliceQRCodeData];
                        }
                            break;
                        case MXKeyVerificationRequestStateCancelled:
                            XCTFail(@"The request should not be cancel - Cancel code: %@", request.reasonCancelCode);
                            break;
                        default:
                            break;
                    }
                }];
            }];
        }];
    }];
}

@end

#pragma clang diagnostic pop
