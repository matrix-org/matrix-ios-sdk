/*
 Copyright 2016 OpenMarket Ltd
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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXSession.h"
#import "MXMegolmExportEncryption.h"
#import "MXFileStore.h"

#import "MXSDKOptions.h"
#import "MXTools.h"
#import "MXSendReplyEventDefaultStringLocalizer.h"
#import "MXLRUCache.h"
#import "MatrixSDKTestsSwiftHeader.h"

#import "MXKey.h"

#if 1 // MX_CRYPTO autamatic definiton does not work well for tests so force it
//#ifdef MX_CRYPTO

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXCryptoTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

    id observer;
}
@end

@implementation MXCryptoTests

- (void)setUp
{
    [super setUp];
    
    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
}

- (void)tearDown
{
    if (observer)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        observer = nil;
    }

    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;

    [super tearDown];
}

- (NSUInteger)checkEncryptedEvent:(MXEvent*)event roomId:(NSString*)roomId clearMessage:(NSString*)clearMessage senderSession:(MXSession*)senderSession
{
    NSUInteger failureCount = self.testRun.failureCount;

    // Check raw event (encrypted) data as sent by the hs
    XCTAssertEqual(event.wireEventType, MXEventTypeRoomEncrypted);
    XCTAssertNil(event.wireContent[kMXMessageBodyKey], @"No body field in an encrypted content");
    XCTAssertEqualObjects(event.wireContent[@"algorithm"], kMXCryptoMegolmAlgorithm);
    XCTAssertNotNil(event.wireContent[@"ciphertext"]);
    XCTAssertNotNil(event.wireContent[@"session_id"]);
    XCTAssertNotNil(event.wireContent[@"sender_key"]);

    // Check decrypted data
    XCTAssert(event.eventId);
    XCTAssertEqualObjects(event.roomId, roomId);
    XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
    XCTAssertLessThan(event.age, 10000);
    XCTAssertEqualObjects(event.content[kMXMessageBodyKey], clearMessage);
    XCTAssertEqualObjects(event.sender, senderSession.myUser.userId);
    XCTAssertNil(event.decryptionError);

    // Return the number of failures in this method
    return self.testRun.failureCount - failureCount;
}


#pragma mark - MXCrypto

- (void)testEnableCrypto
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        XCTAssertNil(mxSession.crypto, @"Crypto is disabled by default");

        MXKeyProvider.sharedInstance.delegate = [[MXKeyProviderStub alloc] init];
        [mxSession enableCrypto:YES success:^{
            MXKeyProvider.sharedInstance.delegate = nil;

            XCTAssert(mxSession.crypto);

            [mxSession enableCrypto:NO success:^{

                XCTAssertNil(mxSession.crypto);
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMXSDKOptionsEnableCryptoWhenOpeningMXSession
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
    MXKeyProvider.sharedInstance.delegate = [[MXKeyProviderStub alloc] init];

    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        // Reset the option to not disturb other tests
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
        MXKeyProvider.sharedInstance.delegate = nil;

        XCTAssert(mxSession.crypto);

        [mxSession enableCrypto:NO success:^{

            XCTAssertNil(mxSession.crypto);
            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

#pragma mark - MXSession

// Test MXSession.event(withEventId:)
// - Have Alice with an encrypted message
// - Get the event content using MXSession.event(withEventId:)
// -> The event must be decrypted
- (void)testMXSessionEventWithEventId
{
    NSString *message = @"Hello myself!";
    
    // - Have Alice with an encrypted message
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        [roomFromAlicePOV sendTextMessage:message threadId:nil success:^(NSString *eventId) {

            // - Get the event content using MXSession.event(withEventId:)
            [aliceSession eventWithEventId:eventId inRoom:nil success:^(MXEvent *event) {
                
                // -> The event must be decrypted
                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession]);
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

- (void)testAliceInACryptedRoom
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *message = @"Hello myself!";

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        // Check the echo from hs of a post message is correct
        [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession]);

                [expectation fulfill];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:message threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)sendEventOfType:(MXEventTypeString)eventTypeString
                content:(NSDictionary *)content
                   room:(MXRoom *)room
                success:(void(^)(MXEvent *))success
                failure:(void(^)(NSError *error))failure
{
    __block id listener = [room listenToEventsOfTypes:@[eventTypeString]
                                              onEvent:^(MXEvent * _Nonnull event, MXTimelineDirection direction, MXRoomState * _Nullable roomState)
    {
        [room removeListener:listener];
        success(event);
    }];
    
    [room sendEventOfType:eventTypeString
                  content:content
                 threadId:nil
                localEcho:nil
                  success:nil
                  failure:failure];
}

- (void)testAliceInACryptedRoomAfterInitialSync
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRestClient *aliceRestClient = aliceSession.matrixRestClient;
        [aliceSession close];
        aliceSession = nil;

        MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:aliceSession2];

        [aliceSession2 setStore:[[MXMemoryStore alloc] init] success:^{

            [self restartSession:aliceSession2
                waitingForRoomId:roomId
                         success:^(MXRoom *roomFromAlicePOV) {

                XCTAssert(aliceSession2.crypto, @"MXSession must recall that it has crypto engaged");

                NSString *message = @"Hello myself!";

                XCTAssert(roomFromAlicePOV.summary.isEncrypted);

                // Check the echo from hs of a post message is correct
                [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                    XCTAssert(liveTimeline.state.isEncrypted);

                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession2]);

                        [expectation fulfill];
                    }];

                    [roomFromAlicePOV sendTextMessage:message threadId:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testAliceAndBobInACryptedRoom
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                [expectation fulfill];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test with more messages
- (void)testAliceAndBobInACryptedRoom2
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        __block NSUInteger receivedMessagesFromAlice = 0;
        __block NSUInteger receivedMessagesFromBob = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if ([event.sender isEqualToString:bobSession.myUser.userId])
                {
                    return;
                }

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[receivedMessagesFromAlice++] senderSession:aliceSession]);

                switch (receivedMessagesFromAlice)
                {
                    case 1:
                    {
                        // Send messages in expected order
                        [roomFromBobPOV sendTextMessage:matrixSDKTestsE2EData.messagesFromBob[0] threadId:nil success:^(NSString *eventId) {
                            [roomFromBobPOV sendTextMessage:matrixSDKTestsE2EData.messagesFromBob[1] threadId:nil success:^(NSString *eventId) {
                                [roomFromBobPOV sendTextMessage:matrixSDKTestsE2EData.messagesFromBob[2] threadId:nil success:nil failure:nil];
                            } failure:nil];
                        } failure:nil];

                        break;
                    }

                    case 2:
                        [expectation fulfill];
                        break;
                    default:
                        break;
                }
            }];
        }];

        [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if ([event.sender isEqualToString:aliceSession.myUser.userId])
                {
                    return;
                }

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[receivedMessagesFromBob++] senderSession:bobSession]);

                if (receivedMessagesFromBob == 3)
                {
                    [roomFromAlicePOV sendTextMessage:matrixSDKTestsE2EData.messagesFromAlice[1] threadId:nil success:nil failure:nil];
                }
            }];
        }];

        [roomFromAlicePOV sendTextMessage:matrixSDKTestsE2EData.messagesFromAlice[0] threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testAliceAndBobInACryptedRoomFromInitialSync
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient = bobSession.matrixRestClient;

        [bobSession close];
        bobSession = nil;

        bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:bobSession];

        [bobSession setStore:[[MXMemoryStore alloc] init] success:^{

            XCTAssert(bobSession.crypto, @"MXSession must recall that it has crypto engaged");
            
            [self restartSession:bobSession
                waitingForRoomId:roomId
                         success:^(MXRoom * roomFromBobPOV) {

                __block NSUInteger paginatedMessagesCount = 0;

                [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                    [liveTimeline resetPagination];
                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(direction, MXTimelineDirectionBackwards);

                        switch (paginatedMessagesCount++)
                        {
                            case 0:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[1] senderSession:aliceSession]);
                                break;

                            case 1:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[2] senderSession:bobSession]);
                                break;

                            case 2:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[1] senderSession:bobSession]);
                                break;

                            case 3:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[0] senderSession:bobSession]);
                                break;

                            case 4:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[0] senderSession:aliceSession]);
                                break;

                            default:
                                break;
                        }

                    }];

                    XCTAssert([liveTimeline canPaginate:MXTimelineDirectionBackwards]);

                    [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:YES complete:^{

                        XCTAssertEqual(paginatedMessagesCount, 5);

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
}

- (void)testAliceAndBobInACryptedRoomBackPaginationFromMemoryStore
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        __block NSUInteger paginatedMessagesCount = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline resetPagination];

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(direction, MXTimelineDirectionBackwards);

                switch (paginatedMessagesCount++) {
                    case 0:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[1] senderSession:aliceSession]);
                        break;

                    case 1:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[2] senderSession:bobSession]);
                        break;

                    case 2:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[1] senderSession:bobSession]);
                        break;

                    case 3:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[0] senderSession:bobSession]);
                        break;

                    case 4:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[0] senderSession:aliceSession]);
                        break;

                    default:
                        break;
                }

            }];

            XCTAssert([liveTimeline canPaginate:MXTimelineDirectionBackwards]);

            [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:YES complete:^{

                XCTAssertEqual(paginatedMessagesCount, 5);

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];

    }];
}

- (void)testAliceAndBobInACryptedRoomBackPaginationFromHomeServer
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        __block NSUInteger paginatedMessagesCount = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        // Create a timeline from the last event
        // Internally, events of this timeline will be fetched on the homeserver
        // which is the use case of this test
        NSString *lastEventId = roomFromBobPOV.summary.lastMessage.eventId;
        id<MXEventTimeline> timeline = [roomFromBobPOV timelineOnEvent:lastEventId];

        [timeline resetPagination];

        [timeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            XCTAssertEqual(direction, MXTimelineDirectionBackwards);

            switch (paginatedMessagesCount++) {
                case 0:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[1] senderSession:aliceSession]);
                    break;

                case 1:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[2] senderSession:bobSession]);
                    break;

                case 2:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[1] senderSession:bobSession]);
                    break;

                case 3:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[0] senderSession:bobSession]);
                    break;

                case 4:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[0] senderSession:aliceSession]);
                    break;

                default:
                    break;
            }

        }];

        XCTAssert([timeline canPaginate:MXTimelineDirectionBackwards]);

        [timeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

            XCTAssertEqual(paginatedMessagesCount, 5);

            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testAliceAndNotCryptedBobInACryptedRoom
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:NO warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted, "Even if his crypto is disabled, Bob should know that a room is encrypted");
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        __block NSUInteger messageCount = 0;

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomEncrypted, kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                switch (messageCount++)
                {
                    case 0:
                    {
                        XCTAssert(event.isEncrypted);
                        XCTAssertEqual(event.eventType, MXEventTypeRoomEncrypted);
                        XCTAssertNil(event.content[kMXMessageBodyKey]);

                        XCTAssert(event.decryptionError);
                        XCTAssertEqualObjects(event.decryptionError.domain, MXDecryptingErrorDomain);
                        XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorEncryptionNotEnabledCode);
                        XCTAssertEqualObjects(event.decryptionError.localizedDescription, MXDecryptingErrorEncryptionNotEnabledReason);

                        [roomFromBobPOV sendTextMessage:@"Hello I'm Bob!" threadId:nil success:nil failure:nil];
                        break;
                    }

                    case 1:
                    {
                        XCTAssertFalse(event.isEncrypted);

                        [expectation fulfill];
                        break;
                    }

                    default:
                        break;
                }

            }];

        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma marks - New device tests

// As the web client, we should not be able to decrypt an event in the past
// when using a new device.
- (void)testAliceDecryptOldMessageWithANewDeviceInACryptedRoom
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *message = @"Hello myself!";

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        [roomFromAlicePOV sendTextMessage:message threadId:nil success:^(NSString *eventId) {

            // Relog alice to simulate a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSession:self session:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                MXRoom *roomFromAlicePOV2 = [aliceSession2 roomWithRoomId:roomId];

                XCTAssert(roomFromAlicePOV2.summary.isEncrypted, @"The room must still appear as encrypted");

                [aliceSession2 eventWithEventId:roomFromAlicePOV2.summary.lastMessage.eventId
                                         inRoom:roomFromAlicePOV2.roomId
                                        success:^(MXEvent *event) {
                    
                    XCTAssert(event.isEncrypted);

                    XCTAssertNil(event.clearEvent);
                    XCTAssert(event.decryptionError);
                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);

                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up initial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testAliceAndBobWithNewDevice
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                NSString *messageFromAlice = @"Hello I'm still Alice!";

                // Relog bob to simulate a new device
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                [matrixSDKTestsData relogUserSession:self session:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                    MXRoom *roomFromBob2POV = [bobSession2 roomWithRoomId:roomId];

                    [roomFromBob2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                            [expectation fulfill];

                        }];
                    }];
                }];

                // Wait a bit before sending the 2nd message to Bob with his 2 devices.
                // We wait until Alice receives the new device information event. This cannot be more accurate.
                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:aliceSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

                    [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                }];

            }];
        }];

        // 1st message to Bob and his single device
        [roomFromAlicePOV sendTextMessage:@"Hello I'm Alice!" threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testAliceAndBlockedBob
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        NSArray *aliceMessages = @[
                                   @"Hello I'm Alice!",
                                   @"Hello I'm still Alice but you cannot read this!",
                                   @"Hello I'm still Alice and you can read this!"
                                   ];

        __block NSUInteger messageCount = 0;

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                switch (messageCount++)
                {
                    case 0:
                    {
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[0] senderSession:aliceSession]);

                        // Make Alice block Bob
                        [aliceSession.crypto setDeviceVerification:MXDeviceBlocked
                                                         forDevice:bobSession.matrixRestClient.credentials.deviceId
                                                            ofUser:bobSession.myUser.userId
                                                           success:
                         ^{

                             [roomFromAlicePOV sendTextMessage:aliceMessages[1] threadId:nil success:nil failure:^(NSError *error) {
                                 XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                 [expectation fulfill];
                             }];

                         } failure:^(NSError *error) {
                             XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                             [expectation fulfill];
                         }];

                        break;
                    }

                    case 1:
                    {
                        // Bob must be not able to decrypt the 2nd message
                        XCTAssertEqual(event.eventType, MXEventTypeRoomEncrypted);
                        XCTAssertNil(event.clearEvent);
                        XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);

                        // Make Alice unblock Bob
                        [aliceSession.crypto setDeviceVerification:MXDeviceUnverified
                                                         forDevice:bobSession.matrixRestClient.credentials.deviceId
                                                            ofUser:bobSession.myUser.userId success:
                         ^{
                             [roomFromAlicePOV sendTextMessage:aliceMessages[2] threadId:nil success:nil failure:^(NSError *error) {
                                 XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                 [expectation fulfill];
                             }];

                         } failure:^(NSError *error) {
                             XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                             [expectation fulfill];
                         }];

                        break;
                    }

                    case 2:
                    {
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[2] senderSession:aliceSession]);
                        [expectation fulfill];
                        break;
                    }

                    default:
                        break;
                }

            }];

        }];

        // 1st message to Bob
        [roomFromAlicePOV sendTextMessage:aliceMessages[0] threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

// Test method copy from MXRoomTests -testSendReplyToTextMessage
- (void)testSendReplyToTextMessage
{
    NSString *firstMessage = @"**First message!**";
    NSString *firstFormattedMessage = @"<p><strong>First message!</strong></p>";
    
    NSString *secondMessageReplyToFirst = @"**Reply to first message**";
    NSString *secondMessageFormattedReplyToFirst = @"<p><strong>Reply to first message</strong></p>";
    
    NSString *expectedSecondEventBodyStringFormat = @"> <%@> **First message!**\n\n**Reply to first message**";
    NSString *expectedSecondEventFormattedBodyStringFormat = @"<mx-reply><blockquote><a href=\"%@\">In reply to</a> <a href=\"%@\">%@</a><br><p><strong>First message!</strong></p></blockquote></mx-reply><p><strong>Reply to first message</strong></p>";
    
    NSString *thirdMessageReplyToSecond = @"**Reply to second message**";
    NSString *thirdMessageFormattedReplyToSecond = @"<p><strong>Reply to second message</strong></p>";
    
    NSString *expectedThirdEventBodyStringFormat = @"> <%@> **Reply to first message**\n\n**Reply to second message**";
    NSString *expectedThirdEventFormattedBodyStringFormat = @"<mx-reply><blockquote><a href=\"%@\">In reply to</a> <a href=\"%@\">%@</a><br><p><strong>Reply to first message</strong></p></blockquote></mx-reply><p><strong>Reply to second message</strong></p>";
    
    MXSendReplyEventDefaultStringLocalizer *defaultStringLocalizer = [MXSendReplyEventDefaultStringLocalizer new];
    
    __block NSUInteger successFullfillCount = 0;
    NSUInteger expectedSuccessFulfillCount = 2; // Bob and Alice have finished their tests
    
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        void (^testExpectationFullfillIfComplete)(void) = ^() {
            successFullfillCount++;
            if (successFullfillCount == expectedSuccessFulfillCount)
            {
                [expectation fulfill];
            }
        };
        
        __block NSUInteger messageCount = 0;
        __block NSUInteger messageCountFromAlice = 0;
        
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // Listen to messages from Bob POV
        [roomFromBobPOV listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            messageCount++;
            
            if (messageCount == 1)
            {
                __block MXEvent *localEchoEvent = nil;
                
                // Reply to first message
                [roomFromBobPOV sendReplyToEvent:event withTextMessage:secondMessageReplyToFirst formattedTextMessage:secondMessageFormattedReplyToFirst stringLocalizer:defaultStringLocalizer threadId:nil localEcho:&localEchoEvent success:^(NSString *eventId) {
                    MXLogDebug(@"Send reply to first message with success");
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                XCTAssertNotNil(localEchoEvent);
                
                NSString *firstEventId = event.eventId;
                NSString *firstEventSender = event.sender;
                
                NSString *secondEventBody = localEchoEvent.content[kMXMessageBodyKey];
                NSString *secondEventFormattedBody = localEchoEvent.content[@"formatted_body"];
                NSString *secondEventRelatesToEventId = localEchoEvent.content[kMXEventRelationRelatesToKey][kMXEventContentRelatesToKeyInReplyTo][kMXEventContentRelatesToKeyEventId];
                NSString *secondWiredEventRelatesToEventId = localEchoEvent.relatesTo.inReplyTo.eventId;
                
                NSString *permalinkToUser = [MXTools permalinkToUserWithUserId:firstEventSender];
                NSString *permalinkToEvent = [MXTools permalinkToEvent:firstEventId inRoom:roomId];
                
                NSString *expectedSecondEventBody = [NSString stringWithFormat:expectedSecondEventBodyStringFormat, firstEventSender];
                NSString *expectedSecondEventFormattedBody = [NSString stringWithFormat:expectedSecondEventFormattedBodyStringFormat, permalinkToEvent, permalinkToUser, firstEventSender];
                
                XCTAssertEqualObjects(secondEventBody, expectedSecondEventBody);
                XCTAssertEqualObjects(secondEventFormattedBody, expectedSecondEventFormattedBody);
                XCTAssertEqualObjects(secondEventRelatesToEventId, firstEventId);
                XCTAssertEqualObjects(secondWiredEventRelatesToEventId, firstEventId);
            }
            else if (messageCount == 2)
            {
                __block MXEvent *localEchoEvent = nil;
                
                // Reply to second message, which was also a reply
                [roomFromBobPOV sendReplyToEvent:event withTextMessage:thirdMessageReplyToSecond formattedTextMessage:thirdMessageFormattedReplyToSecond stringLocalizer:defaultStringLocalizer threadId:nil localEcho:&localEchoEvent success:^(NSString *eventId) {
                    MXLogDebug(@"Send reply to second message with success");
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                XCTAssertNotNil(localEchoEvent);
                
                NSString *secondEventId = event.eventId;
                NSString *secondEventSender = event.sender;
                
                NSString *thirdEventBody = localEchoEvent.content[kMXMessageBodyKey];
                NSString *thirdEventFormattedBody = localEchoEvent.content[@"formatted_body"];
                NSString *thirdEventRelatesToEventId = localEchoEvent.content[kMXEventRelationRelatesToKey][kMXEventContentRelatesToKeyInReplyTo][kMXEventContentRelatesToKeyEventId];
                NSString *thirdWiredEventRelatesToEventId = localEchoEvent.relatesTo.inReplyTo.eventId;
                
                NSString *permalinkToUser = [MXTools permalinkToUserWithUserId:secondEventSender];
                NSString *permalinkToEvent = [MXTools permalinkToEvent:secondEventId inRoom:roomId];
                
                NSString *expectedThirdEventBody = [NSString stringWithFormat:expectedThirdEventBodyStringFormat, secondEventSender];
                NSString *expectedThirdEventFormattedBody = [NSString stringWithFormat:expectedThirdEventFormattedBodyStringFormat, permalinkToEvent, permalinkToUser, secondEventSender];
                
                
                XCTAssertEqualObjects(thirdEventBody, expectedThirdEventBody);
                XCTAssertEqualObjects(thirdEventFormattedBody, expectedThirdEventFormattedBody);
                XCTAssertEqualObjects(thirdEventRelatesToEventId, secondEventId);
                XCTAssertEqualObjects(thirdWiredEventRelatesToEventId, secondEventId);
            }
            else
            {
                testExpectationFullfillIfComplete();
            }
        }];
        
        __block NSString *firstEventId;
        __block NSString *secondEventId;
        
        // Listen to messages from Alice POV
        [roomFromAlicePOV listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            messageCountFromAlice++;

            if (messageCountFromAlice == 1)
            {
                firstEventId = event.eventId;
            }
            else if (messageCountFromAlice == 2)
            {
                secondEventId = event.eventId;
                NSString *secondWiredEventRelatesToEventId = event.relatesTo.inReplyTo.eventId;

                XCTAssertEqualObjects(secondWiredEventRelatesToEventId, firstEventId);
            }
            else
            {
                NSString *thirdWiredEventRelatesToEventId = event.relatesTo.inReplyTo.eventId;

                XCTAssertEqualObjects(thirdWiredEventRelatesToEventId, secondEventId);
                
                testExpectationFullfillIfComplete();
            }
        }];
        
        // Send first message
        [roomFromBobPOV sendTextMessage:firstMessage formattedText:firstFormattedMessage threadId:nil localEcho:nil success:^(NSString *eventId) {
            MXLogDebug(@"Send first message with success");
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test the encryption for an invited member when the room history visibility is enabled for invited members.
- (void)testInvitedMemberInACryptedRoom
{
    [matrixSDKTestsE2EData doE2ETestWithAliceByInvitingBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *messageFromAlice = @"Hello I'm Alice!";
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // We force the room history visibility for INVITED members.
        [aliceSession.matrixRestClient setRoomHistoryVisibility:roomId historyVisibility:kMXRoomHistoryVisibilityInvited success:^{
            
            // Send a first message whereas Bob is invited
            [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
            
            // Listen to the room messages in order to check that Bob is able to read the message sent by Alice
            [bobSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                
                if ([event.roomId isEqualToString:roomId])
                {
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                    [expectation fulfill];
                }
                
            }];
            
            [bobSession joinRoom:roomId viaServers:nil success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot join a room - error: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test the encryption when the room history visibility is disabled for invited members.
- (void)testInvitedMemberInACryptedRoom2
{
    [matrixSDKTestsE2EData doE2ETestWithAliceByInvitingBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *messageFromAlice = @"Hello I'm Alice!";
        NSString *message2FromAlice = @"I'm still Alice!";
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // We force the room history visibility for JOINED members.
        [aliceSession.matrixRestClient setRoomHistoryVisibility:roomId historyVisibility:kMXRoomHistoryVisibilityJoined success:^{

            // Send a first message whereas Bob is invited
            [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:^(NSString *eventId) {

                // Make sure Bob joins room after the first message was sent.
                [bobSession joinRoom:roomId viaServers:nil success:^(MXRoom *room) {
                    // Send a second message to Bob who just joins the room
                    [roomFromAlicePOV sendTextMessage:message2FromAlice threadId:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot join a room - error: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
            
            // Listen to the room messages in order to check that Bob is able to read only the second message sent by Alice
            [bobSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                
                if ([event.roomId isEqualToString:roomId])
                {
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message2FromAlice senderSession:aliceSession]);
                    [expectation fulfill];
                }
                
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark - Edge cases
        
- (void)testReplayAttack
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                // Try to decrypt the event again
                [event setClearData:nil];
                [bobSession decryptEvents:@[event] inTimeline:liveTimeline.timelineId onComplete:^(NSArray<MXEvent *> *failedEvents) {
                    
                    // It must fail
                    XCTAssertEqual(failedEvents.count, 1);
                    XCTAssert(event.decryptionError);
                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorDuplicateMessageIndexCode);
                    XCTAssertNil(event.clearEvent);
                    
                    // Decrypting it with no replay attack mitigation must still work
                    [bobSession decryptEvents:@[event] inTimeline:nil onComplete:^(NSArray<MXEvent *> *failedEvents) {
                        XCTAssertEqual(failedEvents.count, 0);
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                        
                        [expectation fulfill];
                    }];
                }];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testReplayAttackForEventEdits
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                // Turn the event into an edit event (not directly rendered) and try to decrypt again
                NSMutableDictionary *content = event.wireContent.mutableCopy;
                content[kMXEventRelationRelatesToKey] = @{
                    kMXEventContentRelatesToKeyRelationType: MXEventRelationTypeReplace
                };
                event.wireContent = content;
                [event setClearData:nil];
                
                [bobSession decryptEvents:@[event] inTimeline:liveTimeline.timelineId onComplete:^(NSArray<MXEvent *> *failedEvents) {
                    
                    // The first edited event with the same content is decrypted successfuly and not treated as a replay attack
                    XCTAssertEqual(failedEvents.count, 0);
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                    [event setClearData:nil];
                    
                    // Decrypt the same edit event again, this time failing as a replay attack
                    [bobSession decryptEvents:@[event] inTimeline:liveTimeline.timelineId onComplete:^(NSArray<MXEvent *> *failedEvents) {
                        XCTAssertEqual(failedEvents.count, 1);
                        XCTAssert(event.decryptionError);
                        XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorDuplicateMessageIndexCode);
                        XCTAssertNil(event.clearEvent);
                        
                        [expectation fulfill];
                    }];
                }];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

#pragma mark - Tests for reproducing bugs

// Test for https://github.com/vector-im/riot-ios/issues/913
- (void)testFirstMessageSentWhileSessionWasPaused
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        // Pause the session outside this callback
        dispatch_async(dispatch_get_main_queue(), ^{
            [bobSession pause];

            [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:^(NSString *eventId) {

                __block BOOL testDone = NO;

                [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                        testDone = YES;

                    }];
                }];

                [bobSession resume:^{
                    XCTAssert(testDone);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        });
    }];
}

// Test that clearing devices keys makes crypto work again:
// - Alice and Bob are in an encrypted room

// - Do a hack to make Alice forget Bob's device (this mimics a buggy situation that may still happen in real life).
// - Alice sends a message to Bob -> Bob receives an UISI for this message.

// - Alice does a new MXSession (which is what apps do when clearing cache). This leads to an initial /sync.
// - Alice sends a message to Bob -> Bob still receives an UISI for this message.

// - Alice resets her devices keys
// - Alice does a new MXSession (which is what apps do when clearing cache). This leads to an initial /sync.
// - Alice sends a message to Bob -> Bob can decrypt this message.

// TODO: Disabled because with the last rework on device list tracking logic (the one with deviceStatusTracking),
// it became impossible to simulate a UISI.
//- (void)testClearCache
//{
//    NSArray *aliceMessages = @[
//                               @"I am alice but I do not have bob keys",
//                               @"I am alice but I do not have bob keys even after full initial /sync",
//                               @"I'm still Alice and I have bob keys now"
//                               ];
//
//    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
//
//        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
//
//        __block MXSession *aliceSession2;
//        __block MXSession *aliceSession3;
//        MXRestClient *aliceRestClient = aliceSession.matrixRestClient;
//
//        // Hack
//        [aliceSession.crypto.store storeDevicesForUser:bobSession.myUser.userId devices:[NSDictionary dictionary]];
//
//        __block NSUInteger messageCount = 0;
//        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
//
//            switch (messageCount++)
//            {
//                case 0:
//                {
//                    XCTAssert(event.isEncrypted, "Bob must get an UISI because Alice did have his devices keys");
//                    XCTAssertNil(event.clearEvent);
//                    XCTAssert(event.decryptionError);
//                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);
//
//                    [aliceSession close];
//
//                    aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
//                    [matrixSDKTestsData retain:aliceSession2];
//
//                    [aliceSession2 start:^{
//
//                        aliceSession2.crypto.warnOnUnknowDevices = NO;
//
//                        MXRoom *roomFromAlicePOV2 = [aliceSession2 roomWithRoomId:roomId];
//                        [roomFromAlicePOV2 sendTextMessage:aliceMessages[1] success:nil failure:^(NSError *error) {
//                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                            [expectation fulfill];
//                        }];
//
//                    } failure:^(NSError *error) {
//                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                        [expectation fulfill];
//                    }];
//
//                    break;
//                }
//
//                case 1:
//                {
//                    XCTAssert(event.isEncrypted, "Bob must get an UISI because Alice did have his devices keys even after a full initial sync");
//                    XCTAssertNil(event.clearEvent);
//                    XCTAssert(event.decryptionError);
//                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);
//
//
//                    [aliceSession2.crypto resetDeviceKeys];
//                    [aliceSession2 close];
//
//                    aliceSession3 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
//                    [matrixSDKTestsData retain:aliceSession3];
//
//                    [aliceSession3 start:^{
//
//                        aliceSession3.crypto.warnOnUnknowDevices = NO;
//
//                        MXRoom *roomFromAlicePOV3 = [aliceSession3 roomWithRoomId:roomId];
//                        [roomFromAlicePOV3 sendTextMessage:aliceMessages[2] success:nil failure:^(NSError *error) {
//                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                            [expectation fulfill];
//                        }];
//
//                    } failure:^(NSError *error) {
//                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                        [expectation fulfill];
//                    }];
//
//                    break;
//                }
//
//                case 2:
//                {
//                    XCTAssert(event.clearEvent, @"Bob must now be able to decrypt Alice's message");
//
//                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[2] senderSession:aliceSession3]);
//
//                    [expectation fulfill];
//                    break;
//                }
//            }
//        }];
//
//        MXRoom *roomFromAlicePOV1 = [aliceSession roomWithRoomId:roomId];
//        [roomFromAlicePOV1 sendTextMessage:aliceMessages[0] success:nil failure:^(NSError *error) {
//            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//            [expectation fulfill];
//        }];
//    }];
//}

#pragma mark - import/export

- (void)testImportRoomKeysWithWrongPassword
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        [bobSession.crypto exportRoomKeysWithPassword:@"APassword" success:^(NSData *keyFile) {

            [bobSession.crypto importRoomKeys:keyFile withPassword:@"AnotherPassword" success:^(NSUInteger total, NSUInteger imported) {

                XCTFail(@"The import must fail when using a wrong password");
                [expectation fulfill];

            } failure:^(NSError *error) {

                XCTAssert(error);
                XCTAssertEqualObjects(error.domain, MXMegolmExportEncryptionErrorDomain);
                XCTAssertEqual(error.code, MXMegolmExportErrorAuthenticationFailedCode);

                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

/*
 Check kMXCryptoRoomKeyRequestNotification and data at that moment.

 1 - Create a first MXSession for Alice with a device
 2 - Close it by keeping her credentials
 3 - Recreate a second MXSession, aliceSession2, for Alice with a new device
 4 - Send a message to a room with aliceSession2
 5 - Instantiante a MXRestclient, alice1MatrixRestClient, with the credentials of
     the 1st device (kept at step #2)
 6 - Make alice1MatrixRestClient make a fake room key request for the message sent at step #4
 7 - aliceSession2 must receive kMXCryptoRoomKeyRequestNotification
 8 - Do checks
 9 - Check [MXSession.crypto pendingKeyRequests:] result
 10 - Check [MXSession.crypto acceptAllPendingKeyRequestsFromUser:] with a wrong userId:deviceId pair
 11 - Check [MXSession.crypto acceptAllPendingKeyRequestsFromUser:] with a valid userId:deviceId pair
 */

