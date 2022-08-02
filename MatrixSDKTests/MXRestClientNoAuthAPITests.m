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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MXError.h"

#import "MXRestClient.h"
#import "MXHTTPClient_Private.h"

#define MXTESTS_USER @"mxtest"
#define MXTESTS_PWD @"password"

@interface MXRestClientNoAuthAPITests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;

    MXRestClient *mxRestClient;
}

@end

@implementation MXRestClientNoAuthAPITests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];

    mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                          andOnUnrecognizedCertificateBlock:nil];
}

- (void)tearDown
{
    [MXHTTPClient removeAllDelays];
    mxRestClient = nil;
    matrixSDKTestsData = nil;
    
    [super tearDown];
}

// Make sure MXTESTS_USER exists on the HS
- (void)createTestAccount:(void (^)(void))onReady
{
    // Register the user
    MXHTTPOperation *operation = [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:MXTESTS_USER password:MXTESTS_PWD success:^(MXCredentials *credentials) {

        onReady();

    } failure:^(NSError *error) {
        MXError *mxError = [[MXError alloc] initWithNSError:error];
        if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
        {
            // The user already exists. This error is normal
            onReady();
        }
        else
        {
            XCTFail(@"Cannot create the test account");
        }
    }];
    operation.maxNumberOfTries = 1;
}

- (void)testInit
{
    XCTAssertNotNil(mxRestClient, @"Valid init");
    XCTAssertTrue([mxRestClient.homeserver isEqualToString:kMXTestsHomeServerURL], @"Pass");
}


