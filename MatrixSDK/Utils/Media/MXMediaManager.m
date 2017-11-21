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

#import "TargetConditionals.h"

#import <Photos/Photos.h>

#import "MXMediaManager.h"

#import "MXSDKOptions.h"

#import "MXLRUCache.h"
#import "MXTools.h"

NSUInteger const kMXMediaCacheSDKVersion = 1;

NSString *const kMXMediaManagerAvatarThumbnailFolder = @"kMXMediaManagerAvatarThumbnailFolder";
NSString *const kMXMediaManagerDefaultCacheFolder = @"kMXMediaManagerDefaultCacheFolder";

static NSString* mediaCachePath  = nil;
static NSString *mediaDir        = @"mediacache";

static MXMediaManager *sharedMediaManager = nil;

// store the current cache size
// avoid listing files because it is useless
static NSUInteger storageCacheSize = 0;

@implementation MXMediaManager

/**
 Table of downloads in progress
 */
static NSMutableDictionary* downloadTable = nil;

/**
 Table of uploads in progress
 */
static NSMutableDictionary* uploadTableById = nil;

+ (MXMediaManager *)sharedManager
{
    @synchronized(self)
    {
        if(sharedMediaManager == nil)
        {
            sharedMediaManager = [[super allocWithZone:NULL] init];
        }
    }
    return sharedMediaManager;
}

#pragma mark - File handling

+ (BOOL)writeMediaData:(NSData *)mediaData toFilePath:(NSString*)filePath
{
    BOOL isCacheFile = [filePath hasPrefix:[MXMediaManager getCachePath]];
    if (isCacheFile)
    {
        [MXMediaManager reduceCacheSizeToInsert:mediaData.length];
    }
    
    if ([mediaData writeToFile:filePath atomically:YES])
    {
        if (isCacheFile)
        {
            storageCacheSize += mediaData.length;
        }
        
        return YES;
    }
    return NO;
}

static MXLRUCache* imagesCacheLruCache = nil;

#if TARGET_OS_IPHONE
+ (UIImage*)loadThroughCacheWithFilePath:(NSString*)filePath
#elif TARGET_OS_OSX
+ (NSImage*)loadThroughCacheWithFilePath:(NSString*)filePath
#endif
{
#if TARGET_OS_IPHONE
    UIImage *image = [MXMediaManager getFromMemoryCacheWithFilePath:filePath];
#elif TARGET_OS_OSX
    NSImage *image = [MXMediaManager getFromMemoryCacheWithFilePath:filePath];
#endif
    
    if (image) return image;
    
    image = [MXMediaManager loadPictureFromFilePath:filePath];
    
    if (image)
    {
        [MXMediaManager cacheImage:image withCachePath:filePath];
    }
    
    return image;
}


#if TARGET_OS_IPHONE
+ (UIImage*)getFromMemoryCacheWithFilePath:(NSString*)filePath
#elif TARGET_OS_OSX
+ (NSImage*)getFromMemoryCacheWithFilePath:(NSString*)filePath
#endif
{
    if (!imagesCacheLruCache)
    {
        imagesCacheLruCache = [[MXLRUCache alloc] initWithCapacity:20];
    }
    
#if TARGET_OS_IPHONE
    return (UIImage*)[imagesCacheLruCache get:filePath];
#elif TARGET_OS_OSX
    return (NSImage*)[imagesCacheLruCache get:filePath];
#endif
}

#if TARGET_OS_IPHONE
+ (void)cacheImage:(UIImage *)image withCachePath:(NSString *)filePath
#elif TARGET_OS_OSX
+ (void)cacheImage:(NSImage *)image withCachePath:(NSString *)filePath
#endif
{
    [imagesCacheLruCache put:filePath object:image];
}


#if TARGET_OS_IPHONE
+ (UIImage*)loadPictureFromFilePath:(NSString*)filePath
#elif TARGET_OS_OSX
+ (NSImage*)loadPictureFromFilePath:(NSString*)filePath
#endif
{
#if TARGET_OS_IPHONE
    UIImage* res = nil;
#elif TARGET_OS_OSX
    NSImage* res = nil;
#endif
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath])
    {
        NSData* imageContent = [NSData dataWithContentsOfFile:filePath options:(NSDataReadingMappedAlways | NSDataReadingUncached) error:nil];
        if (imageContent)
        {
#if TARGET_OS_IPHONE
            res = [[UIImage alloc] initWithData:imageContent];
#elif TARGET_OS_OSX
            res = [[NSImage alloc] initWithData:imageContent];
#endif
        }
    }
    
    return res;
}

