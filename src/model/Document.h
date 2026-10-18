// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
// The editable state of one capture: the annotation list, the crop window and
// an undo history. The pixels themselves live in a CGImage owned by the UI
// layer; this class only ever refers to them by size and crop rectangle, which
// keeps crop fully undoable without duplicating bitmaps.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

#include "model/Annotation.h"

namespace sk {

class Document {
public:
    Document() = default;

    // ---- lifecycle -------------------------------------------------------

    // `w`/`h` are the pixel dimensions of the underlying base image.
    void reset(double w, double h);

    double baseWidth() const { return baseWidth_; }
    double baseHeight() const { return baseHeight_; }

    // Visible region of the base image, in base-image pixels.
    const RectD& cropRect() const { return state_.crop; }
    // Size of the document as the user sees it (i.e. after cropping).
    double width() const { return state_.crop.w; }
    double height() const { return state_.crop.h; }

    // Document space (origin at the crop's top-left) <-> base-image space.
    Vec2 toBase(const Vec2& p) const { return {p.x + state_.crop.x, p.y + state_.crop.y}; }
    Vec2 fromBase(const Vec2& p) const { return {p.x - state_.crop.x, p.y - state_.crop.y}; }

    // ---- annotations -----------------------------------------------------

    const std::vector<Annotation>& items() const { return state_.items; }
    std::size_t count() const { return state_.items.size(); }

    // Adds `a` (which must be expressed in base-image coordinates) and returns
    // its assigned id.
    int add(const Annotation& a);
    bool remove(int id);
    void clear();

    Annotation* find(int id);
    const Annotation* find(int id) const;

    // Topmost annotation whose geometry contains `p` (base-image coords).
    int hitTest(const Vec2& p, double tolerance) const;

    bool raise(int id);
    bool lower(int id);

    // ---- crop ------------------------------------------------------------

    // `r` is given in the current document space; it is composed onto the
    // existing crop and clamped to the base image.
    void applyCrop(const RectD& r);
    // Returns false, changing nothing, when the full frame is already showing.
    bool resetCrop();

    /// True when the crop shows less than the whole base image.
    bool isCropped() const;

    // ---- revert ----------------------------------------------------------

    /// True when anything has been drawn or cropped away from the capture.
    bool hasEdits() const;

    /// Back to the pristine capture: no annotations, no crop.
    void revert();

    // ---- undo ------------------------------------------------------------

    // Call before any mutation that should be undoable as a single step.
    void beginUndoGroup();
    // Discards the group pushed by the most recent beginUndoGroup() when the
    // edit turned out to be a no-op (e.g. a click that moved nothing).
    void abortUndoGroup();
    // Closes the open group once its edit has landed, so a later stray
    // abortUndoGroup() cannot roll back work that was already committed.
    void endUndoGroup();

    bool canUndo() const { return !undo_.empty(); }
    bool canRedo() const { return !redo_.empty(); }
    void undo();
    void redo();

    // Dirty means "differs from the last markClean()", so undoing back to the
    // saved state reads as clean again.
    bool isDirty() const { return state_.rev != cleanRev_; }
    void markClean() { cleanRev_ = state_.rev; }

private:
    struct State {
        std::vector<Annotation> items;
        RectD crop;
        int nextId = 1;
        // Identifies this exact state; snapshots carry theirs through undo.
        std::uint64_t rev = 0;
    };

    // Gives the current state a revision no snapshot shares.
    void touch() { state_.rev = nextRev_++; }

    State state_;
    std::vector<State> undo_;
    std::vector<State> redo_;
    // Parked during an open group so an aborted edit can put it back.
    std::vector<State> savedRedo_;
    bool groupOpen_ = false;
    std::uint64_t nextRev_ = 1;
    std::uint64_t cleanRev_ = 0;
    double baseWidth_ = 0.0;
    double baseHeight_ = 0.0;

    static constexpr std::size_t kMaxUndo = 128;
};

}  // namespace sk
