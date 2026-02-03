/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectPaletteView.h"
#import "XLEffectsGridView.h"
#import "../XLEngineBridge.h"

static const CGFloat kDefaultItemHeight = 28.0;
static const CGFloat kIconSize = 16.0;
static const CGFloat kIconLeftPadding = 8.0;
static const CGFloat kTextLeftPadding = 30.0;
static const CGFloat kTextRightPadding = 8.0;

#pragma mark - XLEffectPaletteItemView

/// A single item view in the effect palette, representing one effect type.
@interface XLEffectPaletteItemView : NSView <NSDraggingSource>
@property (nonatomic, copy) NSString *effectTypeName;
@property (nonatomic, strong) NSImage *icon;
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, assign) BOOL isHovered;
@property (nonatomic, weak) XLEffectPaletteView *owningPaletteView;
@end

@implementation XLEffectPaletteItemView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _isSelected = NO;
        _isHovered = NO;

        NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited
                                      | NSTrackingActiveInActiveApp
                                      | NSTrackingInVisibleRect;
        NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                                   options:options
                                                                     owner:self
                                                                  userInfo:nil];
        [self addTrackingArea:trackingArea];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;

    // Background
    if (_isSelected) {
        [[NSColor selectedContentBackgroundColor] setFill];
        NSRectFill(bounds);
    } else if (_isHovered) {
        [[NSColor colorWithWhite:0.3 alpha:1.0] setFill];
        NSRectFill(bounds);
    }

    // Icon
    if (_icon) {
        NSRect iconRect = NSMakeRect(kIconLeftPadding,
                                     (bounds.size.height - kIconSize) / 2.0,
                                     kIconSize,
                                     kIconSize);
        [_icon drawInRect:iconRect
                 fromRect:NSZeroRect
                operation:NSCompositingOperationSourceOver
                 fraction:1.0
           respectFlipped:YES
                    hints:nil];
    }

    // Text
    NSColor *textColor = _isSelected ? [NSColor alternateSelectedControlTextColor]
                                     : [NSColor labelColor];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName: textColor
    };

    NSRect textRect = NSMakeRect(kTextLeftPadding,
                                 (bounds.size.height - 14) / 2.0,
                                 bounds.size.width - kTextLeftPadding - kTextRightPadding,
                                 14);
    [_effectTypeName drawInRect:textRect withAttributes:attrs];
}

- (void)mouseEntered:(NSEvent *)event {
    _isHovered = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    _isHovered = NO;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    // Notify palette of selection
    if (_owningPaletteView && [_owningPaletteView respondsToSelector:@selector(itemViewClicked:)]) {
        [_owningPaletteView performSelector:@selector(itemViewClicked:) withObject:self];
    }

    // Handle double-click
    if (event.clickCount == 2) {
        if (_owningPaletteView.delegate &&
            [_owningPaletteView.delegate respondsToSelector:@selector(effectPaletteView:didDoubleClickEffectType:)]) {
            [_owningPaletteView.delegate effectPaletteView:_owningPaletteView
                                  didDoubleClickEffectType:_effectTypeName];
        }
        return;
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_effectTypeName) return;

    // Begin drag operation
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:_effectTypeName forType:XLEffectTypePasteboardType];

    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pbItem];

    // Create drag image
    NSImage *dragImage = [self createDragImage];
    NSPoint dragPoint = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect dragRect = NSMakeRect(dragPoint.x - dragImage.size.width / 2,
                                 dragPoint.y - dragImage.size.height / 2,
                                 dragImage.size.width,
                                 dragImage.size.height);
    [dragItem setDraggingFrame:dragRect contents:dragImage];

    NSDraggingSession *session = [self beginDraggingSessionWithItems:@[dragItem]
                                                               event:event
                                                              source:self];
    session.animatesToStartingPositionsOnCancelOrFail = YES;
    session.draggingFormation = NSDraggingFormationNone;
}

