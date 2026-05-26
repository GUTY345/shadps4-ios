// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <iomanip>
#include <sstream>

#include "core/jit/external_jit_bridge.h"
#include "core/platform/ios_emulator_core_bridge.h"
#include "core/platform/ios_device_policy.h"

namespace {

UIColor* Color(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

NSString* ToNSString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

NSString* SupportTierText(Core::IOSPort::SupportTier tier) {
    switch (tier) {
    case Core::IOSPort::SupportTier::Recommended:
        return @"Recommended";
    case Core::IOSPort::SupportTier::Minimum:
        return @"Minimum";
    case Core::IOSPort::SupportTier::Unsupported:
        return @"Unsupported";
    }
    return @"Unknown";
}

NSString* FormatDeviceSummary() {
    const auto policy = Core::IOSPort::QueryDevicePolicy();
    const double ram_gib =
        static_cast<double>(policy.physical_memory_bytes) / (1024.0 * 1024.0 * 1024.0);

    std::ostringstream out;
    out << policy.machine_identifier << " / iPadOS " << policy.os_major_version << "."
        << policy.os_minor_version << " / " << std::fixed << std::setprecision(1) << ram_gib
        << " GiB RAM";
    out << "\n" << [SupportTierText(policy.tier) UTF8String] << " policy: " << policy.reason;
    return ToNSString(out.str());
}

UILabel* MakeLabel(NSString* text, CGFloat size, UIFontWeight weight, UIColor* color) {
    UILabel* label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.text = text;
    label.textColor = color;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    return label;
}

UIButton* MakeButton(NSString* title, NSString* symbolName, UIColor* background) {
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration* config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = title;
    config.baseBackgroundColor = background;
    config.baseForegroundColor = [UIColor whiteColor];
    config.cornerStyle = UIButtonConfigurationCornerStyleFixed;
    config.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    if (symbolName.length > 0) {
        config.image = [UIImage systemImageNamed:symbolName];
        config.imagePadding = 8.0;
        config.imagePlacement = NSDirectionalRectEdgeLeading;
    }
    button.configuration = config;
    button.layer.cornerRadius = 8.0;
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [button.heightAnchor constraintEqualToConstant:48.0].active = YES;
    return button;
}

UIStackView* MakeVerticalStack(NSArray<UIView*>* views, CGFloat spacing) {
    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = spacing;
    return stack;
}

NSURL* URLByAppendingPath(NSURL* url, NSString* path) {
    return [url URLByAppendingPathComponent:path isDirectory:NO];
}

BOOL URLIsDirectory(NSURL* url) {
    NSNumber* isDirectory = nil;
    if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil]) {
        return NO;
    }
    return isDirectory.boolValue;
}

uint16_t ReadU16LE(const uint8_t* bytes, NSUInteger offset) {
    return static_cast<uint16_t>(bytes[offset] | (bytes[offset + 1] << 8));
}

uint32_t ReadU32LE(const uint8_t* bytes, NSUInteger offset) {
    return static_cast<uint32_t>(bytes[offset] | (bytes[offset + 1] << 8) |
                                 (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24));
}

NSDictionary<NSString*, NSString*>* ReadParamSfo(NSURL* paramURL) {
    NSData* data = [NSData dataWithContentsOfURL:paramURL];
    if (data.length < 0x14) {
        return @{};
    }

    const uint8_t* bytes = static_cast<const uint8_t*>(data.bytes);
    const uint32_t magic = ReadU32LE(bytes, 0);
    if (magic != 0x00505346) {
        return @{};
    }

    const uint32_t keyTableOffset = ReadU32LE(bytes, 0x08);
    const uint32_t dataTableOffset = ReadU32LE(bytes, 0x0c);
    const uint32_t entryCount = ReadU32LE(bytes, 0x10);
    NSMutableDictionary<NSString*, NSString*>* values = [NSMutableDictionary dictionary];

    for (uint32_t i = 0; i < entryCount; i++) {
        const NSUInteger entryOffset = 0x14 + i * 0x10;
        if (entryOffset + 0x10 > data.length) {
            break;
        }

        const uint16_t keyOffset = ReadU16LE(bytes, entryOffset);
        const uint32_t dataLength = ReadU32LE(bytes, entryOffset + 0x04);
        const uint32_t dataOffset = ReadU32LE(bytes, entryOffset + 0x0c);
        const NSUInteger keyStart = keyTableOffset + keyOffset;
        const NSUInteger valueStart = dataTableOffset + dataOffset;
        if (keyStart >= data.length || valueStart >= data.length) {
            continue;
        }

        NSUInteger keyEnd = keyStart;
        while (keyEnd < data.length && bytes[keyEnd] != 0) {
            keyEnd++;
        }
        if (keyEnd <= keyStart) {
            continue;
        }

        NSString* key = [[NSString alloc] initWithBytes:bytes + keyStart
                                                 length:keyEnd - keyStart
                                               encoding:NSUTF8StringEncoding];
        if (key.length == 0 || dataLength == 0) {
            continue;
        }

        const NSUInteger availableLength = data.length - valueStart;
        const NSUInteger safeLength = dataLength < availableLength ? dataLength : availableLength;
        NSUInteger valueLength = safeLength;
        while (valueLength > 0 && bytes[valueStart + valueLength - 1] == 0) {
            valueLength--;
        }
        NSString* value = [[NSString alloc] initWithBytes:bytes + valueStart
                                                   length:valueLength
                                                 encoding:NSUTF8StringEncoding];
        if (value.length > 0) {
            values[key] = value;
        }
    }

    return values;
}

} // namespace

