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

#import "MXLogger.h"

#import "MatrixSDK.h"

// stderr so it can be restored
int stderrSave = 0;

#define MXLOGGER_CRASH_LOG @"crash.log"

@implementation MXLogger

#pragma mark - NSLog redirection
+ (void)redirectNSLogToFiles:(BOOL)redirectNSLogToFiles
{
    if (redirectNSLogToFiles)
    {
        // Set log location
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];

        // Do a circular buffer based on 3 files
        for (NSInteger index = 1; index >= 0; index--)
        {
            NSString *nsLogPathOlder;
            NSString *nsLogPathCurrent;

            if (index == 0)
            {
                nsLogPathOlder   = @"console.1.log";
                nsLogPathCurrent = @"console.log";
            }
            else
            {
                nsLogPathOlder   = [NSString stringWithFormat:@"console.%tu.log", index + 1];
                nsLogPathCurrent = [NSString stringWithFormat:@"console.%tu.log", index];
            }

            nsLogPathOlder = [documentsDirectory stringByAppendingPathComponent:nsLogPathOlder];
            nsLogPathCurrent = [documentsDirectory stringByAppendingPathComponent:nsLogPathCurrent];

            if([fileManager fileExistsAtPath:nsLogPathCurrent])
            {
                if([fileManager fileExistsAtPath:nsLogPathOlder])
                {
                    [fileManager removeItemAtPath:nsLogPathOlder error:nil];
                }
                [fileManager copyItemAtPath:nsLogPathCurrent toPath:nsLogPathOlder error:nil];
            }
        }

        // Save stderr so it can be restored.
        stderrSave = dup(STDERR_FILENO);

        NSString *nsLogPath = [documentsDirectory stringByAppendingPathComponent:@"console.log"];
        freopen([nsLogPath fileSystemRepresentation], "w+", stderr);
    }
    else if (stderrSave)
    {
        // Flush before restoring stderr
        fflush(stderr);

        // Now restore stderr, so new output goes to console.
        dup2(stderrSave, STDERR_FILENO);
        close(stderrSave);
    }
}

+ (void)deleteLogFiles
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *logFile in [self logFiles])
    {
        [fileManager removeItemAtPath:logFile error:nil];
    }
}

+ (NSArray*)logFiles
{
    NSMutableArray *logFiles = [NSMutableArray array];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:documentsDirectory];

    // Find all *.log files
    NSString *file = nil;
    while ((file = [dirEnum nextObject]))
    {
        if ([[file lastPathComponent] hasPrefix:@"console."])
        {
            NSString *logPath = [documentsDirectory stringByAppendingPathComponent:file];
            [logFiles addObject:logPath];
        }
    }
    return logFiles;
}


#pragma mark - Exceptions and crashes
// Exceptions uncaught by try catch block are handled here
static void handleUncaughtException(NSException *exception)
{
    [MXLogger logCrashes:NO];

    // Extract running app information
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* appVersion;
    NSString* app, *appId;

    app = infoDict[@"CFBundleExecutable"];
    appId = infoDict[@"CFBundleIdentifier"];

    if ([infoDict objectForKey:@"CFBundleVersion"])
    {
        appVersion =  [NSString stringWithFormat:@"%@ (r%@)", [infoDict objectForKey:@"CFBundleShortVersionString"],  [infoDict objectForKey:@"CFBundleVersion"]];
    }
    else
    {
        appVersion =  [infoDict objectForKey:@"CFBundleShortVersionString"];
    }

    // Build the crash log
    NSString *model = [[UIDevice currentDevice] model];
    NSString *version = [[UIDevice currentDevice] systemVersion];
    NSArray  *backtrace = [exception callStackSymbols];
    NSString *description = [NSString stringWithFormat:@"[%@]\n%@\nApplication: %@ (%@)\nApplication version: %@\nMatrix SDK version: %@\n%@ %@\n%@\n",
                             [NSDate date],
                             exception.description,
                             app, appId,
                             appVersion,
                             MatrixSDKVersion,
                             model, version,
                             backtrace];

    // Write to the crash log file
    [MXLogger deleteCrashLog];
    NSString *crashLog = crashLogPath();
    [description writeToFile:crashLog
                  atomically:NO
                    encoding:NSStringEncodingConversionAllowLossy
                       error:nil];

    NSLog(@"[MXLogger] handleUncaughtException:\n%@", description);
}

// Signals emitted by the app are handled here
static void handleSignal(int signalValue)
{
    // Throw a custom Objective-C exception
    // The Objective-C runtime will then be able to build a readable call stack in handleUncaughtException
    [NSException raise:@"Signal detected" format:@"Signal detected: %d", signalValue];
}

+ (void)logCrashes:(BOOL)logCrashes
{
    if (logCrashes)
    {
        // Handle not managed exceptions by ourselves
        NSSetUncaughtExceptionHandler(&handleUncaughtException);

        // Register signal event (seg fault & cie)
        signal(SIGABRT, handleSignal);
        signal(SIGILL, handleSignal);
        signal(SIGSEGV, handleSignal);
        signal(SIGFPE, handleSignal);
        signal(SIGBUS, handleSignal);
    }
    else
    {
        // Disable crash handling
        NSSetUncaughtExceptionHandler(NULL);
        signal(SIGABRT, SIG_DFL);
        signal(SIGILL, SIG_DFL);
        signal(SIGSEGV, SIG_DFL);
        signal(SIGFPE, SIG_DFL);
        signal(SIGBUS, SIG_DFL);
    }
}
// Return the path of the crash log file
static NSString* crashLogPath(void)
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];

    return [documentsDirectory stringByAppendingPathComponent:MXLOGGER_CRASH_LOG];
}

+ (NSString*)crashLog
{
    NSString *exceptionLog;

    NSString *crashLog = crashLogPath();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if([fileManager fileExistsAtPath:crashLog])
    {
        exceptionLog = crashLog;
    }
    return exceptionLog;
}

+ (void)deleteCrashLog
{
    NSString *crashLog = crashLogPath();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if([fileManager fileExistsAtPath:crashLog])
    {
        [fileManager removeItemAtPath:crashLog error:nil];
    }
}

@end


