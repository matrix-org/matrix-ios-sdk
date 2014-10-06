//
//  MXErrorTests.m
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 06/10/14.
//  Copyright (c) 2014 matrix.org. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MXError.h"

NSString *const myErrCode = @"MY_MATRIX_ERR_CODE";
NSString *const myError = @"This is detailed information about this fake error";


@interface MXErrorTests : XCTestCase
{
    MXError *mxError;
}
@end

@implementation MXErrorTests

- (void)setUp
{
    [super setUp];

    mxError = [[MXError alloc] initWithErrorCode:myErrCode error:myError];
}

- (void)tearDown
{
    mxError = nil;
    
    [super tearDown];
}

- (void)testInit
{
    XCTAssert([mxError.errCode isEqualToString:myErrCode], @"Valid error");
    XCTAssert([mxError.error isEqualToString:myError], @"Valid errCode");
}

- (void)testNSError
{
    NSError *nsError = [mxError createNSError];
    XCTAssert(nil != nsError, @"Valid nsError");
    XCTAssert([nsError.domain isEqualToString:kMatrixNSErrorDomain], @"Valid nsError domain");
    
    XCTAssert([MXError isMXError:nsError], @"This NSError must be in MXError domain");

    MXError *mxError2 = [[MXError alloc] initWithNSError:nsError];
    XCTAssert(nil != nsError, @"Valid MXError extraction");
    XCTAssert([mxError2.errCode isEqualToString:mxError.errCode], @"Valid error");
    XCTAssert([mxError2.error isEqualToString:mxError.error], @"Valid errCode");
}

- (void)testNonMatrixNSError
{
    NSError *nsError = [NSError errorWithDomain: @"bar.foo"
                                           code: 1
                                       userInfo: nil];
    
    XCTAssert(NO == [MXError isMXError:nsError], @"This NSError must not be in MXError domain");
    
    MXError *mxError2 = [[MXError alloc] initWithNSError:nsError];
    XCTAssert(nil == mxError2, @"We should not be init an MXError from this non-compatible NSError");
}


@end
