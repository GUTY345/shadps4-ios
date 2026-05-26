// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <iomanip>
#include <sstream>

#include "core/jit/external_jit_bridge.h"
#include "core/platform/ios_device_policy.h"

namespace {

NSString* ToNSString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

NSString* SupportTierText(Core::IOSPort::SupportTier tier) {
    switch (tier) {
    case Core::IOSPort::SupportTier::Recommended:
        return @"recommended";
    case Core::IOSPort::SupportTier::Minimum:
        return @"minimum";
    case Core::IOSPort::SupportTier::Unsupported:
        return @"unsupported";
    }
    return @"unknown";
}

NSString* FormatDeviceSummary() {
    const auto policy = Core::IOSPort::QueryDevicePolicy();
    const double ram_gib =
        static_cast<double>(policy.physical_memory_bytes) / (1024.0 * 1024.0 * 1024.0);

    std::ostringstream out;
    out << policy.machine_identifier << " • iPadOS " << policy.os_major_version << "."
        << policy.os_minor_version << " • " << std::fixed << std::setprecision(1) << ram_gib
        << " GiB";
    out << "\nPolicy: " << [SupportTierText(policy.tier) UTF8String] << " • " << policy.reason;
    return ToNSString(out.str());
}

UILabel* MakeLabel(NSString* text, CGFloat size, UIFontWeight weight, UIColor* color) {
    UILabel* label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.text = text;
    label.textColor = color;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    return label;
}

UIButton* MakeCommandButton(NSString* title, UIColor* background) {
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = background;
    button.tintColor = [UIColor whiteColor];
    button.layer.cornerRadius = 8.0;
    button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    [button setTitle:title forState:UIControlStateNormal];
    [button.heightAnchor constraintEqualToConstant:48.0].active = YES;
    return button;
}

} // namespace

@interface StatusCard : UIView
@property(nonatomic, strong) UILabel* valueLabel;
- (instancetype)initWithTitle:(NSString*)title value:(NSString*)value;
- (void)setValue:(NSString*)value;
@end

@implementation StatusCard

- (instancetype)initWithTitle:(NSString*)title value:(NSString*)value {
    self = [super initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    if (self == nil) {
        return nil;
    }

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:1.0];
    self.layer.cornerRadius = 8.0;

    UILabel* titleLabel =
        MakeLabel(title, 13.0, UIFontWeightMedium, [UIColor colorWithRed:0.62 green:0.68 blue:0.78 alpha:1.0]);
    self.valueLabel =
        MakeLabel(value, 19.0, UIFontWeightSemibold, [UIColor colorWithRed:0.95 green:0.97 blue:1.0 alpha:1.0]);

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[ titleLabel, self.valueLabel ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6.0;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14.0],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:88.0]
    ]];
    return self;
}

- (void)setValue:(NSString*)value {
    self.valueLabel.text = value;
}

@end

@interface ShadPS4ViewController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* detailLabel;
@property(nonatomic, strong) UILabel* gameLabel;
@property(nonatomic, strong) UILabel* logLabel;
@property(nonatomic, strong) UIButton* launchButton;
@property(nonatomic, strong) UISegmentedControl* resolutionControl;
@property(nonatomic, strong) StatusCard* gameCard;
@property(nonatomic, strong) StatusCard* jitCard;
@property(nonatomic, strong) StatusCard* renderCard;
@property(nonatomic, strong) NSURL* selectedGameURL;
@property(nonatomic, assign) BOOL selectedURLNeedsStopAccessing;
@end

