/*
 Copyright 2014 OpenMarket Ltd
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

#import "MatrixSDKTestsData.h"

#import "MXSDKOptions.h"
#import "MXRestClient.h"
#import "MXError.h"
#import "MXNoStore.h"
#import "MatrixSDKTestsSwiftHeader.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

/*
 Out of the box, the tests are supposed to be run with the iOS simulator attacking
 a test home server running on the same Mac machine.
 The reason is that the simulator can access to the home server running on the Mac
 via localhost. So everyone can use a localhost HS url that works everywhere.
 
 Here, we use one of the home servers launched by the ./demo/start.sh script
 */
NSString *const kMXTestsHomeServerURL = @"http://localhost:8080";
NSString *const kMXTestsHomeServerHttpsURL = @"https://localhost:8481";

NSString * const kMXTestsAliceDisplayName = @"mxAlice";
NSString * const kMXTestsAliceAvatarURL = @"mxc://matrix.org/kciiXusgZFKuNLIfLqmmttIQ";


@interface MatrixSDKTestsData ()

@property (nonatomic, strong, readonly)NSDate *startDate;

@property (nonatomic, strong, readonly) NSMutableArray <NSObject*> *retainedObjects;

@property (nonatomic, strong) MXCredentials *aliceCredentials;
@property (nonatomic, strong) MXCredentials *bobCredentials;

@property (nonatomic, strong) NSString *thePublicRoomId;
@property (nonatomic, strong) NSString *thePublicRoomAlias;

@end

@implementation MatrixSDKTestsData

+ (void)load
{
    // Be sure there is no open MXSession instances when ending a test
    [TestObserver.shared trackMXSessions];
}

- (id)init
{
    if (self = [super init])
    {
        _startDate = [NSDate date];
        _retainedObjects = [NSMutableArray array];
        _autoCloseMXSessions = YES;
    }
    
    return self;
}

- (void)dealloc
{
    [self releaseRetainedObjects];
}

- (void)getBobCredentials:(XCTestCase*)testCase
              readyToTest:(void (^)(void))readyToTest
{
    if (self.bobCredentials)
    {
        // Credentials are already here, they are ready
        readyToTest();
    }
    else
    {
        // Use a different Bob each time so that tests are independent
        NSString *bobUniqueUser = [NSString stringWithFormat:@"%@-%@", MXTESTS_BOB, [[NSUUID UUID] UUIDString]];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                            andOnUnrecognizedCertificateBlock:nil];
        [self retain:mxRestClient];

        // First, try register the user
        MXHTTPOperation *operation = [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:bobUniqueUser password:MXTESTS_BOB_PWD success:^(MXCredentials *credentials) {

            self.bobCredentials = credentials;
            readyToTest();
            
        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Bob in to get his keys
                [mxRestClient loginWithLoginType:kMXLoginFlowTypeDummy username:bobUniqueUser password:MXTESTS_BOB_PWD success:^(MXCredentials *credentials) {
                    
                    self.bobCredentials = credentials;
                    readyToTest();
                    
                } failure:^(NSError *error) {
                    [self breakTestCase:testCase reason:@"Cannot log mxBOB in"];
                }];
            }
            else
            {
                [self breakTestCase:testCase reason:@"Cannot create mxBOB account. Make sure the homeserver at %@ is running", mxRestClient.homeserver];
            }
        }];
        operation.maxNumberOfTries = 1;
    }
}

- (void)getBobMXRestClient:(XCTestCase*)testCase
               readyToTest:(void (^)(MXRestClient *))readyToTest
{
    [self getBobCredentials:testCase readyToTest:^{

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithCredentials:self.bobCredentials
                                           andOnUnrecognizedCertificateBlock:nil];
        [self retain:mxRestClient];

        readyToTest(mxRestClient);
    }];
}


- (void)doMXRestClientTestWithBob:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXRestClient *bobRestClient, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }

    [self getBobCredentials:testCase readyToTest:^{
        
        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithCredentials:self.bobCredentials
                                           andOnUnrecognizedCertificateBlock:nil];
        [self retain:mxRestClient];

        readyToTest(mxRestClient, expectation);
    }];
    
    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:60 handler:nil];
    }
}