#pragma mark - Outbound Group Session


// Test encryption algorithm change with a blank m.room.encryption event
// - Alice and bob in a megolm encrypted room
// - Send a blank m.room.encryption event
// -> The room should be still marked as encrypted
// - Send a message
// -> The room algorithm is restored to the one present in Crypto store
// -> It is possible to send a message
// -> The message must be e2e encrypted
- (void)testEncryptionAlgorithmChange
{
    // - Alice and bob in a megolm encrypted room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRoom *roomFromAlicePOV= [aliceSession roomWithRoomId:roomId];
        
        // - Send a blank m.room.encryption event
        [roomFromAlicePOV sendStateEventOfType:kMXEventTypeStringRoomEncryption
                                       content:@{ }
                                      stateKey:nil
                                       success:nil
                                       failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
        __block id listener = [roomFromAlicePOV listenToEventsOfTypes:@[kMXEventTypeStringRoomEncryption] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            
            [roomFromAlicePOV removeListener:listener];
            
            [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                
                // -> The room should be still marked as encrypted
                XCTAssertTrue(liveTimeline.state.isEncrypted);
                XCTAssertEqual(liveTimeline.state.encryptionAlgorithm.length, 0);   // with a nil algorithm
                XCTAssertTrue(roomFromAlicePOV.summary.isEncrypted);
                
                // -> It is still possible to send a message because crypto will use backup algorithm (which can never be removed)
                [roomFromAlicePOV sendTextMessage:@"An encrypted message" threadId:nil success:^(NSString *eventId) {
                    
                    // - Fix e2e algorithm in the room
                    [roomFromAlicePOV enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{
                        
                        // -> The room should be still marked as encrypted with the right algorithm
                        XCTAssertTrue(liveTimeline.state.isEncrypted);
                        XCTAssertEqualObjects(liveTimeline.state.encryptionAlgorithm, kMXCryptoMegolmAlgorithm);
                        XCTAssertTrue(roomFromAlicePOV.summary.isEncrypted);
                        
                        // -> It must be possible to send message again
                        [roomFromAlicePOV sendTextMessage:@"An encrypted message" threadId:nil success:nil failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot send message");
                    [expectation fulfill];
                }];
                
                __block NSInteger recievedMessages = 0;
                [roomFromAlicePOV listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    // -> The message must be e2e encrypted
                    XCTAssertTrue(event.isEncrypted);
                    XCTAssertEqualObjects(event.wireContent[@"algorithm"], kMXCryptoMegolmAlgorithm);
                    
                    recievedMessages += 1;
                    if (recievedMessages == 2) {
                        [expectation fulfill];
                    }
                }];
            }];
        }];
    }];
}