- (NSImage *)createDragImage {
    NSSize size = NSMakeSize(120, kDefaultItemHeight);
    NSImage *image = [[NSImage alloc] initWithSize:size];

    [image lockFocus];

    // Draw rounded rect background
    NSRect rect = NSMakeRect(0, 0, size.width, size.height);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4 yRadius:4];
    [[NSColor colorWithWhite:0.2 alpha:0.9] setFill];
    [path fill];
    [[NSColor colorWithWhite:0.5 alpha:1.0] setStroke];
    path.lineWidth = 1.0;
    [path stroke];

    // Draw icon
    if (_icon) {
        NSRect iconRect = NSMakeRect(kIconLeftPadding,
                                     (size.height - kIconSize) / 2.0,
                                     kIconSize,
                                     kIconSize);
        [_icon drawInRect:iconRect
                 fromRect:NSZeroRect
                operation:NSCompositingOperationSourceOver
                 fraction:1.0
           respectFlipped:YES
                    hints:nil];
    }

    // Draw text
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSRect textRect = NSMakeRect(kTextLeftPadding,
                                 (size.height - 12) / 2.0,
                                 size.width - kTextLeftPadding - kTextRightPadding,
                                 12);
    [_effectTypeName drawInRect:textRect withAttributes:attrs];

    [image unlockFocus];

    return image;
}

#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    if (context == NSDraggingContextWithinApplication) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

@end

#pragma mark - XLEffectPaletteView

static const CGFloat kHeaderHeight = 28.0;

@interface XLEffectPaletteView ()

@property (nonatomic, strong) NSTextField *headerLabel;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSArray<NSString *> *allEffectTypes;
@property (nonatomic, strong) NSArray<NSString *> *filteredEffectTypes;
@property (nonatomic, copy, readwrite) NSString *selectedEffectType;
@property (nonatomic, assign) BOOL isRebuildingItemViews;

@end