@implementation ShadPS4ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1.0];

    UIView* sidebar = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:1.0];

    UILabel* brand =
        MakeLabel(@"shadPS4", 34.0, UIFontWeightBold, [UIColor colorWithRed:0.96 green:0.98 blue:1.0 alpha:1.0]);
    UILabel* subtitle = MakeLabel(@"iOS / iPadOS Port", 14.0, UIFontWeightMedium,
                                  [UIColor colorWithRed:0.56 green:0.64 blue:0.76 alpha:1.0]);

    UIButton* libraryButton =
        MakeCommandButton(@"Game Library", [UIColor colorWithRed:0.16 green:0.22 blue:0.32 alpha:1.0]);
    UIButton* settingsButton =
        MakeCommandButton(@"Settings", [UIColor colorWithRed:0.12 green:0.15 blue:0.21 alpha:1.0]);
    UIButton* logsButton =
        MakeCommandButton(@"Logs", [UIColor colorWithRed:0.12 green:0.15 blue:0.21 alpha:1.0]);
    [libraryButton addTarget:self action:@selector(openGamePicker) forControlEvents:UIControlEventTouchUpInside];
    [settingsButton addTarget:self action:@selector(showSettingsSummary) forControlEvents:UIControlEventTouchUpInside];
    [logsButton addTarget:self action:@selector(showLogsSummary) forControlEvents:UIControlEventTouchUpInside];

    UIStackView* sidebarStack =
        [[UIStackView alloc] initWithArrangedSubviews:@[ brand, subtitle, libraryButton, settingsButton, logsButton ]];
    sidebarStack.translatesAutoresizingMaskIntoConstraints = NO;
    sidebarStack.axis = UILayoutConstraintAxisVertical;
    sidebarStack.spacing = 14.0;
    [sidebar addSubview:sidebarStack];

    UIView* content = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = MakeLabel(@"Game Library", 30.0, UIFontWeightBold,
                                [UIColor colorWithRed:0.96 green:0.98 blue:1.0 alpha:1.0]);
    self.detailLabel = MakeLabel(FormatDeviceSummary(), 16.0, UIFontWeightRegular,
                                 [UIColor colorWithRed:0.68 green:0.75 blue:0.86 alpha:1.0]);

    self.resolutionControl = [[UISegmentedControl alloc] initWithItems:@[ @"720p", @"900p" ]];
    self.resolutionControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.resolutionControl.selectedSegmentIndex = 1;
    [self.resolutionControl addTarget:self
                               action:@selector(resolutionChanged)
                     forControlEvents:UIControlEventValueChanged];

    UIButton* selectGameButton =
        MakeCommandButton(@"Select Game or Folder", [UIColor colorWithRed:0.06 green:0.45 blue:0.80 alpha:1.0]);
    self.launchButton =
        MakeCommandButton(@"Start Emulation", [UIColor colorWithRed:0.22 green:0.55 blue:0.38 alpha:1.0]);
    [selectGameButton addTarget:self action:@selector(openGamePicker) forControlEvents:UIControlEventTouchUpInside];
    [self.launchButton addTarget:self action:@selector(startEmulation) forControlEvents:UIControlEventTouchUpInside];

    self.gameCard = [[StatusCard alloc] initWithTitle:@"Selected Game" value:@"None"];
    self.jitCard = [[StatusCard alloc] initWithTitle:@"External JIT" value:@"Not detected"];
    self.renderCard = [[StatusCard alloc] initWithTitle:@"Resolution" value:@"900p"];

    self.gameLabel = MakeLabel(@"Choose a PS4 game folder, eboot.bin, or ELF file from Files.",
                               15.0, UIFontWeightRegular,
                               [UIColor colorWithRed:0.76 green:0.82 blue:0.90 alpha:1.0]);
    self.logLabel = MakeLabel(@"Status: waiting for game selection.", 14.0, UIFontWeightRegular,
                              [UIColor colorWithRed:0.62 green:0.70 blue:0.82 alpha:1.0]);
    self.logLabel.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];

    UIStackView* cardRow =
        [[UIStackView alloc] initWithArrangedSubviews:@[ self.gameCard, self.jitCard, self.renderCard ]];
    cardRow.translatesAutoresizingMaskIntoConstraints = NO;
    cardRow.axis = UILayoutConstraintAxisHorizontal;
    cardRow.distribution = UIStackViewDistributionFillEqually;
    cardRow.spacing = 14.0;

    UIStackView* commandRow =
        [[UIStackView alloc] initWithArrangedSubviews:@[ selectGameButton, self.launchButton ]];
    commandRow.translatesAutoresizingMaskIntoConstraints = NO;
    commandRow.axis = UILayoutConstraintAxisHorizontal;
    commandRow.distribution = UIStackViewDistributionFillEqually;
    commandRow.spacing = 14.0;

    UIStackView* contentStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[ self.titleLabel, self.detailLabel, self.resolutionControl,
                                    cardRow, self.gameLabel, commandRow, self.logLabel ]];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 18.0;
    [content addSubview:contentStack];

    [self.view addSubview:sidebar];
    [self.view addSubview:content];
    UILayoutGuide* guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sidebar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:250.0],
        [sidebarStack.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:24.0],
        [sidebarStack.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-24.0],
        [sidebarStack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:28.0],
        [content.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:32.0],
        [contentStack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-32.0],
        [contentStack.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [contentStack.topAnchor constraintGreaterThanOrEqualToAnchor:content.topAnchor constant:24.0],
        [contentStack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-24.0]
    ]];

    [self refreshRuntimeState];
}