- (void)doMXRestClientTestWithBobAndARoom:(XCTestCase*)testCase
                           readyToTest:(void (^)(MXRestClient *bobRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBob:testCase
                     readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        // Create a random room to use
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

            MXLogDebug(@"Created room %@ for %@", response.roomId, testCase.name);
            
            readyToTest(bobRestClient, response.roomId, expectation);
            
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot create a room - error: %@", error];
        }];
    }];
}

- (void)doMXRestClientTestWithBobAndAPublicRoom:(XCTestCase*)testCase
                                    readyToTest:(void (^)(MXRestClient *bobRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBob:testCase
                        readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
                            // Create a random room to use
                            [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPublic roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

                                MXLogDebug(@"Created public room %@ for %@", response.roomId, testCase.name);

                                readyToTest(bobRestClient, response.roomId, expectation);
                                
                            } failure:^(NSError *error) {
                                [self breakTestCase:testCase reason:@"Cannot create a room - error: %@", error];
                            }];
                        }];
}

- (void)doMXRestClientTestWithBobAndThePublicRoom:(XCTestCase*)testCase
                                   readyToTest:(void (^)(MXRestClient *bobRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBob:testCase readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        if (self.thePublicRoomId)
        {
            readyToTest(bobRestClient, self.thePublicRoomId, expectation);
        }
        else
        {
            // Create a public room starting with #mxPublic
            self.thePublicRoomAlias = [NSString stringWithFormat:@"mxPublic-%@", [[NSUUID UUID] UUIDString]];

            [bobRestClient createRoom:@"MX Public Room test"
                           visibility:kMXRoomDirectoryVisibilityPublic
                            roomAlias:self.thePublicRoomAlias
                                topic:@"The public room used by SDK tests"
                              success:^(MXCreateRoomResponse *response) {

                                  self.thePublicRoomId = response.roomId;
                                  readyToTest(bobRestClient, response.roomId, expectation);

                              } failure:^(NSError *error) {
                                  [self breakTestCase:testCase reason:@"Cannot create the public room - error: %@", error];
                              }];
        }

    }];
}

- (void)doMXRestClientTestInABobRoomAndANewTextMessage:(XCTestCase*)testCase
                                  newTextMessage:(NSString*)newTextMessage
                                   onReadyToTest:(void (^)(MXRestClient *bobRestClient, NSString* roomId, NSString* new_text_message_eventId, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }
    
    [self getBobMXRestClient:testCase readyToTest:^(MXRestClient *bobRestClient) {
        // Create a random room to use
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

            MXLogDebug(@"Created room %@ for %@", response.roomId, testCase.name);

            // Send the the message text in it
            [bobRestClient sendTextMessageToRoom:response.roomId threadId:nil text:newTextMessage success:^(NSString *eventId) {
                
                readyToTest(bobRestClient, response.roomId, eventId, expectation);
                
            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot set up intial test conditions"];
            }];
            
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot create a room - error: %@", error];
        }];
    }];
    
    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:60 handler:nil];
    }
}

- (void)doMXRestClientTestWithBobAndARoomWithMessages:(XCTestCase*)testCase
                                       readyToTest:(void (^)(MXRestClient *bobRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBobAndARoom:testCase
                             readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        // Add 5 messages to the room
        [self for:bobRestClient andRoom:roomId sendMessages:5 testCase:testCase success:^{
            
            readyToTest(bobRestClient, roomId, expectation);
        }];
        
    }];
}

- (void)doMXRestClientTestWihBobAndSeveralRoomsAndMessages:(XCTestCase*)testCase
                                         readyToTest:(void (^)(MXRestClient *bobRestClient, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }
    
    [self getBobMXRestClient:testCase readyToTest:^(MXRestClient *bobRestClient) {
        
        // Fill Bob's account with 5 rooms of 3 messages
        [self for:bobRestClient createRooms:5 withMessages:3 testCase:testCase success:^{
            readyToTest(bobRestClient, expectation);
        }];
    }];
    
    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:60 handler:nil];
    }
}


