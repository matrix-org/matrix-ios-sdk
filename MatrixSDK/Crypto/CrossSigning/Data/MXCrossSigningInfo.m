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

@implementation MXCrossSigningInfo

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


#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        _userId = [aDecoder decodeObjectForKey:@"userId"];
        _keys = [aDecoder decodeObjectForKey:@"keys"];
        _trustLevel = [aDecoder decodeObjectForKey:@"trustLevel"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_userId forKey:@"userId"];
    [aCoder encodeObject:_keys forKey:@"keys"];
    [aCoder encodeObject:_trustLevel forKey:@"trustLevel"];
}


#pragma mark - SDK-Private methods -

- (instancetype)initWithUserId:(NSString *)userId
{
    self = [self init];
    if (self)
    {
        _userId = userId;
        _trustLevel = [MXUserTrustLevel new];
    }
    return self;
}

- (BOOL)updateTrustLevel:(MXUserTrustLevel*)trustLevel;
{
    BOOL updated = NO;

    if (![_trustLevel isEqual:trustLevel])
    {
        _trustLevel = trustLevel;
        updated = YES;
    }

    return updated;
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

@end
