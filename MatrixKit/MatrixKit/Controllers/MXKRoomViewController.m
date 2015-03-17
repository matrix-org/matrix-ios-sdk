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

    /**
     The data source providing UITableViewCells for the current room.
     */
    MXKRoomDataSource *dataSource;
    
    /**
     The input toolbar view
     */
    MXKRoomInputToolbarView *inputToolbarView;
}

@property (nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic) IBOutlet UIView *roomInputToolbarContainer;

@end

@implementation MXKRoomViewController

#pragma mark - Class methods

+ (UINib *)nib
{
    return [UINib nibWithNibName:NSStringFromClass([MXKRoomViewController class])
                          bundle:[NSBundle bundleForClass:[MXKRoomViewController class]]];
}

+ (instancetype)roomViewController
{
    return [[[self class] alloc] initWithNibName:NSStringFromClass([MXKRoomViewController class])
                                          bundle:[NSBundle bundleForClass:[MXKRoomViewController class]]];
}

#pragma mark -

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Check whether the view controller has been pushed via storyboard
    if (!_tableView) {
        // Instantiate view controller objects
        [[[self class] nib] instantiateWithOwner:self options:nil];
    }
    
    // Set default input toolbar view
    [self setRoomInputToolbarViewClass:MXKRoomInputToolbarView.class];
    
    // Check whether a room source has been defined
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
    [_tableView registerClass:[dataSource cellViewClassForCellIdentifier:kMXKIncomingRoomBubbleCellIdentifier] forCellReuseIdentifier:kMXKIncomingRoomBubbleCellIdentifier];
    [_tableView registerClass:[dataSource cellViewClassForCellIdentifier:kMXKOutgoingRoomBubbleCellIdentifier] forCellReuseIdentifier:kMXKOutgoingRoomBubbleCellIdentifier];

    // Start showing history right now
    [dataSource paginateBackMessagesToFillRect:self.view.frame success:^{
        // @TODO (hide loading wheel)
    } failure:^(NSError *error) {
        // @TODO
    }];
}

#pragma mark -

- (void)displayRoom:(MXKRoomDataSource *)roomDataSource {

    dataSource = roomDataSource;
    dataSource.delegate = self;
    
    if (_tableView) {
        [self configureView];
    }
}

- (void)setRoomInputToolbarViewClass:(Class)roomInputToolbarViewClass {
    // Sanity check: accept only MXKRoomInputToolbarView classes or sub-classes
    NSParameterAssert([roomInputToolbarViewClass isSubclassOfClass:MXKRoomInputToolbarView.class]);
    
    // Remove potential toolbar
    if (inputToolbarView) {
        [inputToolbarView removeFromSuperview];
    }
    inputToolbarView = [[roomInputToolbarViewClass alloc] init];
    
    // Add the input toolbar view and define edge constraints
    CGRect frame = _roomInputToolbarContainer.frame;
    frame.origin.x = 0;
    frame.origin.y = 0;
    inputToolbarView.frame = frame;
    [_roomInputToolbarContainer addSubview:inputToolbarView];
    [_roomInputToolbarContainer addConstraint:[NSLayoutConstraint constraintWithItem:_roomInputToolbarContainer
                                                     attribute:NSLayoutAttributeBottom
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:inputToolbarView
                                                     attribute:NSLayoutAttributeBottom
                                                    multiplier:1.0f
                                                      constant:0.0f]];
    [_roomInputToolbarContainer addConstraint:[NSLayoutConstraint constraintWithItem:_roomInputToolbarContainer
                                                     attribute:NSLayoutAttributeTop
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:inputToolbarView
                                                     attribute:NSLayoutAttributeTop
                                                    multiplier:1.0f
                                                      constant:0.0f]];
    [_roomInputToolbarContainer addConstraint:[NSLayoutConstraint constraintWithItem:_roomInputToolbarContainer
                                                     attribute:NSLayoutAttributeLeading
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:inputToolbarView
                                                     attribute:NSLayoutAttributeLeading
                                                    multiplier:1.0f
                                                      constant:0.0f]];
    [_roomInputToolbarContainer addConstraint:[NSLayoutConstraint constraintWithItem:_roomInputToolbarContainer
                                                     attribute:NSLayoutAttributeTrailing
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:inputToolbarView
                                                     attribute:NSLayoutAttributeTrailing
                                                    multiplier:1.0f
                                                      constant:0.0f]];
    [_roomInputToolbarContainer setNeedsUpdateConstraints];
}

#pragma mark - MXKDataSourceDelegate
- (void)dataSource:(MXKDataSource *)dataSource didChange:(id)changes {
    // For now, do a simple full reload
    [_tableView reloadData];
}

@end
