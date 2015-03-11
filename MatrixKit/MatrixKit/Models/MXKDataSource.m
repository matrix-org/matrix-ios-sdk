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

#import "MXKDataSource.h"

#import "MXKCellData.h"
#import "MXKCellRendering.h"

@interface MXKDataSource () {
    /**
     The mapping between cell identifiers and MXKCellData classes.
     */
    NSMutableDictionary *cellDataMap;

    /**
     The mapping between cell identifiers and MXKCellRendering classes.
     */
    NSMutableDictionary *cellViewMap;
}
@end

@implementation MXKDataSource

- (instancetype)init {

    self = [super init];
    if (self) {
        cellDataMap = [NSMutableDictionary dictionary];
        cellViewMap = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - MXKCellData classes
- (void)registerCellDataClass:(Class)cellDataClass forCellIdentifier:(NSString *)identifier {

    // Sanity check: accept only MXKCellData classes or sub-classes
    NSParameterAssert([cellDataClass isSubclassOfClass:MXKCellData.class]);

    cellDataMap[identifier] = cellDataClass;
}

- (Class)cellDataClassForCellIdentifier:(NSString *)identifier {

    return cellDataMap[identifier];
}

#pragma mark - MXKCellRendering classes
- (void)registerCellViewClass:(Class)cellViewClass forCellIdentifier:(NSString *)identifier {

    // Sanity check: accept only classes implementing MXKCellRendering
    NSParameterAssert([cellViewClass conformsToProtocol:@protocol(MXKCellRendering)]);

    cellViewMap[identifier] = cellViewClass;
}

- (Class)cellViewClassForCellIdentifier:(NSString *)identifier {

    return cellViewMap[identifier];
}

@end
