// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#import "ui/ToolPalette.h"

using sk::Tool;

namespace {

struct ToolSpec {
    Tool tool;
    const char *symbol;
    const char *fallback;
    const char *tip;
};

const ToolSpec kTools[] = {
    {Tool::Select,      "cursorarrow",           "S",  "Select  (V)"},
    {Tool::Arrow,       "arrow.up.right",        "→",  "Arrow  (A)"},
    {Tool::Line,        "line.diagonal",         "/",  "Line  (L)"},
    {Tool::Rect,        "rectangle",             "▭",  "Rectangle  (R)"},
    {Tool::Ellipse,     "circle",                "◯",  "Ellipse  (O)"},
    {Tool::Squircle,    "app",                   "▢",  "Squircle  (S)"},
    {Tool::Pen,         "pencil.tip",            "✎",  "Pen  (P)"},
    {Tool::Highlighter, "highlighter",           "▬",  "Highlighter  (H)"},
    {Tool::Text,        "textformat",            "T",  "Text  (T)"},
    {Tool::Pixelate,    "square.grid.3x3.fill",  "▩",  "Pixelate  (X)"},
    {Tool::Redact,      "rectangle.fill",        "■",  "Redact  (B)"},
    {Tool::Crop,        "crop",                  "⌗",  "Crop  (C)"},
};
const int kToolCount = sizeof(kTools) / sizeof(kTools[0]);

NSColor *SwatchColor(int i) {
    switch (i) {
        case 0: return [NSColor colorWithSRGBRed:0.93 green:0.16 blue:0.16 alpha:1.0];
        case 1: return [NSColor colorWithSRGBRed:1.00 green:0.62 blue:0.06 alpha:1.0];
        case 2: return [NSColor colorWithSRGBRed:0.99 green:0.85 blue:0.20 alpha:1.0];
        case 3: return [NSColor colorWithSRGBRed:0.20 green:0.72 blue:0.35 alpha:1.0];
        case 4: return [NSColor colorWithSRGBRed:0.16 green:0.50 blue:0.95 alpha:1.0];
        case 5: return [NSColor colorWithSRGBRed:0.10 green:0.10 blue:0.12 alpha:1.0];
        default: return [NSColor whiteColor];
    }
}
const int kSwatchCount = 6;

NSImage *SymbolImage(const char *name, const char *fallback) {
    if (@available(macOS 11.0, *)) {
        NSImage *img = [NSImage imageWithSystemSymbolName:@(name)
                                 accessibilityDescription:@(fallback)];
        if (img) return img;
    }
    return nil;
}

NSButton *MakeTextButton(NSString *title, id target, SEL action) {
    NSButton *b = [NSButton buttonWithTitle:title target:target action:action];
    b.bezelStyle = NSBezelStyleRounded;
    b.controlSize = NSControlSizeSmall;
    b.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    return b;
}

}  // namespace

@implementation SKToolPalette {
    NSSegmentedControl *_toolControl;
    NSColorWell *_colorWell;
    NSMutableArray<NSButton *> *_swatches;
    NSSlider *_sizeSlider;
    NSTextField *_sizeLabel;
    NSButton *_fillCheck;
    NSButton *_undoButton;
    NSButton *_redoButton;
    NSButton *_captureButton;
    NSButton *_copyButton;
    NSButton *_saveButton;
    NSBox *_separator;
}

