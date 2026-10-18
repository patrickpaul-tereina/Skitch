# SPDX-FileCopyrightText: 2026 Kunkka
# SPDX-License-Identifier: GPL-2.0-only
cmake_minimum_required(VERSION 3.20)

project(Skitch
        VERSION 1.0.0
        DESCRIPTION "Screenshot capture and annotation"
        LANGUAGES C CXX)

# The GUI, capture and rendering layers are Cocoa/CoreGraphics and cannot build
# off macOS. The document model is plain C++ and builds anywhere, so other
# platforms configure that core plus its tests instead of failing outright.
# OBJCXX is enabled below rather than in project(), because naming it there
# would abort configuration on Linux and Windows before anything else runs.
option(SKITCH_CORE_ONLY "Build only the portable core, even on macOS" OFF)
option(SKITCH_BUILD_TESTS "Build the test suite" ON)

if(APPLE AND NOT SKITCH_CORE_ONLY)
    set(SKITCH_BUILD_APP ON)
    enable_language(OBJCXX)
else()
    set(SKITCH_BUILD_APP OFF)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(SKITCH_BUILD_APP)
    set(CMAKE_OBJCXX_STANDARD 17)
    set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
endif()

if(APPLE AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "Minimum macOS version" FORCE)
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# /utf-8 is not optional on MSVC: these sources contain UTF-8 punctuation.
if(MSVC)
    set(SKITCH_WARNINGS /W4 /permissive- /utf-8)
else()
    set(SKITCH_WARNINGS -Wall -Wextra -Wno-unused-parameter)
endif()

set(APP_NAME        "Skitch")
set(APP_BUNDLE_ID   "com.skitch.app")
# Shown in the About box, via NSHumanReadableCopyright.
set(APP_COPYRIGHT   "Copyright © 2026 Kunkka. Licensed under the GNU General Public License, version 2.")

# ----------------------------------------------------------- portable core ---
# Annotation and Document pull in no platform headers, so this library compiles
# on macOS, Linux and Windows alike. Every other target builds on it.

add_library(skitch_core STATIC
    src/model/Annotation.cpp
    src/model/Document.cpp
    src/model/Types.h
    src/model/Annotation.h
    src/model/Document.h
)
target_include_directories(skitch_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_features(skitch_core PUBLIC cxx_std_17)
target_compile_options(skitch_core PRIVATE ${SKITCH_WARNINGS})
set_target_properties(skitch_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

# ------------------------------------------------------------------- tests ---

if(SKITCH_BUILD_TESTS)
    enable_testing()

    # Portable: no platform headers, runs everywhere skitch_core builds.
    add_executable(skitch_core_tests tests/core_tests.cpp)
    target_link_libraries(skitch_core_tests PRIVATE skitch_core)
    target_compile_options(skitch_core_tests PRIVATE ${SKITCH_WARNINGS})
    add_test(NAME core COMMAND skitch_core_tests)
endif()

if(NOT SKITCH_BUILD_APP)
    message(STATUS "Skitch: GUI is macOS-only (Cocoa/CoreGraphics); "
                   "configured the portable core and its tests only.")

    # ------------------------------------------------------ packaging the core
    # With no app to ship on these platforms, the library and its headers are
    # what a release can offer. The GPL makes shipping LICENSE alongside them a
    # requirement, not a courtesy.
    #
    # Deliberately inside this branch. The macOS build forces the install prefix
    # to /Applications so `cmake --install` drops the bundle where it belongs,
    # and scattering lib/ and include/ through /Applications would be wrong.
    include(GNUInstallDirs)

    install(TARGETS skitch_core
            ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})

    install(FILES
                src/model/Types.h
                src/model/Annotation.h
                src/model/Document.h
            DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/skitch/model)

    install(FILES LICENSE README.md packaging/USING-THE-CORE.md
            DESTINATION ${CMAKE_INSTALL_DOCDIR})

    return()
endif()

# ==================================================== macOS-only from here ====

# ---------------------------------------------------------------- sources ---

set(SKITCH_SOURCES
    src/main.mm

    src/render/Renderer.mm

    src/capture/ScreenCapture.mm
    src/capture/OverlayWindow.mm
    src/capture/CountdownWindow.mm

    src/ui/AppDelegate.mm
    src/ui/EditorWindowController.mm
    src/ui/CanvasView.mm
    src/ui/ToolPalette.mm

    src/util/ImageIO.mm
    src/util/Hotkeys.mm
)

set(SKITCH_HEADERS
    src/render/Renderer.h
    src/capture/ScreenCapture.h
    src/capture/OverlayWindow.h
    src/capture/CountdownWindow.h
    src/ui/AppDelegate.h
    src/ui/EditorWindowController.h
    src/ui/CanvasView.h
    src/ui/ToolPalette.h
    src/util/ImageIO.h
    src/util/Hotkeys.h
)

add_executable(Skitch MACOSX_BUNDLE ${SKITCH_SOURCES} ${SKITCH_HEADERS})

target_include_directories(Skitch PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_compile_options(Skitch PRIVATE
    ${SKITCH_WARNINGS}
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
)

# ------------------------------------------------------------- frameworks ---

target_link_libraries(Skitch PRIVATE
    skitch_core
    "-framework Cocoa"
    "-framework CoreGraphics"
    "-framework CoreText"
    "-framework CoreImage"
    "-framework ImageIO"
    "-framework QuartzCore"
    "-framework ApplicationServices"
    "-framework Carbon"
    "-framework UniformTypeIdentifiers"
    # Weak: it first shipped in 12.3, above the 12.0 deployment target, and is
    # only called on 14+ (see ScreenCapture.mm).
    "-Wl,-weak_framework,ScreenCaptureKit"
)

# ------------------------------------------------------------------ icon ---
# The icon is generated rather than checked in: a small host tool draws it with
# CoreGraphics at every native size and writes the .icns container itself.

# The artwork is self-contained CoreGraphics — it draws no annotations, so the
# tool needs none of the app's own sources.
add_executable(skitch_iconmaker tools/make_icon.mm)
target_compile_options(skitch_iconmaker PRIVATE
    ${SKITCH_WARNINGS}
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_link_libraries(skitch_iconmaker PRIVATE
    "-framework Foundation" "-framework CoreGraphics" "-framework ImageIO")

set(SKITCH_ICONSET "${CMAKE_CURRENT_BINARY_DIR}/${APP_NAME}.iconset")
set(SKITCH_ICNS "${CMAKE_CURRENT_BINARY_DIR}/${APP_NAME}.icns")

add_custom_command(
    OUTPUT ${SKITCH_ICNS}
    COMMAND skitch_iconmaker ${SKITCH_ICNS} ${SKITCH_ICONSET}
    DEPENDS skitch_iconmaker
    COMMENT "Generating ${APP_NAME}.icns"
    VERBATIM)
add_custom_target(skitch_icon DEPENDS ${SKITCH_ICNS})
add_dependencies(Skitch skitch_icon)

set(APP_ICON_FILE "${APP_NAME}")
target_sources(Skitch PRIVATE ${SKITCH_ICNS})
set_source_files_properties(${SKITCH_ICNS} PROPERTIES
    GENERATED TRUE
    MACOSX_PACKAGE_LOCATION "Resources")

# ----------------------------------------------------------- app bundling ---
# Configured after the icon block so CFBundleIconFile reflects APP_ICON_FILE.

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/resources/Info.plist.in
               ${CMAKE_CURRENT_BINARY_DIR}/Info.plist @ONLY)

set_target_properties(Skitch PROPERTIES
    OUTPUT_NAME "${APP_NAME}"
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_BINARY_DIR}/Info.plist
)

# An ad-hoc signature keeps the bundle's identity stable so macOS remembers the
# Screen Recording grant between rebuilds instead of re-prompting every time.
#
# --options runtime turns on the hardened runtime. Without it, anything running
# as the user could start Skitch with DYLD_INSERT_LIBRARIES and inherit its
# Screen Recording grant without a prompt. The app needs no exception
# entitlements: no JIT, no unsigned plug-ins, no injected libraries.
add_custom_command(TARGET Skitch POST_BUILD
    COMMAND codesign --force --sign - --timestamp=none --options runtime
            "$<TARGET_BUNDLE_DIR:Skitch>"
    COMMENT "Ad-hoc signing ${APP_NAME}.app"
    VERBATIM)

# -------------------------------------------------------------- installing ---
# `cmake --install build` drops the bundle into /Applications by default;
# override with `--prefix ~/Applications` to install somewhere you own.

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "/Applications" CACHE PATH "Install location" FORCE)
endif()

