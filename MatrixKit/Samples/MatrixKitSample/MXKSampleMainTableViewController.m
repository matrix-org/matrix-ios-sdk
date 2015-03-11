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

#import "MXKSampleMainTableViewController.h"
#import "MXKSampleRoomViewController.h"
#import <MatrixSDK/MXFileStore.h>

@interface MXKSampleMainTableViewController () {
    
    MXSession *mxSession;
    MXRoom *room;
}

@end

@implementation MXKSampleMainTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // We need a room
    // So, initialise a Matrix session on matrix.org to display #test:matrix.org
    MXCredentials *credentials = [[MXCredentials alloc] initWithHomeServer:@"https://matrix.org"
                                                                    userId:@"@your_matrix_id"
                                                               accessToken:@"your_access_token"];

    mxSession = [[MXSession alloc] initWithMatrixRestClient:[[MXRestClient alloc] initWithCredentials:credentials]];

    // As there is no mock for MatrixSDK yet, use a cache for Matrix data to boost init
    MXFileStore *mxFileStore = [[MXFileStore alloc] init];
    __weak typeof(self) weakSelf = self;
    [mxSession setStore:mxFileStore success:^{
        typeof(self) self = weakSelf;
        [self->mxSession start:^{

            // Resolve #test:matrix.org to room id in order to make tests there
            [self->mxSession.matrixRestClient roomIDForRoomAlias:@"#test:matrix.org" success:^(NSString *roomId) {

                self->room = [self->mxSession roomWithRoomId:roomId];
                NSAssert(self->room, @"The user must be in the the room");

                [self.tableView reloadData];
            } failure:^(NSError *error) {
                NSAssert(false, @"roomIDForRoomAlias should not fail. Error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(false, @"%@", error);
        }];
    } failure:^(NSError *error) {
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (!room) {
        return 0;
    }
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SampleMainTableViewCell" forIndexPath:indexPath];
    cell.textLabel.text = @"Room view controller sample";
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self performSegueWithIdentifier:@"showSampleRoomViewController" sender:self];
}

#pragma mark - Segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"showSampleRoomViewController"]) {
        MXKSampleRoomViewController *sampleRoomViewController = (MXKSampleRoomViewController *)segue.destinationViewController;

        MXKRoomDataSource *roomDataSource = [[MXKRoomDataSource alloc] initWithRoom:room andMatrixSession:mxSession];
       [sampleRoomViewController displayRoom:roomDataSource];
    }
}

@end
