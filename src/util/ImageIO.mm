// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#import "util/ImageIO.h"

#import <ImageIO/ImageIO.h>

static CFStringRef UTTypeForURL(NSURL *url) {
    NSString *ext = url.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) return CFSTR("public.jpeg");
    if ([ext isEqualToString:@"tif"] || [ext isEqualToString:@"tiff"]) return CFSTR("public.tiff");
    if ([ext isEqualToString:@"heic"]) return CFSTR("public.heic");
    if ([ext isEqualToString:@"gif"]) return CFSTR("com.compuserve.gif");
    return CFSTR("public.png");
}

BOOL SKWriteImage(CGImageRef image, NSURL *url, NSError **error) {
    if (!image || !url) {
        if (error) {
            *error = [NSError errorWithDomain:@"Skitch"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey : @"Nothing to save."}];
        }
        return NO;
    }

    CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)url, UTTypeForURL(url), 1, NULL);
    if (!dest) {
        if (error) {
            *error = [NSError
                errorWithDomain:@"Skitch"
                           code:2
                       userInfo:@{NSLocalizedDescriptionKey : @"Unsupported image format."}];
        }
        return NO;
    }

    NSDictionary *props = @{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality : @0.92};
    CGImageDestinationAddImage(dest, image, (__bridge CFDictionaryRef)props);
    const BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);

    if (!ok && error) {
        *error = [NSError errorWithDomain:@"Skitch"
                                     code:3
                                 userInfo:@{NSLocalizedDescriptionKey : @"Could not write the file."}];
    }
    return ok;
}

CGImageRef SKReadImage(NSURL *url) {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return NULL;
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    return img;
}

void SKCopyImageToPasteboard(CGImageRef image) {
    if (!image) return;

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    rep.size = NSMakeSize(CGImageGetWidth(image), CGImageGetHeight(image));

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];

    NSMutableArray *items = [NSMutableArray array];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    if (png) [item setData:png forType:NSPasteboardTypePNG];
    NSData *tiff = [rep TIFFRepresentation];
    if (tiff) [item setData:tiff forType:NSPasteboardTypeTIFF];
    [items addObject:item];

    [pb writeObjects:items];
}

CGImageRef SKImageFromPasteboard(void) {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];

    NSArray *objects = [pb readObjectsForClasses:@[ [NSImage class] ] options:nil];
    NSImage *img = objects.firstObject;
    if (!img) return NULL;

    NSRect proposed = NSMakeRect(0, 0, img.size.width, img.size.height);
    CGImageRef cg = [img CGImageForProposedRect:&proposed context:nil hints:nil];
    return cg ? CGImageRetain(cg) : NULL;
}

NSString *SKSuggestedFileName(void) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    return [NSString stringWithFormat:@"Screenshot %@.png", [fmt stringFromDate:[NSDate date]]];
}
