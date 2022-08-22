// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "MXFileRoomSummaryStore.h"
#import "MXTools.h"
#import "MatrixSDKSwiftHeader.h"

static NSString *const kMXFileRoomSummaryStoreFolder = @"MXFileRoomSummaryStore";

@interface MXFileRoomSummaryStore()
{
    // The user credentials
    MXCredentials *credentials;
    
    // The path of the MXFileStore folder
    NSString *storePath;

    //  Execution queue for computationally expensive operations.
    dispatch_queue_t executionQueue;
}
@end

@implementation MXFileRoomSummaryStore

- (instancetype)initWithCredentials:(MXCredentials *)credentials
{
    if (self = [super init])
    {
        self->credentials = credentials;
        executionQueue = dispatch_queue_create("MXFileRoomSummaryStoreExecutionQueue", DISPATCH_QUEUE_SERIAL);
        [self setUpStoragePaths];
    }
    return self;
}

- (void)setUpStoragePaths
{
    // credentials must be set before this method starts execution
    NSParameterAssert(credentials);
    
    NSString *cachePath = nil;
    
    NSURL *sharedContainerURL = [[NSFileManager defaultManager] applicationGroupContainerURL];
    if (sharedContainerURL)
    {
        cachePath = [sharedContainerURL path];
    }
    else
    {
        NSArray *cacheDirList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        cachePath  = [cacheDirList objectAtIndex:0];
    }
    
    storePath = [[cachePath stringByAppendingPathComponent:kMXFileRoomSummaryStoreFolder] stringByAppendingPathComponent:credentials.userId];
}

- (void)checkStorePathExistence
{
    NSString *folder = storePath;
    if (![NSFileManager.defaultManager fileExistsAtPath:folder])
    {
        [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:folder error:nil];
    }
}

- (NSString*)summaryFileForRoom:(NSString*)roomId
{
    return [storePath stringByAppendingPathComponent:roomId];
}

#pragma mark - MXRoomSummaryStore

- (NSArray<NSString *> *)rooms
{
    NSArray<NSString *> *result = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storePath error:nil];
    if (!result)
    {
        return @[];
    }
    return result;
}

- (NSUInteger)countOfRooms
{
    NSArray<NSString *> *result = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storePath error:nil];
    return result.count;
}

- (void)storeSummary:(id<MXRoomSummaryProtocol>)summary
{
    [super storeSummary:summary];
    
    dispatch_async(executionQueue, ^{
        NSString *file = [self summaryFileForRoom:summary.roomId];
        [self checkStorePathExistence];
        
        [NSKeyedArchiver archiveRootObject:summary toFile:file];
    });
}

- (id<MXRoomSummaryProtocol>)summaryOfRoom:(NSString *)roomId
{
    id<MXRoomSummaryProtocol> summary = [super summaryOfRoom:roomId];
    if (!summary)
    {
        NSString *summaryFile = [self summaryFileForRoom:roomId];
        if ([[NSFileManager defaultManager] fileExistsAtPath:summaryFile])
        {
            @try
            {
                NSDate *startDate = [NSDate date];
                summary = [NSKeyedUnarchiver unarchiveObjectWithFile:summaryFile];
                [super storeSummary:summary];
                
                if ([NSThread isMainThread])
                {
                    MXLogWarning(@"[MXFileStore] Loaded room summary of room: %@ in %.0fms, in main thread", roomId, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
                }
            }
            @catch(NSException *exception)
            {
                NSDictionary *details = @{
                    @"room_id": roomId ?: @"unknown",
                    @"exception": exception ?: @"unknown"
                };
                MXLogErrorDetails(@"[MXFileStore] Warning: room summary file for room has been corrupted", details);
            }
        }
    }
    return summary;
}

- (void)removeSummaryOfRoom:(NSString *)roomId
{
    [super removeSummaryOfRoom:roomId];
    
    NSString *summaryFile = [self summaryFileForRoom:roomId];
    [[NSFileManager defaultManager] removeItemAtPath:summaryFile error:nil];
}

- (void)removeAllSummaries
{
    [super removeAllSummaries];
    
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:nil];
}

- (void)fetchAllSummaries:(void (^)(NSArray<id<MXRoomSummaryProtocol>> * _Nonnull))completion
{
    dispatch_async(executionQueue, ^{
        NSArray<NSString *> *roomIDs = self.rooms;
        NSMutableArray<id<MXRoomSummaryProtocol>> *result = [NSMutableArray arrayWithCapacity:roomIDs.count];
        
        for (NSString *roomId in roomIDs)
        {
            NSString *summaryFile = [self summaryFileForRoom:roomId];
            id<MXRoomSummaryProtocol> summary = [NSKeyedUnarchiver unarchiveObjectWithFile:summaryFile];
            if (summary)
            {
                [result addObject:summary];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    });
}

@end