- (void)for:(MXRestClient *)mxRestClient2 andRoom:(NSString*)roomId sendMessages:(NSUInteger)messagesCount testCase:(XCTestCase*)testCase success:(void (^)(void))success
{
    MXLogDebug(@"sendMessages :%tu to %@", messagesCount, roomId);
    if (0 == messagesCount)
    {
        success();
    }
    else
    {
        [mxRestClient2 sendTextMessageToRoom:roomId threadId:nil text:[NSString stringWithFormat:@"Fake message sent at %.0f ms", [[NSDate date] timeIntervalSinceDate:self.startDate] * 1000]
                           success:^(NSString *eventId) {

            // Send the next message
            [self for:mxRestClient2 andRoom:roomId sendMessages:messagesCount - 1 testCase:testCase success:success];

        } failure:^(NSError *error) {
            // If the error is M_LIMIT_EXCEEDED, make sure your home server rate limit is high
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }
}

- (void)for:(MXRestClient *)mxRestClient2 createRooms:(NSUInteger)roomsCount withMessages:(NSUInteger)messagesCount testCase:(XCTestCase*)testCase success:(void (^)(void))success
{
    if (0 == roomsCount)
    {
        // The recursivity is done
        success();
    }
    else
    {
        // Create the room
        [mxRestClient2 createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

            MXLogDebug(@"Created room %@ in createRooms", response.roomId);

            // Fill it with messages
            [self for:mxRestClient2 andRoom:response.roomId sendMessages:messagesCount testCase:testCase success:^{

                // Go to the next room
                [self for:mxRestClient2 createRooms:roomsCount - 1 withMessages:messagesCount testCase:testCase success:success];
            }];
        } failure:^(NSError *error) {
            // If the error is M_LIMIT_EXCEEDED, make sure your home server rate limit is high
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }
}

- (void)doMXSessionTestWithBob:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXSession *mxSession, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBob:testCase readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [self retain:mxSession];

        [mxSession start:^{

            readyToTest(mxSession, expectation);

        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }];
}


- (void)doMXSessionTestWithBobAndARoomWithMessages:(XCTestCase*)testCase
                                       readyToTest:(void (^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBobAndARoomWithMessages:testCase readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [self retain:mxSession];
        
        [mxSession start:^{
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            readyToTest(mxSession, room, expectation);
            
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }];
}

- (void)doMXSessionTestWithBobAndThePublicRoom:(XCTestCase*)testCase
                                   readyToTest:(void (^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBobAndThePublicRoom:testCase readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [self retain:mxSession];
        
        [mxSession start:^{
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            readyToTest(mxSession, room, expectation);
            
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }];
}

- (void)doMXSessionTestWithBob:(XCTestCase *)testCase andStore:(id<MXStore>)store readyToTest:(void (^)(MXSession *, XCTestExpectation *))readyToTest
{
    [self doMXRestClientTestWithBob:testCase readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [self retain:mxSession];

        [mxSession setStore:store success:^{

            [mxSession start:^{

                readyToTest(mxSession, expectation);

            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
            }];
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }];
}

- (void)doMXSessionTestWithBobAndARoom:(XCTestCase*)testCase andStore:(id<MXStore>)store
                           readyToTest:(void (^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBob:testCase readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [self retain:mxSession];

        [bobRestClient createRoom:@"A room" visibility:nil roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

            [mxSession setStore:store success:^{

                [mxSession start:^{

                    MXRoom *room = [mxSession roomWithRoomId:response.roomId];
                    readyToTest(mxSession, room, expectation);

                } failure:^(NSError *error) {
                    [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
                }];
            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
            }];

        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }];
}


#pragma mark - mxAlice
- (void)getAliceCredentials:(XCTestCase*)testCase
                readyToTest:(void (^)(void))readyToTest
{
    if (self.aliceCredentials)
    {
        // Credentials are already here, they are ready
        readyToTest();
    }
    else
    {
        // Use a different Alice each time so that tests are independent
        NSString *aliceUniqueUser = [NSString stringWithFormat:@"%@-%@", MXTESTS_ALICE, [[NSUUID UUID] UUIDString]];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                            andOnUnrecognizedCertificateBlock:nil];
        [self retain:mxRestClient];

        // First, try register the user
        MXHTTPOperation *operation = [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:aliceUniqueUser password:MXTESTS_ALICE_PWD success:^(MXCredentials *credentials) {
            
            self.aliceCredentials = credentials;
            readyToTest();
            
        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Alice in to get his keys
                [mxRestClient loginWithLoginType:kMXLoginFlowTypeDummy username:aliceUniqueUser password:MXTESTS_ALICE_PWD success:^(MXCredentials *credentials) {

                    self.aliceCredentials = credentials;
                    readyToTest();
                    
                } failure:^(NSError *error) {
                    [self breakTestCase:testCase reason:@"Cannot log mxAlice in"];
                }];
            }
            else
            {
                [self breakTestCase:testCase reason:@"Cannot create mxAlice account"];
            }
        }];
        operation.maxNumberOfTries = 1;
    }
}

- (void)getAliceMXRestClient:(XCTestCase*)testCase
                 readyToTest:(void (^)(MXRestClient *aliceRestClient))readyToTest
{
    [self getAliceCredentials:testCase readyToTest:^{
        
        MXRestClient *aliceRestClient = [[MXRestClient alloc] initWithCredentials:self.aliceCredentials
                                                andOnUnrecognizedCertificateBlock:nil];
        [self retain:aliceRestClient];

        __block MXRestClient *aliceRestClient2 = aliceRestClient;
        
        // Set Alice displayname and avator
        [aliceRestClient setDisplayName:kMXTestsAliceDisplayName success:^{
            
            __block MXRestClient *aliceRestClient3 = aliceRestClient2;
            
            [aliceRestClient2 setAvatarUrl:kMXTestsAliceAvatarURL success:^{
                
                readyToTest(aliceRestClient3);
                
            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot set mxAlice avatar"];
            }];
            
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set mxAlice displayname"];
        }];
        
    }];
}


- (void)doMXRestClientTestWithAlice:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXRestClient *aliceRestClient, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }
    
    [self getAliceMXRestClient:testCase readyToTest:^(MXRestClient *aliceRestClient) {
        readyToTest(aliceRestClient, expectation);
    }];
    
    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:60 handler:nil];
    }
}

