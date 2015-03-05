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

#import "MXKRoomViewController.h"

#import "MXKRoomIncomingBubbleTableViewCell.h"
#import "MXKRoomOutgoingBubbleTableViewCell.h"

@interface MXKRoomViewController () {

    MXSession *mxSession;
    MXRoom *room;
}
@end

@implementation MXKRoomViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:_tableView];
}

- (void)dealloc {
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
    _tableView = nil;
    _dataSource = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    // Dispose of any resources that can be recreated.
}

- (void)displayRoom:(MXRoom *)aRoom withMXSession:(MXSession *)session {

    room = aRoom;
    mxSession = session;

    // Set up table data source
    _dataSource = [[MXKRoomDataSource alloc] initWithRoom:room andMatrixSession:mxSession];
    _tableView.dataSource = _dataSource;

    // Listen to data source changes
    _dataSource.delegate = self;

    // Set up classes to use for cells
    [_tableView registerClass:MXKRoomIncomingBubbleTableViewCell.class forCellReuseIdentifier:kMXKIncomingRoomBubbleCellIdentifier];
    [_tableView registerClass:MXKRoomOutgoingBubbleTableViewCell.class forCellReuseIdentifier:kMXKOutgoingRoomBubbleCellIdentifier];

    // Start showing history right now
    [_dataSource paginateBackMessagesToFillRect:self.view.frame success:^{
        // @TODO (hide loading wheel)
    } failure:^(NSError *error) {
        // @TODO
    }];
}

#pragma mark - MXKDataSourceDelegate
- (void)dataSource:(MXKDataSource *)dataSource didChange:(id)changes {
    // For now, do a simple full reload
    [_tableView reloadData];
}

@end