@interface PanelView : UIView
@property(nonatomic, strong) UIStackView* stack;
- (instancetype)initWithTitle:(NSString*)title subtitle:(NSString*)subtitle;
@end

@implementation PanelView

- (instancetype)initWithTitle:(NSString*)title subtitle:(NSString*)subtitle {
    self = [super initWithFrame:CGRectZero];
    if (self == nil) {
        return nil;
    }

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = Color(0.09, 0.11, 0.15);
    self.layer.cornerRadius = 8.0;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = Color(0.20, 0.24, 0.31).CGColor;

    UILabel* titleLabel = MakeLabel(title, 17.0, UIFontWeightSemibold, Color(0.95, 0.97, 1.0));
    UILabel* subtitleLabel = MakeLabel(subtitle, 13.0, UIFontWeightRegular, Color(0.60, 0.67, 0.77));
    self.stack = MakeVerticalStack(@[ titleLabel, subtitleLabel ], 6.0);
    [self addSubview:self.stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18.0],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18.0],
        [self.stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:16.0],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16.0]
    ]];
    return self;
}

@end

@interface StatusCard : UIView
@property(nonatomic, strong) UILabel* valueLabel;
- (instancetype)initWithTitle:(NSString*)title value:(NSString*)value color:(UIColor*)color;
- (void)setValue:(NSString*)value;
@end

@implementation StatusCard

- (instancetype)initWithTitle:(NSString*)title value:(NSString*)value color:(UIColor*)color {
    self = [super initWithFrame:CGRectZero];
    if (self == nil) {
        return nil;
    }

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = Color(0.10, 0.12, 0.17);
    self.layer.cornerRadius = 8.0;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = Color(0.20, 0.24, 0.32).CGColor;

    UIView* accent = [[UIView alloc] initWithFrame:CGRectZero];
    accent.translatesAutoresizingMaskIntoConstraints = NO;
    accent.backgroundColor = color;
    accent.layer.cornerRadius = 2.0;

    UILabel* titleLabel = MakeLabel(title, 12.0, UIFontWeightMedium, Color(0.58, 0.65, 0.75));
    self.valueLabel = MakeLabel(value, 19.0, UIFontWeightBold, Color(0.96, 0.98, 1.0));

    UIStackView* textStack = MakeVerticalStack(@[ titleLabel, self.valueLabel ], 5.0);
    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:@[ accent, textStack ]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12.0;
    row.alignment = UIStackViewAlignmentCenter;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [accent.widthAnchor constraintEqualToConstant:4.0],
        [accent.heightAnchor constraintEqualToConstant:44.0],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:14.0],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14.0],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:88.0]
    ]];
    return self;
}

- (void)setValue:(NSString*)value {
    self.valueLabel.text = value;
}

@end

@interface SettingRow : UIView
- (instancetype)initWithTitle:(NSString*)title detail:(NSString*)detail accessory:(UIView*)accessory;
@end

@implementation SettingRow

- (instancetype)initWithTitle:(NSString*)title detail:(NSString*)detail accessory:(UIView*)accessory {
    self = [super initWithFrame:CGRectZero];
    if (self == nil) {
        return nil;
    }

    self.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel* titleLabel = MakeLabel(title, 15.0, UIFontWeightSemibold, Color(0.93, 0.96, 1.0));
    UILabel* detailLabel = MakeLabel(detail, 13.0, UIFontWeightRegular, Color(0.58, 0.66, 0.76));
    UIStackView* labels = MakeVerticalStack(@[ titleLabel, detailLabel ], 4.0);

    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:@[ labels, accessory ]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 18.0;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [accessory.widthAnchor constraintGreaterThanOrEqualToConstant:92.0],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0]
    ]];
    return self;
}

@end

@interface GamePreviewCard : UIView
@property(nonatomic, strong) UIImageView* artworkView;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* metaLabel;
@property(nonatomic, strong) UILabel* pathLabel;
- (void)showEmptyState;
- (void)showGameWithTitle:(NSString*)title
                   serial:(NSString*)serial
                  version:(NSString*)version
                     path:(NSString*)path
                  artwork:(UIImage*)artwork;
@end

