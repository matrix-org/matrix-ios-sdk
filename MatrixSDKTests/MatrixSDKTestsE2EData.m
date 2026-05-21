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

#import "MatrixSDKTestsE2EData.h"

#ifdef MX_CRYPTO

#import "MXSession.h"
#import "MXMegolmExportEncryption.h"
#import "MXFileStore.h"
#import "MXNoStore.h"
#import "MXTools.h"
#import "MatrixSDKTestsSwiftHeader.h"

@interface MatrixSDKTestsE2EData ()

@property (nonatomic, weak) MatrixSDKTestsData *matrixSDKTestsData;

@end

@implementation MatrixSDKTestsE2EData
@synthesize matrixSDKTestsData, messagesFromAlice, messagesFromBob;

- (instancetype)initWithMatrixSDKTestsData:(MatrixSDKTestsData *)theMatrixSDKTestsData
{
    self = [super init];
    if (self)
    {
        matrixSDKTestsData = theMatrixSDKTestsData;

        messagesFromAlice = @[
                              @"0 - Hello I'm Alice!",
                              @"4 - Go!"
                              ];

        messagesFromBob = @[
                            @"1 - Hello I'm Bob!",
                            @"2 - Isn't life grand?",
                            @"3 - Let's go to the opera."
                            ];
    }
    return self;
}


#pragma mark - Scenarii
- (void)doE2ETestWithBobAndAlice:(XCTestCase*)testCase
                     readyToTest:(void (^)(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation))readyToTest
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
    MXKeyProvider.sharedInstance.delegate = [[MXKeyProviderStub alloc] init];

    [matrixSDKTestsData doMXSessionTestWithBob:testCase readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {

            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
            MXKeyProvider.sharedInstance.delegate = nil;

            readyToTest(bobSession, aliceSession, expectation);

        }];
    }];
}

- (void)doE2ETestWithAliceInARoom:(XCTestCase*)testCase
                      readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doE2ETestWithAliceInARoom:testCase andStore:[[MXNoStore alloc] init] readyToTest:readyToTest];
}

- (void)doE2ETestWithAliceInARoom:(XCTestCase *)testCase andStore:(id<MXStore>)store readyToTest:(void (^)(MXSession *, NSString *, XCTestExpectation *))readyToTest
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
    MXKeyProvider.sharedInstance.delegate = [[MXKeyProviderStub alloc] init];

    [matrixSDKTestsData doMXSessionTestWithAlice:testCase andStore:store
                                     readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {

        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
        MXKeyProvider.sharedInstance.delegate = nil;

        [aliceSession createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXRoom *room) {

            [room enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                readyToTest(aliceSession, room.roomId, expectation);

            } failure:^(NSError *error) {
                [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot enable encryption in room - error: %@", error];
            }];

        } failure:^(NSError *error) {
            [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot create a room - error: %@", error];
        }];
        
    }];
}

- (void)doE2ETestWithAliceByInvitingBobInARoom:(XCTestCase*)testCase
                             cryptedBob:(BOOL)cryptedBob
                    warnOnUnknowDevices:(BOOL)warnOnUnknowDevices
                            readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doE2ETestWithAliceByInvitingBobInARoom:testCase cryptedBob:cryptedBob warnOnUnknowDevices:warnOnUnknowDevices aliceStore:[[MXNoStore alloc] init] bobStore:[[MXNoStore alloc] init] readyToTest:readyToTest];
}

- (void)doE2ETestWithAliceAndBobInARoomWithCryptedMessages:(XCTestCase*)testCase
                                                cryptedBob:(BOOL)cryptedBob
                                               readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doE2ETestWithAliceAndBobInARoom:testCase cryptedBob:cryptedBob warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        __block NSUInteger messagesCount = 0;

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                if (++messagesCount == 5)
                {
                    readyToTest(aliceSession, bobSession, roomId, expectation);
                }
            }];
        }];


        // Send messages in expected order
        [roomFromAlicePOV sendTextMessage:messagesFromAlice[0] threadId:nil success:^(NSString *eventId) {

            [roomFromBobPOV sendTextMessage:messagesFromBob[0] threadId:nil success:^(NSString *eventId) {

                [roomFromBobPOV sendTextMessage:messagesFromBob[1] threadId:nil success:^(NSString *eventId) {

                    [roomFromBobPOV sendTextMessage:messagesFromBob[2] threadId:nil success:^(NSString *eventId) {

                        [roomFromAlicePOV sendTextMessage:messagesFromAlice[1] threadId:nil success:nil failure:nil];

                    } failure:nil];

                } failure:nil];

            } failure:nil];

        } failure:^(NSError *error) {
            [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];

    }];
}

- (void)loginUserOnANewDevice:(XCTestCase*)testCase
                  credentials:(MXCredentials*)credentials
                 withPassword:(NSString*)password
                   onComplete:(void (^)(MXSession *newSession))onComplete
{
    [self loginUserOnANewDevice:testCase
                    credentials:credentials
                   withPassword:password
                          store:[[MXNoStore alloc] init]
                     onComplete:onComplete];
}