- (void)doMXSessionTestWithAlice:(XCTestCase *)testCase readyToTest:(void (^)(MXSession *, XCTestExpectation *))readyToTest
{
    [self doMXRestClientTestWithAlice:testCase readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        MXSession *aliceSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [self retain:aliceSession];

        [aliceSession start:^{

            readyToTest(aliceSession, expectation);

        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }];
}

- (void)doMXSessionTestWithAlice:(XCTestCase *)testCase andStore:(id<MXStore>)store readyToTest:(void (^)(MXSession *, XCTestExpectation *))readyToTest
{
    [self doMXRestClientTestWithAlice:testCase readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [self retain:mxSession];

        [mxSession setStore:store success:^{

            [mxSession start:^{

                readyToTest(mxSession, expectation);

            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
            }];
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }];
}


#pragma mark - both
- (void)doMXRestClientTestWithBobAndAliceInARoom:(XCTestCase*)testCase
                                     readyToTest:(void (^)(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBobAndARoom:testCase readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            [bobRestClient inviteUser:self.aliceCredentials.userId toRoom:roomId success:^{
                
                [aliceRestClient joinRoom:roomId viaServers:nil withThirdPartySigned:nil success:^(NSString *theRoomId) {
                    
                    readyToTest(bobRestClient, aliceRestClient, roomId, expectation);
                    
                } failure:^(NSError *error) {
                    [self breakTestCase:testCase reason:@"mxAlice cannot join room"];
                }];
                
            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot invite mxAlice"];
            }];
        }];
    }];
}