// Check MXRoom.checkEncryptionState can autofix the disabling of E2E encryption
// For dev purpose, it is interesting to comment https://github.com/matrix-org/matrix-ios-sdk/blob/610db96cf8e470770f92d6afc40bc4332b240da4/MatrixSDK/Data/MXRoomSummary.m#L552
//
// - Alice is in an encrypted room
// - Try to corrupt summary.isEncrypted
// - Send a message
// -> The message must be e2e encrypted
- (void)testBadSummaryIsEncryptedState
{
    // - Alice is in an encrypted room
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *message = @"Hello myself!";
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);
        
        // - Try to corrupt summary.isEncrypted
        roomFromAlicePOV.summary.isEncrypted = NO;
        [roomFromAlicePOV.summary save:YES];
        
        // - Send a message
        // Add some delay because there are some dispatch_asyncs in the crypto code
        // This is a hole but a matter of few ms. This should be fine for real life
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [roomFromAlicePOV sendTextMessage:message threadId:nil success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        });
        
        /// -> The message must be e2e encrypted
        [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                
                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession]);
                
                [expectation fulfill];
            }];
        }];
    }];
}

#pragma mark Helpers

/**
 Manually restart the session and wait until a given room has finished syncing all state
 
 Note: there is a lot of state update and sync going on when the session is started,
 and integration tests often assume given state before it has finished updating. To solve
 that this helper method makes the best guesses by observing global notifications
 and adding small delays to ensure all updates have really completed.
 */
