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

#import <Foundation/Foundation.h>

/**
 The `MXLogger` tool redirects NSLog output into a fixed pool of files.
 Another log file is used every time [MXLogger redirectNSLogToFiles:YES]
 is called. The pool contains 3 files.
 
 `MXLogger` can track and log uncatched exceptions or crashes.
 */
@interface MXLogger : NSObject

/**
 Redirect NSLog output to MXLogger files.
 
 It is advised to condition this redirection in '#if (!isatty(STDERR_FILENO))' block to enable
 it only when the device is not attached to the debugger.

 @param redirectNSLogToFiles YES to enable the redirection.
 */
+ (void)redirectNSLogToFiles:(BOOL)redirectNSLogToFiles;

/**
 Delete all log files.
 */
+ (void)deleteLogFiles;

/**
 Get the list of all log files.
 
 @return files of
 */
+ (NSArray*)logFiles;

/**
 Make `MXLogger` catch and log unmanaged exceptions or application crashes.

 When such error happens, `MXLogger` stores the application stack trace into a file
 just before the application leaves. The path of this file is provided by [MXLogger crashLog].
 
 @param logCrashes YES to enable the catch.
 */
+ (void)logCrashes:(BOOL)logCrashes;

/**
 If any, get the file containing the last application crash log.
 
 Only one crash log is stored at a time. The best moment for the app to handle it is the 
 at its next startup.
 
 @return the crash log file. nil if there is none.
 */
+ (NSString*)crashLog;

/**
 Delete the crash log file.
 */
+ (void)deleteCrashLog;

@end
