// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

#import "MXKeyProvider.h"

static MXKeyProvider *sharedInstance = nil;
static NSDictionary* configurationsForDataType = nil;

@interface MXKeyConfig: NSObject

+ (instancetype) configWithMandatory: (BOOL)isMandatory keyType: (MXKeyType)keyType;

- (instancetype) initWithMandatory: (BOOL)isMandatory keyType: (MXKeyType)keyType;

@property (nonatomic) BOOL isMandatory;

@property (nonatomic) MXKeyType keyType;

@end


@implementation MXKeyProvider

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
        
        configurationsForDataType =
        @{
            @(kContactsType) : [MXKeyConfig configWithMandatory:NO keyType:kAes],
            @(kAccountType) : [MXKeyConfig configWithMandatory:YES keyType:kAes],
        };
        
    });
    return sharedInstance;
}

- (nullable MXKeyData *)requestKeyForDataOfType:(MXDataType)dataType {
    if ([self isEncryptionAvailableForDataOfType:dataType]
        && [self hasKeyForDataOfType:dataType])
    {
        return [self keyDataForDataOfType:dataType];
    }
    
    return nil;
}

- (BOOL)isEncryptionAvailableForDataOfType:(MXDataType)dataType
{
    return self.delegate && [self.delegate enableEncryptionForDataOfType:dataType];
}

- (BOOL)hasKeyForDataOfType:(MXDataType)dataType
{
    BOOL keyAvailable = [self.delegate hasKeyForDataOfType:dataType];
    
    MXKeyConfig *config = [self configForDataOfType:dataType];
    
    if (!keyAvailable && config.isMandatory)
    {
        [NSException raise:@"MandatoryKey" format:@"Mandatory Key not available for data of type %lu", dataType];
    }
    
    return keyAvailable;
}

- (nonnull MXKeyData *)keyDataForDataOfType:(MXDataType)dataType
{
    MXKeyData *keyData = [self.delegate keyDataForDataOfType:dataType];
    MXKeyConfig *config = [configurationsForDataType objectForKey:@(dataType)];
    
    if (!keyData && config.isMandatory)
    {
        [NSException raise:@"MandatoryKey" format:@"No key value for mandatory Key (date type : %lu)", dataType];
    }

    if (keyData.type != config.keyType)
    {
        [NSException raise:@"KeyType" format:@"Wrong key type (%lu expected %lu) for data of type : %lu", keyData.type, config.keyType, dataType];
    }

    return keyData;
}

#pragma mark private methods

- (MXKeyConfig *) configForDataOfType:(MXDataType)dataType
{
    MXKeyConfig *config = [configurationsForDataType objectForKey:@(dataType)];
    
    if (!config)
    {
        [NSException raise:@"MissingConfigurationForDataType" format:@"Missing configuration for data of type %lu", dataType];
    }
    
    return config;
}

@end

@implementation MXKeyConfig

+ (instancetype)configWithMandatory:(BOOL)isMandatory keyType: (MXKeyType)keyType
{
    return [[MXKeyConfig alloc] initWithMandatory:isMandatory keyType:keyType];
}

- (instancetype)initWithMandatory:(BOOL)isMandatory keyType: (MXKeyType)keyType
{
    self = [super init];
    
    if (self) {
        self.isMandatory = isMandatory;
        self.keyType = keyType;
    }
    
    return self;
}

@end
