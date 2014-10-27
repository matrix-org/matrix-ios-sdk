/*
 Copyright 2014 OpenMarket Ltd
 
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

#import "MXHomeServer.h"
#import "MXError.h"

/*
 Out of the box, the tests are supposed to be run with the iOS simulator attacking
 a test home server running on the same Mac machine.
 The reason is that the simulator can access to the home server running on the Mac 
 via localhost. So everyone can use a localhost HS url that works everywhere.
 
 You are free to change this URL and you have to if you want to run tests on a true
 device.
 
 Here, we use one of the home servers launched by the ./demo/start.sh script
 */
NSString *const kMXTestsHomeServerURL = @"http://localhost:8080";


#define MXTESTS_BOB @"mxBob"
#define MXTESTS_BOB_PWD @"bobbob"

#define MXTESTS_ALICE @"mxAlice"
#define MXTESTS_ALICE_PWD @"alicealice"

@interface MatrixSDKTestsData ()
{
    MXHomeServer *homeServer;
    
    NSDate *startDate;
}
@end

@implementation MatrixSDKTestsData

- (id)init
{
    self = [super init];
    if (self)
    {
        homeServer = [[MXHomeServer alloc] initWithHomeServer:kMXTestsHomeServerURL];
        
        startDate = [NSDate date];
    }
    return self;
}

+ (id)sharedData
{
    static MatrixSDKTestsData *sharedData = nil;
    @synchronized(self) {
        if (sharedData == nil)
            sharedData = [[self alloc] init];
    }
    return sharedData;
}


- (void)getBobCredentials:(void (^)())success
{
    if (self.bobCredentials)
    {
        // Credentials are already here, they are ready
        success();
    }
    else
    {
        // First, try register the user
        [homeServer registerWithUser:MXTESTS_BOB andPassword:MXTESTS_BOB_PWD success:^(MXLoginResponse *credentials) {
            
            _bobCredentials = credentials;
            success();
            
        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Bob in to get his keys
                [homeServer loginWithUser:MXTESTS_BOB andPassword:MXTESTS_BOB_PWD success:^(MXLoginResponse *credentials) {
                    
                    _bobCredentials = credentials;
                    success();
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot log mxBOB in");
                }];
            }
            else
            {
                NSAssert(NO, @"Cannot create mxBOB account");
            }
        }];
    }
}

- (void)getBobMXSession:(void (^)(MXSession *))success
{
    [self getBobCredentials:^{
        
        MXSession *session = [[MXSession alloc] initWithHomeServer:kMXTestsHomeServerURL userId:self.bobCredentials.user_id accessToken:self.bobCredentials.access_token];
        
        success(session);
    }];
}


- (void)doMXSessionTestWithBob:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXSession *bobSession, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getBobCredentials:^{
        
        MXSession *session = [[MXSession alloc] initWithHomeServer:kMXTestsHomeServerURL userId:sharedData.bobCredentials.user_id accessToken:sharedData.bobCredentials.access_token];
        
        readyToTest(session, expectation);
        
    }];
    
    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:10000 handler:nil];
    }
}

- (void)doMXSessionTestWithBobAndARoom:(XCTestCase*)testCase
                           readyToTest:(void (^)(MXSession *bobSession, NSString* room_id, XCTestExpectation *expectation))readyToTest
{
    [self doMXSessionTestWithBob:testCase
                     readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        // Create a random room to use
        [bobSession createRoom:nil visibility:kMXRoomVisibilityPrivate room_alias_name:nil topic:nil success:^(MXCreateRoomResponse *response) {
            
            readyToTest(bobSession, response.room_id, expectation);
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create a room - error: %@", error);
        }];
    }];
}

- (void)doMXSessionTestWithBobAndThePublicRoom:(XCTestCase*)testCase
                                   readyToTest:(void (^)(MXSession *bobSession, NSString* room_id, XCTestExpectation *expectation))readyToTest
{
    [self doMXSessionTestWithBob:testCase
                     readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
                         
        // Create THE allocated public room: #mxPublic
        [bobSession createRoom:@"MX Public Room test"
                    visibility:kMXRoomVisibilityPublic
               room_alias_name:@"mxPublic"
                         topic:@"The public room used by SDK tests"
                       success:^(MXCreateRoomResponse *response) {
            
            readyToTest(bobSession, response.room_id, expectation);
            
        } failure:^(NSError *error) {
            if ([MXError isMXError:error])
            {
                NSString *mxPublicAlias = [NSString stringWithFormat:@"#mxPublic:%@", self.bobCredentials.home_server];
                
                // The room may already exist, try to retrieve its room id
                [bobSession roomIDForRoomAlias:mxPublicAlias success:^(NSString *room_id) {
                    
                    readyToTest(bobSession, room_id, expectation);
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot retrieve mxPublic from its alias - error: %@", error);
                }];
            }
            else
            {
                NSAssert(NO, @"Cannot create a room - error: %@", error);
            }
        }];
    }];
}

- (void)doMXSessionTestInABobRoomAndANewTextMessage:(XCTestCase*)testCase
                                  newTextMessage:(NSString*)newTextMessage
                                   onReadyToTest:(void (^)(MXSession *bobSession, NSString* room_id, NSString* new_text_message_event_id, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getBobMXSession:^(MXSession *bobSession) {
        // Create a random room to use
        [bobSession createRoom:nil visibility:kMXRoomVisibilityPrivate room_alias_name:nil topic:nil success:^(MXCreateRoomResponse *response) {
            
            // Post the the message text in it
            [bobSession postTextMessage:response.room_id text:newTextMessage success:^(NSString *event_id) {
                
                readyToTest(bobSession, response.room_id, event_id, expectation);
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions");
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create a room - error: %@", error);
        }];
    }];
    
    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:10000 handler:nil];
    }
}

