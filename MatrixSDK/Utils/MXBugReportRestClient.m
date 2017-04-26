/*
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

#import "MXBugReportRestClient.h"

#import "MXLogger.h"
#import "MatrixSDK.h"

#import <AFNetworking/AFNetworking.h>
#import <GZIP/GZIP.h>

#ifdef MX_CRYPTO
#import <OLMKit/OLMKit.h>
#endif

#if __has_include(<MatrixKit/MatrixKit.h>)
#import <MatrixKit/MatrixKit.h>
#endif

@interface MXBugReportRestClient ()
{
    // The bug report API server URL.
    NSString *bugReportEndpoint;

    // Use AFNetworking as HTTP client.
    AFURLSessionManager *manager;

    // The temporary zipped log files.
    NSMutableArray<NSURL*> *logZipFiles;
}

@end

@implementation MXBugReportRestClient

- (instancetype)initWithBugReportEndpoint:(NSString *)theBugReportEndpoint
{
    self = [super init];
    if (self)
    {
        bugReportEndpoint = theBugReportEndpoint;

        manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

        logZipFiles = [NSMutableArray array];

        _userAgent = @"iOS";
        _deviceModel = [[UIDevice currentDevice] model];
        _deviceOS = [NSString stringWithFormat:@"%@ %@", [[UIDevice currentDevice] systemName], [[UIDevice currentDevice] systemVersion]];
    }

    return self;
}

- (void)sendBugReport:(NSString *)text sendLogs:(BOOL)sendLogs success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    // The bugreport api needs at least app and version to render well
    NSParameterAssert(_appName && _version);

    NSString *apiPath = [NSString stringWithFormat:@"%@/api/submit", bugReportEndpoint];

    if (manager.tasks.count)
    {
        NSLog(@"[MXBugReport] sendBugReport failed. There is already a submission in progress");

        if (failure)
        {
            failure(nil);
        }
        return;
    }

    // Zip log files into temporary files
    if (sendLogs)
    {
        NSDate *startDate = [NSDate date];
        NSArray *logFiles = [MXLogger logFiles];
        for (NSString *logFile in logFiles)
        {
            // Use a temporary file for the export
            NSURL *logZipFile = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:logFile.lastPathComponent]];

            [[NSFileManager defaultManager] removeItemAtURL:logZipFile error:nil];

            NSData *logData = [NSData dataWithContentsOfFile:logFile];
            NSData *logZipData = [logData gzippedData];

            if ([logZipData writeToURL:logZipFile atomically:YES])
            {
                [logZipFiles addObject:logZipFile];
            }
            else
            {
                NSLog(@"[MXBugReport] sendBugReport: Failed to zip %@", logFile);
            }
        }

        NSLog(@"[MXBugReport] sendBugReport: Zipped %tu logs in %.3fms", logFiles.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
    }

    NSDate *startDate = [NSDate date];

    // Populate multipart form data
    NSError *error;
    NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] multipartFormRequestWithMethod:@"POST" URLString:apiPath parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {

        // Fill params defined in https://github.com/matrix-org/rageshake#post-apisubmit
        if (text)
        {
            [formData appendPartWithFormData:[text dataUsingEncoding:NSUTF8StringEncoding] name:@"text"];
        }
        if (_userAgent)
        {
            [formData appendPartWithFormData:[_userAgent dataUsingEncoding:NSUTF8StringEncoding] name:@"user_agent"];
        }
        if (_appName)
        {
            [formData appendPartWithFormData:[_appName dataUsingEncoding:NSUTF8StringEncoding] name:@"app"];
        }
        if (_version)
        {
            [formData appendPartWithFormData:[_version dataUsingEncoding:NSUTF8StringEncoding] name:@"version"];
        }

        // Add each zipped log file
        for (NSURL *logZipFile in logZipFiles)
        {
            [formData appendPartWithFileURL:logZipFile
                                       name:@"compressed-log"
                                   fileName:logZipFile.absoluteString.lastPathComponent
                                   mimeType:@"application/octet-stream"
                                      error:nil];
        }

        // Add iOS specific params
        if (_build)
        {
            [formData appendPartWithFormData:[_build dataUsingEncoding:NSUTF8StringEncoding] name:@"build"];
        }

#if __has_include(<MatrixKit/MatrixKit.h>)
        [formData appendPartWithFormData:[MatrixKitVersion dataUsingEncoding:NSUTF8StringEncoding] name:@"matrix_kit_version"];
#endif

        [formData appendPartWithFormData:[MatrixSDKVersion dataUsingEncoding:NSUTF8StringEncoding] name:@"matrix_sdk_version"];

#ifdef MX_CRYPTO
        [formData appendPartWithFormData:[[OLMKit versionString] dataUsingEncoding:NSUTF8StringEncoding] name:@"olm_kit_version"];
#endif

        if (_deviceModel)
        {
            [formData appendPartWithFormData:[_deviceModel dataUsingEncoding:NSUTF8StringEncoding] name:@"device"];
        }
        if (_deviceOS)
        {
            [formData appendPartWithFormData:[_deviceOS dataUsingEncoding:NSUTF8StringEncoding] name:@"os"];
        }

        // Additional custom data
        for (NSString *key in _others)
        {
            [formData appendPartWithFormData:[_others[key] dataUsingEncoding:NSUTF8StringEncoding] name:key];
        }

    } error:&error];

    if (error)
    {
        NSLog(@"[MXBugReport] sendBugReport: multipartFormRequestWithMethod failed. Error: %@", error);
        if (failure)
        {
            failure(error);
        }
        return;
    }

    // Launch the request
    NSURLSessionUploadTask *uploadTask = [manager
                                          uploadTaskWithStreamedRequest:request
                                          progress:^(NSProgress * _Nonnull uploadProgress) {

                                              // Move to the main queue
                                              dispatch_async(dispatch_get_main_queue(), ^{

                                                  // TODO
                                                  NSLog(@"[MXBugReport] sendBugReport: uploadProgress: %@", @(uploadProgress.fractionCompleted));
                                              });
                                          }
                                          completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {

                                              [self deleteZipZiles];

                                              if (error)
                                              {
                                                  NSLog(@"[MXBugReport] sendBugReport: report failed. Error: %@", error);

                                                  if (failure)
                                                  {
                                                      failure(error);
                                                  }
                                              }
                                              else
                                              {
                                                  NSLog(@"[MXBugReport] sendBugReport: report done in %.3fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

                                                  if (success)
                                                  {
                                                      success();
                                                  }
                                              }
                                          }];

    [uploadTask resume];
}

- (void)cancel
{
    [manager invalidateSessionCancelingTasks:YES];

    [self deleteZipZiles];
}


#pragma mark - Private methods
- (void)deleteZipZiles
{
    for (NSURL *logZipFile in logZipFiles)
    {
        [[NSFileManager defaultManager] removeItemAtURL:logZipFile error:nil];
    }

    [logZipFiles removeAllObjects];
}

@end
