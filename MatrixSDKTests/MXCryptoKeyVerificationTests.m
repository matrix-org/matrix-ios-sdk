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

#import "MXFileStore.h"

#import "MXKeyVerificationRequestByDMJSONModel.h"
#import "MatrixSDKTestsSwiftHeader.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
#pragma clang diagnostic ignored "-Wdeprecated"

@interface MXCryptoKeyVerificationTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

    NSMutableArray<id> *observers;
}
@end

@implementation MXCryptoKeyVerificationTests

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

- (void)observeTransactionUpdate:(id<MXKeyVerificationTransaction>)transaction block:(void (^)(void))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationTransactionDidChangeNotification object:transaction queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
            block();
    }];

    [observers addObject:observer];
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


- (void)observeKeyVerificationRequestUpdate:(id<MXKeyVerificationRequest>)request block:(void (^)(void))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXKeyVerificationRequestDidChangeNotification object:request queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
        block();
    }];
    
    [observers addObject:observer];
}


#pragma mark - Verification by to_device
/**
 Test new to_device requests
 
 - Alice and Bob are in a room
 - Bob requests a verification of Alice in this Room
 -> Alice gets the requests notification
 -> They both have it in their pending requests
 */
- (void)testVerificationByToDeviceRequests
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        __block NSString *requestId;
        
        MXCredentials *alice = aliceSession.matrixRestClient.credentials;
        
        // - Bob requests a verification of Alice
        [bobSession.crypto.keyVerificationManager requestVerificationByToDeviceWithUserId:alice.userId
                                                                                deviceIds:@[alice.deviceId]
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
        
        
        // -> Alice gets the requests notification
        [self observeKeyVerificationRequestInSession:aliceSession block:^(id<MXKeyVerificationRequest> _Nullable request) {
            XCTAssertEqualObjects(request.requestId, requestId);
            XCTAssertFalse(request.isFromMyUser);
            
            id<MXKeyVerificationRequest> requestFromAlicePOV = aliceSession.crypto.keyVerificationManager.pendingRequests.firstObject;
            id<MXKeyVerificationRequest> requestFromBobPOV = bobSession.crypto.keyVerificationManager.pendingRequests.firstObject;
            
            XCTAssertNotNil(requestFromAlicePOV);
            XCTAssertEqual(requestFromAlicePOV.transport, MXKeyVerificationTransportToDevice);
            XCTAssertNotNil(requestFromBobPOV);
            XCTAssertEqual(requestFromBobPOV.transport, MXKeyVerificationTransportToDevice);
            
            [expectation fulfill];
        }];
    }];
}

/**
 Test self verification request when no other device.
 - Have Alice with 1 device
 - Alice sends a self verification request to her all other devices
 -> The request must fail as she has no other device.
 */
- (void)testVerificationByToDeviceRequestWithNoOtherDevice
{
    // - Have Alice with 1 device
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:YES aliceStore:[[MXMemoryStore alloc] init] bobStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *aliceUserId = aliceSession.matrixRestClient.credentials.userId;
        
        NSArray *methods = @[MXKeyVerificationMethodSAS];
        
        // - Alice sends a self verification request to her all other devices
        [aliceSession.crypto.keyVerificationManager requestVerificationByToDeviceWithUserId:aliceUserId
                                                                                  deviceIds:nil
                                                                                    methods:methods
                                                                                    success:^(id<MXKeyVerificationRequest> requestFromAliceDevice1POV)
         {
             XCTFail(@"The request should not succeed ");
             [expectation fulfill];
         }
                                                                                    failure:^(NSError * _Nonnull error)
         {
             //  -> The request must fail as she has no other device.
             XCTAssertEqualObjects(error.domain, MXKeyVerificationErrorDomain);
             XCTAssertEqual(error.code, MXKeyVerificatioNoOtherDeviceCode);
             
             [expectation fulfill];
         }];
    }];
}