+ (CGFloat)preferredHeight { return 46.0; }

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _tool = Tool::Arrow;
        _color = [NSColor colorWithSRGBRed:0.93 green:0.16 blue:0.16 alpha:1.0];
        _lineWidth = 6.0;
        _fontSize = 28.0;
        _fillShapes = NO;
        self.wantsLayer = YES;
        [self buildSubviews];
        [self layout];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)buildSubviews {
    _toolControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    _toolControl.segmentCount = kToolCount;
    _toolControl.segmentStyle = NSSegmentStyleTexturedRounded;
    _toolControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
    _toolControl.target = self;
    _toolControl.action = @selector(toolChanged:);
    for (int i = 0; i < kToolCount; ++i) {
        NSImage *img = SymbolImage(kTools[i].symbol, kTools[i].fallback);
        if (img) {
            [_toolControl setImage:img forSegment:i];
            [_toolControl setImageScaling:NSImageScaleProportionallyDown forSegment:i];
        } else {
            [_toolControl setLabel:@(kTools[i].fallback) forSegment:i];
        }
        [_toolControl setWidth:34 forSegment:i];
        [_toolControl setToolTip:@(kTools[i].tip) forSegment:i];
    }
    [self addSubview:_toolControl];
    [self syncToolControl];

    _swatches = [NSMutableArray array];
    for (int i = 0; i < kSwatchCount; ++i) {
        NSButton *b = [[NSButton alloc] initWithFrame:NSZeroRect];
        b.bordered = NO;
        b.title = @"";
        b.tag = i;
        b.target = self;
        b.action = @selector(swatchClicked:);
        b.wantsLayer = YES;
        b.layer.cornerRadius = 7.0;
        b.layer.backgroundColor = SwatchColor(i).CGColor;
        b.layer.borderWidth = 1.0;
        b.layer.borderColor = [NSColor colorWithWhite:0.0 alpha:0.18].CGColor;
        [self addSubview:b];
        [_swatches addObject:b];
    }

    _colorWell = [[NSColorWell alloc] initWithFrame:NSZeroRect];
    _colorWell.color = _color;
    _colorWell.target = self;
    _colorWell.action = @selector(colorChanged:);
    _colorWell.toolTip = @"Custom colour";
    [self addSubview:_colorWell];

    _sizeSlider = [NSSlider sliderWithValue:_lineWidth
                                   minValue:1.0
                                   maxValue:40.0
                                     target:self
                                     action:@selector(sizeChanged:)];
    _sizeSlider.controlSize = NSControlSizeSmall;
    _sizeSlider.continuous = YES;
    _sizeSlider.toolTip = @"Stroke width / text size";
    [self addSubview:_sizeSlider];

    _sizeLabel = [NSTextField labelWithString:@"6"];
    _sizeLabel.font = [NSFont monospacedDigitSystemFontOfSize:11
                                                       weight:NSFontWeightRegular];
    _sizeLabel.textColor = [NSColor secondaryLabelColor];
    _sizeLabel.alignment = NSTextAlignmentRight;
    [self addSubview:_sizeLabel];

    _fillCheck = [NSButton checkboxWithTitle:@"Fill"
                                      target:self
                                      action:@selector(fillChanged:)];
    _fillCheck.font = [NSFont systemFontOfSize:11];
    _fillCheck.toolTip = @"Fill rectangles and ellipses";
    [self addSubview:_fillCheck];

    _undoButton = MakeTextButton(@"⤺", self, @selector(undoClicked:));
    _undoButton.toolTip = @"Undo  (⌘Z)";
    [self addSubview:_undoButton];

    _redoButton = MakeTextButton(@"⤻", self, @selector(redoClicked:));
    _redoButton.toolTip = @"Redo  (⇧⌘Z)";
    [self addSubview:_redoButton];

    _separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    _separator.boxType = NSBoxSeparator;
    [self addSubview:_separator];

    _captureButton = MakeTextButton(@"Capture", self, @selector(captureClicked:));
    _captureButton.toolTip = @"New region capture  (⇧⌘4)";
    [self addSubview:_captureButton];

    _copyButton = MakeTextButton(@"Copy", self, @selector(copyClicked:));
    _copyButton.toolTip = @"Copy flattened image  (⌘C)";
    [self addSubview:_copyButton];

    _saveButton = MakeTextButton(@"Save…", self, @selector(saveClicked:));
    _saveButton.keyEquivalent = @"";
    _saveButton.toolTip = @"Save as PNG  (⌘S)";
    [self addSubview:_saveButton];

    [self updateSizeLabel];
}

// ------------------------------------------------------------- layout ----

// This view positions its children by hand, so re-run the pass on every frame
// change rather than waiting for AppKit's constraint-driven layout.
- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layout];
}

- (void)layout {
    [super layout];

    const CGFloat h = self.bounds.size.height;
    const CGFloat pad = 10.0;
    CGFloat x = pad;

    NSSize toolSize = _toolControl.intrinsicContentSize;
    if (toolSize.width < 10) toolSize.width = kToolCount * 34.0;
    if (toolSize.height < 10) toolSize.height = 24.0;
    _toolControl.frame = NSMakeRect(x, (h - toolSize.height) * 0.5, toolSize.width,
                                    toolSize.height);
    x = NSMaxX(_toolControl.frame) + 14;

    for (NSButton *b in _swatches) {
        b.frame = NSMakeRect(x, (h - 14) * 0.5, 14, 14);
        x += 18;
    }
    x += 4;

    _colorWell.frame = NSMakeRect(x, (h - 22) * 0.5, 34, 22);
    x = NSMaxX(_colorWell.frame) + 14;

    _sizeSlider.frame = NSMakeRect(x, (h - 20) * 0.5, 96, 20);
    x = NSMaxX(_sizeSlider.frame) + 4;

    _sizeLabel.frame = NSMakeRect(x, (h - 16) * 0.5, 24, 16);
    x = NSMaxX(_sizeLabel.frame) + 10;

    _fillCheck.frame = NSMakeRect(x, (h - 18) * 0.5, 46, 18);
    x = NSMaxX(_fillCheck.frame) + 10;

    _undoButton.frame = NSMakeRect(x, (h - 22) * 0.5, 30, 22);
    x = NSMaxX(_undoButton.frame) + 4;
    _redoButton.frame = NSMakeRect(x, (h - 22) * 0.5, 30, 22);

    // Right-aligned action cluster.
    CGFloat right = self.bounds.size.width - pad;
    _saveButton.frame = NSMakeRect(right - 62, (h - 22) * 0.5, 62, 22);
    right -= 62 + 6;
    _copyButton.frame = NSMakeRect(right - 52, (h - 22) * 0.5, 52, 22);
    right -= 52 + 6;
    _captureButton.frame = NSMakeRect(right - 68, (h - 22) * 0.5, 68, 22);

    _separator.frame = NSMakeRect(0, h - 1, self.bounds.size.width, 1);
}

