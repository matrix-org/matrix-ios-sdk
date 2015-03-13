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

#import <AVFoundation/AVFoundation.h>
#import "MXKMediaLoader.h"

/**
 The predefined folder for avatar thumbnail.
 */
extern NSString *const kMXKMediaManagerAvatarThumbnailFolder;

/**
 `MXKMediaManager` class provide multiple services related to media handling: cache storage, downloading, uploading.
 
 Cache is handled by folders. A specific folder is defined to store avatar thumbnails `kMXKMediaManagerAvatarThumbnailFolder`.
 Other folders creation is free.
 
 Media upload is based on matrix content repository. It requires a matrix session.
 */
@interface MXKMediaManager : NSObject

#pragma mark - File handling

/**
 Write data into the provided file path
 
 @param mediaData
 @param filePath
 @return YES on sucess.
 */
+ (BOOL)writeMediaData:(NSData *)mediaData toFilePath:(NSString*)filePath;

/**
 Load a picture from the local storage
 
 @param filePath picture file path.
 @return Image (if any).
 */
+ (UIImage*)loadPictureFromFilePath:(NSString*)filePath;


#pragma mark - Download

/**
 Download data from the provided URL.
 
 @param url remote media url.
 @param filePath output file in which downloaded media must be saved (may be nil).
 @return a media loader in order to let the user cancel this action.
 */
+ (MXKMediaLoader*)downloadMediaFromURL:(NSString *)mediaURL
                      andSaveAtFilePath:(NSString *)filePath;

/**
 Check whether a download is already running with a specific output file path.
 
 @param filePath output file.
 @return mediaLoader (if any)
 */
+ (MXKMediaLoader*)existingDownloaderWithOutputFilePath:(NSString *)filePath;

/**
 Cancel any pending download within a cache folder
 */
+ (void)cancelDownloadsInCacheFolder:(NSString*)folder;

/**
 Cancel all pending downloads
 */
+ (void)cancelDownloads;


#pragma mark - Upload

/**
 Prepares a media loader to upload data to a matrix content repository.
 
 Note: An upload could be a subpart of a global upload. For example, upload a video can be split in two parts :
 1 - upload the thumbnail -> initialRange = 0, range = 0.1 : assume that the thumbnail upload is 10% of the upload process
 2 - upload the media -> initialRange = 0.1, range = 0.9 : the media upload is 90% of the global upload
 
 @param mxSession the matrix session used to upload media.
 @param initialRange the global upload progress already did done before this current upload.
 @param range the range value of this upload in the global scope.
 @return a media loader.
 */
+ (MXKMediaLoader*)prepareUploaderWithMatrixSession:(MXSession*)mxSession
                                       initialRange:(CGFloat)initialRange
                                           andRange:(CGFloat)range;

/**
 Check whether an upload is already running with this id.
 
 @param uploadId
 @return mediaLoader (if any).
 */
+ (MXKMediaLoader*)existingUploaderWithId:(NSString*)uploadId;

/**
 Cancel any pending upload
 */
+ (void)cancelUploads;


#pragma mark - Cache handling

/**
 Build a cache file path based on media url and an optional cache folder.
 
 @param url media url.
 @param folder cache folder to use (may be nil).
 @return cache file path.
 */
+ (NSString*)cachePathForMediaWithURL:(NSString*)url inFolder:(NSString*)folder;

/**
 Build a cache file path based on media information and an optional cache folder.
 
 @param url media url.
 @param mimeType media mime type.
 @param folder cache folder to use (may be nil).
 @return cache file path.
 */
+ (NSString*)cachePathForMediaWithURL:(NSString*)url andType:(NSString *)mimeType inFolder:(NSString*)folder;

/**
 Check if the media cache size must be reduced to fit the user expected cache size
 
 @param sizeInBytes expected cache size in bytes.
 */
+ (void)reduceCacheSizeToInsert:(NSUInteger)sizeInBytes;

/**
 Clear cache
 */
+ (void)clearCache;

/**
 Cache size management (values are in bytes)
 */
+ (NSUInteger)cacheSize;
+ (NSUInteger)minCacheSize;
+ (NSInteger)currentMaxCacheSize;
+ (void)setCurrentMaxCacheSize:(NSInteger)maxCacheSize;
+ (NSUInteger)maxAllowedCacheSize;

@end
