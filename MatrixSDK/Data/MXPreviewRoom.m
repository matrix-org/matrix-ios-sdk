/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXPreviewRoom.h"

#import "MXMemoryStore.h"
#import "MXSession.h"

@implementation MXPreviewRoom

- (id)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession
{
    // Do not store the data  we will from the hs to the store of the session
    // but to an ephemeral store
    MXMemoryStore *memoryStore = [[MXMemoryStore alloc] init];
    [memoryStore openWithCredentials:mxSession.matrixRestClient.credentials onComplete:nil failure:nil];

    return [self initWithRoomId:roomId matrixSession:mxSession andStore:memoryStore];
}

- (MXHTTPOperation *)initialSync:(void (^)())success failure:(void (^)(NSError *))failure
{
    // Make an /initialSync request to get data
    return [self.mxSession.matrixRestClient initialSyncOfRoom:self.roomId withLimit:0 success:^(MXRoomInitialSync *roomInitialSync) {

        [self.liveTimeline initialiseState:roomInitialSync.state];

        // @TODO: get events

        success();

    } failure:failure];
}

@end