@implementation GamePreviewCard

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = Color(0.08, 0.10, 0.14);
    self.layer.cornerRadius = 8.0;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = Color(0.20, 0.24, 0.32).CGColor;

    self.artworkView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.artworkView.translatesAutoresizingMaskIntoConstraints = NO;
    self.artworkView.backgroundColor = Color(0.12, 0.15, 0.20);
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.layer.cornerRadius = 8.0;
    self.artworkView.layer.borderWidth = 1.0;
    self.artworkView.layer.borderColor = Color(0.22, 0.27, 0.35).CGColor;

    self.titleLabel = MakeLabel(@"No game selected", 24.0, UIFontWeightBold, Color(0.97, 0.99, 1.0));
    self.metaLabel = MakeLabel(@"Choose a game folder or eboot.bin to build a game card.",
                               15.0, UIFontWeightRegular, Color(0.67, 0.75, 0.86));
    self.pathLabel = MakeLabel(@"", 13.0, UIFontWeightRegular, Color(0.54, 0.63, 0.75));
    self.pathLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];

    UIStackView* textStack = MakeVerticalStack(@[ self.titleLabel, self.metaLabel, self.pathLabel ], 8.0);
    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:@[ self.artworkView, textStack ]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 18.0;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [self.artworkView.widthAnchor constraintEqualToConstant:128.0],
        [self.artworkView.heightAnchor constraintEqualToConstant:128.0],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18.0],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18.0],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:18.0],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-18.0],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:164.0]
    ]];

    [self showEmptyState];
    return self;
}

- (UIImage*)placeholderImage {
    const CGFloat size = 256.0;
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
        CGContextRef cg = context.CGContext;
        CGContextSetFillColorWithColor(cg, Color(0.06, 0.08, 0.12).CGColor);
        CGContextFillRect(cg, CGRectMake(0.0, 0.0, size, size));
        CGContextSetFillColorWithColor(cg, Color(0.11, 0.44, 0.76).CGColor);
        CGContextFillEllipseInRect(cg, CGRectMake(42.0, 42.0, 172.0, 172.0));
        NSDictionary* attributes = @{
            NSFontAttributeName : [UIFont systemFontOfSize:48.0 weight:UIFontWeightBlack],
            NSForegroundColorAttributeName : [UIColor whiteColor],
        };
        [@"PS4" drawInRect:CGRectMake(70.0, 96.0, 140.0, 64.0) withAttributes:attributes];
    }];
}

- (void)showEmptyState {
    self.artworkView.image = [self placeholderImage];
    self.titleLabel.text = @"No game selected";
    self.metaLabel.text = @"Choose a game folder or eboot.bin to build a game card.";
    self.pathLabel.text = @"";
}

- (void)showGameWithTitle:(NSString*)title
                   serial:(NSString*)serial
                  version:(NSString*)version
                     path:(NSString*)path
                  artwork:(UIImage*)artwork {
    self.artworkView.image = artwork ?: [self placeholderImage];
    self.titleLabel.text = title.length > 0 ? title : @"Unknown PS4 Game";
    NSString* serialText = serial.length > 0 ? serial : @"Unknown title id";
    NSString* versionText = version.length > 0 ? version : @"Unknown version";
    self.metaLabel.text = [NSString stringWithFormat:@"%@ / %@", serialText, versionText];
    self.pathLabel.text = path;
}

@end

@interface ShadPS4ViewController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIButton* libraryNavButton;
@property(nonatomic, strong) UIButton* settingsNavButton;
@property(nonatomic, strong) UIButton* logsNavButton;
@property(nonatomic, strong) UIScrollView* libraryPage;
@property(nonatomic, strong) UIScrollView* settingsPage;
@property(nonatomic, strong) UIScrollView* logsPage;
@property(nonatomic, strong) UILabel* gameLabel;
@property(nonatomic, strong) UILabel* logLabel;
@property(nonatomic, strong) UILabel* logsBodyLabel;
@property(nonatomic, strong) GamePreviewCard* gamePreviewCard;
@property(nonatomic, strong) UIButton* launchButton;
@property(nonatomic, strong) UISegmentedControl* resolutionControl;
@property(nonatomic, strong) UISegmentedControl* qualityControl;
@property(nonatomic, strong) UISegmentedControl* pacingControl;
@property(nonatomic, strong) UISwitch* jitRefreshSwitch;
@property(nonatomic, strong) UISwitch* deviceGuardSwitch;
@property(nonatomic, strong) UISwitch* verboseLogSwitch;
@property(nonatomic, strong) UISwitch* shaderCacheSwitch;
@property(nonatomic, strong) StatusCard* gameCard;
@property(nonatomic, strong) StatusCard* jitCard;
@property(nonatomic, strong) StatusCard* renderCard;
@property(nonatomic, strong) StatusCard* deviceCard;
@property(nonatomic, strong) StatusCard* coreCard;
@property(nonatomic, strong) NSURL* selectedGameURL;
@property(nonatomic, strong) NSURL* selectedGameRootURL;
@property(nonatomic, assign) BOOL selectedURLNeedsStopAccessing;
@end

