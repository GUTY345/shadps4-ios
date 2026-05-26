// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <UIKit/UIKit.h>

#include <iomanip>
#include <sstream>

#include "core/jit/external_jit_bridge.h"
#include "core/platform/ios_device_policy.h"

namespace {

NSString* ToNSString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

NSString* FormatDevicePolicy() {
    const auto policy = Core::IOSPort::QueryDevicePolicy();
    const auto resolution = Core::IOSPort::ClampResolution(1600, 900);
    const auto jit_status = Core::JIT::QueryExternalJitStatus();
    const double ram_gib =
        static_cast<double>(policy.physical_memory_bytes) / (1024.0 * 1024.0 * 1024.0);

    std::ostringstream out;
    out << "shadPS4 iOS smoke test\n";
    out << "----------------------\n";
    out << "Device: " << policy.machine_identifier << "\n";
    out << "OS: " << policy.os_major_version << "." << policy.os_minor_version << "."
        << policy.os_patch_version << "\n";
    out << "iPad: " << (policy.is_ipad ? "yes" : "no") << "\n";
    out << "M-series policy: " << (policy.is_ipad_m1_or_newer ? "pass" : "not required") << "\n";
    out << "OS policy: " << (policy.os_version_supported ? "pass" : "fail") << "\n";
    out << "RAM detected: " << std::fixed << std::setprecision(2) << ram_gib
        << " GiB (8 GB class)\n";
    out << "Support: ";
    switch (policy.tier) {
    case Core::IOSPort::SupportTier::Recommended:
        out << "recommended";
        break;
    case Core::IOSPort::SupportTier::Minimum:
        out << "minimum";
        break;
    case Core::IOSPort::SupportTier::Unsupported:
        out << "unsupported";
        break;
    }
    out << "\nReason: " << policy.reason << "\n";
    out << "Resolution: " << resolution.name << " (" << resolution.width << "x" << resolution.height
        << ")\n";
    out << "External JIT: " << (jit_status.available ? "ready" : "not detected") << " ("
        << jit_status.provider << ")\n";

    return ToNSString(out.str());
}

NSString* FormatHeroStatus() {
    const auto policy = Core::IOSPort::QueryDevicePolicy();
    const auto jit_status = Core::JIT::QueryExternalJitStatus();
    const double ram_gib =
        static_cast<double>(policy.physical_memory_bytes) / (1024.0 * 1024.0 * 1024.0);

    std::ostringstream out;
    out << policy.machine_identifier << " • iPadOS " << policy.os_major_version << "."
        << policy.os_minor_version << " • " << std::fixed << std::setprecision(1) << ram_gib
        << " GiB";
    out << "\nPolicy: " << (policy.tier == Core::IOSPort::SupportTier::Unsupported ? "Blocked"
                                                                                    : "Ready");
    out << " • External JIT: " << (jit_status.available ? "Ready" : "Not detected");
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

UIView* MakeStatusCard(NSString* title, NSString* value) {
    UIView* card = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:1.0];
    card.layer.cornerRadius = 8.0;

    UILabel* titleLabel =
        MakeLabel(title, 13.0, UIFontWeightMedium, [UIColor colorWithRed:0.62 green:0.68 blue:0.78 alpha:1.0]);
    UILabel* valueLabel =
        MakeLabel(value, 20.0, UIFontWeightSemibold, [UIColor colorWithRed:0.95 green:0.97 blue:1.0 alpha:1.0]);

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[ titleLabel, valueLabel ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6.0;
    [card addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:88.0]
    ]];
    return card;
}

} // namespace

@interface ShadPS4SmokeAppDelegate : UIResponder <UIApplicationDelegate>
@property(strong, nonatomic) UIWindow* window;
@end

@implementation ShadPS4SmokeAppDelegate

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    UIViewController* controller = [[UIViewController alloc] init];
    controller.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1.0];

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

    UIStackView* sidebarStack =
        [[UIStackView alloc] initWithArrangedSubviews:@[ brand, subtitle, libraryButton, settingsButton, logsButton ]];
    sidebarStack.translatesAutoresizingMaskIntoConstraints = NO;
    sidebarStack.axis = UILayoutConstraintAxisVertical;
    sidebarStack.spacing = 14.0;
    [sidebar addSubview:sidebarStack];

    UIView* content = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel* title = MakeLabel(@"Ready for device smoke testing", 28.0, UIFontWeightBold,
                               [UIColor colorWithRed:0.96 green:0.98 blue:1.0 alpha:1.0]);
    UILabel* detail = MakeLabel(FormatHeroStatus(), 16.0, UIFontWeightRegular,
                                [UIColor colorWithRed:0.68 green:0.75 blue:0.86 alpha:1.0]);

    UISegmentedControl* resolutionControl =
        [[UISegmentedControl alloc] initWithItems:@[ @"720p", @"900p" ]];
    resolutionControl.translatesAutoresizingMaskIntoConstraints = NO;
    resolutionControl.selectedSegmentIndex = 1;

    UIButton* selectGameButton =
        MakeCommandButton(@"Select Game Folder", [UIColor colorWithRed:0.06 green:0.45 blue:0.80 alpha:1.0]);
    UIButton* launchButton =
        MakeCommandButton(@"Start Emulation", [UIColor colorWithRed:0.22 green:0.55 blue:0.38 alpha:1.0]);
    launchButton.enabled = NO;
    launchButton.alpha = 0.55;

    UIView* deviceCard = MakeStatusCard(@"Device Policy", @"Passed");
    UIView* jitCard = MakeStatusCard(@"External JIT", @"Not detected");
    UIView* renderCard = MakeStatusCard(@"Render Path", @"MoltenVK planned");

    UILabel* diagnostics = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    diagnostics.translatesAutoresizingMaskIntoConstraints = NO;
    diagnostics.numberOfLines = 0;
    diagnostics.textColor = [UIColor colorWithRed:0.78 green:0.83 blue:0.91 alpha:1.0];
    diagnostics.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    diagnostics.text = FormatDevicePolicy();

    UIStackView* cardRow = [[UIStackView alloc] initWithArrangedSubviews:@[ deviceCard, jitCard, renderCard ]];
    cardRow.translatesAutoresizingMaskIntoConstraints = NO;
    cardRow.axis = UILayoutConstraintAxisHorizontal;
    cardRow.distribution = UIStackViewDistributionFillEqually;
    cardRow.spacing = 14.0;

    UIStackView* commandRow =
        [[UIStackView alloc] initWithArrangedSubviews:@[ selectGameButton, launchButton ]];
    commandRow.translatesAutoresizingMaskIntoConstraints = NO;
    commandRow.axis = UILayoutConstraintAxisHorizontal;
    commandRow.distribution = UIStackViewDistributionFillEqually;
    commandRow.spacing = 14.0;

    UIStackView* contentStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[ title, detail, resolutionControl, cardRow, commandRow, diagnostics ]];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 18.0;
    [content addSubview:contentStack];

    [controller.view addSubview:sidebar];
    [controller.view addSubview:content];
    UILayoutGuide* guide = controller.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sidebar.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:controller.view.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:controller.view.bottomAnchor],
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

    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char* argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([ShadPS4SmokeAppDelegate class]));
    }
}
