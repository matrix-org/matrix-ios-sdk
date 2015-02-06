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

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MXError.h"

#import "MXRestClient.h"

#define MXTESTS_USER @"mxtest"
#define MXTESTS_PWD @"password"

@interface MXRestClientNoAuthAPITests : XCTestCase
{
    MXRestClient *mxRestClient;
}

@end

@implementation MXRestClientNoAuthAPITests

- (void)setUp {
    [super setUp];

    mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerURL];
}

- (void)tearDown {
    mxRestClient = nil;

    [super tearDown];
}

// Make sure MXTESTS_USER exists on the HS
- (void)createTestAccount:(void (^)())onReady
{
    // Register the user
    [mxRestClient registerWithUser:MXTESTS_USER andPassword:MXTESTS_PWD
                         success:^(MXCredentials *credentials) {
                             
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
                                 NSAssert(NO, @"Cannot create the test account");
                             }
                         }];
}

- (void)testInit
{
    XCTAssertNotNil(mxRestClient, @"Valid init");
    XCTAssertTrue([mxRestClient.homeserver isEqualToString:kMXTestsHomeServerURL], @"Pass");
}

- (void)testCancel
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    NSOperation *request = [mxRestClient getRegisterFlow:^(NSArray *flows) {

        XCTFail(@"The request should not succeed");
        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTAssertEqual(error.code, NSURLErrorCancelled, @"The request must be flagged as cancelled");
        [expectation fulfill];
    }];

    [request cancel];

    [self waitForExpectationsWithTimeout:10000 handler:nil];
}


#pragma mark - Registration operations
- (void)testRegisterFlow
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [mxRestClient getRegisterFlow:^(NSArray *flows) {
        
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
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)testRegister
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    // Test the password-based flow with the generic register method
    NSDictionary *parameters = @{
                                 @"type": kMXLoginFlowTypePassword,
                                 @"user": @"",
                                 @"password": MXTESTS_PWD
                                 };

    [mxRestClient register:parameters success:^(NSDictionary *JSONResponse) {

        XCTAssertNotNil(JSONResponse[@"access_token"], @"password-based registration flow is complete in one stage. We must get the access token.");

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)testRegisterPasswordBased
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    // Provide an empty string as user, the HS will provide one for us
    [mxRestClient registerWithUser:@"" andPassword:MXTESTS_PWD
                         success:^(MXCredentials *credentials) {
                             
                             XCTAssertNotNil(credentials);
                             XCTAssertNotNil(credentials.homeServer);
                             XCTAssertNotNil(credentials.userId);
                             XCTAssertNotNil(credentials.accessToken);
                             
                             [expectation fulfill];
                             
                         } failure:^(NSError *error) {
                             XCTFail(@"The request should not fail - NSError: %@", error);
                             [expectation fulfill];
                         }];

    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)testRegisterPasswordBasedWithExistingUser
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [self createTestAccount:^{
        // Register the same user
        [mxRestClient registerWithUser:MXTESTS_USER andPassword:MXTESTS_PWD
                             success:^(MXCredentials *credentials) {
                                 
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

    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

#pragma mark - Login operations
- (void)testLoginFlow
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [mxRestClient getLoginFlow:^(NSArray *flows) {
        
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
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
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

    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)testLoginPasswordBased
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [self createTestAccount:^{
        [mxRestClient loginWithUser:MXTESTS_USER andPassword:MXTESTS_PWD
                          success:^(MXCredentials *credentials) {
                              
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
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)testLoginPasswordBasedWithWrongPassword
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [self createTestAccount:^{
        [mxRestClient loginWithUser:MXTESTS_USER andPassword:[NSString stringWithFormat:@"wrong%@", MXTESTS_PWD]
                          success:^(MXCredentials *credentials) {
                              
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
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}


#pragma mark - Event operations
- (void)testPublicRooms
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [mxRestClient publicRooms:^(NSArray *rooms) {
            
            XCTAssertTrue(0 < rooms.count, @"Valid init");
            
            MXPublicRoom *theMXPublicRoom;
            for (MXPublicRoom *room in rooms)
            {
                // Find the Matrix HQ room (#matrix:matrix.org) by its ID
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

@end