#if TARGET_OS_IPHONE
+ (void)saveImageToPhotosLibrary:(UIImage*)image success:(void (^)(NSURL *imageURL))success failure:(void (^)(NSError *error))failure
{
    if (image)
    {
        __block NSString* localId;
        
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            
            // Request creating an asset from the image.
            PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            
            localId = [[assetRequest placeholderForCreatedAsset] localIdentifier];
            
        } completionHandler:^(BOOL successFlag, NSError *error) {
            
            NSLog(@"Finished adding asset. %@", (successFlag ? @"Success" : error));
            
            if (successFlag)
            {
                if (success)
                {
                    // Retrieve the created asset thanks to the local id of the change request
                    PHFetchResult* assetResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[localId] options:nil];
                    // Sanity check
                    if (assetResult.count)
                    {
                        PHAsset *asset = [assetResult firstObject];
                        PHContentEditingInputRequestOptions *editOptions = [[PHContentEditingInputRequestOptions alloc] init];
                        
                        [asset requestContentEditingInputWithOptions:editOptions
                                                   completionHandler:^(PHContentEditingInput *contentEditingInput, NSDictionary *info) {
                                                       
                                                       // Here the fullSizeImageURL is related to a local file path
                                                       
                                                       // Return on main thread
                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                           success(contentEditingInput.fullSizeImageURL);
                                                       });
                                                   }];
                    }
                    else
                    {
                        // Return on main thread
                        dispatch_async(dispatch_get_main_queue(), ^{
                            success(nil);
                        });
                    }
                }
            }
            else if (failure)
            {
                // Return on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
            
        }];
    }
}
#endif

#if TARGET_OS_IPHONE
+ (void)saveMediaToPhotosLibrary:(NSURL*)fileURL isImage:(BOOL)isImage success:(void (^)(NSURL *imageURL))success failure:(void (^)(NSError *error))failure
{
    if (fileURL)
    {
        __block NSString* localId;
        
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            
            PHAssetChangeRequest *assetRequest;
            
            if (isImage)
            {
                // Request creating an asset from the image.
                assetRequest = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:fileURL];
            }
            else
            {
                // Request creating an asset from the image.
                assetRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
            }
            
            localId = [[assetRequest placeholderForCreatedAsset] localIdentifier];
            
        } completionHandler:^(BOOL successFlag, NSError *error) {
            NSLog(@"Finished adding asset. %@", (successFlag ? @"Success" : error));
            
            if (successFlag)
            {
                if (success)
                {
                    // Retrieve the created asset thanks to the local id of the change request
                    PHFetchResult* assetResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[localId] options:nil];
                    // Sanity check
                    if (assetResult.count)
                    {
                        PHAsset *asset = [assetResult firstObject];
                        PHContentEditingInputRequestOptions *editOptions = [[PHContentEditingInputRequestOptions alloc] init];
                        
                        [asset requestContentEditingInputWithOptions:editOptions
                                                   completionHandler:^(PHContentEditingInput *contentEditingInput, NSDictionary *info) {
                                                       
                                                       if (contentEditingInput.mediaType == PHAssetMediaTypeImage)
                                                       {
                                                           // Here the fullSizeImageURL is related to a local file path
                                                           
                                                           // Return on main thread
                                                           dispatch_async(dispatch_get_main_queue(), ^{
                                                               success(contentEditingInput.fullSizeImageURL);
                                                           });
                                                       }
                                                       else if (contentEditingInput.mediaType == PHAssetMediaTypeVideo)
                                                       {
                                                           if ([contentEditingInput.avAsset isKindOfClass:[AVURLAsset class]])
                                                           {
                                                               AVURLAsset *avURLAsset = (AVURLAsset*)contentEditingInput.avAsset;
                                                               
                                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                                   success ([avURLAsset URL]);
                                                               });
                                                           }
                                                           else
                                                           {
                                                               NSLog(@"[MXMediaManager] Failed to retrieve the asset URL of the saved video!");
                                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                                   success (nil);
                                                               });
                                                           }
                                                       }
                                                       else
                                                       {
                                                           NSLog(@"[MXMediaManager] Failed to retrieve editing input from asset");
                                                           
                                                           // Return on main thread
                                                           dispatch_async(dispatch_get_main_queue(), ^{
                                                               success (nil);
                                                           });
                                                       }
                                                       
                                                   }];
                    }
                    else
                    {
                        // Return on main thread
                        dispatch_async(dispatch_get_main_queue(), ^{
                            success (nil);
                        });
                    }
                }
            }
            else if (failure)
            {
                // Return on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure (error);
                });
            }
        }];
    }
}
#endif

