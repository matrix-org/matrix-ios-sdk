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

    // Set up the room data source and attach it to the table view
    _dataSource = [[MXKRoomDataSource alloc] initWithRoom:room];
    _tableView.dataSource = _dataSource;
    [_tableView reloadData];

    // Start showing history right now
    [_dataSource paginateBackMessages:10];
}

@end
