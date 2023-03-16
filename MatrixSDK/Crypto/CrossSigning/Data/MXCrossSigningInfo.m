/*
 Copyright 2020 The Matrix.org Foundation C.I.C

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

#import "MXCrossSigningInfo_Private.h"
#import "MatrixSDKSwiftHeader.h"

#pragma mark - Constants

NSString *const MXCrossSigningInfoTrustLevelDidChangeNotification = @"MXCrossSigningInfoTrustLevelDidChangeNotification";

#pragma mark - Deprecated user trust

/**
 Deprecated model of user trust that distinguished local vs cross-signing verification
 
 This model is no longer used and is replaced by a combined `isVerified` property on `MXCrossSigningInfo`.
 For backwards compatibility (reading archived values) the model needs to be kept around, albeit as private only.
 */
@interface MXDeprecatedUserTrustLevel : NSObject <NSCoding>
@property (nonatomic, readonly) BOOL isCrossSigningVerified;
@end

@implementation MXDeprecatedUserTrustLevel
- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        // We ignore `isLocallyVerified` field and only consider `isCrossSigningVerified`
        _isCrossSigningVerified = [aDecoder decodeBoolForKey:@"isCrossSigningVerified"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    MXLogFailure(@"[MXDeprecatedUserTrustLevel] encode: This model should only be used for decoding existing data, not encoding new data");
}
@end

#pragma mark - CrossSigningInfo

@implementation MXCrossSigningInfo

- (instancetype)initWithUserIdentity:(MXCryptoUserIdentityWrapper *)userIdentity
{
    self = [self init];
    if (self)
    {
        _userId = userIdentity.userId;
        NSMutableDictionary *keys = [NSMutableDictionary dictionary];
        if (userIdentity.masterKeys)
        {
            keys[MXCrossSigningKeyType.master] = userIdentity.masterKeys;
        }
        if (userIdentity.selfSignedKeys)
        {
            keys[MXCrossSigningKeyType.selfSigning] = userIdentity.selfSignedKeys;
        }
        if (userIdentity.userSignedKeys)
        {
            keys[MXCrossSigningKeyType.userSigning] = userIdentity.userSignedKeys;
        }
        _keys = keys.copy;
        _isVerified = userIdentity.isVerified;
    }
    return self;
}

- (MXCrossSigningKey *)masterKeys
{
    return _keys[MXCrossSigningKeyType.master];
}

- (MXCrossSigningKey *)selfSignedKeys
{
    return _keys[MXCrossSigningKeyType.selfSigning];
}

- (MXCrossSigningKey *)userSignedKeys
{
    return _keys[MXCrossSigningKeyType.userSigning];
}

- (BOOL)hasSameKeysAsCrossSigningInfo:(MXCrossSigningInfo*)otherCrossSigningInfo
{
    if (![self.userId isEqualToString:otherCrossSigningInfo.userId])
    {
        return NO;
    }
    
    BOOL hasSameKeys = YES;
    for (NSString *key in _keys)
    {
        if (![self.keys[key].keys isEqualToString:otherCrossSigningInfo.keys[key].keys])
        {
            hasSameKeys = NO;
            break;
        }
    }
    
    return hasSameKeys;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        _userId = [aDecoder decodeObjectForKey:@"userId"];
        _keys = [aDecoder decodeObjectForKey:@"keys"];
        
        // Initial version (i.e. version 0) of the model stored user trust via `MXUserTrustLevel` submodel.
        // If we are reading this version out we need to decode verification state from this model before
        // migrating it over to `isVerified`
        NSInteger version = [aDecoder decodeIntegerForKey:@"version"];
        if (version == 0)
        {
            [NSKeyedUnarchiver setClass:MXDeprecatedUserTrustLevel.class forClassName:@"MXUserTrustLevel"];
            MXDeprecatedUserTrustLevel *trust = [aDecoder decodeObjectForKey:@"trustLevel"];
            // Only convert cross-signed verification status, not local verification status
            _isVerified = trust.isCrossSigningVerified;
        }
        else
        {
            _isVerified = [aDecoder decodeBoolForKey:@"isVerified"];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_userId forKey:@"userId"];
    [aCoder encodeObject:_keys forKey:@"keys"];
    [aCoder encodeBool:_isVerified forKey:@"isVerified"];
    [aCoder encodeInteger:1 forKey:@"version"];
}


#pragma mark - SDK-Private methods -

- (instancetype)initWithUserId:(NSString *)userId
{
    self = [self init];
    if (self)
    {
        _userId = userId;
        _isVerified = NO;
    }
    return self;
}

- (void)setIsVerified:(BOOL)isVerified
{
    if (_isVerified == isVerified)
    {
        return;
    }
    
    _isVerified = isVerified;
    [self didUpdateVerificationState];
}

- (void)didUpdateVerificationState
{
    dispatch_async(dispatch_get_main_queue(),^{
        [[NSNotificationCenter defaultCenter] postNotificationName:MXCrossSigningInfoTrustLevelDidChangeNotification object:self userInfo:nil];
    });
}

- (void)addCrossSigningKey:(MXCrossSigningKey*)crossSigningKey type:(NSString*)type
{
    NSMutableDictionary<NSString*, MXCrossSigningKey*> *keys = [_keys mutableCopy];
    if (!keys)
    {
        keys = [NSMutableDictionary dictionary];
    }
    keys[type] = crossSigningKey;

    _keys = keys;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXCrossSigningInfo: %p> Verified: %@\nMSK: %@\nSSK: %@\nUSK: %@", self, @(self.isVerified), self.masterKeys, self.selfSignedKeys, self.userSignedKeys];
}

@end
