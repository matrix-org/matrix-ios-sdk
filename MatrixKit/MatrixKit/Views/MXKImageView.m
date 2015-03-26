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

#import "MXKImageView.h"
#import "MXKMediaManager.h"
#import "MXKPieChartView.h"

@interface MXKImageView () {
    NSString *imageURL;
    UIImageOrientation imageOrientation;
    
    UIImage *currentImage;
    
    // the loading view is composed with the spinner and a pie chart
    // the spinner is display until progress > 0
    UIView *loadingView;
    UIActivityIndicatorView *waitingDownloadSpinner;
    MXKPieChartView *pieChartView;
    UILabel *progressInfoLabel;

    // validation buttons
    UIButton *leftButton;
    UIButton *rightButton;
    
    NSString *leftButtonTitle;
    NSString *rightButtonTitle;
    
    blockMXKImageView_onClick leftHandler;
    blockMXKImageView_onClick rightHandler;
    
    UIView* bottomBarView;

    // Subviews
    UIScrollView *scrollView;
    UIImageView *imageView;
}
@end

@implementation MXKImageView
@synthesize stretchable, mediaFolder;

#define CUSTOM_IMAGE_VIEW_BUTTON_WIDTH 100

- (id)initWithFrame:(CGRect)frame {
    
    self = [super initWithFrame:frame];
    
    if (self) {
        leftButtonTitle = nil;
        leftHandler = nil;
        rightButtonTitle = nil;
        rightHandler = nil;
        
        self.backgroundColor = [UIColor blackColor];
        self.contentMode = UIViewContentModeScaleAspectFit;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin;
    }
    
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self stopActivityIndicator];
    
    if (loadingView) {
        [loadingView removeFromSuperview];
        loadingView = nil;
    }
    if (bottomBarView) {
        [bottomBarView removeFromSuperview];
        bottomBarView = nil;
    }
}

- (void)startActivityIndicator {
    // create the views if they don't exist
    if (!waitingDownloadSpinner) {
        waitingDownloadSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        
        CGRect frame = waitingDownloadSpinner.frame;
        frame.size.width += 30;
        frame.size.height += 30;
        waitingDownloadSpinner.bounds = frame;
        [waitingDownloadSpinner.layer setCornerRadius:5];
    }
    
    if (!loadingView) {
        loadingView = [[UIView alloc] init];
        loadingView.frame = waitingDownloadSpinner.bounds;
        waitingDownloadSpinner.frame = waitingDownloadSpinner.bounds;
        [loadingView addSubview:waitingDownloadSpinner];
        loadingView.backgroundColor = [UIColor clearColor];
        [self addSubview:loadingView];
    }
    
    if (!pieChartView) {
        pieChartView = [[MXKPieChartView alloc] init];
        pieChartView.frame = loadingView.bounds;
        pieChartView.progress = 0;
        pieChartView.progressColor = [UIColor colorWithRed:1 green:1 blue:1 alpha:0.25];
        pieChartView.unprogressColor = [UIColor clearColor];
    
        [loadingView addSubview:pieChartView];
    }
    
    // display the download statistics
    if (_fullScreen && !progressInfoLabel) {
        progressInfoLabel = [[UILabel alloc] init];
        progressInfoLabel.backgroundColor = [UIColor whiteColor];
        progressInfoLabel.textColor = [UIColor blackColor];
        progressInfoLabel.font = [UIFont systemFontOfSize:8];
        progressInfoLabel.alpha = 0.25;
        progressInfoLabel.text = @"";
        progressInfoLabel.numberOfLines = 0;
        [progressInfoLabel sizeToFit];
        [self addSubview:progressInfoLabel];
    }
    
    // initvalue
    loadingView.hidden = NO;
    pieChartView.progress = 0;
    
    // Adjust color
    if ([self.backgroundColor isEqual:[UIColor blackColor]]) {
        waitingDownloadSpinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhite;
        // a preview image could be displayed
        // ensure that the white spinner is visible
        // it could be drawn on a white area
        waitingDownloadSpinner.backgroundColor = [UIColor darkGrayColor];
        
    } else {
        waitingDownloadSpinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleGray;
    }

        // ensure that the spinner is drawn at the top
    [loadingView.superview bringSubviewToFront:loadingView];
    
    // Adjust position
    CGPoint center = CGPointMake(self.frame.size.width / 2, self.frame.size.height / 2);
    loadingView.center = center;
    
    // Start
    [waitingDownloadSpinner startAnimating];
}

