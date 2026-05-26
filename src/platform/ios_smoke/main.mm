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
    controller.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.08 alpha:1.0];

    UIView* panel = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.92];
    panel.layer.cornerRadius = 10.0;

    UILabel* label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textColor = [UIColor colorWithRed:0.92 green:0.95 blue:1.0 alpha:1.0];
    label.font = [UIFont monospacedSystemFontOfSize:20.0 weight:UIFontWeightRegular];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.72;
    label.text = FormatDevicePolicy();

    [controller.view addSubview:panel];
    [panel addSubview:label];
    UILayoutGuide* guide = controller.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintGreaterThanOrEqualToAnchor:guide.leadingAnchor constant:24.0],
        [panel.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor constant:-24.0],
        [panel.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [panel.centerYAnchor constraintEqualToAnchor:guide.centerYAnchor],
        [panel.widthAnchor constraintLessThanOrEqualToAnchor:guide.widthAnchor multiplier:0.86],
        [label.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:28.0],
        [label.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-28.0],
        [label.topAnchor constraintEqualToAnchor:panel.topAnchor constant:24.0],
        [label.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-24.0]
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