- (void)doMXSessionTestWithBobAndAliceInARoom:(XCTestCase*)testCase
                                  readyToTest:(void (^)(MXSession *bobSession, MXRestClient *aliceRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBobAndAliceInARoom:testCase readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [self retain:bobSession];

        [bobSession start:^{

            readyToTest(bobSession, aliceRestClient, roomId, expectation);

        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot create bobSession"];
        }];

    }];
}

- (void)doMXSessionTestWithBobAndAliceInARoom:(XCTestCase*)testCase
                                     andStore:(id<MXStore>)bobStore
                                  readyToTest:(void (^)(MXSession *bobSession,  MXRestClient *aliceRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXSessionTestWithBobAndARoom:testCase andStore:bobStore readyToTest:^(MXSession *bobSession, MXRoom *room, XCTestExpectation *expectation) {

        [self doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

            MXRestClient *bobRestClient = bobSession.matrixRestClient;
            NSString *roomId = room.roomId;

            [bobRestClient inviteUser:self.aliceCredentials.userId toRoom:roomId success:^{

                [aliceRestClient joinRoom:roomId viaServers:nil withThirdPartySigned:nil success:^(NSString *theRoomId) {

                    readyToTest(bobSession, aliceRestClient, roomId, expectation);

                } failure:^(NSError *error) {
                    [self breakTestCase:testCase reason:@"mxAlice cannot join room"];
                }];

            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot invite mxAlice"];
            }];
        }];
    }];
}

- (void)doTestWithAliceAndBobInARoom:(XCTestCase*)testCase
                          aliceStore:(id<MXStore>)aliceStore
                            bobStore:(id<MXStore>)bobStore
                         readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXSessionTestWithBobAndAliceInARoom:testCase andStore:bobStore readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *aliceSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [self retain:aliceSession];

        [aliceSession setStore:aliceStore success:^{

            [aliceSession start:^{

                readyToTest(aliceSession, bobSession, roomId, expectation);

            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
            }];
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }];
}


#pragma mark - random user
- (void)doMXSessionTestWithAUser:(XCTestCase*)testCase
                     readyToTest:(void (^)(MXSession *aUserSession, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }

    __block MXRestClient *aUserRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                        andOnUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {
                                            return YES;
                                        }];
    [self retain:aUserRestClient];

    // First, register a new random user
    NSString *anUniqueUser = [NSString stringWithFormat:@"%@", [[NSUUID UUID] UUIDString]];
    MXHTTPOperation *operation = [aUserRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:anUniqueUser password:@"123456" success:^(MXCredentials *credentials) {

        aUserRestClient = [[MXRestClient alloc] initWithCredentials:credentials andOnUnrecognizedCertificateBlock:nil];
        [self retain:aUserRestClient];

        MXSession *aUserSession = [[MXSession alloc] initWithMatrixRestClient:aUserRestClient];
        [self retain:aUserSession];

        [aUserSession start:^{

            readyToTest(aUserSession, expectation);

        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];

    } failure:^(NSError *error) {
        [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
    }];
    operation.maxNumberOfTries = 1;
}


#pragma mark - HTTPS mxBob
- (void)getHttpsBobCredentials:(XCTestCase*)testCase
                   readyToTest:(void (^)(void))readyToTest
{
    [self getHttpsBobCredentials:testCase readyToTest:readyToTest onUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {
        return YES;
    }];
}

- (void)getHttpsBobCredentials:(XCTestCase*)testCase
                   readyToTest:(void (^)(void))readyToTest
onUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    if (self.bobCredentials)
    {
        // Credentials are already here, they are ready
        readyToTest();
    }
    else
    {
        // Use a different Bob each time so that tests are independent
        NSString *bobUniqueUser = [NSString stringWithFormat:@"%@-%@", MXTESTS_BOB, [[NSUUID UUID] UUIDString]];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerHttpsURL
                                            andOnUnrecognizedCertificateBlock:onUnrecognizedCertBlock];
        [self retain:mxRestClient];

        // First, try register the user
        MXHTTPOperation *operation = [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:bobUniqueUser password:MXTESTS_BOB_PWD success:^(MXCredentials *credentials) {

            self.bobCredentials = credentials;
            readyToTest();

        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Bob in to get his keys
                [mxRestClient loginWithLoginType:kMXLoginFlowTypeDummy username:bobUniqueUser password:MXTESTS_BOB_PWD success:^(MXCredentials *credentials) {

                    self.bobCredentials = credentials;
                    readyToTest();

                } failure:^(NSError *error) {
                     [self breakTestCase:testCase reason:@"Cannot log mxBOB in"];
                }];
            }
            else
            {
                [self breakTestCase:testCase reason:@"Cannot create mxBOB account. Make sure the homeserver at %@ is running", mxRestClient.homeserver];
            }
        }];
        operation.maxNumberOfTries = 1;
    }
}

