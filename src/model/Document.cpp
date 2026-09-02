// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#include "model/Document.h"

#include <algorithm>

namespace sk {

void Document::reset(double w, double h) {
    state_ = State();
    state_.crop = RectD(0, 0, w, h);
    baseWidth_ = w;
    baseHeight_ = h;
    undo_.clear();
    redo_.clear();
    groupOpen_ = false;
    dirty_ = false;
}

int Document::add(const Annotation& a) {
    Annotation copy = a;
    copy.id = state_.nextId++;
    state_.items.push_back(copy);
    dirty_ = true;
    return copy.id;
}

bool Document::remove(int id) {
    auto it = std::find_if(state_.items.begin(), state_.items.end(),
                           [id](const Annotation& a) { return a.id == id; });
    if (it == state_.items.end()) return false;
    state_.items.erase(it);
    dirty_ = true;
    return true;
}

void Document::clear() {
    if (state_.items.empty()) return;
    state_.items.clear();
    dirty_ = true;
}

Annotation* Document::find(int id) {
    for (Annotation& a : state_.items) {
        if (a.id == id) return &a;
    }
    return nullptr;
}

const Annotation* Document::find(int id) const {
    for (const Annotation& a : state_.items) {
        if (a.id == id) return &a;
    }
    return nullptr;
}

int Document::hitTest(const Vec2& p, double tolerance) const {
    for (auto it = state_.items.rbegin(); it != state_.items.rend(); ++it) {
        if (it->hitTest(p, tolerance)) return it->id;
    }
    return 0;
}

bool Document::raise(int id) {
    auto it = std::find_if(state_.items.begin(), state_.items.end(),
                           [id](const Annotation& a) { return a.id == id; });
    if (it == state_.items.end() || it + 1 == state_.items.end()) return false;
    std::iter_swap(it, it + 1);
    dirty_ = true;
    return true;
}

bool Document::lower(int id) {
    auto it = std::find_if(state_.items.begin(), state_.items.end(),
                           [id](const Annotation& a) { return a.id == id; });
    if (it == state_.items.end() || it == state_.items.begin()) return false;
    std::iter_swap(it, it - 1);
    dirty_ = true;
    return true;
}

void Document::applyCrop(const RectD& r) {
    // r arrives in document space; compose it onto the current crop.
    RectD next(state_.crop.x + r.x, state_.crop.y + r.y, r.w, r.h);
    next = next.intersect(RectD(0, 0, baseWidth_, baseHeight_));
    if (next.w < 1.0 || next.h < 1.0) return;
    state_.crop = next;
    dirty_ = true;
}

void Document::resetCrop() {
    state_.crop = RectD(0, 0, baseWidth_, baseHeight_);
    dirty_ = true;
}

bool Document::hasEdits() const {
    if (!state_.items.empty()) return true;
    return state_.crop.x != 0.0 || state_.crop.y != 0.0 ||
           state_.crop.w != baseWidth_ || state_.crop.h != baseHeight_;
}

void Document::revert() {
    state_.items.clear();
    state_.crop = RectD(0, 0, baseWidth_, baseHeight_);
    dirty_ = true;
}

void Document::beginUndoGroup() {
    undo_.push_back(state_);
    if (undo_.size() > kMaxUndo) undo_.erase(undo_.begin());
    // Park rather than drop: a gesture that turns out to be a no-op calls
    // abortUndoGroup(), and that must not have cost the user their redo stack.
    savedRedo_ = std::move(redo_);
    redo_.clear();
    groupOpen_ = true;
}

void Document::abortUndoGroup() {
    if (!groupOpen_ || undo_.empty()) return;
    state_ = undo_.back();
    undo_.pop_back();
    redo_ = std::move(savedRedo_);
    savedRedo_.clear();
    groupOpen_ = false;
}

void Document::undo() {
    if (undo_.empty()) return;
    redo_.push_back(state_);
    state_ = undo_.back();
    undo_.pop_back();
    groupOpen_ = false;
    dirty_ = true;
}

void Document::redo() {
    if (redo_.empty()) return;
    undo_.push_back(state_);
    state_ = redo_.back();
    redo_.pop_back();
    groupOpen_ = false;
    dirty_ = true;
}

}  // namespace sk
