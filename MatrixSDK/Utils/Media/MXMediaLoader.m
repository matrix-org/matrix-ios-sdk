/*
 Copyright 2016 OpenMarket Ltd
 
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

#import "MXMediaManager.h"

#import "MXSession.h"
#import "MXHTTPOperation.h"

#import "MXAllowedCertificates.h"
#import <AFNetworking/AFSecurityPolicy.h>

NSString *const kMXMediaDownloadProgressNotification = @"kMXMediaDownloadProgressNotification";
NSString *const kMXMediaDownloadDidFinishNotification = @"kMXMediaDownloadDidFinishNotification";
NSString *const kMXMediaDownloadDidFailNotification = @"kMXMediaDownloadDidFailNotification";

NSString *const kMXMediaUploadProgressNotification = @"kMXMediaUploadProgressNotification";
NSString *const kMXMediaUploadDidFinishNotification = @"kMXMediaUploadDidFinishNotification";
NSString *const kMXMediaUploadDidFailNotification = @"kMXMediaUploadDidFailNotification";

NSString *const kMXMediaLoaderProgressValueKey = @"kMXMediaLoaderProgressValueKey";
NSString *const kMXMediaLoaderCompletedBytesCountKey = @"kMXMediaLoaderCompletedBytesCountKey";
NSString *const kMXMediaLoaderTotalBytesCountKey = @"kMXMediaLoaderTotalBytesCountKey";
NSString *const kMXMediaLoaderCurrentDataRateKey = @"kMXMediaLoaderCurrentDataRateKey";

NSString *const kMXMediaLoaderFilePathKey = @"kMXMediaLoaderFilePathKey";
NSString *const kMXMediaLoaderErrorKey = @"kMXMediaLoaderErrorKey";

NSString *const kMXMediaUploadIdPrefix = @"upload-";

@implementation MXMediaLoader

@synthesize statisticsDict;

- (void)cancel
{
    // Cancel potential connection
    if (downloadConnection)
    {
        NSLog(@"[MXMediaLoader] Media download has been cancelled (%@)", mediaURL);
        if (onError){
            onError(nil);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaDownloadDidFailNotification
                                                            object:mediaURL
                                                          userInfo:nil];
        // Reset blocks
        onSuccess = nil;
        onError = nil;
        [downloadConnection cancel];
        downloadConnection = nil;
        downloadData = nil;
    }
    else
    {
        if (operation && operation.operation
            && operation.operation.state != NSURLSessionTaskStateCanceling && operation.operation.state != NSURLSessionTaskStateCompleted)
        {
            NSLog(@"[MXMediaLoader] Media upload has been cancelled");
            [operation cancel];
            operation = nil;
        }
        
        // Reset blocks
        onSuccess = nil;
        onError = nil;
    }
    statisticsDict = nil;
}

- (void)dealloc
{
    [self cancel];
    
    mxSession = nil;
}

#pragma mark - Download

- (void)downloadMediaFromURL:(NSString *)url
           andSaveAtFilePath:(NSString *)filePath
                     success:(blockMXMediaLoader_onSuccess)success
                     failure:(blockMXMediaLoader_onError)failure
{
    // Report provided params
    mediaURL = url;
    outputFilePath = filePath;
    onSuccess = success;
    onError = failure;
    
    downloadStartTime = statsStartTime = CFAbsoluteTimeGetCurrent();
    lastProgressEventTimeStamp = -1;
    
    // Start downloading
    NSURL *nsURL = [NSURL URLWithString:url];
    downloadData = [[NSMutableData alloc] init];
    
    downloadConnection = [[NSURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:nsURL] delegate:self];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    expectedSize = response.expectedContentLength;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"[MXMediaLoader] Failed to download media (%@): %@", mediaURL, error);
    // send the latest known upload info
    [self progressCheckTimeout:nil];
    statisticsDict = nil;
    if (onError)
    {
        onError (error);
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaDownloadDidFailNotification
                                                        object:mediaURL
                                                      userInfo:@{kMXMediaLoaderErrorKey:error}];
    
    downloadData = nil;
    downloadConnection = nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    // Append data
    [downloadData appendData:data];
    
    if (expectedSize > 0)
    {
        float progressValue = ((float)downloadData.length) / ((float)expectedSize);
        if (progressValue > 1)
        {
            // Should never happen
            progressValue = 1.0;
        }
        
        CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
        CGFloat meanRate = downloadData.length / (currentTime - downloadStartTime);
        
        // build the user info dictionary
        NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
        [dict setValue:[NSNumber numberWithFloat:progressValue] forKey:kMXMediaLoaderProgressValueKey];
        [dict setValue:[NSNumber numberWithUnsignedInteger:downloadData.length] forKey:kMXMediaLoaderCompletedBytesCountKey];
        [dict setValue:[NSNumber numberWithLongLong:expectedSize] forKey:kMXMediaLoaderTotalBytesCountKey];
        [dict setValue:[NSNumber numberWithFloat:meanRate] forKey:kMXMediaLoaderCurrentDataRateKey];
        
        statisticsDict = dict;
        
        // after 0.1s, resend the progress info
        // the upload can be stuck
        [progressCheckTimer invalidate];
        progressCheckTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(progressCheckTimeout:) userInfo:self repeats:NO];
        
        // trigger the event only each 0.1s to avoid send to many events
        if ((lastProgressEventTimeStamp == -1) || ((currentTime - lastProgressEventTimeStamp) > 0.1))
        {
            lastProgressEventTimeStamp = currentTime;
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaDownloadProgressNotification object:mediaURL userInfo:statisticsDict];
        }
    }
}

- (IBAction)progressCheckTimeout:(id)sender
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaDownloadProgressNotification object:mediaURL userInfo:statisticsDict];
    [progressCheckTimer invalidate];
    progressCheckTimer = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    // send the latest known upload info
    [self progressCheckTimeout:nil];
    statisticsDict = nil;
    
    if (downloadData.length)
    {
        // Cache the downloaded data
        if ([MXMediaManager writeMediaData:downloadData toFilePath:outputFilePath])
        {
            // Call registered block
            if (onSuccess)
            {
                onSuccess(outputFilePath);
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaDownloadDidFinishNotification
                                                                object:mediaURL
                                                              userInfo:@{kMXMediaLoaderFilePathKey: outputFilePath}];
        }
        else
        {
            NSLog(@"[MXMediaLoader] Failed to write file: %@", mediaURL);
            if (onError){
                onError(nil);
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaDownloadDidFailNotification
                                                                object:mediaURL
                                                              userInfo:nil];
        }
    }
    else
    {
        NSLog(@"[MXMediaLoader] Failed to download media: %@", mediaURL);
        if (onError){
            onError(nil);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaDownloadDidFailNotification
                                                            object:mediaURL
                                                          userInfo:nil];
    }
    
    downloadData = nil;
    downloadConnection = nil;
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    if ([protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        // List all the allowed certificates to pin against.
        NSMutableArray *pinnedCertificates = [NSMutableArray array];
        
        NSSet <NSData *> *certificates = [AFSecurityPolicy certificatesInBundle:[NSBundle mainBundle]];
        for (NSData *certificateData in certificates)
        {
            [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
        }
        certificates = [MXAllowedCertificates sharedInstance].certificates;
        for (NSData *certificateData in certificates)
        {
            [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
        }
        
        if (pinnedCertificates.count > 0)
        {
            SecTrustSetAnchorCertificates(protectionSpace.serverTrust, (__bridge CFArrayRef)pinnedCertificates);
            // Reenable trusting anchor certificates in addition to those passed in via the SecTrustSetAnchorCertificates API.
            SecTrustSetAnchorCertificatesOnly(protectionSpace.serverTrust, false);
        }
        
        SecTrustRef trust = [protectionSpace serverTrust];

        // Re-evaluate the trust policy
        SecTrustResultType secresult = kSecTrustResultInvalid;
        if (SecTrustEvaluate(trust, &secresult) != errSecSuccess)
        {
            // Trust evaluation failed
            [connection cancel];

            // Generate same kind of error as AFNetworking
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:kCFURLErrorCancelled userInfo:nil];
            [self connection:connection didFailWithError:error];
        }
        else
        {
            switch (secresult)
            {
                case kSecTrustResultUnspecified:    // The OS trusts this certificate implicitly.
                case kSecTrustResultProceed:        // The user explicitly told the OS to trust it.
                {
                    NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
                    [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
                    break;
                }

                default:
                {
                    // Consider here the leaf certificate (the one at index 0).
                    SecCertificateRef certif = SecTrustGetCertificateAtIndex(trust, 0);

                    NSData *certificate = (__bridge NSData*)SecCertificateCopyData(certif);

                    // Was it already trusted by the user ?
                    if ([[MXAllowedCertificates sharedInstance] isCertificateAllowed:certificate])
                    {
                        NSURLCredential *credential = [NSURLCredential credentialForTrust:protectionSpace.serverTrust];
                        [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                    }
                    else
                    {
                        NSLog(@"[MXMediaLoader] Certificate check failed for %@", protectionSpace);
                        [connection cancel];

                        // Generate same kind of error as AFNetworking
                        NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:kCFURLErrorCancelled userInfo:nil];
                        [self connection:connection didFailWithError:error];
                    }
                    break;
                }
            }
        }
    }
}

#pragma mark - Upload

- (id)initForUploadWithMatrixSession:(MXSession*)matrixSession initialRange:(CGFloat)initialRange andRange:(CGFloat)range
{
    if (self = [super init])
    {
        // Create a unique upload Id
        _uploadId = [NSString stringWithFormat:@"%@%@", kMXMediaUploadIdPrefix, [[NSProcessInfo processInfo] globallyUniqueString]];
        
        mxSession = matrixSession;
        _uploadInitialRange = initialRange;
        _uploadRange = range;
    }
    return self;
}

- (void)uploadData:(NSData *)data filename:(NSString*)filename mimeType:(NSString *)mimeType success:(blockMXMediaLoader_onSuccess)success failure:(blockMXMediaLoader_onError)failure
{
    statsStartTime = CFAbsoluteTimeGetCurrent();
    lastTotalBytesWritten = 0;
    
    operation = [mxSession.matrixRestClient uploadContent:data
                                                 filename:filename
                                                 mimeType:mimeType
                                                  timeout:30
                                                  success:^(NSString *url) {
                                                      if (success)
                                                      {
                                                          success(url);
                                                      }
                                                      [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaUploadDidFinishNotification
                                                                                                          object:_uploadId
                                                                                                        userInfo:nil];
                                                  } failure:^(NSError *error) {
                                                      if (failure)
                                                      {
                                                          failure (error);
                                                      }
                                                      [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaUploadDidFailNotification
                                                                                                          object:_uploadId
                                                                                                        userInfo:@{kMXMediaLoaderErrorKey:error}];
                                                  } uploadProgress:^(NSProgress *uploadProgress) {
                                                      [self updateUploadProgress:uploadProgress];
                                                  }];
}

- (void)updateUploadProgress:(NSProgress*)uploadProgress
{
    int64_t totalBytesWritten = uploadProgress.completedUnitCount;
    int64_t totalBytesExpectedToWrite = uploadProgress.totalUnitCount;

    // Compute the bytes written since last time
    int64_t bytesWritten = totalBytesWritten - lastTotalBytesWritten;
    lastTotalBytesWritten = totalBytesWritten;

    CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
    if (!statisticsDict)
    {
        statisticsDict = [[NSMutableDictionary alloc] init];
    }
    
    CGFloat progressValue = self.uploadInitialRange + (((float)totalBytesWritten) /  ((float)totalBytesExpectedToWrite) * self.uploadRange);
    [statisticsDict setValue:[NSNumber numberWithFloat:progressValue] forKey:kMXMediaLoaderProgressValueKey];
    
    CGFloat dataRate = 0;
    if (currentTime != statsStartTime)
    {
        dataRate = bytesWritten / (currentTime - statsStartTime);
    }
    else
    {
        dataRate = bytesWritten / 0.001;
    }
    statsStartTime = currentTime;
    
    [statisticsDict setValue:[NSNumber numberWithLongLong:totalBytesWritten] forKey:kMXMediaLoaderCompletedBytesCountKey];
    [statisticsDict setValue:[NSNumber numberWithLongLong:totalBytesExpectedToWrite] forKey:kMXMediaLoaderTotalBytesCountKey];
    [statisticsDict setValue:[NSNumber numberWithFloat:dataRate] forKey:kMXMediaLoaderCurrentDataRateKey];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXMediaUploadProgressNotification object:_uploadId userInfo:statisticsDict];
}

@end
