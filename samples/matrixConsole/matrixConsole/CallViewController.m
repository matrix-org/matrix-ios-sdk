/*
 Copyright 2015 Ericsson AB

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

#import "CallViewController.h"
#import "MXEvent.h"

@interface CallViewController ()
{
    IBOutlet UIButton *acceptButton;
    IBOutlet UIButton *declineButton;
    IBOutlet UIButton *hangupButton;
}

@end


@implementation CallViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.selfView.transform = CGAffineTransformMakeRotation(M_PI_2);

    if (self.isAnswering) {
        hangupButton.hidden = YES;
    } else {
        acceptButton.hidden = declineButton.hidden = YES;
    }
}

- (IBAction)hangupButtonTapped:(id)sender
{
    NSLog(@"[CallViewController] hangupButtonTapped");
    [self postNotificationWithName:kMXEventTypeStringCallHangup];
    [self hangupAndDismiss];
}

- (IBAction)acceptButtonTapped:(id)sender
{
    NSLog(@"[CallViewController] acceptButtonTapped");
    [self postNotificationWithName:kMXEventTypeStringCallAnswer];

    acceptButton.hidden = declineButton.hidden = YES;
    hangupButton.hidden = NO;
}

- (IBAction)declineButtonTapped:(id)sender
{
    NSLog(@"[CallViewController] declineButtonTapped");
    [self postNotificationWithName:kMXEventTypeStringCallHangup];
    [self hangupAndDismiss];
}

- (void)postNotificationWithName:(NSString *)name
{
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    [defaultCenter postNotificationName:name object:nil];
}

- (void)hangupAndDismiss
{
    self.remoteView = nil;
    self.selfView = nil;

    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
