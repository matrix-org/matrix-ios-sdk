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

#import "MXKRoomInputToolbarView.h"

@interface MXKRoomInputToolbarView()

@property (weak, nonatomic) IBOutlet UIView *textComposerView;

@end

@implementation MXKRoomInputToolbarView

- (instancetype) init{
    NSArray *nibViews = [[NSBundle bundleForClass:[MXKRoomInputToolbarView class]] loadNibNamed:NSStringFromClass([MXKRoomInputToolbarView class])
                                                                                          owner:nil
                                                                                        options:nil];
    return nibViews.firstObject;
}

- (IBAction)onTouchUpInside:(UIButton*)button {
    if (button == _leftInputToolbarButton) {
        
    } else if (button == _rightInputToolbarButton) {
        
    }
}

@end