- (void)loginUserOnANewDevice:(XCTestCase*)testCase
                  credentials:(MXCredentials*)credentials
                 withPassword:(NSString*)password
                        store:(id<MXStore>)store
                   onComplete:(void (^)(MXSession *newSession))onComplete
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
    MXKeyProvider.sharedInstance.delegate = [[MXKeyProviderStub alloc] init];
    
    MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:credentials.homeServer
                                        andOnUnrecognizedCertificateBlock:nil];
    [matrixSDKTestsData retain:mxRestClient];
    
    [mxRestClient loginWithLoginType:kMXLoginFlowTypePassword username:credentials.userId password:password success:^(MXCredentials *credentials2) {
        
        MXRestClient *mxRestClient2 = [[MXRestClient alloc] initWithCredentials:credentials2 andOnUnrecognizedCertificateBlock:nil andPersistentTokenDataHandler:nil andUnauthenticatedHandler:nil];
        [matrixSDKTestsData retain:mxRestClient2];
        
        MXSession *newSession = [[MXSession alloc] initWithMatrixRestClient:mxRestClient2];
        [matrixSDKTestsData retain:newSession];
        
        MXWeakify(newSession);
        [newSession setStore:store success:^{
            MXStrongifyAndReturnIfNil(newSession);
            [newSession start:^{
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
                MXKeyProvider.sharedInstance.delegate = nil;
                
                onComplete(newSession);
                
            } failure:^(NSError *error) {
                [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
            }];
        } failure:^(NSError *error) {
            [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up store - error: %@", error];
        }];
        
    } failure:^(NSError *error) {
        [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot log %@ in again. Error: %@", credentials.userId , error];
    }];
}


#pragma mark - Cross-signing

// Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
// - Create Alice & Bob accounts
// - Bootstrap cross-signing x2
// - Make Alice2 aware of Bob
// - Make each Alice devices trust each other
// - Make Alice & Bob trust each other
- (void)doTestWithBobAndAliceWithTwoDevicesAllTrusted:(XCTestCase*)testCase
                                          readyToTest:(void (^)(MXSession *bobSession, MXSession *aliceSession1, MXSession *aliceSession2, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice & Bob accounts
    [self doE2ETestWithAliceAndBobInARoom:testCase
                                                cryptedBob:YES
                                       warnOnUnknowDevices:YES
                                                aliceStore:[[MXNoStore alloc] init]
                                                  bobStore:[[MXNoStore alloc] init]
                                               readyToTest:^(MXSession *aliceSession1, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation)
     {
         // - Bootstrap cross-signing x2
         [aliceSession1.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
             [bobSession.crypto.crossSigning setupWithPassword:MXTESTS_BOB_PWD success:^{
                 
                 [self loginUserOnANewDevice:testCase credentials:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                     
                     NSString *aliceUserId = aliceSession1.matrixRestClient.credentials.userId;
                     NSString *bobUserId = bobSession.matrixRestClient.credentials.userId;
                     
                     NSString *aliceSession1DeviceId = aliceSession1.matrixRestClient.credentials.deviceId;
                     NSString *aliceSession2DeviceId = aliceSession2.matrixRestClient.credentials.deviceId;
                     
                     // - Make Alice2 aware of Bob
                     [aliceSession2.crypto downloadKeys:@[bobUserId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                         
                         // - Make each Alice devices trust each other
                         // This simulates a self verification and trigger cross-signing behind the shell
                         [aliceSession1.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession2DeviceId ofUser:aliceUserId success:^{
                             [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession1DeviceId ofUser:aliceUserId success:^{
                                 
                                 // - Make Alice & Bob trust each other
                                 [aliceSession1.crypto.crossSigning signUserWithUserId:bobUserId success:^{
                                     [bobSession.crypto.crossSigning signUserWithUserId:aliceUserId success:^{
                                         
                                         // Wait a bit to make background requests for cross-signing happen
                                         dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                             readyToTest(aliceSession1, aliceSession2, bobSession, roomId, expectation);
                                         });
                                         
                                     } failure:^(NSError *error) {
                                         [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
                                         [expectation fulfill];
                                     }];
                                     
                                 } failure:^(NSError *error) {
                                     [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
                                     [expectation fulfill];
                                 }];
                                 
                             } failure:^(NSError *error) {
                                 [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
                                 [expectation fulfill];
                             }];
                         } failure:^(NSError *error) {
                             [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
                             [expectation fulfill];
                         }];
                         
                     } failure:^(NSError *error) {
                         [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
                         [expectation fulfill];
                     }];
                 }];
                 
             } failure:^(NSError *error) {
                 [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
                 [expectation fulfill];
             }];
             
         } failure:^(NSError *error) {
             [matrixSDKTestsData breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
             [expectation fulfill];
         }];
     }];
}


@end

#endif // MX_CRYPTO