#pragma mark - Verification by DM
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


        // -> Alice gets the requests notification
        [self observeKeyVerificationRequestInSession:aliceSession block:^(id<MXKeyVerificationRequest> _Nullable request) {
            XCTAssertEqualObjects(request.requestId, requestId);
            XCTAssertFalse(request.isFromMyUser);

            id<MXKeyVerificationRequest> requestFromAlicePOV = aliceSession.crypto.keyVerificationManager.pendingRequests.firstObject;
            id<MXKeyVerificationRequest> requestFromBobPOV = bobSession.crypto.keyVerificationManager.pendingRequests.firstObject;

            XCTAssertNotNil(requestFromAlicePOV);
            XCTAssertEqual(requestFromAlicePOV.transport, MXKeyVerificationTransportDirectMessage);
            XCTAssertNotNil(requestFromBobPOV);
            XCTAssertEqual(requestFromBobPOV.transport, MXKeyVerificationTransportDirectMessage);

            [expectation fulfill];
        }];
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

        // Alice gets the request in the timeline
        [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                    onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject)
         {
             if ([event.content[kMXMessageTypeKey] isEqualToString:kMXMessageTypeKeyVerificationRequest])
             {
                 MXKeyVerificationRequestByDMJSONModel *requestJSON;
                 MXJSONModelSetMXJSONModel(requestJSON, MXKeyVerificationRequestByDMJSONModel.class, event.content);
                 XCTAssertNotNil(requestJSON);

                 // Wait a bit
                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                     // - Alice rejects the incoming request
                     id<MXKeyVerificationRequest> requestFromAlicePOV = aliceSession.crypto.keyVerificationManager.pendingRequests.firstObject;
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
                [aliceSession.crypto.keyVerificationManager keyVerificationFromKeyVerificationEvent:event roomId:roomId success:^(MXKeyVerification * _Nonnull verificationFromAlicePOV) {

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
- (void)testVerificationByDMWithRoomDetection
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *fallbackText = @"fallbackText";
        __block NSString *requestId;
        
        MXCredentials *alice = aliceSession.matrixRestClient.credentials;
        
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        [roomFromBobPOV setIsDirect:YES withUserId:alice.userId success:^{
            
            // - Bob requests a verification of Alice without indicating a room to use
            [bobSession.crypto.keyVerificationManager requestVerificationByDMWithUserId:alice.userId
                                                                                    roomId:nil
                                                                              fallbackText:fallbackText
                                                                                   methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                                   success:^(id<MXKeyVerificationRequest> request)
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
        [self observeKeyVerificationRequestInSession:aliceSession block:^(id<MXKeyVerificationRequest> _Nullable request) {
            XCTAssertEqualObjects(request.requestId, requestId);
            XCTAssertFalse(request.isFromMyUser);
            
            id<MXKeyVerificationRequest> requestFromAlicePOV = aliceSession.crypto.keyVerificationManager.pendingRequests.firstObject;
            id<MXKeyVerificationRequest> requestFromBobPOV = bobSession.crypto.keyVerificationManager.pendingRequests.firstObject;
            
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
- (void)testVerificationByDMWithNoRoom
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *aliceSession, MXSession *bobSession, XCTestExpectation *expectation) {
        
        NSString *fallbackText = @"fallbackText";
        __block NSString *requestId;
        
        MXCredentials *alice = aliceSession.matrixRestClient.credentials;
            
        // - Bob requests a verification of Alice without indicating a room to use
        [bobSession.crypto.keyVerificationManager requestVerificationByDMWithUserId:alice.userId
                                                                                roomId:nil
                                                                          fallbackText:fallbackText
                                                                               methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                               success:^(id<MXKeyVerificationRequest> request)
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
        [self observeKeyVerificationRequestInSession:aliceSession block:^(id<MXKeyVerificationRequest> _Nullable request) {
        
            
            XCTAssertEqualObjects(request.requestId, requestId);
            XCTAssertFalse(request.isFromMyUser);
            
            id<MXKeyVerificationRequest> requestFromAlicePOV = aliceSession.crypto.keyVerificationManager.pendingRequests.firstObject;
            id<MXKeyVerificationRequest> requestFromBobPOV = bobSession.crypto.keyVerificationManager.pendingRequests.firstObject;
            
            XCTAssertNotNil(requestFromAlicePOV);
            XCTAssertNotNil(requestFromBobPOV);
            
            
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop
