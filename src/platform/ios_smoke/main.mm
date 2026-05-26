// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <UIKit/UIKit.h>

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

    std::ostringstream out;
    out << "shadPS4 iOS smoke test\n\n";
    out << "Device: " << policy.machine_identifier << "\n";
    out << "OS: " << policy.os_major_version << "." << policy.os_minor_version << "."
        << policy.os_patch_version << "\n";
    out << "iPad: " << (policy.is_ipad ? "yes" : "no") << "\n";
    out << "M-series iPad policy: " << (policy.is_ipad_m1_or_newer ? "pass" : "not required")
        << "\n";
    out << "OS policy: " << (policy.os_version_supported ? "pass" : "fail") << "\n";
    out << "RAM: " << (policy.physical_memory_bytes / (1024ULL * 1024ULL * 1024ULL)) << " GB\n";
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
    out << "Resolution preset: " << resolution.name << " (" << resolution.width << "x"
        << resolution.height << ")\n";
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

    UILabel* label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 0.0)];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textColor = [UIColor colorWithRed:0.92 green:0.95 blue:1.0 alpha:1.0];
    label.font = [UIFont monospacedSystemFontOfSize:18.0 weight:UIFontWeightRegular];
    label.text = FormatDevicePolicy();

    [controller.view addSubview:label];
    UILayoutGuide* guide = controller.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:32.0],
        [label.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-32.0],
        [label.centerYAnchor constraintEqualToAnchor:guide.centerYAnchor]
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
