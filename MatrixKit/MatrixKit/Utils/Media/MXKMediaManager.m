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

#import "MXKMediaManager.h"

#import "MXKTools.h"

NSString *const kMXKMediaManagerAvatarThumbnailFolder = @"kMXKMediaManagerAvatarThumbnailFolder";
NSString *const kMXKMediaManagerDefaultCacheFolder = @"kMXKMediaManagerDefaultCacheFolder";

static NSString* mediaCachePath  = nil;
static NSString *mediaDir        = @"mediacache";

// store the current cache size
// avoid listing files because it is useless
static NSUInteger storageCacheSize = 0;

@implementation MXKMediaManager

/**
 Table of downloads in progress
 */
static NSMutableDictionary* downloadTable = nil;

/**
 Table of uploads in progress
 */
static NSMutableDictionary* uploadTableById = nil;

#pragma mark - File handling

+ (BOOL)writeMediaData:(NSData *)mediaData toFilePath:(NSString*)filePath {
    BOOL isCacheFile = [filePath hasPrefix:[MXKMediaManager getCachePath]];
    if (isCacheFile) {
        [MXKMediaManager reduceCacheSizeToInsert:mediaData.length];
    }
    
    if ([mediaData writeToFile:filePath atomically:YES]) {
        if (isCacheFile) {
            storageCacheSize += mediaData.length;
        }
        
        return YES;
    }
    return NO;
}

+ (UIImage*)loadPictureFromFilePath:(NSString*)filePath {
    UIImage* res = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSData* imageContent = [NSData dataWithContentsOfFile:filePath options:(NSDataReadingMappedAlways | NSDataReadingUncached) error:nil];
        if (imageContent) {
            res = [[UIImage alloc] initWithData:imageContent];
        }
    }
    
    return res;
}

#pragma mark - Media Download

+ (MXKMediaLoader*)downloadMediaFromURL:(NSString *)mediaURL
                      andSaveAtFilePath:(NSString *)filePath {
    // Check provided file path
    if (!filePath.length) {
        filePath = [self cachePathForMediaWithURL:mediaURL inFolder:kMXKMediaManagerDefaultCacheFolder];
    }
    
    if (mediaURL) {
        // Create a media loader to download data
        MXKMediaLoader *mediaLoader = [[MXKMediaLoader alloc] init];
        // Report this loader
        if (!downloadTable) {
            downloadTable = [[NSMutableDictionary alloc] init];
        }
        [downloadTable setValue:mediaLoader forKey:filePath];
        
        // Launch download
        [mediaLoader downloadMediaFromURL:mediaURL andSaveAtFilePath:filePath success:^(NSString *outputFilePath) {
            [downloadTable removeObjectForKey:filePath];
        } failure:^(NSError *error) {
            [downloadTable removeObjectForKey:filePath];
        }];
        return mediaLoader;
    }
    
    return nil;
}


+ (MXKMediaLoader*)existingDownloaderWithOutputFilePath:(NSString *)filePath {
    if (downloadTable && filePath) {
        return [downloadTable valueForKey:filePath];
    }
    return nil;
}

+ (void)cancelDownloadsInCacheFolder:(NSString*)folder {
    NSMutableArray *pendingLoaders =[[NSMutableArray alloc] init];
    NSArray *allKeys = [downloadTable allKeys];
    
    if (folder.length > 0) {
        NSString *folderPath = [MXKMediaManager cacheFolderPath:folder];
        for (NSString* key in allKeys) {
            if ([key hasPrefix:folderPath]) {
                [pendingLoaders addObject:[downloadTable valueForKey:key]];
                [downloadTable removeObjectForKey:key];
            }
        }
    }
    
    if (pendingLoaders.count) {
        for (MXKMediaLoader* loader in pendingLoaders) {
            [loader cancel];
        }
    }
}

+ (void)cancelDownloads {
    NSArray* allKeys = [downloadTable allKeys];
    
    for(NSString* key in allKeys) {
        [[downloadTable valueForKey:key] cancel];
        [downloadTable removeObjectForKey:key];
    }
}

#pragma mark - Media Uploader