- (void)doHttpsMXRestClientTestWithBob:(XCTestCase*)testCase
                           readyToTest:(void (^)(MXRestClient *bobRestClient, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }

    [self getHttpsBobCredentials:testCase readyToTest:^{

        MXRestClient *restClient = [[MXRestClient alloc] initWithCredentials:self.bobCredentials
                                           andOnUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {
                                               return YES;
                                           }];
        [self retain:restClient];

        readyToTest(restClient, expectation);
    }];

    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:10 handler:nil];
    }
}

- (void)doHttpsMXSessionTestWithBob:(XCTestCase*)testCase
                        readyToTest:(void (^)(MXSession *mxSession, XCTestExpectation *expectation))readyToTest
{
    [self doHttpsMXRestClientTestWithBob:testCase readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [self retain:mxSession];

        [mxSession start:^{

            readyToTest(mxSession, expectation);
            
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
        }];
    }];
}


#pragma mark - tools

- (void)breakTestCase:(XCTestCase*)testCase reason:(NSString *)reason, ...
{
    va_list arguments;
    va_start(arguments, reason);
    NSString *log = [[NSString alloc] initWithFormat:reason arguments:arguments];
    va_end(arguments);
    
    testCase.continueAfterFailure = NO;
    _XCTPrimitiveFail(testCase, "[MatrixSDKTestsData] breakTestCase: %@", log);
}

- (void)relogUserSession:(XCTestCase*)testCase
                 session:(MXSession*)session
            withPassword:(NSString*)password
              onComplete:(void (^)(MXSession *newSession))onComplete
{
    NSString *userId = session.matrixRestClient.credentials.userId;

    [session logout:^{

        [session close];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                            andOnUnrecognizedCertificateBlock:nil];
        [self retain:mxRestClient];

        [mxRestClient loginWithLoginType:kMXLoginFlowTypePassword username:userId password:password success:^(MXCredentials *credentials) {

            MXRestClient *mxRestClient2 = [[MXRestClient alloc] initWithCredentials:credentials andOnUnrecognizedCertificateBlock:nil];
            [self retain:mxRestClient2];

            MXSession *newSession = [[MXSession alloc] initWithMatrixRestClient:mxRestClient2];
            [self retain:newSession];

            [newSession start:^{

                onComplete(newSession);

            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
            }];

        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot relog %@. Error: %@", userId, error];
        }];
    } failure:^(NSError *error) {
        [self breakTestCase:testCase reason:@"Cannot logout %@. Error: %@", userId, error];
    }];
}