- (void)restartSession:(MXSession *)session
      waitingForRoomId:(NSString *)roomId
               success:(void (^)(MXRoom *))success
               failure:(void (^)(NSError *))failure
{
    __block id observer;
    
    // First start the session
    [session start:^{
        
        // Wait until we know that the room has actually been created
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification
                                                                     object:nil
                                                                      queue:[NSOperationQueue mainQueue]
                                                                 usingBlock:^(NSNotification * notification) {
            if ([notification.userInfo[kMXSessionNotificationRoomIdKey] isEqualToString:roomId])
            {
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                
                MXRoom *room = [session roomWithRoomId:roomId];
                if (room)
                {
                    // Now wait until this room reports sync completion
                    observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification
                                                                                 object:nil
                                                                                  queue:[NSOperationQueue mainQueue]
                                                                             usingBlock:^(NSNotification * notification) {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        
                        // Even when sync completed, there are actually still a few async updates that happen (i.e. the notification
                        // fires too early), so have to add some small arbitrary delay.
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            success(room);
                        });
                    }];
                }
                else
                {
                    NSError *error = [NSError errorWithDomain:@"MatrixSDKTestsData" code:0 userInfo:@{
                        @"reason": @"Missing room"
                    }];
                    failure(error);
                }
            }
        
        }];
    } failure:failure];
}

@end

#pragma clang diagnostic pop

#endif