#pragma mark - Media Download

+ (MXMediaLoader*)downloadMediaFromURL:(NSString *)mediaURL
                      andSaveAtFilePath:(NSString *)filePath
                                success:(void (^)(void))success
                                failure:(void (^)(NSError *error))failure
{
    // Check provided file path
    if (!filePath.length)
    {
        filePath = [self cachePathForMediaWithURL:mediaURL andType:nil inFolder:kMXMediaManagerDefaultCacheFolder];
    }
    
    if (mediaURL)
    {
        // Create a media loader to download data
        MXMediaLoader *mediaLoader = [[MXMediaLoader alloc] init];
        // Report this loader
        if (!downloadTable)
        {
            downloadTable = [[NSMutableDictionary alloc] init];
        }
        [downloadTable setValue:mediaLoader forKey:filePath];
        
        // Launch download
        [mediaLoader downloadMediaFromURL:mediaURL andSaveAtFilePath:filePath success:^(NSString *outputFilePath)
         {
             [downloadTable removeObjectForKey:filePath];
             if (success) success();
         } failure:^(NSError *error)
         {
             if (failure) failure(error);
             [downloadTable removeObjectForKey:filePath];
         }];
        return mediaLoader;
    }
    
    return nil;
}

+ (MXMediaLoader*)downloadMediaFromURL:(NSString *)mediaURL
                      andSaveAtFilePath:(NSString *)filePath
{
    return [MXMediaManager downloadMediaFromURL:mediaURL andSaveAtFilePath:filePath success:nil failure:nil];
}

+ (MXMediaLoader*)existingDownloaderWithOutputFilePath:(NSString *)filePath
{
    if (downloadTable && filePath)
    {
        return [downloadTable valueForKey:filePath];
    }
    return nil;
}

+ (void)cancelDownloadsInCacheFolder:(NSString*)folder
{
    NSMutableArray *pendingLoaders =[[NSMutableArray alloc] init];
    NSArray *allKeys = [downloadTable allKeys];
    
    if (folder.length > 0)
    {
        NSString *folderPath = [MXMediaManager cacheFolderPath:folder];
        for (NSString* key in allKeys)
        {
            if ([key hasPrefix:folderPath])
            {
                [pendingLoaders addObject:[downloadTable valueForKey:key]];
                [downloadTable removeObjectForKey:key];
            }
        }
    }
    
    if (pendingLoaders.count)
    {
        for (MXMediaLoader* loader in pendingLoaders)
        {
            [loader cancel];
        }
    }
}

+ (void)cancelDownloads
{
    NSArray* allKeys = [downloadTable allKeys];
    
    for(NSString* key in allKeys)
    {
        [[downloadTable valueForKey:key] cancel];
        [downloadTable removeObjectForKey:key];
    }
}

#pragma mark - Media Uploader

+ (MXMediaLoader*)prepareUploaderWithMatrixSession:(MXSession*)mxSession
                                       initialRange:(CGFloat)initialRange
                                           andRange:(CGFloat)range
{
    if (mxSession)
    {
        // Create a media loader to upload data
        MXMediaLoader *mediaLoader = [[MXMediaLoader alloc] initForUploadWithMatrixSession:mxSession initialRange:initialRange andRange:range];
        // Report this loader
        if (!uploadTableById)
        {
            uploadTableById =  [[NSMutableDictionary alloc] init];
            
            // Need to listen to kMXMediaUploadDid* notifications to automatically release allocated upload ids
            if (0 == uploadTableById.count)
            {
                
                MXMediaManager *sharedManager = [MXMediaManager sharedManager];
                [[NSNotificationCenter defaultCenter] addObserver:sharedManager selector:@selector(onMediaUploadEnd:) name:kMXMediaUploadDidFinishNotification object:nil];
                [[NSNotificationCenter defaultCenter] addObserver:sharedManager selector:@selector(onMediaUploadEnd:) name:kMXMediaUploadDidFailNotification object:nil];
            }
        }
        [uploadTableById setValue:mediaLoader forKey:mediaLoader.uploadId];
        return mediaLoader;
    }
    return nil;
}

+ (MXMediaLoader*)existingUploaderWithId:(NSString*)uploadId
{
    if (uploadTableById && uploadId)
    {
        return [uploadTableById valueForKey:uploadId];
    }
    return nil;
}

- (void)onMediaUploadEnd:(NSNotification *)notif
{
    [MXMediaManager removeUploaderWithId:notif.object];
    
    // If there is no more upload in progress, stop observing upload notifications
    if (0 == uploadTableById.count)
    {
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXMediaUploadDidFinishNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXMediaUploadDidFailNotification object:nil];
    }
}