- (void)stopActivityIndicator {
    if (waitingDownloadSpinner && waitingDownloadSpinner.isAnimating) {
        [waitingDownloadSpinner stopAnimating];
    }
    
    pieChartView.progress = 0;
    loadingView.hidden = YES;
    
    if (progressInfoLabel) {
        [progressInfoLabel removeFromSuperview];
        progressInfoLabel = nil;
    }
}

#pragma mark - setters/getters

- (void)setImage:(UIImage *)anImage {
    currentImage = anImage;
    imageView.image = anImage;
    [self initScrollZoomFactors];
}

- (UIImage*)image {
    return currentImage;
}

- (void)showFullScreen {
    
    _fullScreen = YES;
    
    [self initLayout];

    if (_fullScreen) {
        [self removeFromSuperview];
        [UIApplication sharedApplication].statusBarHidden = YES;

        UIWindow *window = [[UIApplication sharedApplication] keyWindow];
                
        self.frame = window.rootViewController.view.bounds;
        [window.rootViewController.view addSubview:self];
    }
}

#pragma mark -
- (IBAction)onButtonToggle:(id)sender
{
    if (sender == leftButton) {
        dispatch_async(dispatch_get_main_queue(), ^{
            leftHandler(self, leftButtonTitle);
        });
    } else if (sender == rightButton) {
        dispatch_async(dispatch_get_main_queue(), ^{
            rightHandler(self, rightButtonTitle);
        });
    }
}

// add a generic button to the bottom view
// return the added UIButton
- (UIButton*) addbuttonWithTitle:(NSString*)title  {
    UIButton* button = [[UIButton alloc] init];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitle:title forState:UIControlStateHighlighted];
    
    if (_fullScreen) {
        // use the same text color as the tabbar
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    }
// TODO
//    else  {
//        // use the same text color as the tabbar
//        [button setTitleColor:[AppDelegate theDelegate].masterTabBarController.tabBar.tintColor forState:UIControlStateNormal];
//        [button setTitleColor:[AppDelegate theDelegate].masterTabBarController.tabBar.tintColor forState:UIControlStateHighlighted];
//    }

    // keep the bottomView background color
    button.backgroundColor = [UIColor clearColor];
    
    [button addTarget:self action:@selector(onButtonToggle:) forControlEvents:UIControlEventTouchUpInside];
    [bottomBarView addSubview:button];
    
    return button;
}

- (void)initScrollZoomFactors {
    // check if the image can be zoomed
    if (self.image && self.stretchable && imageView.frame.size.width && imageView.frame.size.height) {
        // ensure that the content size is properly initialized
        scrollView.contentSize = scrollView.frame.size;
        
        // compute the appliable zoom factor
        // assume that the user does not expect to zoom more than 100%
        CGSize imageSize = self.image.size;
        
        CGFloat scaleX = imageSize.width  / imageView.frame.size.width;
        CGFloat scaleY = imageSize.height / imageView.frame.size.height;
        
        if (scaleX < scaleY)
        {
            scaleX = scaleY;
        }
        
        if (scaleX < 1.0)
        {
            scaleX = 1.0;
        }
        
        scrollView.zoomScale        = 1.0;
        scrollView.minimumZoomScale = 1.0;
        scrollView.maximumZoomScale = scaleX;
        
        // update the image frame to ensure that it fits to the scrollview frame
        imageView.frame = scrollView.bounds;
    }
}

- (void)removeFromSuperview {
    [super removeFromSuperview];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_fullScreen) {
        [UIApplication sharedApplication].statusBarHidden = NO;
    }
    
    [self stopActivityIndicator];
}

- (void)initLayout {
    // create the subviews if they don't exist
    if (!scrollView) {
        scrollView = [[UIScrollView alloc] init];
        scrollView.delegate = self;
        scrollView.backgroundColor = [UIColor clearColor];
        [self addSubview:scrollView];
        
        imageView = [[UIImageView alloc] init];
        imageView.backgroundColor = [UIColor clearColor];
        imageView.contentMode = self.contentMode;
        [scrollView addSubview:imageView];
    }
}