@implementation XLEffectPaletteView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _itemHeight = kDefaultItemHeight;
    _allEffectTypes = @[];
    _filteredEffectTypes = @[];

    self.wantsLayer = YES;
    self.layer.backgroundColor = [[NSColor colorWithWhite:0.15 alpha:1.0] CGColor];

    // Create header label
    _headerLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _headerLabel.stringValue = @"Effects";
    _headerLabel.font = [NSFont boldSystemFontOfSize:11];
    _headerLabel.textColor = [NSColor secondaryLabelColor];
    _headerLabel.backgroundColor = [NSColor clearColor];
    _headerLabel.bordered = NO;
    _headerLabel.editable = NO;
    _headerLabel.selectable = NO;
    _headerLabel.alignment = NSTextAlignmentCenter;
    [self addSubview:_headerLabel];

    // Create scroll view
    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _scrollView.borderType = NSNoBorder;
    [self addSubview:_scrollView];

    // Create content view (document view)
    _contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.bounds.size.width, 0)];
    _contentView.wantsLayer = YES;
    _scrollView.documentView = _contentView;

    [NSLayoutConstraint activateConstraints:@[
        // Header at top
        [_headerLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [_headerLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_headerLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_headerLabel.heightAnchor constraintEqualToConstant:kHeaderHeight - 4],

        // Scroll view below header
        [_scrollView.topAnchor constraintEqualToAnchor:_headerLabel.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)setEngineBridge:(XLEngineBridge *)engineBridge {
    _engineBridge = engineBridge;
    [self reloadEffectTypes];
}

- (void)reloadEffectTypes {
    if (!_engineBridge) {
        _allEffectTypes = @[];
        _filteredEffectTypes = @[];
        [self rebuildItemViews];
        return;
    }

    NSArray<NSString *> *types = [_engineBridge getEffectTypes];
    if (types) {
        // Sort alphabetically
        _allEffectTypes = [types sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    } else {
        _allEffectTypes = @[];
    }

    _filteredEffectTypes = _allEffectTypes;
    [self rebuildItemViews];
}

- (void)filterWithSearchText:(NSString *)searchText {
    if (!searchText || searchText.length == 0) {
        _filteredEffectTypes = _allEffectTypes;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF CONTAINS[cd] %@", searchText];
        _filteredEffectTypes = [_allEffectTypes filteredArrayUsingPredicate:predicate];
    }
    [self rebuildItemViews];
}

- (void)rebuildItemViews {
    // Prevent re-entry and signal that we're rebuilding
    if (_isRebuildingItemViews) {
        return;
    }
    _isRebuildingItemViews = YES;

    // Remove existing item views from content view directly
    // Don't use _itemViews array as it may be corrupted
    if (_contentView) {
        NSArray *subviewsCopy = [_contentView.subviews copy];
        for (NSView *subview in subviewsCopy) {
            [subview removeFromSuperview];
        }
    }

    CGFloat width = self.bounds.size.width;
    if (width <= 0) {
        width = 200; // Default width
    }
    CGFloat yOffset = 0;

    for (NSString *effectType in _filteredEffectTypes) {
        NSRect itemRect = NSMakeRect(0, yOffset, width, _itemHeight);
        XLEffectPaletteItemView *itemView = [[XLEffectPaletteItemView alloc] initWithFrame:itemRect];
        itemView.effectTypeName = effectType;
        itemView.icon = [self iconForEffectType:effectType];
        itemView.isSelected = [effectType isEqualToString:_selectedEffectType];
        itemView.owningPaletteView = self;
        itemView.autoresizingMask = NSViewWidthSizable;

        [_contentView addSubview:itemView];

        yOffset += _itemHeight;
    }

    // Update content view frame to fit all items
    CGFloat contentHeight = _filteredEffectTypes.count * _itemHeight;
    if (_contentView) {
        _contentView.frame = NSMakeRect(0, 0, width, contentHeight);
    }

    _isRebuildingItemViews = NO;
}

- (NSImage *)iconForEffectType:(NSString *)effectType {
    // Generate a colored icon based on the effect type name hash
    // In the future, this could load actual effect icons
    NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(kIconSize, kIconSize)];

    NSUInteger hash = [effectType hash];
    CGFloat hue = (hash % 360) / 360.0;
    NSColor *color = [NSColor colorWithHue:hue saturation:0.7 brightness:0.8 alpha:1.0];

    [icon lockFocus];

    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 1, kIconSize - 2, kIconSize - 2)
                                                         xRadius:3
                                                         yRadius:3];
    [color setFill];
    [path fill];

    // Draw first letter of effect type
    NSString *letter = [[effectType substringToIndex:1] uppercaseString];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:9],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSSize letterSize = [letter sizeWithAttributes:attrs];
    NSPoint letterPoint = NSMakePoint((kIconSize - letterSize.width) / 2,
                                      (kIconSize - letterSize.height) / 2);
    [letter drawAtPoint:letterPoint withAttributes:attrs];

    [icon unlockFocus];

    return icon;
}

- (void)selectEffectType:(NSString *)effectType {
    _selectedEffectType = effectType;

    // Skip if rebuilding
    if (_isRebuildingItemViews) {
        return;
    }

    // Update selection state by iterating content view's subviews directly
    // This avoids using _itemViews array which can become corrupted
    if (_contentView) {
        for (NSView *subview in _contentView.subviews) {
            if ([subview isKindOfClass:[XLEffectPaletteItemView class]]) {
                XLEffectPaletteItemView *itemView = (XLEffectPaletteItemView *)subview;
                BOOL shouldBeSelected = [itemView.effectTypeName isEqualToString:effectType];
                if (itemView.isSelected != shouldBeSelected) {
                    itemView.isSelected = shouldBeSelected;
                    [itemView setNeedsDisplay:YES];
                }
            }
        }
    }
}

- (void)itemViewClicked:(XLEffectPaletteItemView *)itemView {
    [self selectEffectType:itemView.effectTypeName];

    if (_delegate && [_delegate respondsToSelector:@selector(effectPaletteView:didSelectEffectType:)]) {
        [_delegate effectPaletteView:self didSelectEffectType:itemView.effectTypeName];
    }
}

// Note: setFrame: override removed - item views use autoresizingMask for automatic sizing

- (BOOL)isFlipped {
    return YES;
}

@end