- (void)doMXSessionTestWithBobAndARoomWithMessages:(XCTestCase*)testCase
                                       readyToTest:(void (^)(MXSession *bobSession, NSString* room_id, XCTestExpectation *expectation))readyToTest
{
    [self doMXSessionTestWithBobAndARoom:testCase
                             readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
        
        // Add 5 messages to the room
        [sharedData for:bobSession andRoom:room_id postMessages:5 success:^{
            
            readyToTest(bobSession, room_id, expectation);
        }];
        
    }];
}

- (void)doMXSessionTestWihBobAndSeveralRoomsAndMessages:(XCTestCase*)testCase
                                         readyToTest:(void (^)(MXSession *bobSession, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getBobMXSession:^(MXSession *bobSession) {
        
        // Fill Bob's account with 5 rooms of 3 messages
        [sharedData for:bobSession createRooms:5 withMessages:3 success:^{
            readyToTest(bobSession, expectation);
        }];
    }];
    
    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:10000 handler:nil];
    }
}


- (void)for:(MXSession *)mxSession andRoom:(NSString*)room_id postMessages:(NSUInteger)messagesCount success:(void (^)())success
{
    NSLog(@"postMessages :%ld", messagesCount);
    if (0 == messagesCount)
    {
        success();
    }
    else
    {
        [mxSession postTextMessage:room_id text:[NSString stringWithFormat:@"Fake message posted at %.0f ms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000]
                           success:^(NSString *event_id) {

            // Post the next message
            [self for:mxSession andRoom:room_id postMessages:messagesCount - 1 success:success];

        } failure:^(NSError *error) {
            // If the error is M_LIMIT_EXCEEDED, make sure your home server rate limit is high
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }
}

- (void)for:(MXSession *)mxSession createRooms:(NSUInteger)roomsCount withMessages:(NSUInteger)messagesCount success:(void (^)())success
{
    if (0 == roomsCount)
    {
        // The recursivity is done
        success();
    }
    else
    {
        // Create the room
        [mxSession createRoom:nil visibility:kMXRoomVisibilityPrivate room_alias_name:nil topic:nil success:^(MXCreateRoomResponse *response) {

            // Fill it with messages
            [self for:mxSession andRoom:response.room_id postMessages:messagesCount success:^{

                // Go to the next room
                [self for:mxSession createRooms:roomsCount - 1 withMessages:messagesCount success:success];
            }];
        } failure:^(NSError *error) {
            // If the error is M_LIMIT_EXCEEDED, make sure your home server rate limit is high
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }
}


#pragma mark - mxAlice
- (void)getAliceCredentials:(void (^)())success
{
    if (self.aliceCredentials)
    {
        // Credentials are already here, they are ready
        success();
    }
    else
    {
        // First, try register the user
        [homeServer registerWithUser:MXTESTS_ALICE andPassword:MXTESTS_ALICE_PWD success:^(MXLoginResponse *credentials) {
            
            _aliceCredentials = credentials;
            success();
            
        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Bob in to get his keys
                [homeServer loginWithUser:MXTESTS_ALICE andPassword:MXTESTS_ALICE_PWD success:^(MXLoginResponse *credentials) {
                    
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

- (void)getAliceMXSession:(void (^)(MXSession *))success
{
    [self getAliceCredentials:^{
        
        MXSession *session = [[MXSession alloc] initWithHomeServer:kMXTestsHomeServerURL userId:self.aliceCredentials.user_id accessToken:self.aliceCredentials.access_token];
        
        success(session);
    }];
}


- (void)doMXSessionTestWithAlice:(XCTestCase*)testCase
                   readyToTest:(void (^)(MXSession *aliceSession, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation;
    if (testCase)
    {
        expectation = [testCase expectationWithDescription:@"asyncTest"];
    }
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getAliceCredentials:^{
        
        MXSession *session = [[MXSession alloc] initWithHomeServer:kMXTestsHomeServerURL userId:sharedData.aliceCredentials.user_id accessToken:sharedData.aliceCredentials.access_token];
        
        readyToTest(session, expectation);
        
    }];
    
    if (testCase)
    {
        [testCase waitForExpectationsWithTimeout:10000 handler:nil];
    }
}

#pragma mark - both
- (void)doMXSessionTestWithBobAndAliceInARoom:(XCTestCase*)testCase
                                  readyToTest:(void (^)(MXSession *bobSession, MXSession *aliceSession, NSString* room_id, XCTestExpectation *expectation))readyToTest
{
    [self doMXSessionTestWithBobAndARoom:testCase readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [self doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {
            
            [bobSession inviteUser:self.aliceCredentials.user_id toRoom:room_id success:^{
                
                [aliceSession joinRoom:room_id success:^{
                    
                    readyToTest(bobSession, aliceSession, room_id, expectation);
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"mxAlice cannot join room");
                }];
                
            } failure:^(NSError *error) {
                 NSAssert(NO, @"Cannot invite mxAlice");
            }];
        }];
    }];
}


@end