+ (void)removeUploaderWithId:(NSString*)uploadId
{
    if (uploadTableById && uploadId)
    {
        [uploadTableById removeObjectForKey:uploadId];
    }
}

+ (void)cancelUploads
{
    NSArray* allKeys = [uploadTableById allKeys];
    
    for(NSString* key in allKeys)
    {
        [[uploadTableById valueForKey:key] cancel];
        [uploadTableById removeObjectForKey:key];
    }
}

#pragma mark - Cache Handling

+ (NSString*)cacheFolderPath:(NSString*)folder
{
    NSString* path = [MXMediaManager getCachePath];
    
    // update the path if the folder is provided
    if (folder.length > 0)
    {
        path = [[MXMediaManager getCachePath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu", (unsigned long)folder.hash]];
    }
    
    // create the folder it does not exist
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
    {
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil];
    }
    
    return path;
}

static NSMutableDictionary* fileBaseFromMimeType = nil;

+ (NSString*)filebase:(NSString*)mimeType
{
    // sanity checks
    if (!mimeType || !mimeType.length)
    {
        return @"";
    }
    
    NSString* fileBase;

    if (!fileBaseFromMimeType)
    {
        fileBaseFromMimeType = [[NSMutableDictionary alloc] init];
    }
    
    fileBase = fileBaseFromMimeType[mimeType];
    
    if (!fileBase)
    {
        fileBase = @"";
        
        if ([mimeType rangeOfString:@"/"].location != NSNotFound)
        {
            NSArray *components = [mimeType componentsSeparatedByString:@"/"];
            fileBase = [components objectAtIndex:0];
            if (fileBase.length > 3)
            {
                fileBase = [fileBase substringToIndex:3];
            }
        }
        
        [fileBaseFromMimeType setObject:fileBase forKey:mimeType];
    }
    
    return fileBase;
}

+ (NSString*)cachePathForMediaWithURL:(NSString*)url andType:(NSString *)mimeType inFolder:(NSString*)folder
{
    NSString* fileBase = @"";
    NSString *extension = @"";
    
    if (!folder.length)
    {
        folder = kMXMediaManagerDefaultCacheFolder;
    }
    
    if (mimeType.length)
    {
        extension = [MXTools fileExtensionFromContentType:mimeType];
        
        // use the mime type to extract a base filename
        fileBase = [MXMediaManager filebase:mimeType];
    }
    
    if (!extension.length)
    {
        // Try to get this extension from url
        NSString *pathExtension = [url pathExtension];
        if (pathExtension.length)
        {
            extension = [NSString stringWithFormat:@".%@", pathExtension];
        }
        else if ([folder isEqualToString:kMXMediaManagerAvatarThumbnailFolder])
        {
            // Consider the default image type for thumbnail folder
            extension = [MXTools fileExtensionFromContentType:@"image/jpeg"];
        }
    }
    
    return [[MXMediaManager cacheFolderPath:folder] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%lu%@", fileBase, (unsigned long)url.hash, extension]];
}

+ (void)reduceCacheSizeToInsert:(NSUInteger)sizeInBytes
{
    if (([MXMediaManager cacheSize] + sizeInBytes) > [MXMediaManager maxAllowedCacheSize])
    {
        
        NSString* thumbnailPath = [MXMediaManager cacheFolderPath:kMXMediaManagerAvatarThumbnailFolder];
        
        // add a 50 MB margin to reduce this method call
        NSUInteger maxSize = 0;
        
        // check if the cache cannot content the file
        if ([MXMediaManager maxAllowedCacheSize] < (sizeInBytes - 50 * 1024 * 1024))
        {
            // delete item as much as possible
            maxSize = 0;
        }
        else
        {
            maxSize = [MXMediaManager maxAllowedCacheSize] - sizeInBytes - 50 * 1024 * 1024;
        }
        
        NSArray* filesList = [MXTools listFiles:mediaCachePath timeSorted:YES largeFilesFirst:YES];
        
        // list the files sorted by timestamp
        for(NSString* filepath in filesList)
        {
            // do not release the contact thumbnails : they must be released when the contacts are deleted
            if (![filepath hasPrefix:thumbnailPath])
            {
                NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filepath error:nil];
                
                // sanity check
                if (fileAttributes)
                {
                    // delete the files
                    if ([[NSFileManager defaultManager] removeItemAtPath:filepath error:nil])
                    {
                        storageCacheSize -= fileAttributes.fileSize;
                        if (storageCacheSize < maxSize)
                        {
                            return;
                        }
                    }
                }
            }
        }
    }
}

+ (NSUInteger)cacheSize
{
    if (!mediaCachePath)
    {
        // compute the path
        mediaCachePath = [MXMediaManager getCachePath];
    }
    
    // assume that 0 means uninitialized
    if (storageCacheSize == 0)
    {
        storageCacheSize = (NSUInteger)[MXTools folderSize:mediaCachePath];
    }
    
    return storageCacheSize;
}

+ (NSUInteger)minCacheSize
{
    NSUInteger minSize = [MXMediaManager cacheSize];
    NSArray* filenamesList = [MXTools listFiles:mediaCachePath timeSorted:NO largeFilesFirst:YES];
    
    NSFileManager* defaultManager = [NSFileManager defaultManager];
    
    for(NSString* filename in filenamesList)
    {
        NSDictionary* attsDict = [defaultManager attributesOfItemAtPath:filename error:nil];
        
        if (attsDict)
        {
            if (attsDict.fileSize > 100 * 1024)
            {
                minSize -= attsDict.fileSize;
            }
        }
    }
    return minSize;
}

+ (NSInteger)currentMaxCacheSize
{
    NSInteger res = [[NSUserDefaults standardUserDefaults] integerForKey:@"maxMediaCacheSize"];
    if (res == 0)
    {
        // no default value, use the max allowed value
        res = [MXMediaManager maxAllowedCacheSize];
    }
    
    return res;
}

+ (void)setCurrentMaxCacheSize:(NSInteger)maxCacheSize
{
    if ((maxCacheSize == 0) || (maxCacheSize > [MXMediaManager maxAllowedCacheSize]))
    {
        maxCacheSize = [MXMediaManager maxAllowedCacheSize];
    }
    
    [[NSUserDefaults standardUserDefaults] setInteger:maxCacheSize forKey:@"maxMediaCacheSize"];
}

+ (NSInteger)maxAllowedCacheSize
{
    NSInteger res = [[NSUserDefaults standardUserDefaults] integerForKey:@"maxAllowedMediaCacheSize"];
    if (res == 0)
    {
        // no default value, assume that 1 GB is enough
        res = 1024 * 1024 * 1024;
    }
    
    return res;
}

+ (void)clearCache
{
    NSError *error = nil;
    
    if (!mediaCachePath)
    {
        // compute the path
        mediaCachePath = [MXMediaManager getCachePath];
    }
    
    [MXMediaManager cancelDownloads];
    [MXMediaManager cancelUploads];
    
    if (mediaCachePath)
    {
        NSLog(@"[MXMediaManager] Delete media cache directory");
        
        if (![[NSFileManager defaultManager] removeItemAtPath:mediaCachePath error:&error])
        {
            NSLog(@"[MXMediaManager] Failed to delete media cache dir: %@", error);
        }
    }
    else
    {
        NSLog(@"[MXMediaManager] Media cache does not exist");
    }
    
    mediaCachePath = nil;
    
    // force to recompute the cache size at next cacheSize call
    storageCacheSize = 0;
}

+ (NSString*)getCachePath
{
    NSString *cachePath = nil;
    
    if (!mediaCachePath)
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheRoot = [paths objectAtIndex:0];
        NSString *mediaCacheVersionString = [MXMediaManager getCacheVersionString];
        
        mediaCachePath = [cacheRoot stringByAppendingPathComponent:mediaDir];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:mediaCachePath])
        {
            [[NSFileManager defaultManager] createDirectoryAtPath:mediaCachePath withIntermediateDirectories:NO attributes:nil error:nil];
            
            // Add the cache version file
            NSString *cacheVersionFile = [mediaCachePath stringByAppendingPathComponent:mediaCacheVersionString];
            [[NSFileManager defaultManager]createFileAtPath:cacheVersionFile contents:nil attributes:nil];
        }
        else
        {
            // Check the cache version
            NSString *cacheVersionFile = [mediaCachePath stringByAppendingPathComponent:mediaCacheVersionString];
            if (![[NSFileManager defaultManager] fileExistsAtPath:cacheVersionFile])
            {
                NSLog(@"[MXMediaManager] New media cache version detected");
                [MXMediaManager clearCache];
            }
        }
    }
    cachePath = mediaCachePath;
    
    return cachePath;
}

+ (NSString*)getCacheVersionString
{
    return [NSString stringWithFormat:@"v%tu.%tu", [MXSDKOptions sharedInstance].mediaCacheAppVersion, kMXMediaCacheSDKVersion];
}

@end