@implementation ShadPS4ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = Color(0.04, 0.05, 0.07);

    UIView* sidebar = [[UIView alloc] initWithFrame:CGRectZero];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.backgroundColor = Color(0.075, 0.085, 0.115);
    sidebar.layer.borderWidth = 1.0;
    sidebar.layer.borderColor = Color(0.17, 0.20, 0.27).CGColor;

    UILabel* brand = MakeLabel(@"shadPS4", 35.0, UIFontWeightBold, Color(0.96, 0.98, 1.0));
    UILabel* subtitle = MakeLabel(@"iOS / iPadOS Port", 14.0, UIFontWeightMedium, Color(0.55, 0.64, 0.76));

    self.libraryNavButton = [self makeNavButton:@"Library" symbol:@"square.grid.2x2.fill"];
    self.settingsNavButton = [self makeNavButton:@"Settings" symbol:@"slider.horizontal.3"];
    self.logsNavButton = [self makeNavButton:@"Runtime Logs" symbol:@"terminal.fill"];
    [self.libraryNavButton addTarget:self action:@selector(showLibraryPage) forControlEvents:UIControlEventTouchUpInside];
    [self.settingsNavButton addTarget:self action:@selector(showSettingsPage) forControlEvents:UIControlEventTouchUpInside];
    [self.logsNavButton addTarget:self action:@selector(showLogsPage) forControlEvents:UIControlEventTouchUpInside];

    UIView* spacer = [[UIView alloc] initWithFrame:CGRectZero];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer.heightAnchor constraintEqualToConstant:12.0].active = YES;

    UILabel* deviceLabel = MakeLabel(FormatDeviceSummary(), 13.0, UIFontWeightRegular, Color(0.63, 0.70, 0.80));
    UIStackView* sidebarStack = MakeVerticalStack(@[
        brand, subtitle, spacer, self.libraryNavButton, self.settingsNavButton, self.logsNavButton, deviceLabel
    ], 13.0);
    [sidebar addSubview:sidebarStack];

    UIView* content = [[UIView alloc] initWithFrame:CGRectZero];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    self.libraryPage = [self buildLibraryPage];
    self.settingsPage = [self buildSettingsPage];
    self.logsPage = [self buildLogsPage];
    [content addSubview:self.libraryPage];
    [content addSubview:self.settingsPage];
    [content addSubview:self.logsPage];

    [self.view addSubview:sidebar];
    [self.view addSubview:content];

    UILayoutGuide* guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sidebar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:272.0],
        [sidebarStack.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:22.0],
        [sidebarStack.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-22.0],
        [sidebarStack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:28.0],
        [content.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];

    for (UIScrollView* page in @[ self.libraryPage, self.settingsPage, self.logsPage ]) {
        [NSLayoutConstraint activateConstraints:@[
            [page.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [page.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [page.topAnchor constraintEqualToAnchor:content.topAnchor],
            [page.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
        ]];
    }

    [self showLibraryPage];
    [self refreshRuntimeState];
}

- (UIButton*)makeNavButton:(NSString*)title symbol:(NSString*)symbol {
    UIButton* button = MakeButton(title, symbol, Color(0.11, 0.13, 0.18));
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    return button;
}

- (UIScrollView*)makePageWithStack:(UIStackView*)stack {
    UIScrollView* scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.backgroundColor = [UIColor clearColor];
    scroll.alwaysBounceVertical = YES;
    [scroll addSubview:stack];
    UILayoutGuide* frameGuide = scroll.frameLayoutGuide;
    UILayoutGuide* contentGuide = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:contentGuide.leadingAnchor constant:32.0],
        [stack.trailingAnchor constraintEqualToAnchor:contentGuide.trailingAnchor constant:-32.0],
        [stack.topAnchor constraintEqualToAnchor:contentGuide.topAnchor constant:28.0],
        [stack.bottomAnchor constraintEqualToAnchor:contentGuide.bottomAnchor constant:-28.0],
        [stack.widthAnchor constraintEqualToAnchor:frameGuide.widthAnchor constant:-64.0]
    ]];
    return scroll;
}

- (UIScrollView*)buildLibraryPage {
    UILabel* title = MakeLabel(@"Game Library", 34.0, UIFontWeightBold, Color(0.97, 0.98, 1.0));
    UILabel* detail = MakeLabel(@"Select a PS4 game package or folder, then validate the iPadOS runtime before launch.",
                                16.0, UIFontWeightRegular, Color(0.64, 0.72, 0.83));

    self.gameCard = [[StatusCard alloc] initWithTitle:@"Selected Game" value:@"None" color:Color(0.10, 0.55, 0.86)];
    self.jitCard = [[StatusCard alloc] initWithTitle:@"External JIT" value:@"Not detected" color:Color(0.95, 0.54, 0.25)];
    self.renderCard = [[StatusCard alloc] initWithTitle:@"Resolution" value:@"900p" color:Color(0.38, 0.72, 0.48)];
    self.deviceCard = [[StatusCard alloc] initWithTitle:@"Device Policy" value:@"Checking" color:Color(0.50, 0.58, 0.96)];
    self.coreCard = [[StatusCard alloc] initWithTitle:@"Core Bridge" value:@"Checking" color:Color(0.74, 0.52, 0.96)];

    UIStackView* cardRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.gameCard, self.jitCard, self.renderCard, self.deviceCard, self.coreCard
    ]];
    cardRow.translatesAutoresizingMaskIntoConstraints = NO;
    cardRow.axis = UILayoutConstraintAxisHorizontal;
    cardRow.distribution = UIStackViewDistributionFillEqually;
    cardRow.spacing = 12.0;

    UIButton* selectGameButton = MakeButton(@"Select Game or Folder", @"folder.badge.plus",
                                           Color(0.06, 0.43, 0.76));
    self.launchButton = MakeButton(@"Start Emulation", @"play.fill", Color(0.18, 0.52, 0.36));
    [selectGameButton addTarget:self action:@selector(openGamePicker) forControlEvents:UIControlEventTouchUpInside];
    [self.launchButton addTarget:self action:@selector(startEmulation) forControlEvents:UIControlEventTouchUpInside];

    UIStackView* commandRow =
        [[UIStackView alloc] initWithArrangedSubviews:@[ selectGameButton, self.launchButton ]];
    commandRow.translatesAutoresizingMaskIntoConstraints = NO;
    commandRow.axis = UILayoutConstraintAxisHorizontal;
    commandRow.distribution = UIStackViewDistributionFillEqually;
    commandRow.spacing = 12.0;

    PanelView* selectedPanel =
        [[PanelView alloc] initWithTitle:@"Selected Content"
                                subtitle:@"Pick a game folder, parent library folder, eboot.bin, or ELF file from Files."];
    self.gamePreviewCard = [[GamePreviewCard alloc] initWithFrame:CGRectZero];
    self.gameLabel = MakeLabel(@"The picker scans for eboot.bin and sce_sys/param.sfo automatically.",
                               14.0, UIFontWeightRegular, Color(0.74, 0.82, 0.92));
    [selectedPanel.stack addArrangedSubview:self.gamePreviewCard];
    [selectedPanel.stack addArrangedSubview:self.gameLabel];

    PanelView* runtimePanel =
        [[PanelView alloc] initWithTitle:@"Runtime Readiness"
                                subtitle:@"Launch checks are performed locally before any emulator core is entered."];
    self.logLabel = MakeLabel(@"Status: waiting for game selection.", 14.0, UIFontWeightRegular,
                              Color(0.66, 0.75, 0.88));
    self.logLabel.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    [runtimePanel.stack addArrangedSubview:self.logLabel];

    UIStackView* stack = MakeVerticalStack(@[
        title, detail, cardRow, commandRow, selectedPanel, runtimePanel
    ], 18.0);
    return [self makePageWithStack:stack];
}

- (UIScrollView*)buildSettingsPage {
    UILabel* title = MakeLabel(@"Settings", 34.0, UIFontWeightBold, Color(0.97, 0.98, 1.0));
    UILabel* detail = MakeLabel(@"Tune the iPadOS port surface. These controls prepare state for the emulator core.",
                                16.0, UIFontWeightRegular, Color(0.64, 0.72, 0.83));

    self.resolutionControl = [[UISegmentedControl alloc] initWithItems:@[ @"720p", @"900p" ]];
    self.resolutionControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.resolutionControl.selectedSegmentIndex = 1;
    [self.resolutionControl addTarget:self action:@selector(resolutionChanged)
                     forControlEvents:UIControlEventValueChanged];

    self.qualityControl = [[UISegmentedControl alloc] initWithItems:@[ @"Stable", @"Balanced", @"Sharp" ]];
    self.qualityControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.qualityControl.selectedSegmentIndex = 1;
    [self.qualityControl addTarget:self action:@selector(settingChanged:)
                  forControlEvents:UIControlEventValueChanged];

    self.pacingControl = [[UISegmentedControl alloc] initWithItems:@[ @"Smooth", @"Low Latency" ]];
    self.pacingControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.pacingControl.selectedSegmentIndex = 0;
    [self.pacingControl addTarget:self action:@selector(settingChanged:)
                 forControlEvents:UIControlEventValueChanged];

    PanelView* renderPanel = [[PanelView alloc] initWithTitle:@"Rendering"
                                                     subtitle:@"Resolution is intentionally limited to mobile-safe presets."];
    [renderPanel.stack addArrangedSubview:[[SettingRow alloc] initWithTitle:@"Resolution preset"
                                                                     detail:@"Only 720p and 900p are exposed for this iOS build."
                                                                  accessory:self.resolutionControl]];
    [renderPanel.stack addArrangedSubview:[[SettingRow alloc] initWithTitle:@"Visual profile"
                                                                     detail:@"Changes presentation intent before the renderer is linked."
                                                                  accessory:self.qualityControl]];
    [renderPanel.stack addArrangedSubview:[[SettingRow alloc] initWithTitle:@"Frame pacing"
                                                                     detail:@"Choose a calmer frame queue or lower input latency."
                                                                  accessory:self.pacingControl]];

    self.jitRefreshSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.jitRefreshSwitch.on = YES;
    [self.jitRefreshSwitch addTarget:self action:@selector(settingChanged:)
                    forControlEvents:UIControlEventValueChanged];

    self.deviceGuardSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.deviceGuardSwitch.on = YES;
    [self.deviceGuardSwitch addTarget:self action:@selector(settingChanged:)
                     forControlEvents:UIControlEventValueChanged];

    PanelView* runtimePanel = [[PanelView alloc] initWithTitle:@"Runtime"
                                                      subtitle:@"The iOS build expects JIT to be provided externally."];
    [runtimePanel.stack addArrangedSubview:[[SettingRow alloc] initWithTitle:@"Auto refresh JIT status"
                                                                      detail:@"Refresh the external JIT bridge when entering launch flow."
                                                                   accessory:self.jitRefreshSwitch]];
    [runtimePanel.stack addArrangedSubview:[[SettingRow alloc] initWithTitle:@"Device requirement guard"
                                                                      detail:@"Keep iOS 18, RAM, and iPad M-series checks enabled."
                                                                   accessory:self.deviceGuardSwitch]];

    self.verboseLogSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [self.verboseLogSwitch addTarget:self action:@selector(settingChanged:)
                    forControlEvents:UIControlEventValueChanged];
    self.shaderCacheSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.shaderCacheSwitch.on = YES;
    [self.shaderCacheSwitch addTarget:self action:@selector(settingChanged:)
                     forControlEvents:UIControlEventValueChanged];

    PanelView* diagnosticsPanel = [[PanelView alloc] initWithTitle:@"Diagnostics"
                                                          subtitle:@"Local flags for logs, cache behavior, and future crash reporting."];
    [diagnosticsPanel.stack addArrangedSubview:[[SettingRow alloc] initWithTitle:@"Verbose logging"
                                                                          detail:@"Record more detailed startup and bridge messages."
                                                                       accessory:self.verboseLogSwitch]];
    [diagnosticsPanel.stack addArrangedSubview:[[SettingRow alloc] initWithTitle:@"Shader cache placeholder"
                                                                          detail:@"Reserve a stable setting for future Metal pipeline caching."
                                                                       accessory:self.shaderCacheSwitch]];

    UIStackView* stack = MakeVerticalStack(@[ title, detail, renderPanel, runtimePanel, diagnosticsPanel ], 18.0);
    return [self makePageWithStack:stack];
}

- (UIScrollView*)buildLogsPage {
    UILabel* title = MakeLabel(@"Runtime Logs", 34.0, UIFontWeightBold, Color(0.97, 0.98, 1.0));
    UILabel* detail = MakeLabel(@"A compact log surface for launch checks and settings changes.",
                                16.0, UIFontWeightRegular, Color(0.64, 0.72, 0.83));
    PanelView* logPanel = [[PanelView alloc] initWithTitle:@"Session"
                                                  subtitle:@"Newest events are mirrored here while testing on device."];
    self.logsBodyLabel = MakeLabel(@"Status: app initialized.", 14.0, UIFontWeightRegular, Color(0.70, 0.79, 0.90));
    self.logsBodyLabel.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    [logPanel.stack addArrangedSubview:self.logsBodyLabel];

    UIButton* refreshButton = MakeButton(@"Refresh Runtime State", @"arrow.clockwise", Color(0.16, 0.22, 0.32));
    [refreshButton addTarget:self action:@selector(refreshRuntimeState) forControlEvents:UIControlEventTouchUpInside];

    UIStackView* stack = MakeVerticalStack(@[ title, detail, logPanel, refreshButton ], 18.0);
    return [self makePageWithStack:stack];
}

- (void)setActivePage:(UIScrollView*)page selectedButton:(UIButton*)selectedButton {
    self.libraryPage.hidden = page != self.libraryPage;
    self.settingsPage.hidden = page != self.settingsPage;
    self.logsPage.hidden = page != self.logsPage;

    for (UIButton* button in @[ self.libraryNavButton, self.settingsNavButton, self.logsNavButton ]) {
        UIButtonConfiguration* config = button.configuration;
        config.baseBackgroundColor =
            button == selectedButton ? Color(0.18, 0.25, 0.36) : Color(0.11, 0.13, 0.18);
        config.baseForegroundColor =
            button == selectedButton ? Color(0.98, 1.0, 1.0) : Color(0.74, 0.82, 0.94);
        button.configuration = config;
    }
}

- (void)showLibraryPage {
    [self setActivePage:self.libraryPage selectedButton:self.libraryNavButton];
}

- (void)showSettingsPage {
    [self setActivePage:self.settingsPage selectedButton:self.settingsNavButton];
}

- (void)showLogsPage {
    [self setActivePage:self.logsPage selectedButton:self.logsNavButton];
}

- (void)appendLog:(NSString*)line {
    self.logLabel.text = line;
    NSString* existing = self.logsBodyLabel.text ?: @"";
    self.logsBodyLabel.text = [existing stringByAppendingFormat:@"\n%@", line];
}

- (void)refreshRuntimeState {
    const auto policy = Core::IOSPort::QueryDevicePolicy();
    const auto jitStatus = Core::JIT::QueryExternalJitStatus();
    [self.deviceCard setValue:SupportTierText(policy.tier)];
    NSString* jitValue = jitStatus.available ? ToNSString(jitStatus.provider) : @"Not detected";
    [self.jitCard setValue:jitValue];
    const auto coreStatus = Core::IOSPort::QueryEmulatorCoreStatus();
    [self.coreCard setValue:coreStatus.state_core_linked ? @"State linked" : @"Bridge only"];
    self.launchButton.enabled = self.selectedGameURL != nil;
    self.launchButton.alpha = self.launchButton.enabled ? 1.0 : 0.55;
}

- (void)resolutionChanged {
    NSString* value = self.resolutionControl.selectedSegmentIndex == 0 ? @"720p" : @"900p";
    [self.renderCard setValue:value];
    [self appendLog:[NSString stringWithFormat:@"Status: resolution set to %@.", value]];
}

- (void)settingChanged:(id)sender {
    (void)sender;
    NSArray<NSString*>* profiles = @[ @"Stable", @"Balanced", @"Sharp" ];
    NSArray<NSString*>* pacing = @[ @"Smooth", @"Low Latency" ];
    NSString* message = [NSString stringWithFormat:@"Status: settings updated. Profile=%@, Pacing=%@, JIT refresh=%@.",
                                                   profiles[self.qualityControl.selectedSegmentIndex],
                                                   pacing[self.pacingControl.selectedSegmentIndex],
                                                   self.jitRefreshSwitch.on ? @"on" : @"off"];
    [self appendLog:message];
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

- (NSDictionary<NSString*, id>*)gameCandidateForRootURL:(NSURL*)rootURL {
    NSFileManager* fileManager = NSFileManager.defaultManager;
    NSURL* ebootURL = URLByAppendingPath(rootURL, @"eboot.bin");
    NSURL* paramURL = URLByAppendingPath(rootURL, @"sce_sys/param.sfo");

    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:ebootURL.path isDirectory:&isDirectory] || isDirectory) {
        return nil;
    }

    NSDictionary<NSString*, NSString*>* psf = ReadParamSfo(paramURL);
    NSString* title = psf[@"TITLE"];
    NSString* serial = psf[@"TITLE_ID"];
    NSString* version = psf[@"APP_VER"];
    if (serial.length == 0 && psf[@"CONTENT_ID"].length >= 16) {
        serial = [psf[@"CONTENT_ID"] substringWithRange:NSMakeRange(7, 9)];
    }
    if (title.length == 0) {
        title = rootURL.lastPathComponent.length > 0 ? rootURL.lastPathComponent : @"Unknown PS4 Game";
    }

    NSURL* iconURL = URLByAppendingPath(rootURL, @"sce_sys/icon0.png");
    if (![fileManager fileExistsAtPath:iconURL.path]) {
        iconURL = nil;
    }

    return @{
        @"rootURL" : rootURL,
        @"executableURL" : ebootURL,
        @"title" : title,
        @"serial" : serial ?: @"",
        @"version" : version ?: @"",
        @"iconURL" : iconURL ?: [NSNull null],
    };
}

- (NSArray<NSDictionary<NSString*, id>*>*)gameCandidatesForURL:(NSURL*)url {
    NSFileManager* fileManager = NSFileManager.defaultManager;
    NSMutableArray<NSDictionary<NSString*, id>*>* candidates = [NSMutableArray array];
    const BOOL isDirectory = URLIsDirectory(url);

    if (!isDirectory) {
        NSString* filename = url.lastPathComponent.lowercaseString;
        NSURL* rootURL = nil;
        if ([filename isEqualToString:@"eboot.bin"] || [filename.pathExtension isEqualToString:@"elf"]) {
            rootURL = url.URLByDeletingLastPathComponent;
        } else if ([filename isEqualToString:@"param.sfo"]) {
            rootURL = url.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
        }
        NSDictionary<NSString*, id>* candidate = rootURL != nil ? [self gameCandidateForRootURL:rootURL] : nil;
        if (candidate != nil) {
            [candidates addObject:candidate];
        }
        return candidates;
    }

    NSDictionary<NSString*, id>* directCandidate = [self gameCandidateForRootURL:url];
    if (directCandidate != nil) {
        [candidates addObject:directCandidate];
        return candidates;
    }

    NSArray<NSURL*>* children = [fileManager contentsOfDirectoryAtURL:url
                                           includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
                                                              options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                error:nil];
    for (NSURL* child in children) {
        if (!URLIsDirectory(child)) {
            continue;
        }
        NSDictionary<NSString*, id>* candidate = [self gameCandidateForRootURL:child];
        if (candidate != nil) {
            [candidates addObject:candidate];
        }
    }
    return candidates;
}

- (void)applyGameCandidate:(NSDictionary<NSString*, id>*)candidate {
    NSURL* executableURL = candidate[@"executableURL"];
    NSURL* rootURL = candidate[@"rootURL"];
    self.selectedGameURL = executableURL;
    self.selectedGameRootURL = rootURL;

    NSString* title = candidate[@"title"];
    NSString* serial = candidate[@"serial"];
    NSString* version = candidate[@"version"];
    id iconValue = candidate[@"iconURL"];
    UIImage* artwork = nil;
    if ([iconValue isKindOfClass:NSURL.class]) {
        artwork = [UIImage imageWithContentsOfFile:((NSURL*)iconValue).path];
    }

    [self.gameCard setValue:title.length > 0 ? title : @"Selected"];
    [self.gamePreviewCard showGameWithTitle:title
                                     serial:serial
                                    version:version
                                       path:rootURL.path
                                    artwork:artwork];
    self.gameLabel.text = [NSString stringWithFormat:@"Launch target:\n%@", executableURL.path];
    [self appendLog:[NSString stringWithFormat:@"Status: selected %@.", title ?: @"game"]];
    [self refreshRuntimeState];
}

- (void)showGameCandidatePicker:(NSArray<NSDictionary<NSString*, id>*>*)candidates {
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:@"Select Game"
                                                                   message:@"Multiple PS4 games were found in this folder."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary<NSString*, id>* candidate in candidates) {
        NSString* title = candidate[@"title"];
        NSString* serial = candidate[@"serial"];
        NSString* label = serial.length > 0 ? [NSString stringWithFormat:@"%@ / %@", title, serial] : title;
        [sheet addAction:[UIAlertAction actionWithTitle:label
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction* action) {
                                                    [self applyGameCandidate:candidate];
                                                }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController* popover = sheet.popoverPresentationController;
    popover.sourceView = self.view;
    popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    [self presentViewController:sheet animated:YES completion:nil];
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
    NSArray<NSDictionary<NSString*, id>*>* candidates = [self gameCandidatesForURL:url];
    if (candidates.count == 0) {
        self.selectedGameURL = nil;
        self.selectedGameRootURL = nil;
        [self.gameCard setValue:@"None"];
        [self.gamePreviewCard showEmptyState];
        self.gameLabel.text = [NSString stringWithFormat:@"No playable PS4 entry was found in:\n%@", url.path];
        [self appendLog:@"Status: no eboot.bin was found in the selected location."];
        [self showAlertWithTitle:@"No game found"
                         message:@"Select a PS4 game folder that contains eboot.bin, a parent folder containing game folders, or eboot.bin directly."];
        [self refreshRuntimeState];
        return;
    }

    if (candidates.count == 1) {
        [self applyGameCandidate:candidates.firstObject];
        return;
    }

    [self showGameCandidatePicker:candidates];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller {
    (void)controller;
    [self appendLog:@"Status: game selection cancelled."];
}

- (void)startEmulation {
    if (self.selectedGameURL == nil) {
        [self showAlertWithTitle:@"No game selected" message:@"Choose a game folder or executable first."];
        return;
    }

    if (self.jitRefreshSwitch.on) {
        [self refreshRuntimeState];
    }

    const auto policy = Core::IOSPort::QueryDevicePolicy();
    if (self.deviceGuardSwitch.on && policy.tier == Core::IOSPort::SupportTier::Unsupported) {
        [self showAlertWithTitle:@"Unsupported device" message:ToNSString(policy.reason)];
        return;
    }

    const auto jitStatus = Core::JIT::QueryExternalJitStatus();
    Core::IOSPort::EmulatorCoreLaunchRequest request{
        .game_path = self.selectedGameURL.path.UTF8String ?: "",
        .resolution_name = self.resolutionControl.selectedSegmentIndex == 0 ? "720p" : "900p",
        .resolution_width = self.resolutionControl.selectedSegmentIndex == 0 ? 1280U : 1600U,
        .resolution_height = self.resolutionControl.selectedSegmentIndex == 0 ? 720U : 900U,
        .external_jit_available = jitStatus.available,
        .enforce_device_policy = self.deviceGuardSwitch.on,
    };
    const auto coreStatus = Core::IOSPort::PrepareEmulatorCoreLaunch(request);
    if (!jitStatus.available) {
        [self appendLog:ToNSString("Status: " + coreStatus.blocker)];
        [self showAlertWithTitle:@"External JIT required"
                         message:@"Open SideStore, enable JIT for this app, then return here and refresh runtime state before starting emulation."];
        return;
    }

    [self appendLog:ToNSString("Status: " + coreStatus.summary)];
    [self showAlertWithTitle:@"Core bridge linked"
                     message:ToNSString(coreStatus.blocker)];
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
