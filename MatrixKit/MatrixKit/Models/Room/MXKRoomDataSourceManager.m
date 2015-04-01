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

#import "MXKRoomDataSourceManager.h"

@interface MXKRoomDataSourceManager() {

    MXSession *mxSession;

    /**
     The list of running roomDataSources.
     Each key is a room ID. Each value, the MXKRoomDataSource instance.
     */
    NSMutableDictionary *roomDataSources;
}

@end

@implementation MXKRoomDataSourceManager

+ (MXKRoomDataSourceManager *)sharedManagerForMatrixSession:(MXSession *)mxSession {

    // Manage a pool of managers: one per Matrix session
    static NSMutableDictionary *_roomDataSourceManagers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _roomDataSourceManagers = [NSMutableDictionary dictionary];
    });

    MXKRoomDataSourceManager *roomDataSourceManager;

    // Compute an id for this mxSession object: its pointer address as a string
    NSString *mxSessionId = [NSString stringWithFormat:@"%p", mxSession];

    @synchronized(_roomDataSourceManagers) {
        // If not available yet, create the `MXKRoomDataSourceManager` for this Matrix session
        roomDataSourceManager = _roomDataSourceManagers[mxSessionId];
        if (!roomDataSourceManager) {
            roomDataSourceManager = [[MXKRoomDataSourceManager alloc]initWithMatrixSession:mxSession];
            _roomDataSourceManagers[mxSessionId] = roomDataSourceManager;
        }
    }

    return roomDataSourceManager;
}

- (instancetype)initWithMatrixSession:(MXSession *)matrixSession {

    self = [super init];
    if (self) {
        mxSession = matrixSession;
        roomDataSources = [NSMutableDictionary dictionary];
        _releasePolicy = MXKRoomDataSourceManagerReleasePolicyNeverRelease;
    }
    return self;
}

- (MXKRoomDataSource *)roomDataSourceForRoom:(NSString *)roomId create:(BOOL)create {

    // If not available yet, create the room data source
    MXKRoomDataSource *roomDataSource = roomDataSources[roomId];
    if (!roomDataSource && create) {
        roomDataSource = [[MXKRoomDataSource alloc] initWithRoomId:roomId andMatrixSession:mxSession];
        [self addRoomDataSource:roomDataSource];
    }
    return roomDataSource;
}

- (void)addRoomDataSource:(MXKRoomDataSource *)roomDataSource {
    roomDataSources[roomDataSource.roomId] = roomDataSource;
}

- (void)closeRoomDataSource:(MXKRoomDataSource *)roomDataSource forceClose:(BOOL)forceRelease {

    // The close consists in no more sending actions to the currrent view controller, the room data source delegate
    // According to the policy, it is interesting to keep the room data source in life: it can keep managing echo messages
    // in background for instance
    roomDataSource.delegate = nil;

    MXKRoomDataSourceManagerReleasePolicy releasePolicy = _releasePolicy;
    if (forceRelease) {
        // Act as ReleaseOnClose policy
        releasePolicy = MXKRoomDataSourceManagerReleasePolicyReleaseOnClose;
    }

    switch (releasePolicy) {

        case MXKRoomDataSourceManagerReleasePolicyReleaseOnClose:

            // Destroy and forget the instance
            [roomDataSource destroy];
            [roomDataSources removeObjectForKey:roomDataSource.roomId];
            break;

        case MXKRoomDataSourceManagerReleasePolicyNeverRelease:

            // Keep the instance for life. Do nothing
            break;

        default:
            break;
    }
}

@end
