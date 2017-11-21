/*
 Copyright 2016 OpenMarket Ltd
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

#import <AVFoundation/AVFoundation.h>
#import "MXMediaLoader.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#endif


/**
 The predefined folder for avatar thumbnail.
 */
extern NSString *const kMXMediaManagerAvatarThumbnailFolder;
extern NSString *const kMXMediaManagerDefaultCacheFolder;

/**
 `MXMediaManager` class provide multiple services related to media handling: cache storage, downloading, uploading.
 
 Cache is handled by folders. A specific folder is defined to store avatar thumbnails `kMXMediaManagerAvatarThumbnailFolder`.
 Other folders creation is free.
 
 Media upload is based on matrix content repository. It requires a matrix session.
 */
@interface MXMediaManager : NSObject

#pragma mark - File handling

/**
 Write data into the provided file path.
 
 @param mediaData the data to write.
 @param filePath the file to write data to.
 @return YES on sucess.
 */
+ (BOOL)writeMediaData:(NSData *)mediaData toFilePath:(NSString*)filePath;

/**
 Load an image in memory cache. If the image is not in the cache,
 load it from the given path, insert it into the cache and return it.
 The images are cached in a LRU cache if they are not yet loaded.
 So, it should be faster than calling loadPictureFromFilePath;
 
 @param filePath picture file path.
 @return Image (if any).
 */
#if TARGET_OS_IPHONE
+ (UIImage*)loadThroughCacheWithFilePath:(NSString*)filePath;
#elif TARGET_OS_OSX
+ (NSImage*)loadThroughCacheWithFilePath:(NSString*)filePath;
#endif

/**
 Load an image from the in memory cache, or return nil if the image
 is not in the cache
 
 @param filePath picture file path.
 @return Image (if any).
 */
#if TARGET_OS_IPHONE
+ (UIImage*)getFromMemoryCacheWithFilePath:(NSString*)filePath;
#elif TARGET_OS_OSX
+ (NSImage*)getFromMemoryCacheWithFilePath:(NSString*)filePath;
#endif

/**
 * Save an image to in-memory cache, evicting other images
 * if necessary
 */

#if TARGET_OS_IPHONE
+ (void)cacheImage:(UIImage *)image withCachePath:(NSString *)cachePath;
#elif TARGET_OS_OSX
+ (void)cacheImage:(NSImage *)image withCachePath:(NSString *)cachePath;
#endif

/**
 Load a picture from the local storage
 
 @param filePath picture file path.
 @return Image (if any).
 */
#if TARGET_OS_IPHONE
+ (UIImage*)loadPictureFromFilePath:(NSString*)filePath; 
#elif TARGET_OS_OSX
+ (NSImage*)loadPictureFromFilePath:(NSString*)filePath;
#endif

/**
 Save an image to user's photos library
 
 @param image
 @param success A block object called when the operation succeeds. The returned url
 references the image in the file system or in the AssetsLibrary framework.
 @param failure A block object called when the operation fails.
 */
#if TARGET_OS_IPHONE
+ (void)saveImageToPhotosLibrary:(UIImage*)image success:(void (^)(NSURL *imageURL))success failure:(void (^)(NSError *error))failure;
#endif
/**
 Save a media to user's photos library
 
 @param fileURL URL based on local media file path.
 @param isImage YES for images, NO for video files.
 @param success A block object called when the operation succeeds.The returned url
 references the media in the file system or in the AssetsLibrary framework.
 @param failure A block object called when the operation fails.
 */
#if TARGET_OS_IPHONE
+ (void)saveMediaToPhotosLibrary:(NSURL*)fileURL isImage:(BOOL)isImage success:(void (^)(NSURL *imageURL))success failure:(void (^)(NSError *error))failure;
#endif

#pragma mark - Download

/**
 Download data from the provided URL.
 
 @param mediaURL the remote media url.
 @param filePath output file in which downloaded media must be saved (may be nil).
 @param success block called on success
 @param failure block called on failure
 @return a media loader in order to let the user cancel this action.
 */
+ (MXMediaLoader*)downloadMediaFromURL:(NSString *)mediaURL
                      andSaveAtFilePath:(NSString *)filePath
                                success:(void (^)(void))success
                                failure:(void (^)(NSError *error))failure;

/**
 Download data from the provided URL.
 
 @param mediaURL the remote media url.
 @param filePath output file in which downloaded media must be saved (may be nil).
 @return a media loader in order to let the user cancel this action.
 */
+ (MXMediaLoader*)downloadMediaFromURL:(NSString *)mediaURL
                      andSaveAtFilePath:(NSString *)filePath;

/**
 Check whether a download is already running with a specific output file path.
 
 @param filePath output file.
 @return mediaLoader (if any)
 */
+ (MXMediaLoader*)existingDownloaderWithOutputFilePath:(NSString *)filePath;

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
+ (MXMediaLoader*)prepareUploaderWithMatrixSession:(MXSession*)mxSession
                                       initialRange:(CGFloat)initialRange
                                           andRange:(CGFloat)range;

/**
 Check whether an upload is already running with this id.
 
 @param uploadId the id of the upload to fectch.
 @return mediaLoader (if any).
 */
+ (MXMediaLoader*)existingUploaderWithId:(NSString*)uploadId;

/**
 Cancel any pending upload
 */
+ (void)cancelUploads;


#pragma mark - Cache handling

/**
 Build a cache file path based on media information and an optional cache folder.
 
 The file extension is extracted from the provided mime type (if any). If no type is available, we look for a potential
 extension in the url.
 By default 'image/jpeg' is considered for thumbnail folder (kMXMediaManagerAvatarThumbnailFolder). No default mime type 
 is defined for other folders.
 
 @param url the media url.
 @param mimeType the media mime type (may be nil).
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
 Return cache root path
 */
+ (NSString*)getCachePath;

/**
 Return the current media cache version.
 This value depends on the version defined at the application level (see [MXSDKOptions mediaCacheAppVersion]),
 and the one defined at SDK level.
 */
+ (NSString*)getCacheVersionString;

/**
 Cache size management (values are in bytes)
 */
+ (NSUInteger)cacheSize;
+ (NSUInteger)minCacheSize;

/**
 The current maximum size of the media cache (in bytes).
 */
+ (NSInteger)currentMaxCacheSize;
+ (void)setCurrentMaxCacheSize:(NSInteger)maxCacheSize;

/**
 The maximum allowed size of the media cache (in bytes).
 
 Return the value for the key `maxAllowedMediaCacheSize` in the shared defaults object (1 GB if no default value is defined).
 */
+ (NSInteger)maxAllowedCacheSize;

@end
