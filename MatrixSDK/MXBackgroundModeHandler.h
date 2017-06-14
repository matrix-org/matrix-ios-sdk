//
//  MXBackgroundModeHandler.h
//  Pods
//
//  Created by Samuel Gallet on 24/05/2017.
//
//

#ifndef MXBackgroundModeHandler_h
#define MXBackgroundModeHandler_h

#import <Foundation/Foundation.h>

/**
 Interface to handle enabling background mode
 */
@protocol MXBackgroundModeHandler <NSObject>
- (NSUInteger)invalidIdentifier;
- (NSUInteger)startBackgroundTask;
- (NSUInteger)startBackgroundTaskWithName:(NSString *)name completion:(void(^)())completion;
- (void)endBackgrounTaskWithIdentifier:(NSUInteger)identifier;
@end

#endif /* MXBackgroundModeHandler_h */
