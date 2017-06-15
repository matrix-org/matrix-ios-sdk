//
//  MXCallKitConfiguration.m
//  MatrixSDK
//
//  Created by Denis on 15.06.17.
//  Copyright © 2017 matrix.org. All rights reserved.
//

#import "MXCallKitConfiguration.h"

@implementation MXCallKitConfiguration

- (instancetype)init
{
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    return [self initWithName:appDisplayName
                 ringtoneName:nil
                     iconName:nil
                supportsVideo:YES];
}

- (instancetype)initWithName:(NSString *)name
                ringtoneName:(nullable NSString *)ringtoneName
                    iconName:(nullable NSString *)iconName
               supportsVideo:(BOOL)supportsVideo
{
    if (self = [super init])
    {
        _name = [name copy];
        _ringtoneName = [ringtoneName copy];
        _iconName = [iconName copy];
        _supportsVideo = supportsVideo;
    }
    
    return self;
}

@end
