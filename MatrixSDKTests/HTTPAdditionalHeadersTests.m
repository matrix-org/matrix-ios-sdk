//
//  HTTPAdditionalHeadersTests.m
//  MatrixSDKTests-iOS
//
//  Created by Ismail on 19.08.2020.
//  Copyright © 2020 matrix.org. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "MXTools.h"
#import "MXRestClient.h"
#import "MXSDKOptions.h"

#import <OHHTTPStubs/HTTPStubs.h>

static NSString *const kVersionPath = @"_matrix/client/versions";
static NSString *const kUserAgent = @"Dummy-User-Agent";

@interface HTTPAdditionalHeadersTests : XCTestCase

@end

@implementation HTTPAdditionalHeadersTests

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
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    [HTTPStubs removeAllStubs];
    
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
