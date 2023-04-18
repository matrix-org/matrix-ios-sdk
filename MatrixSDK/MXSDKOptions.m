/*
 Copyright 2015 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
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

#import "MXSDKOptions.h"

#import "MXBaseProfiler.h"
#import "MatrixSDKSwiftHeader.h"

static MXSDKOptions *sharedOnceInstance = nil;

@implementation MXSDKOptions

+ (MXSDKOptions *)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sharedOnceInstance = [[self alloc] init]; });
    return sharedOnceInstance;
}

#pragma mark - Initializations -

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _profiler = [MXBaseProfiler new];
        _disableIdenticonUseForUserAvatar = NO;
        _enableCryptoWhenStartingMXSession = NO;
        _enableKeyBackupWhenStartingMXCrypto = YES;
        _mediaCacheAppVersion = 0;
        _videoConversionPresetName = AVAssetExportPreset1920x1080;
        _applicationGroupIdentifier = nil;
        _HTTPAdditionalHeaders = @{};
        _autoAcceptRoomInvites = NO;
        _callTransferType = MXCallTransferTypeBridged;
        self.roomListDataManagerClass = [MXCoreDataRoomListDataManager class];
        _clientPermalinkBaseUrl = nil;
        _authEnableRefreshTokens = NO;
        _enableThreads = NO;
        _enableRoomSharedHistoryOnInvite = NO;
        _enableSymmetricBackup = NO;
        _enableNewClientInformationFeature = NO;
        _cryptoMigrationDelegate = nil;
    }
    
    return self;
}

- (void)setRoomListDataManagerClass:(Class)roomListDataManagerClass
{
    // Sanity check
    NSAssert([roomListDataManagerClass conformsToProtocol:@protocol(MXRoomListDataManager)], @"MXSDKOptions only manages room list data manager class that conforms to MXRoomListDataManager protocol");
    
    _roomListDataManagerClass = roomListDataManagerClass;
}

@end
