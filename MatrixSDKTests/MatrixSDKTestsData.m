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

#import "MXRestClient.h"
#import "MXError.h"

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
{
    NSDate *startDate;
}
@end

MXRestClient *accountToClean;
NSMutableArray *roomsToClean;

@implementation MatrixSDKTestsData

- (id)init
{
    self = [super init];
    if (self)
    {
        startDate = [NSDate date];
    }
    return self;
}

- (void)getBobCredentials:(void (^)(void))success
{
    if (self.bobCredentials)
    {
        // Credentials are already here, they are ready
        success();
    }
    else
    {
        // Use a different Bob each time so that tests are independent
        NSString *bobUniqueUser = [NSString stringWithFormat:@"%@-%@", MXTESTS_BOB, [[NSUUID UUID] UUIDString]];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                            andOnUnrecognizedCertificateBlock:nil];

        // First, try register the user
        [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:bobUniqueUser password:MXTESTS_BOB_PWD success:^(MXCredentials *credentials) {

            _bobCredentials = credentials;
            success();
            
        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Bob in to get his keys
                [mxRestClient loginWithLoginType:kMXLoginFlowTypeDummy username:bobUniqueUser password:MXTESTS_BOB_PWD success:^(MXCredentials *credentials) {
                    
                    _bobCredentials = credentials;
                    success();
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot log mxBOB in");
                }];
            }
            else
            {
                NSAssert(NO, @"Cannot create mxBOB account. Make sure the homeserver at %@ is running", mxRestClient.homeserver);
            }
        }];
    }
}

- (void)getBobMXRestClient:(void (^)(MXRestClient *))success
{
    [self getBobCredentials:^{
        
        MXRestClient *restClient = [[MXRestClient alloc] initWithCredentials:self.bobCredentials
                                           andOnUnrecognizedCertificateBlock:nil];
        
        success(restClient);
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

    [self getBobCredentials:^{
        
        MXRestClient *restClient = [[MXRestClient alloc] initWithCredentials:self.bobCredentials
                                           andOnUnrecognizedCertificateBlock:nil];

        if (accountToClean)
        {
            NSLog(@"Start cleaning user data (%tu rooms) from %@ ...", roomsToClean.count, testCase.name);

            // Before giving the hand to the test, clean the rooms of the user.
            // It is done now rather than at the end of each test because
            // once [expectation fulfill] is called, the system allows no more HTTP requests.
            [self leaveAllRoomsAsync:roomsToClean onComplete:^{
                accountToClean = nil;

                NSLog(@"End of cleaning user data");

                readyToTest(restClient, expectation);
            }];
        }
        else
        {
            readyToTest(restClient, expectation);
        }
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

            NSLog(@"Created room %@ for %@", response.roomId, testCase.name);
            
            readyToTest(bobRestClient, response.roomId, expectation);
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create a room - error: %@", error);
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

                                NSLog(@"Created public room %@ for %@", response.roomId, testCase.name);

                                readyToTest(bobRestClient, response.roomId, expectation);
                                
                            } failure:^(NSError *error) {
                                NSAssert(NO, @"Cannot create a room - error: %@", error);
                            }];
                        }];
}

