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

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MXError.h"

#import "MXRestClient.h"

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

- (void)tearDown {
    mxRestClient = nil;

    [super tearDown];
}

// Make sure MXTESTS_USER exists on the HS
- (void)createTestAccount:(void (^)(void))onReady
{
    // Register the user
    [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:MXTESTS_USER password:MXTESTS_PWD success:^(MXCredentials *credentials) {

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
}

- (void)testInit
{
    XCTAssertNotNil(mxRestClient, @"Valid init");
    XCTAssertTrue([mxRestClient.homeserver isEqualToString:kMXTestsHomeServerURL], @"Pass");
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

- (void)testRegisterWithDummyLoginType
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    // Provide nil as username, the HS will provide one for us
    [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:nil password:MXTESTS_PWD success:^(MXCredentials *credentials) {

        XCTAssertNotNil(credentials);
        XCTAssertNotNil(credentials.homeServer);
        XCTAssertNotNil(credentials.userId);
        XCTAssertNotNil(credentials.accessToken);

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testRegisterWithDummyLoginTypeWithExistingUser
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [self createTestAccount:^{

        // Register the same user
        [mxRestClient registerWithLoginType:kMXLoginFlowTypeDummy username:MXTESTS_USER password:MXTESTS_PWD success:^(MXCredentials *credentials) {

            XCTFail(@"The request should fail (User already exists)");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTAssertTrue([MXError isMXError:error], @"HS should have sent detailed error in the body");

            MXError *mxError = [[MXError alloc] initWithNSError:error];
            XCTAssertNotNil(mxError);

            XCTAssertTrue([mxError.errcode isEqualToString:@"M_USER_IN_USE"], @"M_USER_IN_USE errcode is expected. Received: %@", error);

            [expectation fulfill];
        }];
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
            XCTAssertNil(publicRoomsResponse.nextBatch, @"We requested all rooms. There must not be a pagination token");
            
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
            
            [expectation fulfill];
            
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
        [bobRestClient publicRoomsOnServer:nil limit:10 since:nil filter:@"mxPublic" thirdPartyInstanceId:nil includeAllNetworks:NO success:^(MXPublicRoomsResponse *publicRoomsResponse) {

            XCTAssertGreaterThan(publicRoomsResponse.chunk.count, 0);
            XCTAssertGreaterThan(publicRoomsResponse.totalRoomCountEstimate, 0);
            XCTAssertNil(publicRoomsResponse.nextBatch, @"We requested all rooms. There must not be a pagination token");

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

            [expectation fulfill];

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
        XCTAssertEqual(dispatch_get_current_queue(), dispatch_get_main_queue());

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

    [client publicRoomsOnServer:nil limit:-1 since:nil filter:nil thirdPartyInstanceId:nil includeAllNetworks:NO success:^(MXPublicRoomsResponse *publicRoomsResponse) {

        XCTAssertFalse([[NSThread currentThread] isMainThread]);
        XCTAssertEqual(dispatch_get_current_queue(), client.completionQueue);

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];

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
        XCTAssertEqual(dispatch_get_current_queue(), client.completionQueue);

        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}


@end
