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


@implementation MXKeyProvider

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (nullable MXKeyData *)requestKeyForDataOfType:(nonnull NSString *)dataType
                                    isMandatory:(BOOL)isMandatory
                                expectedKeyType:(MXKeyType)keyType
{
    if ([self isEncryptionAvailableForDataOfType:dataType]
        && [self hasKeyForDataOfType:dataType isMandatory:isMandatory])
    {
        return [self keyDataForDataOfType:dataType isMandatory:isMandatory expectedKeyType:keyType];
    }
    
    return nil;
}

- (BOOL)isEncryptionAvailableForDataOfType:(nonnull NSString *)dataType
{
    return self.delegate && [self.delegate isEncryptionAvailableForDataOfType:dataType];
}

- (BOOL)hasKeyForDataOfType:(nonnull NSString *)dataType
                isMandatory:(BOOL)isMandatory
{
    BOOL keyAvailable = [self.delegate hasKeyForDataOfType:dataType];
    
    if (!keyAvailable && isMandatory)
    {
        [NSException raise:@"MandatoryKey" format:@"Mandatory Key not available for data of type %@", dataType];
    }
    
    return keyAvailable;
}

- (nonnull MXKeyData *)keyDataForDataOfType:(NSString *)dataType
                                isMandatory:(BOOL)isMandatory
                            expectedKeyType:(MXKeyType)keyType
{
    MXKeyData *keyData = [self.delegate keyDataForDataOfType:dataType];
    
    if (!keyData && isMandatory)
    {
        [NSException raise:@"MandatoryKey" format:@"No key value for mandatory Key (data type : %@)", dataType];
    }

    if (keyData && keyData.type != keyType)
    {
        [NSException raise:@"KeyType" format:@"Wrong key type (%lu expected %lu) for data of type : %@", keyData.type, keyType, dataType];
    }

    return keyData;
}

@end
