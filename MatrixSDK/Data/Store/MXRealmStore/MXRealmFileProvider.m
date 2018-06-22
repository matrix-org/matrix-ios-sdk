/*
 Copyright 2018 New Vector Ltd
 
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

#import "MXRealmFileProvider.h"
#import "MXSDKOptions.h"
#import <Realm/Realm.h>

#pragma mark - Defines & Constants

static NSString* const kRealmIdentifierFormat = @"matrix-%@";
static NSString* const kRealmFileExtension = @"realm";
static NSString* const kRealmFileFolderName = @"user-realm-store";

#pragma mark - Private Interface

@interface MXRealmFileProvider()

// RealmConfiguration by user id
// RLMRealmConfiguration is thread safe contrary to RLMRealm
@property(nonatomic, strong) NSMutableDictionary<NSString*, RLMRealmConfiguration*> *usersRealmConfiguration;

@end

@implementation MXRealmFileProvider

#pragma mark - Setup & Teardown

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _usersRealmConfiguration = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - MXRealmProvider

- (RLMRealm*)realmForUserId:(NSString*)userId
{
    RLMRealmConfiguration *realmConfiguration = self.usersRealmConfiguration[userId];
    
    if (!realmConfiguration)
    {
        realmConfiguration = [self realmConfigurationForUserId:userId];
        self.usersRealmConfiguration[userId] = realmConfiguration;
    }
    
    NSError *error;
    RLMRealm *realm = [RLMRealm realmWithConfiguration:realmConfiguration error:&error];
    if (error)
    {
        NSLog(@"[MXRealmCryptoStore] realmForUser gets error: %@", error);
        
        // Remove the db file
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:realmConfiguration.fileURL.path error:&error];
        NSLog(@"[MXRealmCryptoStore] removeItemAtPath error result: %@", error);
        
        // And try again
        realm = [RLMRealm realmWithConfiguration:realmConfiguration error:&error];
        if (!realm)
        {
            NSLog(@"[MXRealmCryptoStore] realmForUser still gets after reset. Error: %@", error);
        }
    }
    
    return realm;
}

- (void)deleteRealmForUserId:(NSString*)userId
{
    RLMRealmConfiguration *realmConfiguration = [self realmConfigurationForUserId:userId];
    [self deleteRealmFilesWithConfiguration:realmConfiguration];
    self.usersRealmConfiguration[userId] = nil;
}

#pragma mark - Private

- (RLMRealmConfiguration*)realmConfigurationForUserId:(NSString*)userId
{
    // Each user has its own db file.
    RLMRealmConfiguration *realmConfiguration = [RLMRealmConfiguration defaultConfiguration];
    
    NSString *fileName = [NSString stringWithFormat:kRealmIdentifierFormat, userId];
    NSString *fileExtension = kRealmFileExtension;
    NSString *applicationGroupStoreFolder = kRealmFileFolderName;
    
    // Default db file URL: use the default directory, but replace the filename with the userId.
    NSURL *defaultRealmFileURL = [[[realmConfiguration.fileURL URLByDeletingLastPathComponent]
                                   URLByAppendingPathComponent:fileName]
                                  URLByAppendingPathExtension:fileExtension];
    
    // Check for a potential application group id.
    NSString *applicationGroupIdentifier = [MXSDKOptions sharedInstance].applicationGroupIdentifier;
    if (applicationGroupIdentifier)
    {
        // Use the shared db file URL.
        NSURL *sharedContainerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:applicationGroupIdentifier];
        NSURL *realmFileFolderURL = [sharedContainerURL URLByAppendingPathComponent:applicationGroupStoreFolder];
        NSURL *realmFileURL = [[realmFileFolderURL URLByAppendingPathComponent:fileName] URLByAppendingPathExtension:fileExtension];
        
        realmConfiguration.fileURL = realmFileURL;
        
        // Check whether an existing db file has to be be moved from the default folder to the shared container.
        if ([NSFileManager.defaultManager fileExistsAtPath:[defaultRealmFileURL path]])
        {
            if (![NSFileManager.defaultManager fileExistsAtPath:[realmFileURL path]])
            {
                // Move this db file in the container directory associated with the application group identifier.
                NSLog(@"[MXRealmFileProvider] Move the db file to the application group container");
                
                if (![NSFileManager.defaultManager fileExistsAtPath:realmFileFolderURL.path])
                {
                    [[NSFileManager defaultManager] createDirectoryAtPath:realmFileFolderURL.path withIntermediateDirectories:YES attributes:nil error:nil];
                }
                
                NSError *fileManagerError = nil;
                
                [NSFileManager.defaultManager moveItemAtURL:defaultRealmFileURL toURL:realmFileURL error:&fileManagerError];
                
                if (fileManagerError)
                {
                    NSLog(@"[MXRealmFileProvider] Move db file failed (%@)", fileManagerError);
                    // Keep using the old file
                    realmConfiguration.fileURL = defaultRealmFileURL;
                }
            }
            else
            {
                // Remove the residual db file.
                [NSFileManager.defaultManager removeItemAtURL:defaultRealmFileURL error:nil];
            }
        }
        else
        {
            // Make sure the full exists before giving it to Realm
            if (![NSFileManager.defaultManager fileExistsAtPath:realmFileFolderURL.path])
            {
                [[NSFileManager defaultManager] createDirectoryAtPath:realmFileFolderURL.path withIntermediateDirectories:YES attributes:nil error:nil];
            }
        }
    }
    else
    {
        //         Use the default URL
        realmConfiguration.fileURL = defaultRealmFileURL;
    }
    
    realmConfiguration.deleteRealmIfMigrationNeeded = YES;
    
    return realmConfiguration;
}

- (void)deleteRealmFilesWithConfiguration:(RLMRealmConfiguration*)realmConfiguration
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *realmFileURL = realmConfiguration.fileURL;
    NSArray<NSURL *> *realmFileURLs = @[
                                        realmFileURL,
                                        [realmFileURL URLByAppendingPathExtension:@"lock"],
                                        [realmFileURL URLByAppendingPathExtension:@"note"],
                                        [realmFileURL URLByAppendingPathExtension:@"management"]
                                        ];
    for (NSURL *URL in realmFileURLs)
    {
        NSError *error = nil;
        [fileManager removeItemAtURL:URL error:&error];
        
        if (error)
        {
            // handle error
        }
    }
}


@end