- (void)drawRect:(NSRect)dirty {
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(dirty);
}

// ------------------------------------------------------------ accessors ---

- (void)setTool:(sk::Tool)tool {
    if (_tool == tool) return;
    _tool = tool;
    [self syncToolControl];
    [self updateSizeLabel];
    [self syncSliderForTool];
}

- (void)syncToolControl {
    for (int i = 0; i < kToolCount; ++i) {
        if (kTools[i].tool == _tool) {
            [_toolControl setSelectedSegment:i];
            return;
        }
    }
}

- (void)syncSliderForTool {
    if (_tool == Tool::Text) {
        _sizeSlider.minValue = 8.0;
        _sizeSlider.maxValue = 120.0;
        _sizeSlider.doubleValue = _fontSize;
    } else {
        _sizeSlider.minValue = 1.0;
        _sizeSlider.maxValue = 40.0;
        _sizeSlider.doubleValue = _lineWidth;
    }
    [self updateSizeLabel];
}

- (void)setColor:(NSColor *)color {
    _color = color ?: [NSColor redColor];
    _colorWell.color = _color;
}

- (void)setLineWidth:(CGFloat)lineWidth {
    _lineWidth = lineWidth;
    if (_tool != Tool::Text) _sizeSlider.doubleValue = lineWidth;
    [self updateSizeLabel];
}

- (void)setFontSize:(CGFloat)fontSize {
    _fontSize = fontSize;
    if (_tool == Tool::Text) _sizeSlider.doubleValue = fontSize;
    [self updateSizeLabel];
}

- (void)setFillShapes:(BOOL)fillShapes {
    _fillShapes = fillShapes;
    _fillCheck.state = fillShapes ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)updateSizeLabel {
    const CGFloat v = (_tool == Tool::Text) ? _fontSize : _lineWidth;
    _sizeLabel.stringValue = [NSString stringWithFormat:@"%.0f", v];
}

- (void)setUndoEnabled:(BOOL)undoEnabled redoEnabled:(BOOL)redoEnabled {
    _undoButton.enabled = undoEnabled;
    _redoButton.enabled = redoEnabled;
}

// -------------------------------------------------------------- actions ---

- (void)toolChanged:(id)sender {
    const NSInteger i = _toolControl.selectedSegment;
    if (i < 0 || i >= kToolCount) return;
    _tool = kTools[i].tool;
    [self syncSliderForTool];
    [self.delegate toolPaletteDidChangeTool:self];
}

- (void)swatchClicked:(NSButton *)sender {
    self.color = SwatchColor((int)sender.tag);
    [self.delegate toolPaletteDidChangeStyle:self];
}

- (void)colorChanged:(id)sender {
    _color = _colorWell.color;
    [self.delegate toolPaletteDidChangeStyle:self];
}

- (void)sizeChanged:(id)sender {
    if (_tool == Tool::Text) {
        _fontSize = _sizeSlider.doubleValue;
    } else {
        _lineWidth = _sizeSlider.doubleValue;
    }
    [self updateSizeLabel];
    [self.delegate toolPaletteDidChangeStyle:self];
}

- (void)fillChanged:(id)sender {
    _fillShapes = (_fillCheck.state == NSControlStateValueOn);
    [self.delegate toolPaletteDidChangeStyle:self];
}

- (void)captureClicked:(id)sender { [self.delegate toolPaletteDidRequestCapture:self]; }
- (void)copyClicked:(id)sender { [self.delegate toolPaletteDidRequestCopy:self]; }
- (void)saveClicked:(id)sender { [self.delegate toolPaletteDidRequestSave:self]; }
- (void)undoClicked:(id)sender { [self.delegate toolPaletteDidRequestUndo:self]; }
- (void)redoClicked:(id)sender { [self.delegate toolPaletteDidRequestRedo:self]; }

@end