install(TARGETS Skitch BUNDLE DESTINATION ".")

# Convenience targets around the packaging scripts. These replace an existing
# copy and build a drag-to-install disk image respectively.
add_custom_target(install-app
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/scripts/install.sh" "$<TARGET_BUNDLE_DIR:Skitch>"
    DEPENDS Skitch
    COMMENT "Installing Skitch.app into /Applications"
    USES_TERMINAL
    VERBATIM)

add_custom_target(dmg
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/scripts/make-dmg.sh"
            "$<TARGET_BUNDLE_DIR:Skitch>" "${CMAKE_CURRENT_BINARY_DIR}"
    DEPENDS Skitch
    COMMENT "Building the Skitch disk image"
    USES_TERMINAL
    VERBATIM)

# ------------------------------------------------------------------ tests ---

if(SKITCH_BUILD_TESTS)
    add_executable(skitch_render_smoke
        tests/render_smoke.mm
        src/render/Renderer.mm
        src/util/ImageIO.mm
    )
    target_compile_options(skitch_render_smoke PRIVATE
        ${SKITCH_WARNINGS}
        $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
    target_link_libraries(skitch_render_smoke PRIVATE
        skitch_core
        "-framework Cocoa" "-framework CoreGraphics" "-framework CoreText"
        "-framework ImageIO")

    add_test(NAME render_smoke
             COMMAND skitch_render_smoke "${CMAKE_CURRENT_BINARY_DIR}/smoke.png")

    # Exercises the hide/restore of our own windows around a capture. Touches
    # only NSWindow bookkeeping, so it runs without a window server.
    add_executable(skitch_capture_hide_test
        tests/capture_hide_test.mm
        src/capture/ScreenCapture.mm
    )
    # The capture layer is standalone — it does not use the document model — so
    # this target needs the include root without linking skitch_core for it.
    target_include_directories(skitch_capture_hide_test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_compile_options(skitch_capture_hide_test PRIVATE
        ${SKITCH_WARNINGS}
        $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
    target_link_libraries(skitch_capture_hide_test PRIVATE
        "-framework Cocoa" "-framework CoreGraphics"
        "-Wl,-weak_framework,ScreenCaptureKit")

    add_test(NAME capture_hide COMMAND skitch_capture_hide_test)
endif()