- (void)doMXRestClientTestWithBobAndThePublicRoom:(XCTestCase*)testCase
                                   readyToTest:(void (^)(MXRestClient *bobRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBob:testCase readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        if (_thePublicRoomId)
        {
            readyToTest(bobRestClient, _thePublicRoomId, expectation);
        }
        else
        {
            // Create a public room starting with #mxPublic
            _thePublicRoomAlias = [NSString stringWithFormat:@"mxPublic-%@", [[NSUUID UUID] UUIDString]];

            [bobRestClient createRoom:@"MX Public Room test"
                           visibility:kMXRoomDirectoryVisibilityPublic
                            roomAlias:_thePublicRoomAlias
                                topic:@"The public room used by SDK tests"
                              success:^(MXCreateRoomResponse *response) {

                                  _thePublicRoomId = response.roomId;
                                  _thePublicRoomAlias = response.roomAlias;
                                  readyToTest(bobRestClient, response.roomId, expectation);

                              } failure:^(NSError *error) {
                                  NSAssert(NO, @"Cannot create the public room - error: %@", error);
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
    
    [self getBobMXRestClient:^(MXRestClient *bobRestClient) {
        // Create a random room to use
        [bobRestClient createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

            NSLog(@"Created room %@ for %@", response.roomId, testCase.name);

            // Send the the message text in it
            [bobRestClient sendTextMessageToRoom:response.roomId text:newTextMessage success:^(NSString *eventId) {
                
                readyToTest(bobRestClient, response.roomId, eventId, expectation);
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions");
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create a room - error: %@", error);
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
        [self for:bobRestClient andRoom:roomId sendMessages:5 success:^{
            
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
    
    [self getBobMXRestClient:^(MXRestClient *bobRestClient) {
        
        // Fill Bob's account with 5 rooms of 3 messages
        [self for:bobRestClient createRooms:5 withMessages:3 success:^{
            readyToTest(bobRestClient, expectation);
        }];
    }];
    
    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:60 handler:nil];
    }
}


- (void)for:(MXRestClient *)mxRestClient2 andRoom:(NSString*)roomId sendMessages:(NSUInteger)messagesCount success:(void (^)(void))success
{
    NSLog(@"sendMessages :%tu to %@", messagesCount, roomId);
    if (0 == messagesCount)
    {
        success();
    }
    else
    {
        [mxRestClient2 sendTextMessageToRoom:roomId text:[NSString stringWithFormat:@"Fake message sent at %.0f ms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000]
                           success:^(NSString *eventId) {

            // Send the next message
            [self for:mxRestClient2 andRoom:roomId sendMessages:messagesCount - 1 success:success];

        } failure:^(NSError *error) {
            // If the error is M_LIMIT_EXCEEDED, make sure your home server rate limit is high
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }
}

- (void)for:(MXRestClient *)mxRestClient2 createRooms:(NSUInteger)roomsCount withMessages:(NSUInteger)messagesCount success:(void (^)(void))success
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

            NSLog(@"Created room %@ in createRooms", response.roomId);

            // Fill it with messages
            [self for:mxRestClient2 andRoom:response.roomId sendMessages:messagesCount success:^{

                // Go to the next room
                [self for:mxRestClient2 createRooms:roomsCount - 1 withMessages:messagesCount success:success];
            }];
        } failure:^(NSError *error) {
            // If the error is M_LIMIT_EXCEEDED, make sure your home server rate limit is high
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }
}

- (void)doMXSessionTestWithBob:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXSession *mxSession, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBob:testCase readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [mxSession start:^{

            readyToTest(mxSession, expectation);

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}


- (void)doMXSessionTestWithBobAndARoomWithMessages:(XCTestCase*)testCase
                                       readyToTest:(void (^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBobAndARoomWithMessages:testCase readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        [mxSession start:^{
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            readyToTest(mxSession, room, expectation);
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)doMXSessionTestWithBobAndThePublicRoom:(XCTestCase*)testCase
                                   readyToTest:(void (^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBobAndThePublicRoom:testCase readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        [mxSession start:^{
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            readyToTest(mxSession, room, expectation);
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)doMXSessionTestWithBob:(XCTestCase *)testCase andStore:(id<MXStore>)store readyToTest:(void (^)(MXSession *, XCTestExpectation *))readyToTest
{
    [self doMXRestClientTestWithBob:testCase readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [mxSession setStore:store success:^{

            [mxSession start:^{

                readyToTest(mxSession, expectation);

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)doMXSessionTestWithBobAndARoom:(XCTestCase*)testCase andStore:(id<MXStore>)store
                           readyToTest:(void (^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBob:testCase readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [bobRestClient createRoom:@"A room" visibility:nil roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

            [mxSession setStore:store success:^{

                [mxSession start:^{

                    MXRoom *room = [mxSession roomWithRoomId:response.roomId];
                    readyToTest(mxSession, room, expectation);

                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}


#pragma mark - mxAlice
- (void)getAliceCredentials:(void (^)(void))success
{
    if (self.aliceCredentials)
    {
        // Credentials are already here, they are ready
        success();
    }
    else
    {
        // Use a different Alice each time so that tests are independent
        NSString *aliceUniqueUser = [NSString stringWithFormat:@"%@-%@", MXTESTS_ALICE, [[NSUUID UUID] UUIDString]];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                            andOnUnrecognizedCertificateBlock:nil];

        // First, try register the user
        [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:aliceUniqueUser password:MXTESTS_ALICE_PWD success:^(MXCredentials *credentials) {
            
            _aliceCredentials = credentials;
            success();
            
        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Alice in to get his keys
                [mxRestClient loginWithLoginType:kMXLoginFlowTypeDummy username:aliceUniqueUser password:MXTESTS_ALICE_PWD success:^(MXCredentials *credentials) {

                    _aliceCredentials = credentials;
                    success();
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot log mxAlice in");
                }];
            }
            else
            {
                NSAssert(NO, @"Cannot create mxAlice account");
            }
        }];
    }
}

- (void)getAliceMXRestClient:(void (^)(MXRestClient *aliceRestClient))success
{
    [self getAliceCredentials:^{
        
        MXRestClient *aliceRestClient = [[MXRestClient alloc] initWithCredentials:self.aliceCredentials
                                                andOnUnrecognizedCertificateBlock:nil];
        __block MXRestClient *aliceRestClient2 = aliceRestClient;
        
        // Set Alice displayname and avator
        [aliceRestClient setDisplayName:kMXTestsAliceDisplayName success:^{
            
            __block MXRestClient *aliceRestClient3 = aliceRestClient2;
            
            [aliceRestClient2 setAvatarUrl:kMXTestsAliceAvatarURL success:^{
                
                success(aliceRestClient3);
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set mxAlice avatar");
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set mxAlice displayname");
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
    
    [self getAliceMXRestClient:^(MXRestClient *aliceRestClient) {
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

        [aliceSession start:^{

            readyToTest(aliceSession, expectation);

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)doMXSessionTestWithAlice:(XCTestCase *)testCase andStore:(id<MXStore>)store readyToTest:(void (^)(MXSession *, XCTestExpectation *))readyToTest
{
    [self doMXRestClientTestWithAlice:testCase readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];

        [mxSession setStore:store success:^{

            [mxSession start:^{

                readyToTest(mxSession, expectation);

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
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
                
                [aliceRestClient joinRoom:roomId success:^(NSString *theRoomId) {
                    
                    readyToTest(bobRestClient, aliceRestClient, roomId, expectation);
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"mxAlice cannot join room");
                }];
                
            } failure:^(NSError *error) {
                 NSAssert(NO, @"Cannot invite mxAlice");
            }];
        }];
    }];
}

- (void)doMXSessionTestWithBobAndAliceInARoom:(XCTestCase*)testCase
                                  readyToTest:(void (^)(MXSession *bobSession, MXRestClient *aliceRestClient, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self doMXRestClientTestWithBobAndAliceInARoom:testCase readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [bobSession start:^{

            readyToTest(bobSession, aliceRestClient, roomId, expectation);

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create bobSession");
        }];

    }];
}


#pragma mark - HTTPS mxBob
- (void)getHttpsBobCredentials:(void (^)(void))success
{
    [self getHttpsBobCredentials:success onUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {
        return YES;
    }];
}

- (void)getHttpsBobCredentials:(void (^)(void))success onUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    if (self.bobCredentials)
    {
        // Credentials are already here, they are ready
        success();
    }
    else
    {
        // Use a different Bob each time so that tests are independent
        NSString *bobUniqueUser = [NSString stringWithFormat:@"%@-%@", MXTESTS_BOB, [[NSUUID UUID] UUIDString]];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerHttpsURL
                                            andOnUnrecognizedCertificateBlock:onUnrecognizedCertBlock];

        // First, try register the user
        [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:bobUniqueUser password:MXTESTS_BOB_PWD success:^(MXCredentials *credentials) {

            _bobCredentials = credentials;
            success();

        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Bob in to get his keys
                [mxRestClient loginWithLoginType:kMXLoginFlowTypeDummy username:bobUniqueUser password:MXTESTS_BOB_PWD success:^(MXCredentials *credentials) {

                    _bobCredentials = credentials;
                    success();

                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot log mxBOB in");
                }];
            }
            else
            {
                NSAssert(NO, @"Cannot create mxBOB account. Make sure the homeserver at %@ is running", mxRestClient.homeserver);
            }
        }];
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

    [self getHttpsBobCredentials:^{

        MXRestClient *restClient = [[MXRestClient alloc] initWithCredentials:self.bobCredentials
                                           andOnUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {
                                               return YES;
                                           }];

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

        [mxSession start:^{

            readyToTest(mxSession, expectation);
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}


#pragma mark - tools

- (void)relogUserSession:(MXSession*)session withPassword:(NSString*)password onComplete:(void (^)(MXSession *newSession))onComplete
{
    NSString *userId = session.matrixRestClient.credentials.userId;

    [session logout:^{

        [session close];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                            andOnUnrecognizedCertificateBlock:nil];

        [mxRestClient loginWithLoginType:kMXLoginFlowTypePassword username:userId password:password success:^(MXCredentials *credentials) {

            MXRestClient *mxRestClient2 = [[MXRestClient alloc] initWithCredentials:credentials andOnUnrecognizedCertificateBlock:nil];
            MXSession *newSession = [[MXSession alloc] initWithMatrixRestClient:mxRestClient2];

            [newSession start:^{

                onComplete(newSession);

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot relog %@. Error: %@", userId, error);
        }];
    } failure:^(NSError *error) {
        NSAssert(NO, @"Cannot logout %@. Error: %@", userId, error);
    }];
}

- (void)relogUserSessionWithNewDevice:(MXSession*)session withPassword:(NSString*)password onComplete:(void (^)(MXSession *newSession))onComplete
{
    NSString *userId = session.matrixRestClient.credentials.userId;

    [session enableCrypto:NO success:^{

        [session close];

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                            andOnUnrecognizedCertificateBlock:nil];

        [mxRestClient loginWithLoginType:kMXLoginFlowTypePassword username:userId password:password success:^(MXCredentials *credentials) {

            MXRestClient *mxRestClient2 = [[MXRestClient alloc] initWithCredentials:credentials andOnUnrecognizedCertificateBlock:nil];
            MXSession *newSession = [[MXSession alloc] initWithMatrixRestClient:mxRestClient2];

            [newSession start:^{

                onComplete(newSession);

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot relog %@. Error: %@", userId, error);
        }];
    } failure:^(NSError *error) {
        NSAssert(NO, @"Cannot logout %@. Error: %@", userId, error);
    }];
}



- (void)closeMXSession:(MXSession*)mxSession
{
    // If the user has more than 5 rooms, it worths to leave all of them.
    // While the db is not optimised (see SYN-164), an initialSync request
    // on an account with 100 rooms takes 35s. With less than 5 rooms, it takes less than 0.5s.
    
    // Ideally, to correctly reset the initial conditions, we should erase the home server db
    // between each test but, as a client, it is not possible.
    if (nil == accountToClean && mxSession.rooms.count >= 5)
    {
        roomsToClean = [NSMutableArray array];
        for (MXRoom *room in mxSession.rooms)
        {
            if (NO == room.state.isJoinRulePublic && MXMembershipJoin == room.state.membership)
            {
                [roomsToClean addObject:room.state.roomId];
            }
        }

        if (roomsToClean.count)
        {
            // Mark the account to clean
            accountToClean = mxSession.matrixRestClient;
        }
    }

    [mxSession close];
}

- (void)leaveAllRoomsAsync:(NSMutableArray*)rooms onComplete:(void (^)(void))onComplete
{
    if (rooms.count)
    {
        // Leave room one by one
        NSString *roomId = [rooms lastObject];
        [rooms removeLastObject];

        NSLog(@"Leaving %@...", roomId);

        [accountToClean leaveRoom:roomId success:^{

            [self leaveAllRoomsAsync:rooms onComplete:onComplete];

        } failure:^(NSError *error) {
            NSLog(@"Warning: Cannot leave room: %@. Error: %@", roomId, error);
            [self leaveAllRoomsAsync:rooms onComplete:onComplete];
        }];
    }
    else
    {
        onComplete();
    }
}

@end

#pragma clang diagnostic pop

