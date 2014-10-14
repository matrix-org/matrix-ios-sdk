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

#import "MXHomeServer.h"

#define MXTESTS_USER @"mxtest"
#define MXTESTS_PWD @"password"

@interface MXHomeServerTests : XCTestCase
{
    MXHomeServer *homeServer;
}

@end

@implementation MXHomeServerTests

- (void)setUp {
    [super setUp];

    homeServer = [[MXHomeServer alloc] initWithHomeServer:kMXTestsHomeServerURL];
}

- (void)tearDown {
    homeServer = nil;

    [super tearDown];
}

// Make sure MXTESTS_USER exists on the HS
- (void)createTestAccount:(void (^)())onReady
{
    // Register the user
    [homeServer registerWithUser:MXTESTS_USER andPassword:MXTESTS_PWD
                         success:^(MXLoginResponse *credentials) {
                             
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
    XCTAssertNotNil(homeServer, @"Valid init");
    XCTAssertTrue([homeServer.homeserver isEqualToString:kMXTestsHomeServerURL], @"Pass");
}


#pragma mark - Registration operations
- (void)testRegisterFlow
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [homeServer getRegisterFlow:^(NSArray *flows) {
        
        XCTAssertTrue(0 < flows.count, @"There must be at least one way to login");
        
        BOOL foundPasswordFlowType;
        for (MXLoginFlow *flow in flows)
        {
            if ([flow.type isEqualToString:kMatrixLoginFlowTypePassword])
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

- (void)testRegisterPasswordBased
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    // Provide an empty string as user, the HS will provide one for us
    [homeServer registerWithUser:@"" andPassword:MXTESTS_PWD
                         success:^(MXLoginResponse *credentials) {
                             
                             XCTAssertNotNil(credentials);
                             XCTAssertNotNil(credentials.home_server);
                             XCTAssertNotNil(credentials.user_id);
                             XCTAssertNotNil(credentials.access_token);
                             
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
        [homeServer registerWithUser:MXTESTS_USER andPassword:MXTESTS_PWD
                             success:^(MXLoginResponse *credentials) {
                                 
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

    [homeServer getLoginFlow:^(NSArray *flows) {
        
        XCTAssertTrue(0 < flows.count, @"There must be at least one way to login");
        
        BOOL foundPasswordFlowType;
        for (MXLoginFlow *flow in flows)
        {
            if ([flow.type isEqualToString:kMatrixLoginFlowTypePassword])
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

- (void)testLoginPasswordBased
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    [self createTestAccount:^{
        [homeServer loginWithUser:MXTESTS_USER andPassword:MXTESTS_PWD
                          success:^(MXLoginResponse *credentials) {
                              
                              XCTAssertNotNil(credentials);
                              XCTAssertNotNil(credentials.home_server);
                              XCTAssertNotNil(credentials.user_id);
                              XCTAssertNotNil(credentials.access_token);
                              
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
        [homeServer loginWithUser:MXTESTS_USER andPassword:[NSString stringWithFormat:@"wrong%@", MXTESTS_PWD]
                          success:^(MXLoginResponse *credentials) {
                              
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [homeServer publicRooms:^(NSArray *rooms) {
            
            XCTAssertTrue(0 < rooms.count, @"Valid init");
            
            MXPublicRoom *theMXPublicRoom;
            for (MXPublicRoom *room in rooms)
            {
                // Find the Matrix HQ room (#matrix:matrix.org) by its ID
                if ([room.room_id isEqualToString:room_id])
                {
                    theMXPublicRoom = room;
                }
            }
            
            XCTAssertNotNil(theMXPublicRoom);
            XCTAssertTrue([theMXPublicRoom.name  isEqualToString:@"MX Public Room test"]);
            XCTAssertTrue([theMXPublicRoom.topic isEqualToString:@"The public room used by SDK tests"]);
            XCTAssertGreaterThan(theMXPublicRoom.num_joined_members, 0, @"The is at least mxBob at #matrix:matrix.org");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

@end
