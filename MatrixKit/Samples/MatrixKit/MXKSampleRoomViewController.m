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

#import "MXKSampleRoomViewController.h"

@interface MXKSampleRoomViewController ()

@end

@implementation MXKSampleRoomViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // We need a room
    // So, initialise a Matrix session on matrix.org to display #test:matrix.org
    MXCredentials *credentials = [[MXCredentials alloc] initWithHomeServer:@"https://matrix.org"
                                                                    userId:@"@your_matrix_id"
                                                               accessToken:@"your_access_token"];

    MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:[[MXRestClient alloc] initWithCredentials:credentials]];
    [mxSession start:^{

        // Resolve #test:matrix.org to room id in order to make tests there
        [mxSession.matrixRestClient roomIDForRoomAlias:@"#test:matrix.org" success:^(NSString *roomId) {

            MXRoom *room = [mxSession roomWithRoomId:roomId];
            NSAssert(room, @"The user must be in the the room");

            // Let's start the display of this room
            [self displayRoom:room withMXSession:mxSession];

        } failure:^(NSError *error) {
            NSAssert(false, @"roomIDForRoomAlias should not fail. Error: %@", error);
        }];

    } failure:^(NSError *error) {
        NSAssert(false, @"%@", error);
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