+ (MXKMediaLoader*)prepareUploaderWithMatrixSession:(MXSession*)mxSession
                                       initialRange:(CGFloat)initialRange
                                           andRange:(CGFloat)range {
    if (mxSession) {
        // Create a media loader to upload data
        MXKMediaLoader *mediaLoader = [[MXKMediaLoader alloc] initForUploadWithMatrixSession:mxSession initialRange:initialRange andRange:range];
        // Report this loader
        if (!uploadTableById) {
            uploadTableById =  [[NSMutableDictionary alloc] init];
            
            MXKMediaManager *uploadObserver = [[super allocWithZone:NULL] init];
            [[NSNotificationCenter defaultCenter] addObserver:uploadObserver selector:@selector(onMediaUploadEnd:) name:kMXKMediaUploadDidFinishNotification object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:uploadObserver selector:@selector(onMediaUploadEnd:) name:kMXKMediaUploadDidFailNotification object:nil];
        }
        [uploadTableById setValue:mediaLoader forKey:mediaLoader.uploadId];
        return mediaLoader;
    }
    return nil;
}

+ (MXKMediaLoader*)existingUploaderWithId:(NSString*)uploadId {
    if (uploadTableById && uploadId) {
        return [uploadTableById valueForKey:uploadId];
    }
    return nil;
}

- (void)onMediaUploadEnd:(NSNotification *)notif {
    [MXKMediaManager removeUploaderWithId:notif.object];
}

+ (void)removeUploaderWithId:(NSString*)uploadId {
    if (uploadTableById && uploadId) {
        [uploadTableById removeObjectForKey:uploadId];
    }
}

+ (void)cancelUploads {
    NSArray* allKeys = [uploadTableById allKeys];
    
    for(NSString* key in allKeys) {
        [[uploadTableById valueForKey:key] cancel];
        [uploadTableById removeObjectForKey:key];
    }
}

#pragma mark - Cache Handling

+ (NSString*)cacheFolderPath:(NSString*)folder {
    NSString* path = [MXKMediaManager getCachePath];
    
    // update the path if the folder is provided
    if (folder.length > 0) {
        path = [[MXKMediaManager getCachePath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu", (unsigned long)folder.hash]];
    }
    
    // create the folder it does not exist
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil];
    }
    
    return path;
}

