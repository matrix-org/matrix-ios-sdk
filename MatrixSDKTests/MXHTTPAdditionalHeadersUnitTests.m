//
// Copyright 2020 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <XCTest/XCTest.h>

#import "MXTools.h"
#import "MXRestClient.h"
#import "MXSDKOptions.h"

#import <OHHTTPStubs/HTTPStubs.h>

static NSString *const kVersionPath = @"_matrix/client/versions";
static NSString *const kUserAgent = @"Dummy-User-Agent";

@interface MXHTTPAdditionalHeadersUnitTests : XCTestCase

@end

@implementation MXHTTPAdditionalHeadersUnitTests

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

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [HTTPStubs removeAllStubs];
    
    [MXSDKOptions sharedInstance].HTTPAdditionalHeaders = @{};
    
    [super tearDown];
}

- (void)testUserAgent
{
    NSString *baseURL = @"https://myhs.org";

    NSDictionary *hsVersionResponse = @{
        @"versions": @[@"r0.4.0"],
        @"unstable_features": @{
                @"m.lazy_load_members": @(YES)
                }
        };
    
    [self stubRequestsContaining:kVersionPath withJSONResponse:hsVersionResponse statusCode:200];
    
    [MXSDKOptions sharedInstance].HTTPAdditionalHeaders = @{
        @"User-Agent": kUserAgent
    };
    
    MXRestClient *restClient = [[MXRestClient alloc] initWithHomeServer:baseURL andOnUnrecognizedCertificateBlock:nil];
    
    MXHTTPOperation *operation = [restClient supportedMatrixVersions:nil failure:nil];
    
    NSString *userAgent = operation.operation.currentRequest.allHTTPHeaderFields[@"User-Agent"];
    XCTAssertEqual(userAgent, kUserAgent);
}

@end
