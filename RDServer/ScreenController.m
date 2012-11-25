//
//  ScreenController.m
//  RDServer
//
//  Created by Rohan Shah on 7/12/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ScreenController.h"
#import "AppUtils.h"
#import "ProtocolConstants.h"

#define SMALL_SCREEN_WIDTH 1024
#define SMALL_SCREEN_HEIGHT 600

struct screenMode {
    size_t width;
    size_t height;
    size_t bitsPerPixel;
};

static RDScreenRes originalResolution = {0,0};
static BOOL originalResolutionSet = NO;

RDScreenRes ScreenResMake(NSUInteger width, NSUInteger height) {
    RDScreenRes res = {width, height};
    return res;
}

BOOL ScreenResEqual(RDScreenRes res1, RDScreenRes res2) {
    return ((res1.width == res2.width) && (res1.height == res2.height));
}

@interface ScreenController ()

+(void)setOriginalResolution;
+(size_t)displayBitsPerPixelForMode:(CGDisplayModeRef)mode;
+(CGDisplayModeRef)copyBestMatchForMode:(struct screenMode)screenMode;
+(void)changeResolutionTo:(RDScreenRes)resolution;

@end

@implementation ScreenController

#pragma mark - Screen resolution

+(RDScreenRes)currentResolution {
    NSUInteger width = (NSUInteger)[[NSScreen mainScreen] frame].size.width;
    NSUInteger height = (NSUInteger)[[NSScreen mainScreen] frame].size.height;
    
    RDScreenRes res = {width,height};
    return res;
}

+(void)setOriginalResolution {
    if(!originalResolutionSet) {
        originalResolution = [self currentResolution];
        originalResolutionSet = YES;
    }
}

+(void)changeResolution {
    @synchronized(self) {
        [self setOriginalResolution];

        [self changeResolutionTo:ScreenResMake(SMALL_SCREEN_WIDTH, SMALL_SCREEN_HEIGHT)];
    }
}

+(void)restoreOriginalResolution {
    @synchronized(self) {
        [self setOriginalResolution];
        
        [AppUtils log:FORMAT(@"Restoring original resolution: (%i,%i)...",originalResolution.width,originalResolution.height)];
        [self changeResolutionTo:originalResolution];
    }
}

#pragma mark Actually changing the resolution

+(size_t)displayBitsPerPixelForMode:(CGDisplayModeRef)mode {
    
	size_t depth = 0;
    
	CFStringRef pixEnc = CGDisplayModeCopyPixelEncoding(mode);
	if(CFStringCompare(pixEnc, CFSTR(IO32BitDirectPixels), kCFCompareCaseInsensitive) == kCFCompareEqualTo)
		depth = 32;
	else if(CFStringCompare(pixEnc, CFSTR(IO16BitDirectPixels), kCFCompareCaseInsensitive) == kCFCompareEqualTo)
		depth = 16;
	else if(CFStringCompare(pixEnc, CFSTR(IO8BitIndexedPixels), kCFCompareCaseInsensitive) == kCFCompareEqualTo)
		depth = 8;
    
    CFRelease(pixEnc);
	return depth;
}

+(CGDisplayModeRef)copyBestMatchForMode:(struct screenMode)screenMode {
    
	bool match = false;
    
    // Get a copy of the current display mode
	CGDisplayModeRef displayMode = CGDisplayCopyDisplayMode(kCGDirectMainDisplay);
    
    // Loop through all display modes to determine the closest match.
    // CGDisplayBestModeForParameters is deprecated on 10.6 so we will emulate it's behavior
    // Try to find a mode with the requested depth and equal or greater dimensions first.
    // If no match is found, try to find a mode with greater depth and same or greater dimensions.
    // If still no match is found, just use the current mode.
    CFArrayRef allModes = CGDisplayCopyAllDisplayModes(kCGDirectMainDisplay, NULL);
    
    
    for(int i = 0; i < CFArrayGetCount(allModes); i++)	{
		CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(allModes, i);
        
		if([self displayBitsPerPixelForMode: mode] != screenMode.bitsPerPixel)
			continue;
        
		if((CGDisplayModeGetWidth(mode) == screenMode.width) && (CGDisplayModeGetHeight(mode) == screenMode.height))
		{
            CGDisplayModeRelease(displayMode);
            CGDisplayModeRetain(mode);
			displayMode = mode;
			match = true;
			break;
		}
	}
    
    if(!match) {
        for(int i = 0; i < CFArrayGetCount(allModes); i++)	{
            CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(allModes, i);
            
            if([self displayBitsPerPixelForMode: mode] != screenMode.bitsPerPixel)
                continue;
            
            if((CGDisplayModeGetWidth(mode) <= screenMode.width) && (CGDisplayModeGetHeight(mode) <= screenMode.height))
            {
                CGDisplayModeRelease(displayMode); 
                CGDisplayModeRetain(mode);
                displayMode = mode;
                match = true;
                break;
            }
        }
    }
    
    // No depth match was found
    if(!match)
	{
		for(int i = 0; i < CFArrayGetCount(allModes); i++)
		{
			CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(allModes, i);
			if([self displayBitsPerPixelForMode: mode] >= screenMode.bitsPerPixel)
				continue;
            
			if((CGDisplayModeGetWidth(mode) >= screenMode.width) && (CGDisplayModeGetHeight(mode) >= screenMode.height))
			{
                CGDisplayModeRelease(displayMode);
                CGDisplayModeRetain(mode);
				displayMode = mode;
				break;
			}
		}
	}
    
    CFRelease(allModes);
	return displayMode;
}


+(void)changeResolutionTo:(RDScreenRes)resolution {
#ifdef DONT_CHANGE_RESOLUTION
    if(DONT_CHANGE_RESOLUTION)
        return;
#endif
    [AppUtils log:FORMAT(@"Attempting to change resolution to (%i,%i)",resolution.width,resolution.height)];
    
    if(ScreenResEqual(resolution,[self currentResolution]))
        return;
    
    CGDirectDisplayID display = CGMainDisplayID(); // ID of main display
    struct screenMode modeStruct = {resolution.width, resolution.height, 32};
    CGDisplayModeRef mode = [self copyBestMatchForMode:modeStruct];
    
    CGError result = CGDisplaySetDisplayMode(display, mode, NULL);
    if(result == 0) {
        RDScreenRes newRes = [self currentResolution];
        [AppUtils log:FORMAT(@"Changed resolution to (%i,%i)", newRes.width, newRes.height)];
    } else {
        NSError *error = [NSError errorWithDomain:@"ScreenController" code:result userInfo:nil];
        [AppUtils handleNonFatalError:error context:@"changeResolutionTo:"];
    }
    
    CGDisplayModeRelease(mode);
}

@end
