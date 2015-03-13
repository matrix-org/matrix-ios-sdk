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

#import "MXKRecentListViewController.h"

@interface MXKRecentListViewController () {

    /**
     The data source providing UITableViewCells
     */
    MXKRecentListDataSource *dataSource;
}

@property (nonatomic) IBOutlet UITableView *tableView;

@end

@implementation MXKRecentListViewController

#pragma mark - Class methods

+ (UINib *)nib {
    return [UINib nibWithNibName:NSStringFromClass([MXKRecentListViewController class])
                          bundle:[NSBundle bundleForClass:[MXKRecentListViewController class]]];
}

+ (instancetype)roomViewController {
    return [[[self class] alloc] initWithNibName:NSStringFromClass([MXKRecentListViewController class])
                                          bundle:[NSBundle bundleForClass:[MXKRecentListViewController class]]];
}

#pragma mark -

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[[self class] nib] instantiateWithOwner:self options:nil];
    
    // Check whether a room has been defined
    if (dataSource) {
        [self configureView];
    }
}

- (void)dealloc {
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
    _tableView = nil;
    dataSource = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    // Dispose of any resources that can be recreated.
}

- (void)configureView {

    // Set up table data source
    _tableView.dataSource = dataSource;
    
    // Set up classes to use for cells
    [_tableView registerClass:[dataSource cellViewClassForCellIdentifier:kMXKRoomCellIdentifier] forCellReuseIdentifier:kMXKRoomCellIdentifier];
}

#pragma mark -
- (void)displayList:(MXKRecentListDataSource *)listDataSource {

    dataSource = listDataSource;
    dataSource.delegate = self;

    if (_tableView) {
        [self configureView];
    }
}

#pragma mark - MXKDataSourceDelegate
- (void)dataSource:(MXKDataSource *)dataSource didChange:(id)changes {
    // For now, do a simple full reload
    [_tableView reloadData];
}

@end