#pragma mark - Server administration
- (void)testSupportedMatrixVersions
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [mxRestClient supportedMatrixVersions:^(MXMatrixVersions *matrixVersions) {

        XCTAssertNotNil(matrixVersions);
        XCTAssertNotNil(matrixVersions.versions);

        // Check supported spec version at the time of writing this test
        XCTAssert([matrixVersions.versions containsObject:@"r0.0.1"]);
        XCTAssert([matrixVersions.versions containsObject:@"r0.1.0"]);
        XCTAssert([matrixVersions.versions containsObject:@"r0.2.0"]);
        XCTAssert([matrixVersions.versions containsObject:@"r0.3.0"]);

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// At the time of introducing this test, MXMatrixVersions.supportLazyLoadMembers
// was stored in MXMatrixVersions.unstableFeatures.
// Make sure that, in future versions of the spec, supportLazyLoadMembers is still YES
// wherever it will be stored.
- (void)testSupportedMatrixVersionsSupportLazyLoadMembers
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [mxRestClient supportedMatrixVersions:^(MXMatrixVersions *matrixVersions) {

        XCTAssert(matrixVersions.supportLazyLoadMembers);

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}


#pragma mark - Registration operations
- (void)testGetRegisterSession
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [mxRestClient getRegisterSession:^(MXAuthenticationSession *authSession) {

        XCTAssert(authSession.session);

        NSArray<MXLoginFlow*> *flows = authSession.flows;

        XCTAssertTrue(0 < flows.count, @"There must be at least one way to login");
        
        BOOL foundDummyFlowType;
        for (MXLoginFlow *flow in flows)
        {
            if (NSNotFound != [flow.stages indexOfObject:kMXLoginFlowTypeDummy])
            {
                foundDummyFlowType = YES;
            }
        }
        XCTAssertTrue(foundDummyFlowType, @"Dummy login is the basic type");
        
        [expectation fulfill];
        
    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testUsernameAvailability
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    // Test with a random string as other tests may have already registered the test acounts
    MXHTTPOperation *operation = [mxRestClient isUsernameAvailable:@"notyetregistered" success:^(MXUsernameAvailability *availability) {
        
        XCTAssertTrue(availability.available, @"The username should be available for registration.");
        [expectation fulfill];
        
    } failure:^(NSError *error) {
        
        XCTFail(@"The request should not fail - the username should be available");
        [expectation fulfill];
        
    }];
    operation.maxNumberOfTries = 1;
    
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testUsernameAvailabilityForExistingUsername
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [self createTestAccount:^{
        MXHTTPOperation *operation = [mxRestClient isUsernameAvailable:MXTESTS_USER success:^(MXUsernameAvailability *availability) {
            
            XCTFail(@"The request should fail - the username should already be taken");
            [expectation fulfill];
            
            } failure:^(NSError *error) {
                
                MXError *mxError = [[MXError alloc] initWithNSError:error];
                
                XCTAssertNotNil(mxError);
                XCTAssertTrue([mxError.errcode isEqualToString:kMXErrCodeStringUserInUse], @"The error should indicate that the username is in use");
                
                [expectation fulfill];
                
            }];
        operation.maxNumberOfTries = 1;
    }];
    
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testUsernameAvailabilityForInvalidUsername
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    // Test a username that only has digits which is disallowed by the spec.
    MXHTTPOperation *operation = [mxRestClient isUsernameAvailable:@"123456789" success:^(MXUsernameAvailability *availability) {
        
        XCTFail(@"The request should fail - the username should already be taken");
        [expectation fulfill];
        
    } failure:^(NSError *error) {
        
        MXError *mxError = [[MXError alloc] initWithNSError:error];
        
        XCTAssertNotNil(mxError);
        XCTAssertTrue([mxError.errcode isEqualToString:kMXErrCodeStringInvalidUsername], @"The error should indicate that the username is invalid");
        
        [expectation fulfill];
        
    }];
    operation.maxNumberOfTries = 1;
    
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testRegisterWithDummyLoginType
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    // Provide nil as username, the HS will provide one for us
    MXHTTPOperation *operation = [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:nil password:MXTESTS_PWD success:^(MXCredentials *credentials) {

        XCTAssertNotNil(credentials);
        XCTAssertNotNil(credentials.homeServer);
        XCTAssertNotNil(credentials.userId);
        XCTAssertNotNil(credentials.accessToken);

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
    operation.maxNumberOfTries = 1;

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testRegisterWithDummyLoginTypeWithExistingUser
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [self createTestAccount:^{

        // Register the same user
        MXHTTPOperation *operation = [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:MXTESTS_USER password:MXTESTS_PWD success:^(MXCredentials *credentials) {

            XCTFail(@"The request should fail (User already exists)");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTAssertTrue([MXError isMXError:error], @"HS should have sent detailed error in the body");

            MXError *mxError = [[MXError alloc] initWithNSError:error];
            XCTAssertNotNil(mxError);

            XCTAssertTrue([mxError.errcode isEqualToString:@"M_USER_IN_USE"], @"M_USER_IN_USE errcode is expected. Received: %@", error);

            [expectation fulfill];
        }];
        operation.maxNumberOfTries = 1;
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testRegisterFallback
{
    NSString *registerFallback = [mxRestClient registerFallback];

    XCTAssertNotNil(registerFallback);
    XCTAssertGreaterThan(registerFallback.length, 0);
}


#pragma mark - Login operations
- (void)testGetLoginSession
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [mxRestClient getLoginSession:^(MXAuthenticationSession *authSession) {

        NSArray<MXLoginFlow*> *flows = authSession.flows;
        
        XCTAssertTrue(0 < flows.count, @"There must be at least one way to login");
        
        BOOL foundPasswordFlowType;
        for (MXLoginFlow *flow in flows)
        {
            if ([flow.type isEqualToString:kMXLoginFlowTypePassword])
            {
                foundPasswordFlowType = YES;
            }
        }
        XCTAssertTrue(foundPasswordFlowType, @"Password-based login is the basic type");
        
        [expectation fulfill];
        
    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testLogin
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [self createTestAccount:^{

        // Test the password-based flow with the generic login method
        NSDictionary *parameters = @{
                                     @"type": kMXLoginFlowTypePassword,
                                     @"user": MXTESTS_USER,
                                     @"password": MXTESTS_PWD
                                     };

        [mxRestClient login:parameters success:^(NSDictionary *JSONResponse) {

            XCTAssertNotNil(JSONResponse[@"access_token"], @"password-based login flow is complete in one stage. We must get the access token.");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testLoginWithPasswordLoginType
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [self createTestAccount:^{

        [mxRestClient loginWithLoginType:kMXLoginFlowTypePassword username:MXTESTS_USER password:MXTESTS_PWD success:^(MXCredentials *credentials) {

            XCTAssertNotNil(credentials);
            XCTAssertNotNil(credentials.homeServer);
            XCTAssertNotNil(credentials.userId);
            XCTAssertNotNil(credentials.accessToken);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testLoginWithPasswordLoginTypeWithWrongPassword
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [self createTestAccount:^{

        [mxRestClient loginWithLoginType:kMXLoginFlowTypePassword username:MXTESTS_USER password:@"wrongPwd" success:^(MXCredentials *credentials) {

            XCTFail(@"The request should fail (Wrong password)");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTAssertTrue([MXError isMXError:error], @"HS should have sent detailed error in the body");

            MXError *mxError = [[MXError alloc] initWithNSError:error];
            XCTAssertNotNil(mxError);

            XCTAssertTrue([mxError.errcode isEqualToString:@"M_FORBIDDEN"], @"M_FORBIDDEN errcode is expected. Received: %@", error);

            [expectation fulfill];
        }];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}


#pragma mark - Event operations
- (void)testPublicRooms
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [bobRestClient publicRoomsOnServer:nil limit:-1 since:nil filter:nil thirdPartyInstanceId:nil includeAllNetworks:NO success:^(MXPublicRoomsResponse *publicRoomsResponse) {
            
            XCTAssertGreaterThan(publicRoomsResponse.chunk.count, 0);
            XCTAssertGreaterThan(publicRoomsResponse.totalRoomCountEstimate, 0);
            
            MXPublicRoom *theMXPublicRoom;
            for (MXPublicRoom *room in publicRoomsResponse.chunk)
            {
                // Find the created public room
                if ([room.roomId isEqualToString:roomId])
                {
                    theMXPublicRoom = room;
                }
            }
            
            XCTAssertNotNil(theMXPublicRoom);
            XCTAssertEqualObjects(theMXPublicRoom.name, @"MX Public Room test");
            XCTAssertEqualObjects(theMXPublicRoom.topic, @"The public room used by SDK tests");
            XCTAssertGreaterThan(theMXPublicRoom.numJoinedMembers, 0, @"The is at least mxBob at #matrix:matrix.org");

            if (publicRoomsResponse.nextBatch)
            {
                // Synapse HS (now) returns a non nil nextBatch even if it sent all room
                // in its response.
                // Make sure nextBatch is nil if we paginate again
                [bobRestClient publicRoomsOnServer:nil limit:-1 since:publicRoomsResponse.nextBatch filter:nil thirdPartyInstanceId:nil includeAllNetworks:NO success:^(MXPublicRoomsResponse *publicRoomsResponse2) {

                    XCTAssertNil(publicRoomsResponse2.nextBatch, @"We requested all rooms. There must not be a pagination token");
                    [expectation fulfill];

                } failure:nil];
            }
            else
            {
                [expectation fulfill];
            }

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testSearchPublicRooms
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        // Search for "mxPublic"
        // Room created by doMXRestClientTestWithBobAndThePublicRoom is mxPublic-something
        [bobRestClient publicRoomsOnServer:nil limit:100 since:nil filter:@"mxPublic" thirdPartyInstanceId:nil includeAllNetworks:NO success:^(MXPublicRoomsResponse *publicRoomsResponse) {

            XCTAssertGreaterThan(publicRoomsResponse.chunk.count, 0);
            XCTAssertGreaterThan(publicRoomsResponse.totalRoomCountEstimate, 0);

            MXPublicRoom *theMXPublicRoom;
            for (MXPublicRoom *room in publicRoomsResponse.chunk)
            {
                // Find the created public room
                if ([room.roomId isEqualToString:roomId])
                {
                    theMXPublicRoom = room;
                }
            }

            XCTAssertNotNil(theMXPublicRoom);
            XCTAssertEqualObjects(theMXPublicRoom.name, @"MX Public Room test");
            XCTAssertEqualObjects(theMXPublicRoom.topic, @"The public room used by SDK tests");
            XCTAssertGreaterThan(theMXPublicRoom.numJoinedMembers, 0, @"The is at least mxBob at #matrix:matrix.org");

            if (publicRoomsResponse.nextBatch)
            {
                // Synapse HS (now) returns a non nil nextBatch even if it sent all room
                // in its response.
                // Make sure nextBatch is nil if we paginate again
                [bobRestClient publicRoomsOnServer:nil limit:-1 since:publicRoomsResponse.nextBatch filter:nil thirdPartyInstanceId:nil includeAllNetworks:NO success:^(MXPublicRoomsResponse *publicRoomsResponse2) {

                    XCTAssertNil(publicRoomsResponse2.nextBatch, @"We requested all rooms. There must not be a pagination token");
                    [expectation fulfill];

                } failure:nil];
            }
            else
            {
                [expectation fulfill];
            }

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

#pragma mark - completionQueue
- (void)testCompletionQueueDefaultValue
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    MXRestClient *client = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                  andOnUnrecognizedCertificateBlock:nil];

    [client publicRoomsOnServer:nil limit:-1 since:nil filter:nil thirdPartyInstanceId:nil includeAllNetworks:NO success:^(MXPublicRoomsResponse *publicRoomsResponse) {

        // Result must be returned on the main queue by default
        XCTAssert([[NSThread currentThread] isMainThread]);

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testCompletionQueue
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    MXRestClient *client = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                          andOnUnrecognizedCertificateBlock:nil];

    client.completionQueue = dispatch_queue_create("aQueueFromAnotherThread", DISPATCH_QUEUE_SERIAL);

    MXHTTPOperation *operation = [client publicRoomsOnServer:nil limit:-1 since:nil filter:nil thirdPartyInstanceId:nil includeAllNetworks:NO success:^(MXPublicRoomsResponse *publicRoomsResponse) {

        XCTAssertFalse([[NSThread currentThread] isMainThread]);
        XCTAssertEqual(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), "aQueueFromAnotherThread");

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
    operation.maxNumberOfTries = 1;

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testCompletionQueueOnError
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    MXRestClient *client = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                  andOnUnrecognizedCertificateBlock:nil];

    client.completionQueue = dispatch_queue_create("aQueueFromAnotherThread", DISPATCH_QUEUE_SERIAL);

    [client avatarUrlForUser:nil success:^(NSString *avatarUrl) {

        XCTFail(@"The request should fail");
        [expectation fulfill];

    } failure:^(NSError *error) {

        XCTAssertFalse([[NSThread currentThread] isMainThread]);
        XCTAssertEqual(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), "aQueueFromAnotherThread");

        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testMXHTTPClientPrivateSetDelay
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    // Define a delay for all requests
    [MXHTTPClient setDelay:2000 toRequestsContainingString:@"/"];

    mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL
                                        andOnUnrecognizedCertificateBlock:nil];

    NSDate *date = [NSDate date];
    [mxRestClient supportedMatrixVersions:^(MXMatrixVersions *matrixVersions) {

        NSDate *now = [NSDate date];
        XCTAssertGreaterThanOrEqual([now timeIntervalSinceDate:date], 2);

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}


@end
