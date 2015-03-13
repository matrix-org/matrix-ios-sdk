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

#import <UIKit/UIKit.h>

#import "MatrixSDK.h"

/**
 Posted to provide download progress.
 The notification object is the media url. The `userInfo` dictionary contains the following keys:
 - kMXKMediaLoaderProgressValueKey: progress value nested in a NSNumber (range 0->1)
 - kMXKMediaLoaderProgressStringKey: progress string XXX KB / XXX MB" (optional)
 - kMXKMediaLoaderProgressRemaingTimeKey: remaining time string "XX s left" (optional)
 - kMXKMediaLoaderProgressRateKey: string like XX MB/s (optional).
 */
extern NSString *const kMXKMediaDownloadProgressNotification;

/**
 Posted when a media download is finished with success.
 The notification object is the media url. The `userInfo` dictionary contains an `NSString` object under the `kMXKMediaLoaderFilePathKey` key, representing the resulting file path.
 */
extern NSString *const kMXKMediaDownloadDidFinishNotification;

/**
 Posted when a media download failed.
 The notification object is the media url. The `userInfo` dictionary may contain an `NSError` object under the `kMXKMediaLoaderErrorKey` key.
 */
extern NSString *const kMXKMediaDownloadDidFailNotification;

/**
 Posted to provide upload progress.
 The notification object is the `uploadId`. The `userInfo` dictionary contains the following keys:
 - kMXKMediaLoaderProgressValueKey: progress value nested in a NSNumber (range 0->1)
 - kMXKMediaLoaderProgressStringKey: progress string XXX KB / XXX MB" (optional)
 - kMXKMediaLoaderProgressRemaingTimeKey: remaining time string "XX s left" (optional)
 - kMXKMediaLoaderProgressRateKey: string like XX MB/s (optional).
 */
extern NSString *const kMXKMediaUploadProgressNotification;

/**
 Posted when a media upload is finished with success.
 The notification object is the upload id. The `userInfo` dictionary is nil.
 */
extern NSString *const kMXKMediaUploadDidFinishNotification;

/**
 Posted when a media upload failed.
 The notification object is the upload id. The `userInfo` dictionary may contain an `NSError` object under the `kMXKMediaLoaderErrorKey` key.
 */
extern NSString *const kMXKMediaUploadDidFailNotification;

/**
 Notifications `userInfo` keys
 */
extern NSString *const kMXKMediaLoaderProgressValueKey;
extern NSString *const kMXKMediaLoaderProgressStringKey;
extern NSString *const kMXKMediaLoaderProgressRemaingTimeKey;
extern NSString *const kMXKMediaLoaderProgressRateKey;
extern NSString *const kMXKMediaLoaderFilePathKey;
extern NSString *const kMXKMediaLoaderErrorKey;
/**
 The callback blocks
 */
typedef void (^blockMXKMediaLoader_onSuccess) (NSString *url); // url is the output file path for successful download, or a remote url for upload.
typedef void (^blockMXKMediaLoader_onError) (NSError *error);

/**
 `MXKMediaLoader` defines a class to download/upload media. It provides progress information during the operation.
 */
@interface MXKMediaLoader : NSObject <NSURLConnectionDataDelegate> {
    
    blockMXKMediaLoader_onSuccess onSuccess;
    blockMXKMediaLoader_onError onError;
    
    // Media download
    NSString *mediaURL;
    NSString *outputFilePath;
    long long expectedSize;
    NSMutableData *downloadData;
    NSURLConnection *downloadConnection;
    
    // Media upload
    MXSession* mxSession;
    CGFloat initialRange;
    CGFloat range;
    MXHTTPOperation* operation;
    
    // Statistic info (bitrate, remaining time...)
    CFAbsoluteTime statsStartTime;
    CFAbsoluteTime downloadStartTime;
    CFAbsoluteTime lastProgressEventTimeStamp;
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
                     success:(blockMXKMediaLoader_onSuccess)success
                     failure:(blockMXKMediaLoader_onError)failure;

/**
 Initialise a media loader to upload data to a matrix content repository.
 Note: An upload could be a subpart of a global upload. For example, upload a video can be split in two parts :
 1 - upload the thumbnail -> initialRange = 0, range = 0.1 : assume that the thumbnail upload is 10% of the upload process
 2 - upload the media -> initialRange = 0.1, range = 0.9 : the media upload is 90% of the global upload
 
 @param mxSession the matrix session used to upload media.
 @param initialRange the global upload progress already did done before this current upload.
 @param range the range value of this upload in the global scope.
 @return the newly created instance.
 */
- (id)initForUploadWithMatrixSession:(MXSession*)mxSession initialRange:(CGFloat)anInitialRange andRange:(CGFloat)aRange;

/**
 Upload data.
 
 @param data data to upload.
 @param mimeType media mimetype.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)uploadData:(NSData *)data
          mimeType:(NSString *)mimeType
           success:(blockMXKMediaLoader_onSuccess)success
           failure:(blockMXKMediaLoader_onError)failure;

@end
