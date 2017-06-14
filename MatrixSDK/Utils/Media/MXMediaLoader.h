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

#import "TargetConditionals.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#endif

@class MXSession;
@class MXHTTPOperation;

/**
 Posted to provide download progress.
 The notification object is the media url. The `userInfo` dictionary contains the following keys:
 - kMXMediaLoaderProgressValueKey: progress value in [0, 1] range (NSNumber object).
 - kMXMediaLoaderCompletedBytesCountKey: the number of bytes that have already been completed by the current job (NSNumber object).
 - kMXMediaLoaderTotalBytesCountKey: the total number of bytes tracked for the current job (NSNumber object).
 - kMXMediaLoaderCurrentDataRateKey: The observed data rate in Bytes/s (NSNumber object).
 */
extern NSString *const kMXMediaDownloadProgressNotification;

/**
 Posted when a media download is finished with success.
 The notification object is the media url. The `userInfo` dictionary contains an `NSString` object under the `kMXMediaLoaderFilePathKey` key, representing the resulting file path.
 */
extern NSString *const kMXMediaDownloadDidFinishNotification;

/**
 Posted when a media download failed.
 The notification object is the media url. The `userInfo` dictionary may contain an `NSError` object under the `kMXMediaLoaderErrorKey` key.
 */
extern NSString *const kMXMediaDownloadDidFailNotification;

/**
 Posted to provide upload progress.
 The notification object is the `uploadId`. The `userInfo` dictionary contains the following keys:
 - kMXMediaLoaderProgressValueKey: progress value in [0, 1] range (NSNumber object) [The properties `uploadInitialRange` and `uploadRange` are taken into account here].
 - kMXMediaLoaderCompletedBytesCountKey: the number of bytes that have already been completed by the current job (NSNumber object).
 - kMXMediaLoaderTotalBytesCountKey: the total number of bytes tracked for the current job (NSNumber object).
 - kMXMediaLoaderCurrentDataRateKey: The observed data rate in Bytes/s (NSNumber object).
 */
extern NSString *const kMXMediaUploadProgressNotification;

/**
 Posted when a media upload is finished with success.
 The notification object is the upload id. The `userInfo` dictionary is nil.
 */
extern NSString *const kMXMediaUploadDidFinishNotification;

/**
 Posted when a media upload failed.
 The notification object is the upload id. The `userInfo` dictionary may contain an `NSError` object under the `kMXMediaLoaderErrorKey` key.
 */
extern NSString *const kMXMediaUploadDidFailNotification;

/**
 Notifications `userInfo` keys
 */
extern NSString *const kMXMediaLoaderProgressValueKey;
extern NSString *const kMXMediaLoaderCompletedBytesCountKey;
extern NSString *const kMXMediaLoaderTotalBytesCountKey;
extern NSString *const kMXMediaLoaderCurrentDataRateKey;
extern NSString *const kMXMediaLoaderFilePathKey;
extern NSString *const kMXMediaLoaderErrorKey;

/**
 The callback blocks
 */
typedef void (^blockMXMediaLoader_onSuccess) (NSString *url); // url is the output file path for successful download, or a remote url for upload.
typedef void (^blockMXMediaLoader_onError) (NSError *error);

/**
 The prefix of upload identifier
 */
extern NSString *const kMXMediaUploadIdPrefix;

/**
 `MXMediaLoader` defines a class to download/upload media. It provides progress information during the operation.
 */
@interface MXMediaLoader : NSObject <NSURLConnectionDataDelegate, NSURLConnectionDelegate>
{    
    blockMXMediaLoader_onSuccess onSuccess;
    blockMXMediaLoader_onError onError;
    
    // Media download
    NSString *mediaURL;
    NSString *outputFilePath;
    long long expectedSize;
    NSMutableData *downloadData;
    NSURLConnection *downloadConnection;
    
    // Media upload
    MXSession* mxSession;
    MXHTTPOperation* operation;
    
    // Statistic info (bitrate, remaining time...)
    CFAbsoluteTime statsStartTime;
    CFAbsoluteTime downloadStartTime;
    CFAbsoluteTime lastProgressEventTimeStamp;
    int64_t lastTotalBytesWritten;
    NSTimer* progressCheckTimer;
}

/**
 Statistics on the operation in progress.
 */
@property (strong, readonly) NSMutableDictionary* statisticsDict;

/**
 Upload id defined when a media loader is instantiated as uploader.
 Default is nil.
 */
@property (strong, readonly) NSString *uploadId;

@property (readonly) CGFloat uploadInitialRange;
@property (readonly) CGFloat uploadRange;

/**
 Cancel the operation.
 */
- (void)cancel;

/**
 Download data from the provided URL.
 
 @param url remote media url.
 @param filePath output file in which downloaded media must be saved.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)downloadMediaFromURL:(NSString *)url
           andSaveAtFilePath:(NSString *)filePath
                     success:(blockMXMediaLoader_onSuccess)success
                     failure:(blockMXMediaLoader_onError)failure;

/**
 Initialise a media loader to upload data to a matrix content repository.
 Note: An upload could be a subpart of a global upload. For example, upload a video can be split in two parts :
 1 - upload the thumbnail -> initialRange = 0, range = 0.1 : assume that the thumbnail upload is 10% of the upload process
 2 - upload the media -> initialRange = 0.1, range = 0.9 : the media upload is 90% of the global upload
 
 @param mxSession the matrix session used to upload media.
 @param anInitialRange the global upload progress already did done before this current upload.
 @param aRange the range value of this upload in the global scope.
 @return the newly created instance.
 */
- (id)initForUploadWithMatrixSession:(MXSession*)mxSession initialRange:(CGFloat)anInitialRange andRange:(CGFloat)aRange;

/**
 Upload data.
 
 @param data data to upload.
 @param filename optional filename
 @param mimeType media mimetype.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)uploadData:(NSData *)data
          filename:(NSString*)filename
          mimeType:(NSString *)mimeType
           success:(blockMXMediaLoader_onSuccess)success
           failure:(blockMXMediaLoader_onError)failure;

@end
