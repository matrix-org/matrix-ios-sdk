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

#import "MXRealmInMemoryProvider.h"
#import <Realm/Realm.h>

#pragma mark - Defines & Constants

static NSString* const kRealmIdentifierFormat = @"matrix-%@";

#pragma mark - Private Interface

@interface MXRealmInMemoryProvider()

// RealmConfiguration by user id
// RLMRealmConfiguration is thread safe contrary to RLMRealm
@property(nonatomic, strong) NSMutableDictionary<NSString*, RLMRealmConfiguration*> *usersRealmConfiguration;

@end

#pragma mark - Implementation

@implementation MXRealmInMemoryProvider

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

#pragma mark - Implementation

// Notice from Realm: When all in-memory Realm instances with a particular identifier go out of scope with no references, all data in that Realm is deleted. We recommend holding onto a strong reference to any in-memory Realms during your app’s lifetime. (This is not necessary for on-disk Realms.)
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
        NSLog(@"[MXRealmInMemoryProvider] realmForUser gets error: %@", error);
    }
    
    return realm;
}

- (void)deleteRealmForUserId:(NSString *)userId
{
    RLMRealm *realm = [self realmForUserId:userId];
    
    [realm transactionWithBlock:^{
        [realm deleteAllObjects];
    }];
    
    self.usersRealmConfiguration[userId] = nil;
}

#pragma mark - Private

- (RLMRealmConfiguration*)realmConfigurationForUserId:(NSString*)userId
{    
    RLMRealmConfiguration *realmConfiguration = [RLMRealmConfiguration defaultConfiguration];
    realmConfiguration.inMemoryIdentifier = [NSString stringWithFormat:kRealmIdentifierFormat, userId];
    
    realmConfiguration.deleteRealmIfMigrationNeeded = YES;
    
    return realmConfiguration;
}


@end
