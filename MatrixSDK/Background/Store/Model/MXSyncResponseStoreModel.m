// 
// Copyright 2020 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "MXSyncResponseStoreModel.h"
#import "MXJSONModels.h"

@implementation MXSyncResponseStoreModel

- (instancetype)initWithSyncToken:(NSString *)syncToken syncResponse:(MXSyncResponse *)syncResponse
{
    self = [super init];
    if (self)
    {
        _syncToken = syncToken;
        _syncResponse = syncResponse;
    }
    return self;
}

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSyncResponseStoreModel *syncResponseModel;
    
    NSString *syncToken;
    MXSyncResponse *syncResponse;
    MXJSONModelSetString(syncToken, JSONDictionary[@"sync_token"]);
    MXJSONModelSetMXJSONModel(syncResponse, MXSyncResponse, JSONDictionary[@"sync_response"]);
    
    if (syncToken && syncResponse)
    {
        syncResponseModel = [[MXSyncResponseStoreModel alloc] initWithSyncToken:syncToken syncResponse:syncResponse];
    }

    return syncResponseModel;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    if (self.syncToken)
    {
        JSONDictionary[@"sync_token"] = self.syncToken;
    }
    if (self.syncResponse)
    {
        JSONDictionary[@"sync_response"] = self.syncResponse.JSONDictionary;
    }
    
    return JSONDictionary;
}

@end
