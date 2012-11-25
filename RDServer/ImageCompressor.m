//
//  ImageCompressor.m
//  RDServer
//
//  Created by Rohan Shah on 7/17/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ImageCompressor.h"
#import "../pngquant/pngquant.h"
#import "AppUtils.h"
#import "turbojpeg.h"

static NSData *make_jpeg(NSBitmapImageRep *imageRep) {
    return [imageRep representationUsingType:NSJPEGFileType 
                                  properties:[NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:0.0] 
                                                                         forKey:NSImageCompressionFactor]];
}


static NSData *turbo_make_jpeg(NSBitmapImageRep *imageRep, CGImageRef image) {
    NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
    tjhandle turboJpeg;
    if(![[threadDict objectForKey:@"RD_turboJpegInitialized"] boolValue]) {
        turboJpeg = tjInitCompress();
        [threadDict setObject:[NSNumber numberWithLong:(long)turboJpeg] forKey:@"RD_turboJpeg"];
        [threadDict setObject:[NSNumber numberWithBool:YES] forKey:@"RD_turboJpegInitialized"];
    } else {
        turboJpeg = (tjhandle)[[threadDict objectForKey:@"RD_turboJpeg"] longValue];
    }
    
    
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    size_t bufferSize = TJBUFSIZE((int)width, (int)height);
    unsigned char *buffer = malloc(bufferSize);
    unsigned long size = 0;
    NSBitmapFormat format = [imageRep bitmapFormat];
    BOOL alphaFirst = (format & NSAlphaFirstBitmapFormat);
    
    tjCompress(turboJpeg, 
               [imageRep bitmapData], // source buffer 
               (int)width, // width
               0, // pitch, which is weird. see tJ docs. 
               (int)height, 
               (int)CGImageGetBitsPerPixel(image)/8, 
               buffer,
               &size, 
               TJ_420, // lowest quality subsampling option; see tJ docs 
               50, // quality value 
               (alphaFirst ? TJ_ALPHAFIRST : 0) // flags
               );
    
    return [NSData dataWithBytes:buffer length:size];
    free(buffer);
}

static NSData *make_png24(NSBitmapImageRep *imageRep) {
    return [imageRep representationUsingType:NSPNGFileType properties:nil];
}

static NSData *make_png8(NSBitmapImageRep *imageRep) {
    NSData *png24 = make_png24(imageRep);
    NSData *png8 = nil;
    int reqcolors = 8;
    int retval = new_pngquant([png24 bytes], &png8, 0, reqcolors, 0);
    
    if(retval != 0) {
        NSError *error = [NSError errorWithDomain:@"pngquant" code:retval userInfo:nil];
        [AppUtils handleError:error context:@"sendScreenUpdates"];
    }

    return png8;
}


NSData *compressImage(CGImageRef image) {
    NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSData *result = turbo_make_jpeg(imageRep, image);
    [imageRep release];
    return result;
}