//
//  MXCallKitConfiguration.h
//  MatrixSDK
//
//  Created by Denis on 15.06.17.
//  Copyright © 2017 matrix.org. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

/**
 The `MXCallKitConfiguration` describes the desired appereance and behaviour for CallKit.
 */
@interface MXCallKitConfiguration : NSObject

/**
 The string associated with the application and which will be displayed in the native in-call UI
 to help user identify the source of the call
 
 Defaults to bundle display name.
 */
@property (nonatomic, copy) NSString *name;

/**
 The name of the ringtone sound located in app bundle and that will be played on incoming call. 
 */
@property (nonatomic, nullable, copy) NSString *ringtoneName;

/**
 The name of the icon associated with the application. It will be displayed in the native in-call UI.
 
 The icon image should be a square with side length of 40 points. 
 The alpha channel of the image is used to create a white image mask.
 */
@property (nonatomic, nullable, copy) NSString *iconName;

/**
 Tells whether video calls is supported.
 
 Defaults to YES.
 */
@property (nonatomic) BOOL supportsVideo;


- (instancetype)initWithName:(NSString *)name
                ringtoneName:(nullable NSString *)ringtoneName
                    iconName:(nullable NSString *)iconName
               supportsVideo:(BOOL)supportsVideo NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