- (void)layoutSubviews {
    
    // call upper layer
    [super layoutSubviews];

    [self initLayout];
    
    // the image has been updated
    if (imageView.image != self.image) {
        imageView.image = self.image;
    }
    
    CGRect tabBarFrame = CGRectZero;// TODO [AppDelegate theDelegate].masterTabBarController.tabBar.frame;

    // update the scrollview frame
    CGRect oneSelfFrame = self.frame;
    CGRect scrollViewFrame = CGRectIntegral(scrollView.frame);
    
    if (leftButtonTitle || rightButtonTitle) {
        oneSelfFrame.size.height -= tabBarFrame.size.height;
    }
    
    oneSelfFrame = CGRectIntegral(oneSelfFrame);
    oneSelfFrame.origin = scrollViewFrame.origin = CGPointZero;
    
    // use integral rect to avoid rounded value issue (float precision)
    if (!CGRectEqualToRect(oneSelfFrame, scrollViewFrame)) {
        scrollView.frame = oneSelfFrame;
        imageView.frame = oneSelfFrame;
        
        [self initScrollZoomFactors];
    }
    
    // check if the dedicated buttons are already added
    if (leftButtonTitle || rightButtonTitle) {
        
        if (!bottomBarView) {
            bottomBarView = [[UIView alloc] init];
            
            if (leftButtonTitle) {
                leftButton = [self addbuttonWithTitle:leftButtonTitle];
            }
            
            rightButton = [[UIButton alloc] init];
            
            if (rightButtonTitle) {
                rightButton = [self addbuttonWithTitle:rightButtonTitle];
            }

            // in fullscreen, display both buttons above the view
            if (_fullScreen) {
                bottomBarView.backgroundColor = [UIColor blackColor];
                [self addSubview:bottomBarView];
            }
            // display them above the tabbar
            else {
                // default tabbar background color
                CGFloat base = 248.0 / 255.0f;
  
                bottomBarView.backgroundColor = [UIColor colorWithRed:base green:base blue:base alpha:1.0];
                // TODO
//                [[AppDelegate theDelegate].masterTabBarController.tabBar addSubview:bottomBarView];
            }
        }
        
        if (_fullScreen) {
            tabBarFrame.origin.y = self.frame.size.height - tabBarFrame.size.height;
        }
        else {
            tabBarFrame.origin.y = 0;
        }
        bottomBarView.frame = tabBarFrame;
        
        if (leftButton) {
            leftButton.frame = CGRectMake(0, 0, CUSTOM_IMAGE_VIEW_BUTTON_WIDTH, bottomBarView.frame.size.height);
        }
        
        if (rightButton) {
            rightButton.frame = CGRectMake(bottomBarView.frame.size.width - CUSTOM_IMAGE_VIEW_BUTTON_WIDTH, 0, CUSTOM_IMAGE_VIEW_BUTTON_WIDTH, bottomBarView.frame.size.height);
        }
    }
    
    if (!loadingView.hidden) {
        // ensure that the spinner is drawn at the top
        [loadingView.superview bringSubviewToFront:loadingView];
        
        // Adjust positions
        CGPoint center = CGPointMake(self.frame.size.width / 2, self.frame.size.height / 2);
        loadingView.center = center;
        
        CGRect progressInfoLabelFrame = progressInfoLabel.frame;
        progressInfoLabelFrame.origin.x = center.x - (progressInfoLabelFrame.size.width / 2);
        progressInfoLabelFrame.origin.y = 10 + loadingView.frame.origin.y + loadingView.frame.size.height;
        progressInfoLabel.frame = progressInfoLabelFrame;
    }
}

- (void)setHideActivityIndicator:(BOOL)hideActivityIndicator {
    _hideActivityIndicator = hideActivityIndicator;
    if (hideActivityIndicator) {
        [self stopActivityIndicator];
    } else {
        NSString *cacheFilePath = [MXKMediaManager cachePathForMediaWithURL:imageURL inFolder:mediaFolder];
        if ([MXKMediaManager existingDownloaderWithOutputFilePath:cacheFilePath]) {
            // Loading is in progress, start activity indicator
            [self startActivityIndicator];
        }
    }
}

- (void)setImageURL:(NSString *)anImageURL withImageOrientation:(UIImageOrientation)orientation andPreviewImage:(UIImage*)previewImage {
    // Remove any pending observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    imageURL = anImageURL;
    if (!imageURL) {
        // Set preview by default
        self.image = previewImage;
        return;
    }
    
    // Store image orientation
    imageOrientation = orientation;
    
    // Check whether the image download is in progress
    NSString *cacheFilePath = [MXKMediaManager cachePathForMediaWithURL:imageURL inFolder:mediaFolder];
    MXKMediaLoader* loader = [MXKMediaManager existingDownloaderWithOutputFilePath:cacheFilePath];
    if (loader) {
        // Set preview until the image is loaded
        self.image = previewImage;
        // update the progress UI with the current info
        [self updateProgressUI:loader.statisticsDict];
        
        // Add observers
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMediaDownloadProgress:) name:kMXKMediaDownloadProgressNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMediaDownloadEnd:) name:kMXKMediaDownloadDidFinishNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMediaDownloadEnd:) name:kMXKMediaDownloadDidFailNotification object:nil];
    } else {
        // Retrieve the image from cache
        UIImage* image = [MXKMediaManager loadPictureFromFilePath:cacheFilePath];
        if (image) {
            if (imageOrientation != UIImageOrientationUp) {
                self.image = [UIImage imageWithCGImage:image.CGImage scale:1.0 orientation:imageOrientation];
            } else {
                self.image = image;
            }
            
            [self stopActivityIndicator];
        } else {
            // Set preview until the image is loaded
            self.image = previewImage;
            // Trigger image downloading
            if (!_hideActivityIndicator) {
                [self startActivityIndicator];
            }
            // Add observers
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMediaDownloadProgress:) name:kMXKMediaDownloadProgressNotification object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMediaDownloadEnd:) name:kMXKMediaDownloadDidFinishNotification object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMediaDownloadEnd:) name:kMXKMediaDownloadDidFailNotification object:nil];
            [MXKMediaManager downloadMediaFromURL:imageURL andSaveAtFilePath:cacheFilePath];
        }
    }
}

