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
#import "MXKSampleRecentsViewController.h"
#import "MXKSampleRoomViewController.h"
#import "MXKSampleJSQMessagesViewController.h"
#import <MatrixSDK/MXFileStore.h>

@interface MXKSampleMainTableViewController () {
    
    NSString *roomId;
}

@end

@implementation MXKSampleMainTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self configureView];

    // We need a room
    // So, initialise a Matrix session on matrix.org to display #test:matrix.org
    MXCredentials *credentials = [[MXCredentials alloc] initWithHomeServer:@"https://matrix.org"
                                                                    userId:@"@your_matrix_id"
                                                               accessToken:@"your_access_token"];

    self.mxSession = [[MXSession alloc] initWithMatrixRestClient:[[MXRestClient alloc] initWithCredentials:credentials]];

    // Listen to MXSession state changes
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didMXSessionStateChange:) name:MXSessionStateDidChangeNotification object:nil];

    // As there is no mock for MatrixSDK yet, use a cache for Matrix data to boost init
    MXFileStore *mxFileStore = [[MXFileStore alloc] init];
    __weak typeof(self) weakSelf = self;
    [self.mxSession setStore:mxFileStore success:^{
        typeof(self) self = weakSelf;
        [self.mxSession start:^{
            // Resolve #test:matrix.org to room id in order to make tests there
            [self.mxSession.matrixRestClient roomIDForRoomAlias:@"#test:matrix.org" success:^(NSString *aRoomId) {

                self->roomId = aRoomId;

            } failure:^(NSError *error) {
                NSAssert(false, @"roomIDForRoomAlias should not fail. Error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(false, @"%@", error);
        }];
    } failure:^(NSError *error) {
    }];

    // Test code for directly opening a VC
    //roomId = @"!vfFxDRtZSSdspfTSEr:matrix.org";
    //[self performSegueWithIdentifier:@"showSampleRoomViewController" sender:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)configureView {
    [self.tableView reloadData];
}


#pragma mark - MXSessionStateDidChangeNotification
- (void)didMXSessionStateChange:(NSNotification *)notif {
    // Show the spinner and enable selection in the table only if the MXSession is not up and running
    if (MXSessionStateRunning == self.mxSession.state)
    {
        self.tableView.allowsSelection = YES;
    }
    else
    {
        self.tableView.allowsSelection = NO;
    }
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SampleMainTableViewCell" forIndexPath:indexPath];

    switch (indexPath.row) {
        case 0:
            cell.textLabel.text = @"Recents view controller sample";
            break;

        case 1:
            cell.textLabel.text = @"Room view controller sample";
            break;

        case 2:
            cell.textLabel.text = @"JSQMessages view controller sample";
            break;
    }
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.row) {
        case 0:
            [self performSegueWithIdentifier:@"showSampleRecentsViewController" sender:self];
            break;

        case 1:
            [self performSegueWithIdentifier:@"showSampleRoomViewController" sender:self];
            break;

        case 2:
            [self performSegueWithIdentifier:@"showSampleJSQMessagesViewController" sender:self];
            break;
    }
}

#pragma mark - Segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {

    MXKRoomDataSourceManager *roomDataSourceManager = [MXKRoomDataSourceManager sharedManagerForMatrixSession:self.mxSession];

    if ([segue.identifier isEqualToString:@"showSampleRecentsViewController"]) {
        MXKSampleRecentsViewController *sampleRecentListViewController = (MXKSampleRecentsViewController *)segue.destinationViewController;
        sampleRecentListViewController.delegate = self;

        MXKRecentListDataSource *listDataSource = [[MXKRecentListDataSource alloc] initWithMatrixSession:self.mxSession];
        [sampleRecentListViewController displayList:listDataSource];
    } else if ([segue.identifier isEqualToString:@"showSampleRoomViewController"]) {
        MXKSampleRoomViewController *sampleRoomViewController = (MXKSampleRoomViewController *)segue.destinationViewController;

        MXKRoomDataSource *roomDataSource = [roomDataSourceManager roomDataSourceForRoom:roomId create:YES];
        [sampleRoomViewController displayRoom:roomDataSource];
    } else if ([segue.identifier isEqualToString:@"showSampleJSQMessagesViewController"]) {
        MXKSampleJSQMessagesViewController *sampleRoomViewController = (MXKSampleJSQMessagesViewController *)segue.destinationViewController;

        MXKSampleJSQRoomDataSource *roomDataSource = (MXKSampleJSQRoomDataSource *)[roomDataSourceManager roomDataSourceForRoom:roomId create:NO];
        if (!roomDataSource) {
            roomDataSource = [[MXKSampleJSQRoomDataSource alloc] initWithRoomId:roomId andMatrixSession:self.mxSession];
            [roomDataSourceManager addRoomDataSource:roomDataSource];
        }

        [sampleRoomViewController displayRoom:roomDataSource];
    }
}

#pragma mark - MXKRecentListViewControllerDelegate
- (void)recentListViewController:(MXKRecentListViewController *)recentListViewController didSelectRoom:(NSString *)aRoomId {

    // Change the current room id and come back to the main page
    roomId = aRoomId;
    [self.navigationController popToRootViewControllerAnimated:YES];
}

@end
