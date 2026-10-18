// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#include "model/Annotation.h"

namespace sk {

const char* toolName(Tool t) {
    switch (t) {
        case Tool::Select: return "Select";
        case Tool::Arrow: return "Arrow";
        case Tool::Line: return "Line";
        case Tool::Rect: return "Rectangle";
        case Tool::Ellipse: return "Ellipse";
        case Tool::Squircle: return "Squircle";
        case Tool::Pen: return "Pen";
        case Tool::Highlighter: return "Highlighter";
        case Tool::Text: return "Text";
        case Tool::Pixelate: return "Pixelate";
        case Tool::Redact: return "Redact";
        case Tool::Crop: return "Crop";
        default: return "?";
    }
}

bool toolCreatesAnnotation(Tool t) {
    return t != Tool::Select && t != Tool::Crop;
}

RectD Annotation::coreBounds() const {
    switch (tool) {
        case Tool::Pen:
        case Tool::Highlighter: {
            if (points.empty()) return RectD();
            double x0 = points[0].x, y0 = points[0].y, x1 = x0, y1 = y0;
            for (const Vec2& p : points) {
                x0 = std::min(x0, p.x);
                y0 = std::min(y0, p.y);
                x1 = std::max(x1, p.x);
                y1 = std::max(y1, p.y);
            }
            return RectD(x0, y0, x1 - x0, y1 - y0);
        }
        case Tool::Text: {
            const double w = measuredWidth > 0.0 ? measuredWidth : fontSize * 4.0;
            const double h = measuredHeight > 0.0 ? measuredHeight : fontSize * 1.3;
            return RectD(p0.x, p0.y, w, h);
        }
        default:
            return RectD::fromCorners(p0, p1);
    }
}

RectD Annotation::displayBounds() const {
    RectD b = coreBounds();
    if (tool == Tool::Text) return b.insetBy(4.0);
    if (tool == Tool::Pixelate || tool == Tool::Redact) return b;
    double pad = lineWidth * 0.5 + 1.0;
    if (tool == Tool::Arrow) pad = lineWidth * 2.5 + 1.0;
    return b.insetBy(pad);
}

bool Annotation::hitTest(const Vec2& p, double tolerance) const {
    const double tol = std::max(tolerance, lineWidth * 0.5 + 2.0);

    switch (tool) {
        case Tool::Arrow:
        case Tool::Line:
            return distanceToSegment(p, p0, p1) <= tol;

        case Tool::Pen:
        case Tool::Highlighter: {
            if (points.size() == 1) return (p - points[0]).length() <= tol;
            for (size_t i = 1; i < points.size(); ++i) {
                if (distanceToSegment(p, points[i - 1], points[i]) <= tol) return true;
            }
            return false;
        }

        case Tool::Rect: {
            const RectD b = RectD::fromCorners(p0, p1);
            if (filled) return b.insetBy(tol).contains(p);
            if (!b.insetBy(tol).contains(p)) return false;
            // Outline only: reject the hollow interior.
            const RectD inner(b.x + tol, b.y + tol,
                              std::max(0.0, b.w - 2 * tol), std::max(0.0, b.h - 2 * tol));
            return !inner.contains(p);
        }

        case Tool::Ellipse: {
            const RectD b = RectD::fromCorners(p0, p1);
            const Vec2 c = b.center();
            const double rx = std::max(b.w * 0.5, 1e-6);
            const double ry = std::max(b.h * 0.5, 1e-6);
            const double dx = (p.x - c.x), dy = (p.y - c.y);
            const double outer = (dx * dx) / ((rx + tol) * (rx + tol)) +
                                 (dy * dy) / ((ry + tol) * (ry + tol));
            if (outer > 1.0) return false;
            if (filled) return true;
            const double irx = std::max(rx - tol, 1e-6), iry = std::max(ry - tol, 1e-6);
            const double inner = (dx * dx) / (irx * irx) + (dy * dy) / (iry * iry);
            return inner >= 1.0;
        }

        case Tool::Squircle: {
            // Same scheme as the ellipse, on the degree-4 superellipse metric.
            const RectD b = RectD::fromCorners(p0, p1);
            const Vec2 c = b.center();
            const double rx = std::max(b.w * 0.5, 1e-6);
            const double ry = std::max(b.h * 0.5, 1e-6);
            const double dx = (p.x - c.x), dy = (p.y - c.y);
            auto metric = [&](double ax, double ay) {
                const double u = dx / ax, v = dy / ay;
                return u * u * u * u + v * v * v * v;
            };
            if (metric(rx + tol, ry + tol) > 1.0) return false;
            if (filled) return true;
            return metric(std::max(rx - tol, 1e-6), std::max(ry - tol, 1e-6)) >= 1.0;
        }

        case Tool::Pixelate:
        case Tool::Redact:
            return RectD::fromCorners(p0, p1).contains(p);

        case Tool::Text:
            return coreBounds().insetBy(4.0).contains(p);

        default:
            return false;
    }
}

void Annotation::translate(const Vec2& d) {
    p0 = p0 + d;
    p1 = p1 + d;
    for (Vec2& pt : points) pt = pt + d;
}

void Annotation::transformFromRectToRect(const RectD& from, const RectD& to) {
    if (from.w <= 1e-9 || from.h <= 1e-9) return;
    const double sx = to.w / from.w;
    const double sy = to.h / from.h;

    auto map = [&](const Vec2& v) {
        return Vec2{to.x + (v.x - from.x) * sx, to.y + (v.y - from.y) * sy};
    };

    p0 = map(p0);
    p1 = map(p1);
    for (Vec2& pt : points) pt = map(pt);

    if (tool == Tool::Text) {
        fontSize = std::max(6.0, fontSize * std::min(sx, sy));
        measuredWidth = measuredHeight = 0.0;
    } else {
        lineWidth = std::max(1.0, lineWidth * std::min(std::fabs(sx), std::fabs(sy)));
    }
}

}  // namespace sk
