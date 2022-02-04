/*
 Copyright 2019 New Vector Ltd

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

#import "MXAutoDiscovery.h"
#import "MXTools.h"

#import <OHHTTPStubs/HTTPStubs.h>

#pragma mark - Constant definition
static NSString *const kWellKnowPath = @".well-known/matrix/client";
static NSString *const kVersionPath = @"_matrix/client/versions";
static NSString *const kIdentityServerPingPath = @"_matrix/identity/api/v1";

@interface MXAutoDiscoveryTests : XCTestCase
@end

@implementation MXAutoDiscoveryTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [HTTPStubs removeAllStubs];

    [super tearDown];
}

- (void)stubRequestsContaining:(NSString*)string withResponse:(nullable NSString*)response statusCode:(int)statusCode headers:(nullable NSDictionary*)httpHeaders
{
    [HTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest *request) {
        return [request.URL.absoluteString containsString:string];
    } withStubResponse:^HTTPStubsResponse*(NSURLRequest *request) {

        NSString *responseString = response ? response : @"";
        return [HTTPStubsResponse responseWithData:[responseString dataUsingEncoding:NSUTF8StringEncoding]
                                          statusCode:statusCode
                                             headers:httpHeaders];
    }];
}

- (void)stubRequestsContaining:(NSString*)string withResponse:(nullable NSString*)response statusCode:(int)statusCode
{
    [self stubRequestsContaining:string
                    withResponse:response
                      statusCode:statusCode
                         headers:nil];
}


- (void)stubRequestsContaining:(NSString*)path withJSONResponse:(nullable NSDictionary*)JSONResponse statusCode:(int)statusCode
{
    [self stubRequestsContaining:path
                    withResponse:[MXTools serialiseJSONObject:JSONResponse]
                      statusCode:statusCode
                         headers:@{ @"Content-Type": @"application/json" }];
}

- (MXHTTPOperation *)doFindClientConfig:(void (^)(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig))complete
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    MXAutoDiscovery *autoDiscovery = [[MXAutoDiscovery alloc] initWithDomain:@"homeserver"];
    MXHTTPOperation *operation = [autoDiscovery findClientConfig:^(MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        complete(expectation, discoveredClientConfig);

    } failure:^(NSError * _Nonnull error) {
        XCTFail(@"The request should not fail - NSError: %@", error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:30 handler:nil];

    return operation;
}


// If the returned status code is 404, then IGNORE.
- (void)testAutoDiscoveryNotFound
{
    [self stubRequestsContaining:kWellKnowPath withResponse:nil statusCode:404];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionIgnore);
        [expectation fulfill];
    }];
}

// If the returned status code is not 200 then FAIL_PROMPT.
- (void)testAutoDiscoveryNotOK
{
    [self stubRequestsContaining:kWellKnowPath withResponse:nil statusCode:500];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionFailPrompt);
        [expectation fulfill];
    }];
}

// If the response body is empty then FAIL_PROMPT.
- (void)testAutoDiscoveryEmptyBody
{
    [self stubRequestsContaining:kWellKnowPath withResponse:nil statusCode:200];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionFailPrompt);
        [expectation fulfill];
    }];
}

//   If the content cannot be parsed, then FAIL_PROMPT.
- (void)testAutoDiscoveryNotJSON
{
    NSString *mockBody = @"<html><h1>Hello world!</h1></html>";
    [self stubRequestsContaining:kWellKnowPath withResponse:mockBody statusCode:200 headers:nil];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionFailPrompt);
        [expectation fulfill];
    }];
}

// If m.homeserver value is not provided, then FAIL_PROMPT.
- (void)testAutoDiscoveryMissingHS
{
    NSDictionary *mockBody = @{
                               @"m.homesorv4r": @{}
                               };
    [self stubRequestsContaining:kWellKnowPath withJSONResponse:mockBody statusCode:200];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionFailPrompt);
        [expectation fulfill];
    }];
}

// If base_url from m.homeserver is not provided, then FAIL_PROMPT.
- (void)testAutoDiscoveryMissingHSBaseURl
{
    NSDictionary *mockBody = @{
                               @"m.homeserver": @{}
                               };
    [self stubRequestsContaining:kWellKnowPath withJSONResponse:mockBody statusCode:200];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionFailPrompt);
        [expectation fulfill];
    }];
}

// If base_url from m.homeserver is not an URL, then FAIL_ERROR.
- (void)testAutoDiscoveryHSBaseURLInvalid
{
    NSDictionary *mockBody = @{
                               @"m.homeserver": @{
                                       @"base_url": @"foo\\$[level]/r\\$[y]"
                                       }
                               };
    [self stubRequestsContaining:kWellKnowPath withJSONResponse:mockBody statusCode:200];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionFailError);
        [expectation fulfill];
    }];
}

// If base_url from m.homeserver is not a valid HS, then FAIL_ERROR.
- (void)testAutoDiscoveryNotValidHSURL
{
    NSString *baseURL = @"https://myhs.org";

    NSDictionary *mockBody = @{
                               @"m.homeserver": @{
                                       @"base_url": baseURL
                                       }
                               };
    [self stubRequestsContaining:kWellKnowPath withJSONResponse:mockBody statusCode:200];
    [self stubRequestsContaining:baseURL withResponse:nil statusCode:404];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionFailError);
        [expectation fulfill];
    }];
}

// If base_url from m.homeserver is a valid HS, then PROMPT.
- (void)testAutoDiscoveryHomeserverSuccess
{
    NSString *baseURL = @"https://myhs.org";

    NSDictionary *mockBody = @{
                               @"m.homeserver": @{
                                       @"base_url": baseURL
                                       }
                               };
    NSDictionary *hsVersionResponse = @{
        @"versions": @[@"r0.4.0"],
        @"unstable_features": @{
                @"m.lazy_load_members": @(YES)
                }
        };
    [self stubRequestsContaining:kWellKnowPath withJSONResponse:mockBody statusCode:200];
    [self stubRequestsContaining:kVersionPath withJSONResponse:hsVersionResponse statusCode:200];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionPrompt);
        XCTAssertEqualObjects(discoveredClientConfig.wellKnown.homeServer.baseUrl, baseURL);
        XCTAssertNil(discoveredClientConfig.wellKnown.identityServer);

        [expectation fulfill];
    }];
}

// If base_url from m.identity_server is not a valid IS, then FAIL_ERROR.
- (void)testAutoDiscoveryInvalidIdendityServer
{
    NSString *baseURL = @"https://myhs.org";
    NSString *identityServerBaseURL = @"https://boom.org";

    NSDictionary *mockBody = @{
                               @"m.homeserver": @{
                                       @"base_url" : baseURL
                                       },
                               @"m.identity_server": @{
                                       @"base_url": identityServerBaseURL
                                       }
                               };
    NSDictionary *hsVersionResponse = @{
                                        @"versions": @[@"r0.4.0"],
                                        @"unstable_features": @{
                                                @"m.lazy_load_members": @(YES)
                                                }
                                        };
    [self stubRequestsContaining:kWellKnowPath withJSONResponse:mockBody statusCode:200];
    [self stubRequestsContaining:kVersionPath withJSONResponse:hsVersionResponse statusCode:200];
    [self stubRequestsContaining:kIdentityServerPingPath withResponse:nil statusCode:404];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionFailError);
        [expectation fulfill];
    }];
}

// If base_url from m.homeserver and m.identity_server are valid HS and IS, then PROMPT.
- (void)testAutoDiscoverySuccessful
{
    NSString *baseURL = @"https://myhs.org";
    NSString *identityServerBaseURL = @"https://boom.org";

    NSDictionary *mockBody = @{
                               @"m.homeserver": @{
                                       @"base_url" : baseURL
                                       },
                               @"m.identity_server": @{
                                       @"base_url": identityServerBaseURL
                                       }
                               };
    NSDictionary *hsVersionResponse = @{
                                        @"versions": @[@"r0.4.0"],
                                        @"unstable_features": @{
                                                @"m.lazy_load_members": @(YES)
                                                }
                                        };
    NSDictionary *identityServerResponse = @{};
    [self stubRequestsContaining:kWellKnowPath withJSONResponse:mockBody statusCode:200];
    [self stubRequestsContaining:kVersionPath withJSONResponse:hsVersionResponse statusCode:200];
    [self stubRequestsContaining:kIdentityServerPingPath withJSONResponse:identityServerResponse statusCode:202];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionPrompt);
        XCTAssertEqualObjects(discoveredClientConfig.wellKnown.homeServer.baseUrl, baseURL);
        XCTAssertEqualObjects(discoveredClientConfig.wellKnown.identityServer.baseUrl, identityServerBaseURL);

        [expectation fulfill];
    }];
}

// Same test as testAutoDiscoverySuccessful but with .well-known/matrix/client
// not returned with a JSON content type.
// This is what happens on matrix.org
- (void)testAutoDiscoverySuccessfulWithNoContentType
{
    NSString *baseURL = @"https://myhs.org";
    NSString *identityServerBaseURL = @"https://boom.org";

    NSDictionary *mockBody = @{
                               @"m.homeserver": @{
                                       @"base_url" : baseURL
                                       },
                               @"m.identity_server": @{
                                       @"base_url": identityServerBaseURL
                                       }
                               };
    NSDictionary *hsVersionResponse = @{
                                        @"versions": @[@"r0.4.0"],
                                        @"unstable_features": @{
                                                @"m.lazy_load_members": @(YES)
                                                }
                                        };
    NSDictionary *identityServerResponse = @{};
    // Do no return a content type
    [self stubRequestsContaining:kWellKnowPath withResponse:[MXTools serialiseJSONObject:mockBody] statusCode:200 headers:nil];
    [self stubRequestsContaining:kVersionPath withJSONResponse:hsVersionResponse statusCode:200];
    [self stubRequestsContaining:kIdentityServerPingPath withJSONResponse:identityServerResponse statusCode:202];

    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {

        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionPrompt);
        XCTAssertEqualObjects(discoveredClientConfig.wellKnown.homeServer.baseUrl, baseURL);
        XCTAssertEqualObjects(discoveredClientConfig.wellKnown.identityServer.baseUrl, identityServerBaseURL);

        [expectation fulfill];
    }];
}


// Test that MXWellKnown.JSONDictionary keeps original extended data
- (void)testAutoDiscoveryWellKnownJSONDictionary
{
    NSString *baseURL = @"https://myhs.org";
    NSString *tileServerMapStyleURL = @"https://your.tileserver.org/style.json";
    
    NSDictionary *mockBody = @{
                               @"m.homeserver": @{
                                       @"base_url" : baseURL
                                       },
                               @"m.tile_server": @{
                                       @"map_style_url": tileServerMapStyleURL
                                       },
                               @"im.vector.riot.e2ee": @{
                                       @"default": @(NO)
                                       }
                               };
    NSDictionary *hsVersionResponse = @{
                                        @"versions": @[@"r0.4.0"],
                                        @"unstable_features": @{
                                                @"m.lazy_load_members": @(YES)
                                                }
                                        };
    [self stubRequestsContaining:kWellKnowPath withJSONResponse:mockBody statusCode:200];
    [self stubRequestsContaining:kVersionPath withJSONResponse:hsVersionResponse statusCode:200];
    
    [self doFindClientConfig:^(XCTestExpectation *expectation, MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {
        
        XCTAssertEqualObjects(discoveredClientConfig.wellKnown.JSONDictionary, mockBody);
        XCTAssertEqualObjects(discoveredClientConfig.wellKnown.tileServer.mapStyleURLString, tileServerMapStyleURL);
        
        // Check parsing
        BOOL isE2EByDefaultEnabledByHSAdmin = YES;
        MXWellKnown *wellKnown = discoveredClientConfig.wellKnown;
        if (wellKnown.JSONDictionary[@"im.vector.riot.e2ee"][@"default"])
        {
            MXJSONModelSetBoolean(isE2EByDefaultEnabledByHSAdmin, wellKnown.JSONDictionary[@"im.vector.riot.e2ee"][@"default"]);
        }
        XCTAssertFalse(isE2EByDefaultEnabledByHSAdmin);
        
        [expectation fulfill];
    }];
}



// Test on matrix.org
// Only for development. Must be disabled for automatic tests
//- (void)testAutoDiscoveryWithMatrixDotOrg
//{
//    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
//
//    MXAutoDiscovery *autoDiscovery = [[MXAutoDiscovery alloc] initWithDomain:@"matrix.org"];
//    [autoDiscovery findClientConfig:^(MXDiscoveredClientConfig * _Nonnull discoveredClientConfig) {
//
//        XCTAssertEqual(discoveredClientConfig.action, MXDiscoveredClientConfigActionPrompt);
//        XCTAssertEqualObjects(discoveredClientConfig.wellKnown.homeServer.baseUrl, @"https://matrix.org");
//        XCTAssertEqualObjects(discoveredClientConfig.wellKnown.identityServer.baseUrl,  @"https://vector.im");
//
//        [expectation fulfill];
//
//    } failure:^(NSError * _Nonnull error) {
//        XCTFail(@"The request should not fail - NSError: %@", error);
//        [expectation fulfill];
//    }];
//
//    [self waitForExpectationsWithTimeout:30 handler:nil];
//}

@end
