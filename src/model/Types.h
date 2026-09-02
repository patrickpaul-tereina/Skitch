// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
// Basic geometry / colour value types. Pure C++, no platform headers so the
// document model stays testable and free of Cocoa.
#pragma once

#include <algorithm>
#include <cmath>

namespace sk {

struct Vec2 {
    double x = 0.0;
    double y = 0.0;

    Vec2() = default;
    Vec2(double xx, double yy) : x(xx), y(yy) {}

    Vec2 operator+(const Vec2& o) const { return {x + o.x, y + o.y}; }
    Vec2 operator-(const Vec2& o) const { return {x - o.x, y - o.y}; }
    Vec2 operator*(double s) const { return {x * s, y * s}; }

    double length() const { return std::sqrt(x * x + y * y); }

    Vec2 normalized() const {
        const double l = length();
        return l > 1e-9 ? Vec2{x / l, y / l} : Vec2{0.0, 0.0};
    }

    // Rotate 90 degrees counter-clockwise (the perpendicular used for arrows).
    Vec2 perp() const { return {-y, x}; }
};

struct RectD {
    double x = 0.0;
    double y = 0.0;
    double w = 0.0;
    double h = 0.0;

    RectD() = default;
    RectD(double xx, double yy, double ww, double hh) : x(xx), y(yy), w(ww), h(hh) {}

    static RectD fromCorners(const Vec2& a, const Vec2& b) {
        return RectD(std::min(a.x, b.x), std::min(a.y, b.y),
                     std::fabs(b.x - a.x), std::fabs(b.y - a.y));
    }

    double minX() const { return x; }
    double minY() const { return y; }
    double maxX() const { return x + w; }
    double maxY() const { return y + h; }
    Vec2 center() const { return {x + w * 0.5, y + h * 0.5}; }
    bool isEmpty() const { return w <= 0.0 || h <= 0.0; }

    bool contains(const Vec2& p) const {
        return p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h;
    }

    RectD insetBy(double d) const { return RectD(x - d, y - d, w + 2 * d, h + 2 * d); }

    RectD unionWith(const RectD& o) const {
        if (isEmpty()) return o;
        if (o.isEmpty()) return *this;
        const double x0 = std::min(minX(), o.minX());
        const double y0 = std::min(minY(), o.minY());
        const double x1 = std::max(maxX(), o.maxX());
        const double y1 = std::max(maxY(), o.maxY());
        return RectD(x0, y0, x1 - x0, y1 - y0);
    }

    RectD intersect(const RectD& o) const {
        const double x0 = std::max(minX(), o.minX());
        const double y0 = std::max(minY(), o.minY());
        const double x1 = std::min(maxX(), o.maxX());
        const double y1 = std::min(maxY(), o.maxY());
        if (x1 <= x0 || y1 <= y0) return RectD();
        return RectD(x0, y0, x1 - x0, y1 - y0);
    }
};

struct Color {
    double r = 0.0;
    double g = 0.0;
    double b = 0.0;
    double a = 1.0;

    Color() = default;
    Color(double rr, double gg, double bb, double aa = 1.0) : r(rr), g(gg), b(bb), a(aa) {}

    Color withAlpha(double aa) const { return Color(r, g, b, aa); }
};

inline double clampd(double v, double lo, double hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

// Shortest distance from p to the segment ab.
inline double distanceToSegment(const Vec2& p, const Vec2& a, const Vec2& b) {
    const Vec2 ab = b - a;
    const double len2 = ab.x * ab.x + ab.y * ab.y;
    if (len2 < 1e-9) return (p - a).length();
    double t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len2;
    t = clampd(t, 0.0, 1.0);
    const Vec2 proj{a.x + ab.x * t, a.y + ab.y * t};
    return (p - proj).length();
}

}  // namespace sk