- (void)refreshRuntimeState {
    const auto jitStatus = Core::JIT::QueryExternalJitStatus();
    [self.jitCard setValue:jitStatus.available ? @"Ready" : @"Not detected"];
    self.launchButton.enabled = self.selectedGameURL != nil;
    self.launchButton.alpha = self.launchButton.enabled ? 1.0 : 0.55;
}

- (void)resolutionChanged {
    NSString* value = self.resolutionControl.selectedSegmentIndex == 0 ? @"720p" : @"900p";
    [self.renderCard setValue:value];
    self.logLabel.text = [NSString stringWithFormat:@"Status: resolution set to %@.", value];
}

- (void)openGamePicker {
    NSArray<UTType*>* types = @[ UTTypeFolder, UTTypeItem ];
    UIDocumentPickerViewController* picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    (void)controller;
    NSURL* url = urls.firstObject;
    if (url == nil) {
        return;
    }

    if (self.selectedURLNeedsStopAccessing && self.selectedGameURL != nil) {
        [self.selectedGameURL stopAccessingSecurityScopedResource];
    }

    self.selectedURLNeedsStopAccessing = [url startAccessingSecurityScopedResource];
    self.selectedGameURL = url;

    NSString* displayName = url.lastPathComponent.length > 0 ? url.lastPathComponent : url.path;
    [self.gameCard setValue:displayName];
    self.gameLabel.text = [NSString stringWithFormat:@"Selected path:\n%@", url.path];
    self.logLabel.text = @"Status: game path selected. Start will validate runtime requirements.";
    [self refreshRuntimeState];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller {
    (void)controller;
    self.logLabel.text = @"Status: game selection cancelled.";
}

- (void)startEmulation {
    if (self.selectedGameURL == nil) {
        [self showAlertWithTitle:@"No game selected" message:@"Choose a game folder or executable first."];
        return;
    }

    const auto policy = Core::IOSPort::QueryDevicePolicy();
    if (policy.tier == Core::IOSPort::SupportTier::Unsupported) {
        [self showAlertWithTitle:@"Unsupported device" message:ToNSString(policy.reason)];
        return;
    }

    const auto jitStatus = Core::JIT::QueryExternalJitStatus();
    if (!jitStatus.available) {
        self.logLabel.text = @"Status: blocked. External JIT provider is not detected.";
        [self showAlertWithTitle:@"External JIT required"
                         message:@"The iOS port can select a game now, but emulation cannot start until an external JIT provider is attached."];
        return;
    }

    self.logLabel.text = @"Status: runtime ready, emulator core is not linked into the iOS target yet.";
    [self showAlertWithTitle:@"Core not linked yet"
                     message:@"Device, game path, resolution, and JIT checks passed. The next porting step is linking the shadPS4 emulator core into this iOS app target."];
}

- (void)showSettingsSummary {
    [self showAlertWithTitle:@"Settings"
                     message:@"Current mobile settings are fixed to 720p or 900p. Additional settings will be enabled as emulator subsystems are linked."];
}

- (void)showLogsSummary {
    [self showAlertWithTitle:@"Logs" message:self.logLabel.text ?: @"No log entries yet."];
}

- (void)showAlertWithTitle:(NSString*)title message:(NSString*)message {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface ShadPS4SmokeAppDelegate : UIResponder <UIApplicationDelegate>
@property(strong, nonatomic) UIWindow* window;
@end

@implementation ShadPS4SmokeAppDelegate

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[ShadPS4ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char* argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([ShadPS4SmokeAppDelegate class]));
    }
}
