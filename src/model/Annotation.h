// One drawable mark on top of the captured image. Everything the renderer and
// the hit-tester need lives here; the type is a plain value so undo can be
// implemented by copying whole vectors.
#pragma once

#include <string>
#include <vector>

#include "model/Types.h"

namespace sk {

enum class Tool {
    Select = 0,
    Arrow,
    Line,
    Rect,
    Ellipse,
    Pen,
    Highlighter,
    Text,
    Pixelate,
    Crop,
    Count
};

const char* toolName(Tool t);
bool toolCreatesAnnotation(Tool t);

// Which of the eight resize grips (or none) a point is over.
enum class Grip {
    None = -1,
    TopLeft = 0,
    Top,
    TopRight,
    Right,
    BottomRight,
    Bottom,
    BottomLeft,
    Left,
    // Line-like shapes expose their two endpoints instead of a box.
    Start,
    End
};

struct Annotation {
    int id = 0;
    Tool tool = Tool::Arrow;

    Color stroke{0.93, 0.16, 0.16, 1.0};
    Color fill{1.0, 1.0, 1.0, 0.0};
    double lineWidth = 6.0;
    bool filled = false;

    // Line-like and box-like shapes: two defining corners / endpoints.
    Vec2 p0;
    Vec2 p1;

    // Freehand strokes.
    std::vector<Vec2> points;

    // Text.
    std::string text;
    double fontSize = 28.0;
    // Cached measurement filled in by the renderer so hit-testing knows how big
    // the laid-out text actually is.
    mutable double measuredWidth = 0.0;
    mutable double measuredHeight = 0.0;

    // Pixelate block size in image pixels.
    double blockSize = 12.0;

    bool isLineLike() const { return tool == Tool::Arrow || tool == Tool::Line; }
    bool isBoxLike() const {
        return tool == Tool::Rect || tool == Tool::Ellipse || tool == Tool::Pixelate;
    }
    bool isFreehand() const { return tool == Tool::Pen || tool == Tool::Highlighter; }

    // Tight geometric bounds, ignoring stroke width.
    RectD coreBounds() const;
    // Bounds padded for stroke width / arrow heads; what the UI draws around.
    RectD displayBounds() const;

    bool hitTest(const Vec2& p, double tolerance) const;

    void translate(const Vec2& d);
    // Map the annotation from `from` onto `to` (used by resize handles + crop).
    void transformFromRectToRect(const RectD& from, const RectD& to);
};

}  // namespace sk