- (void)relogUserSessionWithNewDevice:(XCTestCase*)testCase
                              session:(MXSession*)session
                         withPassword:(NSString*)password
                           onComplete:(void (^)(MXSession *newSession))onComplete
{
    NSString *userId = session.matrixRestClient.credentials.userId;

    [session enableCrypto:NO success:^{

        [session close];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                            andOnUnrecognizedCertificateBlock:nil];
        [self retain:mxRestClient];

        [mxRestClient loginWithLoginType:kMXLoginFlowTypePassword username:userId password:password success:^(MXCredentials *credentials) {

            MXRestClient *mxRestClient2 = [[MXRestClient alloc] initWithCredentials:credentials andOnUnrecognizedCertificateBlock:nil];
            [self retain:mxRestClient2];

            MXSession *newSession = [[MXSession alloc] initWithMatrixRestClient:mxRestClient2];
            [self retain:newSession];

            [newSession start:^{

                onComplete(newSession);

            } failure:^(NSError *error) {
                [self breakTestCase:testCase reason:@"Cannot set up intial test conditions - error: %@", error];
            }];

        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot relog %@. Error: %@", userId, error];
        }];
    } failure:^(NSError *error) {
        [self breakTestCase:testCase reason:@"Cannot logout %@. Error: %@", userId, error];
    }];
}

- (void)loginUserOnANewDevice:(XCTestCase*)testCase
                  credentials:(MXCredentials*)credentials
                 withPassword:(NSString*)password
               sessionToLogout:(MXSession*)sessionToLogout
              newSessionStore:(id<MXStore>)newSessionStore
              startNewSession:(BOOL)startNewSession
                          e2e:(BOOL)e2e
                   onComplete:(void (^)(MXSession *newSession))onComplete
{
    if (!credentials && sessionToLogout)
    {
        credentials = sessionToLogout.credentials;
    }
    
    if (sessionToLogout)
    {
        [sessionToLogout logout:^{
            [sessionToLogout close];
            
            [self loginUserOnANewDevice:testCase credentials:credentials withPassword:password sessionToLogout:nil newSessionStore:newSessionStore startNewSession:startNewSession e2e:e2e onComplete:onComplete];
            
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot logout %@. Error: %@", sessionToLogout.myUserId, error];
        }];
        return;
    }
    
    MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:credentials.homeServer
                                        andOnUnrecognizedCertificateBlock:nil];
    [self retain:mxRestClient];
    
    [mxRestClient loginWithLoginType:kMXLoginFlowTypePassword username:credentials.userId password:password success:^(MXCredentials *credentials2) {
        
        MXRestClient *mxRestClient2 = [[MXRestClient alloc] initWithCredentials:credentials2 andOnUnrecognizedCertificateBlock:nil];
        [self retain:mxRestClient2];
        
        MXSession *newSession = [[MXSession alloc] initWithMatrixRestClient:mxRestClient2];
        [self retain:newSession];
        
        if (!newSessionStore)
        {
            if (startNewSession)
            {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = e2e;
                [newSession start:^{
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
                    
                    onComplete(newSession);
                    
                } failure:^(NSError *error) {
                    [self breakTestCase:testCase reason:@"Cannot start the session - error: %@", error];
                }];
            }
            else
            {
                onComplete(newSession);
            }
            return;
        }
        
        [newSession setStore:newSessionStore success:^{
            if (startNewSession)
            {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = e2e;
                [newSession start:^{
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
                    
                    onComplete(newSession);
                    
                } failure:^(NSError *error) {
                    [self breakTestCase:testCase reason:@"Cannot start the session - error: %@", error];
                }];
            }
            else
            {
                onComplete(newSession);
            }
            
        } failure:^(NSError *error) {
            [self breakTestCase:testCase reason:@"Cannot open the store - error: %@", error];
        }];
        
    } failure:^(NSError *error) {
        [self breakTestCase:testCase reason:@"Cannot log %@ in again. Error: %@", credentials.userId , error];
    }];
}

#pragma mark Reference keeping
- (void)retain:(NSObject*)object
{
    [self.retainedObjects addObject:object];
}

- (void)release:(NSObject*)object
{
    [self.retainedObjects removeObject:object];
}

- (void)releaseRetainedObjects
{
    if (_autoCloseMXSessions)
    {
        for (NSObject *object in _retainedObjects)
        {
            if ([object isKindOfClass:MXSession.class])
            {
                MXSession *mxSession = (MXSession*)object;
                [mxSession close];
            }
        }
    }
    _retainedObjects = nil;
}

@end

#pragma clang diagnostic pop
