//
//  MXUsersDevicesMap.m
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 04/10/16.
//  Copyright © 2016 matrix.org. All rights reserved.
//

#import "MXUsersDevicesMap.h"

@implementation MXUsersDevicesMap

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _map = [NSDictionary dictionary];
    }

    return self;
}

- (instancetype)initWithMap:(NSDictionary *)map
{
    self = [super init];
    if (self)
    {
        _map = map;
    }

    return self;
}

- (NSArray<NSString *> *)userIds
{
    return _map.allKeys;
}

- (NSArray<NSString *> *)deviceIdsForUser:(NSString *)userId
{
    return _map[userId].allKeys;
}

-(id)objectForDevice:(NSString *)deviceId forUser:(NSString *)userId
{
    return _map[userId][deviceId];
}

- (void)setObject:(id)object forUser:(NSString *)userId andDevice:(NSString *)deviceId
{
    NSMutableDictionary *mutableMap = [NSMutableDictionary dictionaryWithDictionary:self.map];

    mutableMap[userId] = [NSMutableDictionary dictionaryWithDictionary:mutableMap[userId]];
    mutableMap[userId][deviceId] = object;

    _map = mutableMap;
}

-(void)setObjects:(NSDictionary *)objectsPerDevices forUser:(NSString *)userId
{
    NSMutableDictionary *mutableMap = [NSMutableDictionary dictionaryWithDictionary:_map];
    mutableMap[userId] = objectsPerDevices;

    _map = mutableMap;
}

#pragma mark - NSCopying
- (id)copyWithZone:(NSZone *)zone
{
    // @TODO: write specific and quicker code
    return [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:self]];
}


#pragma mark - NSCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _map = [aDecoder decodeObjectForKey:@"map"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_map forKey:@"map"];
}

@end