+ (NSString*)cachePathForMediaWithURL:(NSString*)url inFolder:(NSString*)folder {
    if (!folder.length) {
        folder = kMXKMediaManagerDefaultCacheFolder;
    }
    
    NSString *cacheFilePath = [[MXKMediaManager cacheFolderPath:folder] stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu", (unsigned long)url.hash]];
    
    NSString *extension = [url pathExtension];
    if (extension.length) {
        cacheFilePath = [NSString stringWithFormat:@"%@.%@", cacheFilePath, extension];
    }
    
    return cacheFilePath;
}

+ (NSString*)cachePathForMediaWithURL:(NSString*)url andType:(NSString *)mimeType inFolder:(NSString*)folder {
    if (!folder.length) {
        folder = kMXKMediaManagerDefaultCacheFolder;
    }
    
    NSString* fileExt = [MXKTools fileExtensionFromContentType:mimeType];
    
    // use the mime type to extract a base filename
    NSString* fileBase = @"";
    if ([mimeType rangeOfString:@"/"].location != NSNotFound){
        NSArray *components = [mimeType componentsSeparatedByString:@"/"];
        fileBase = [components objectAtIndex:0];
        if (fileBase.length > 3) {
            fileBase = [fileBase substringToIndex:3];
        }
    }
    
    return [[MXKMediaManager cacheFolderPath:folder] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%lu%@", fileBase, (unsigned long)url.hash, fileExt]];
}

+ (void)reduceCacheSizeToInsert:(NSUInteger)sizeInBytes {
    
    if (([MXKMediaManager cacheSize] + sizeInBytes) > [MXKMediaManager maxAllowedCacheSize]) {
        
        NSString* thumbnailPath = [MXKMediaManager cacheFolderPath:kMXKMediaManagerAvatarThumbnailFolder];
        
        // add a 50 MB margin to reduce this method call
        NSUInteger maxSize = 0;
        
        // check if the cache cannot content the file
        if ([MXKMediaManager maxAllowedCacheSize] < (sizeInBytes - 50 * 1024 * 1024)) {
            // delete item as much as possible
            maxSize = 0;
        } else {
            maxSize = [MXKMediaManager maxAllowedCacheSize] - sizeInBytes - 50 * 1024 * 1024;
        }
        
        NSArray* filesList = [MXKTools listFiles:mediaCachePath timeSorted:YES largeFilesFirst:YES];
        
        // list the files sorted by timestamp
        for(NSString* filepath in filesList) {
            // do not release the contact thumbnails : they must be released when the contacts are deleted
            if (![filepath hasPrefix:thumbnailPath]) {
                NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filepath error:nil];
                
                // sanity check
                if (fileAttributes) {
                    // delete the files
                    if ([[NSFileManager defaultManager] removeItemAtPath:filepath error:nil]) {
                        storageCacheSize -= fileAttributes.fileSize;
                        if (storageCacheSize < maxSize) {
                            return;
                        }
                    }
                }
            }
        }
    }
}

+ (NSUInteger)cacheSize {
    if (!mediaCachePath) {
        // compute the path
        mediaCachePath = [MXKMediaManager getCachePath];
    }
    
    // assume that 0 means uninitialized
    if (storageCacheSize == 0) {
        storageCacheSize = (NSUInteger)[MXKTools folderSize:mediaCachePath];
    }
        
    return storageCacheSize;
}

+ (NSUInteger)minCacheSize {
    NSUInteger minSize = [MXKMediaManager cacheSize];
    NSArray* filenamesList = [MXKTools listFiles:mediaCachePath timeSorted:NO largeFilesFirst:YES];
 
    NSFileManager* defaultManager = [NSFileManager defaultManager];
    
    for(NSString* filename in filenamesList) {
        NSDictionary* attsDict = [defaultManager attributesOfItemAtPath:filename error:nil];
        
        if (attsDict) {
            if (attsDict.fileSize > 100 * 1024) {
                minSize -= attsDict.fileSize;
            }
        }
    }
    return minSize;
}

+ (NSInteger)currentMaxCacheSize {
    NSInteger res = [[NSUserDefaults standardUserDefaults] integerForKey:@"maxMediaCacheSize"];
    
    // no default value, assume that 1 GB is enough
    if (res == 0) {
        res = self.maxAllowedCacheSize;
    }
    
    return res;
}

+ (void)setCurrentMaxCacheSize:(NSInteger)maxCacheSize {
    if ((maxCacheSize == 0) && (maxCacheSize > self.maxAllowedCacheSize)) {
        maxCacheSize = self.maxAllowedCacheSize;
    }
    
    [[NSUserDefaults standardUserDefaults] setInteger:maxCacheSize forKey:@"maxMediaCacheSize"];
}

+ (NSUInteger)maxAllowedCacheSize {
    return 1024 * 1024 * 1024;
}

+ (void)clearCache {
    NSError *error = nil;
    
    if (!mediaCachePath) {
        // compute the path
        mediaCachePath = [MXKMediaManager getCachePath];
    }
    
    [MXKMediaManager cancelDownloads];
    [MXKMediaManager cancelUploads];
    
    if (mediaCachePath) {
        if (![[NSFileManager defaultManager] removeItemAtPath:mediaCachePath error:&error]) {
            NSLog(@"[MXKMediaManager] Failed to delete media cache dir: %@", error);
        } else {
            NSLog(@"[MXKMediaManager] Media cache has been deleted");
        }
    } else {
        NSLog(@"[MXKMediaManager] Media cache does not exist");
    }
    
    mediaCachePath = nil;
    // force to recompute the cache size at next cacheSize call
    storageCacheSize = 0;
}

+ (NSString*)getCachePath {
    NSString *cachePath = nil;
    
    if (!mediaCachePath) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheRoot = [paths objectAtIndex:0];
        
        mediaCachePath = [cacheRoot stringByAppendingPathComponent:mediaDir];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:mediaCachePath]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:mediaCachePath withIntermediateDirectories:NO attributes:nil error:nil];
        }
    }
    cachePath = mediaCachePath;
    
    return cachePath;
}

@end
