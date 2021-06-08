/*
 Copyright 2015 OpenMarket Ltd

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

#import "MXLogger.h"

#import "MXLog.h"

#import "MatrixSDKSwiftHeader.h"

@interface MXLoggerUnitTests : XCTestCase

@end

@implementation MXLoggerUnitTests

- (void)testMXLogger
{
    MXLogConfiguration *configuration = [[MXLogConfiguration alloc] init];
    configuration.redirectLogsToFiles = YES;
    
    [MXLog configure:configuration];
    
    NSString *log = @"Lorem ipsum dolor sit amet";
    MXLogDebug(@"%@", log);
    
    configuration.redirectLogsToFiles = NO;
    [MXLog configure:configuration];
    
    NSArray *logFiles = [MXLogger logFiles];
    XCTAssertGreaterThanOrEqual(logFiles.count, 1);
    
    // The last string in logFiles should be "console.log"
    NSString* logContent = [NSString stringWithContentsOfFile:logFiles[logFiles.count - 1]
                                                     encoding:NSUTF8StringEncoding
                                                        error:NULL];
    
    if (0 == [logContent rangeOfString:log].length)
    {
        XCTFail(@"%@ does not contain %@\nIts content: %@", logFiles[logFiles.count - 1], log, logContent);
    }
}

- (void)testDeleteLogFiles
{
    [MXLogger redirectNSLogToFiles:YES];
    
    NSString *log = [NSString stringWithFormat:@"testLogFileContent: %@", [NSDate date]];
    MXLogDebug(@"%@", log);
    
    [MXLogger redirectNSLogToFiles:NO];
    
    [MXLogger deleteLogFiles];
    
    NSArray *logFiles = [MXLogger logFiles];
    XCTAssertEqual(logFiles.count, 0, @"All log files must have been deleted. deleteLogFiles returned: %@", logFiles);
}

@end
