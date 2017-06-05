/*
 Copyright 2017 Vector Creations Ltd
 
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

#import "MXCallKitAdapter.h"

@import CallKit;
@import UIKit;

#import "MXCall.h"
#import "MXUser.h"
#import "MatrixSDK/MXSession.h"

@interface MXCallKitAdapter () <CXProviderDelegate>

@property (nonatomic) CXProvider *provider;
@property (nonatomic) CXCallController *callController;

@end

@implementation MXCallKitAdapter

- (instancetype)init
{
    if (!(self = [super init])) return nil;
    
    self.provider = [[CXProvider alloc] initWithConfiguration:[MXCallKitAdapter configuration]];
    [self.provider setDelegate:self queue:nil];
    
    self.callController = [[CXCallController alloc] initWithQueue:dispatch_get_main_queue()];
    
    return self;
}

+ (CXProviderConfiguration *)configuration
{
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    
    CXProviderConfiguration *configuration = [[CXProviderConfiguration alloc] initWithLocalizedName:appDisplayName];
    configuration.maximumCallGroups = 1;
    configuration.maximumCallsPerCallGroup = 1;
    configuration.supportsVideo = false;
    configuration.supportedHandleTypes = [NSSet setWithObject:@(CXHandleTypeGeneric)];
    configuration.iconTemplateImageData = UIImagePNGRepresentation([UIImage imageNamed:@"RiotCallKitLogo"]);
    
    return configuration;
}

// Pass user id or smth like this to determine user id

// Outgoing calll
- (void)startCallWithUUID:(NSUUID *)uuid
{
    CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:@"User name"];
    CXStartCallAction *action = [[CXStartCallAction alloc] initWithCallUUID:uuid handle:handle];
    action.contactIdentifier = @"User display name";
    
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:action];
    
    [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
        if (error != nil) return;
        
        CXCallUpdate *update = [[CXCallUpdate alloc] init];
        update.remoteHandle = handle;
        update.localizedCallerName = @"User display name";
        update.supportsHolding = YES;
        update.hasVideo = NO;
        update.supportsGrouping = NO;
        update.supportsUngrouping = NO;
        update.supportsDTMF = NO;
        
        [self.provider reportNewIncomingCallWithUUID:uuid update:update completion:^(NSError * _Nullable error) {
            if (error != nil) return;
            
            // add call to our list
        }];
    }];
}

- (void)reportIncomingCall:(MXCall *)call {
    // Create CXHandle instance describing a caller
    CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:call.callerId];
    
    MXSession *mxSession = call.room.mxSession;
    MXUser *caller = [mxSession userWithUserId:call.callerId];
    
    CXCallUpdate *update = [[CXCallUpdate alloc] init];
    update.remoteHandle = handle;
    update.localizedCallerName = [caller displayname];
    update.hasVideo = NO;
    update.supportsHolding = NO;
    update.supportsGrouping = NO;
    update.supportsUngrouping = NO;
    update.supportsDTMF = NO;
    
    NSUUID *callUUID = [NSUUID UUID];//[[NSUUID alloc] initWithUUIDString:call.callId];
    
    // Inform system about incoming call
    [self.provider reportNewIncomingCallWithUUID:callUUID update:update completion:^(NSError * _Nullable error) {
        /*
         Only add incoming call to the app's list of calls if the call was allowed (i.e. there was no error)
         since calls may be "denied" for various legitimate reasons. See CXErrorCodeIncomingCallError.
         */
        if (error)
        {
            if ([error.domain isEqualToString:CXErrorDomainIncomingCall] && error.code == CXErrorCodeIncomingCallErrorFilteredByDoNotDisturb)
                // show alert or do smth to inform user
//                completion(NO, YES);
                NSLog(@"Do not disturb!");
            else
//                completion(YES, NO);
            
            return;
        }
        
        // Success
//        completion(NO, NO);
    }];
    
}

- (void)reportCall:(MXCall *)mxCall startedConnectingAtDate:(NSDate *)date
{
    NSUUID *callUUID = [[NSUUID alloc] initWithUUIDString:mxCall.callId];
    [_provider reportOutgoingCallWithUUID:callUUID startedConnectingAtDate:date];
}

- (void)reportCall:(MXCall *)mxCall connectedAtDate:(NSDate *)date
{
    NSUUID *callUUID = [[NSUUID alloc] initWithUUIDString:mxCall.callId];
    [_provider reportOutgoingCallWithUUID:callUUID connectedAtDate:date];
}

- (BOOL)callKitAvailable
{
    // TODO: Check iOS version and return apppropriate result based on the system version
    
    return YES;
}

#pragma mark - CXProviderDelegate

- (void)provider:(CXProvider *)__unused provider performStartCallAction:(CXStartCallAction *)action
{
    [action fulfill];
}

#pragma mark - CXProviderDelegate

- (void)providerDidReset:(CXProvider *)provider
{
    NSLog(@"Provider did reset");
}

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action
{
    // Call on success
    [action fulfill];
    
    // Call on fail
    [action fail];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action
{
    
}

@end