- (void)onMediaDownloadEnd:(NSNotification *)notif {
    // sanity check
    if ([notif.object isKindOfClass:[NSString class]]) {
        NSString* url = notif.object;
        NSString* cacheFilePath = notif.userInfo[kMXKMediaLoaderFilePathKey];
        
        if ([url isEqualToString:imageURL] && cacheFilePath.length) {
            [self stopActivityIndicator];
            // update the image
            UIImage* image = [MXKMediaManager loadPictureFromFilePath:cacheFilePath];
            if (image) {
                if (imageOrientation != UIImageOrientationUp) {
                    self.image = [UIImage imageWithCGImage:image.CGImage scale:1.0 orientation:imageOrientation];
                } else {
                    self.image = image;
                }
            }
            // remove the observers
            [[NSNotificationCenter defaultCenter] removeObserver:self];
        }
    }
}

- (void)updateProgressUI:(NSDictionary*)downloadStatsDict {

    // Sanity check: updateProgressUI may be called while there is no stats available
    // This happens when the download failed at the very beginning.
    if (nil == downloadStatsDict) {
        return;
    }

    NSNumber* progressNumber = [downloadStatsDict valueForKey:kMXKMediaLoaderProgressValueKey];
    
    if (progressNumber) {
        pieChartView.progress = progressNumber.floatValue;
        waitingDownloadSpinner.hidden = YES;
    }
    
    if (progressInfoLabel) {
        NSString* downloadRate = [downloadStatsDict valueForKey:kMXKMediaLoaderProgressRateKey];
        NSString* remaingTime = [downloadStatsDict valueForKey:kMXKMediaLoaderProgressRemaingTimeKey];
        NSString* progressString = [downloadStatsDict valueForKey:kMXKMediaLoaderProgressStringKey];
        
        NSMutableString* text = [[NSMutableString alloc] init];
        
        [text appendString:progressString];
        
        if (remaingTime) {
            [text appendFormat:@" (%@)", remaingTime];
        }
        
        if (downloadRate) {
            [text appendFormat:@"\n %@", downloadRate];
        }
        
        progressInfoLabel.text = text;
        
        // on multilines, sizeToFit uses the current width
        // so reset it
        progressInfoLabel.frame = CGRectZero;
        
        [progressInfoLabel sizeToFit];
        
        //
        CGRect progressInfoLabelFrame = progressInfoLabel.frame;
        progressInfoLabelFrame.origin.x = self.center.x - (progressInfoLabelFrame.size.width / 2);
        progressInfoLabelFrame.origin.y = 10 + loadingView.frame.origin.y + loadingView.frame.size.height;
        progressInfoLabel.frame = progressInfoLabelFrame;
    }
}

- (void)onMediaDownloadProgress:(NSNotification *)notif {
    // sanity check
    if ([notif.object isKindOfClass:[NSString class]]) {
        NSString* url = notif.object;
        
        if ([url isEqualToString:imageURL]) {
            [self updateProgressUI:notif.userInfo];
        }
    }
}

#pragma mark - buttons management

- (void)setLeftButtonTitle: aLeftButtonTitle handler:(blockMXKImageView_onClick)handler {
    leftButtonTitle = aLeftButtonTitle;
    leftHandler = handler;
}

- (void)setRightButtonTitle:aRightButtonTitle handler:(blockMXKImageView_onClick)handler {
    rightButtonTitle = aRightButtonTitle;
    rightHandler = handler;
}

- (void)dismissSelection {
    if (bottomBarView) {
        [bottomBarView removeFromSuperview];
        bottomBarView = nil;
    }
    
    if (_fullScreen) {
        [UIApplication sharedApplication].statusBarHidden = NO;
    }
}

#pragma mark - UIScrollViewDelegate
// require to be able to zoom an image
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.stretchable ? imageView : nil;
}

@end