/*
 Copyright 2015 OpenMarket Ltd
 
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

#import <UIKit/UIKit.h>

@interface MXKTools : NSObject

#pragma mark - Time

/**
 Format time interval
 
 @param secondsInterval time interval in seconds.
 @return formatted string
 */
+ (NSString*)formatSecondsInterval:(CGFloat)secondsInterval;

#pragma mark - File

/**
 Get folder size
 
 @param folderPath
 @return folder size in bytes
 */
+ (long long)folderSize:(NSString *)folderPath;

/**
 List files in folder
 
 @param folderPath
 @param isTimeSorted if YES, the files are sorted by creation date from the oldest to the most recent one.
 @param largeFilesFirst if YES move the largest file to the list head (large > 100KB). It can be combined with isTimeSorted.
 @return the list of files by name.
 */
+ (NSArray*)listFiles:(NSString *)folderPath timeSorted:(BOOL)isTimeSorted largeFilesFirst:(BOOL)largeFilesFirst;

/**
 Deduce the file extension from a contentType
 
 @param contentType
 @return file extension (extension divider is included)
 */
+ (NSString*)fileExtensionFromContentType:(NSString*)contentType;

#pragma mark - Image

/**
 Force image orientation to up
 
 @param imageSrc
 @return image with `UIImageOrientationUp` orientation.
 */
+ (UIImage*)forceImageOrientationUp:(UIImage*)imageSrc;

/**
 Resize image.
 
 @param image
 @param size to fit in.
 @return resized image.
 */
+ (UIImage *)resize:(UIImage *)image toFitInSize:(CGSize)size;

/**
 Convert a rotation angle to the most suitable image orientation.
 
 @param angle rotation angle in degree.
 @return image orientation.
 */
+ (UIImageOrientation)imageOrientationForRotationAngleInDegree:(NSInteger)angle;

@end
