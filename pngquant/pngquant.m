/* pngquant.c - quantize the colors in an alphamap down to a specified number
**
** Copyright (C) 1989, 1991 by Jef Poskanzer.
** Copyright (C) 1997, 2000, 2002 by Greg Roelofs; based on an idea by
**                                Stefan Schneider.
** (C) 2011 by Kornel Lesinski.
**
** Permission to use, copy, modify, and distribute this software and its
** documentation for any purpose and without fee is hereby granted, provided
** that the above copyright notice appear in all copies and that both that
** copyright notice and this permission notice appear in supporting
** documentation.  This software is provided "as is" without express or
** implied warranty.
*/

/* GRR TO DO:  "original file size" and "quantized file size" if verbose? */
/* GRR TO DO:  add option to preserve background color (if any) exactly */
/* GRR TO DO:  add mapfile support, but cleanly (build palette in main()) */
/* GRR TO DO:  support 16 bps without down-conversion */
/* GRR TO DO:  if all samples are gray and image is opaque and sample depth
                would be no bigger than palette and user didn't explicitly
                specify a mapfile, switch to grayscale */
/* GRR TO DO:  if all samples are 0 or maxval, eliminate gAMA chunk (rwpng.c) */

#define PNGQUANT_VERSION "1.4b (March 2011)"

#define PNGQUANT_USAGE "\
   usage:  pngquant [options] [ncolors] [pngfile [pngfile ...]]\n\
                    [options] -map mapfile [pngfile [pngfile ...]]\n\
   options:\n\
      -force         overwrite existing output files\n\
      -ext new.png   set custom extension for output filename\n\
      -nofs          disable dithering (synonyms: -nofloyd, -ordered)\n\
      -verbose       print status messages (synonyms: -noquiet)\n\
      -iebug         increase opacity to work around Internet Explorer 6 bug\n\
\n\
   Quantizes one or more 32-bit RGBA PNGs to 8-bit (or smaller) RGBA-palette\n\
   PNGs using Floyd-Steinberg diffusion dithering (unless disabled).\n\
   The output filename is the same as the input name except that\n\
   it ends in \"-fs8.png\", \"-or8.png\" or your custom extension (unless the\n\
   input is stdin, in which case the quantized image will go to stdout).\n\
   The default behavior if the output file exists is to skip the conversion;\n\
   use -force to overwrite.\n\
   NOTE:  the -map option is NOT YET SUPPORTED.\n"


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdarg.h>
#ifdef WIN32        /* defined in Makefile.w32 (or use _MSC_VER for MSVC) */
#  include <fcntl.h>    /* O_BINARY */
#  include <io.h>   /* setmode() */
#endif

#include <math.h>
#include <stddef.h>

#include "../libpng/png.h"    /* libpng header; includes zlib.h */
#include "rwpng.h"  /* typedefs, common macros, public prototypes */
#include "pam.h"

#import "pngquant.h"

typedef unsigned char   uch;

#define MAXCOLORS  (1<<20)


#if defined(DARWIN) || defined(BSD) /* mergesort() in stdlib is a bsd thing */
#  define USE_MERGESORT 1
#else
#  define USE_MERGESORT 0
#  define mergesort(a,b,c,d) qsort(a,b,c,d)
#endif

typedef struct box *box_vector;
struct box {
    int ind;
    int colors;
    int sum;
    float weight;
};

static hist_item *mediancut(hist_item achv[], float min_opaque_val, int colors, int reqcolors);
typedef int (*comparefunc)(const void *, const void *);
static int weightedcompare_r(const void *ch1, const void *ch2);
static int weightedcompare_g(const void *ch1, const void *ch2);
static int weightedcompare_b(const void *ch1, const void *ch2);
static int weightedcompare_a(const void *ch1, const void *ch2);
static int sumcompare (const void *b1, const void *b2);

static f_pixel averagepixels(int indx, int clrs, hist_item achv[], float min_opaque_val);


static int verbose=0;
void verbose_printf(const char *fmt, ...);
void verbose_printf(const char *fmt, ...)
{
    va_list va;
    va_start(va, fmt);
    if (verbose) vfprintf(stderr, fmt, va);
    va_end(va);
}

int set_palette(write_info *output_image, int newcolors, int* remap, hist_item acolormap[]);
int set_palette(write_info *output_image, int newcolors, int* remap, hist_item acolormap[])
{
    assert(remap); assert(acolormap); assert(output_image);

    /*
    ** Step 3.4 [GRR]: set the bit-depth appropriately, given the actual
    ** number of colors that will be used in the output image.
    */

    int top_idx, bot_idx;

    verbose_printf("  writing %d-color image\n", newcolors);

    /*
    ** Step 3.5 [GRR]: remap the palette colors so that all entries with
    ** the maximal alpha value (i.e., fully opaque) are at the end and can
    ** therefore be omitted from the tRNS chunk.  Note that the ordering of
    ** opaque entries is reversed from how Step 3 arranged them--not that
    ** this should matter to anyone.
    */

    verbose_printf("  remapping colormap to eliminate opaque tRNS-chunk entries...");

    int x=0;
    for (top_idx = newcolors-1, bot_idx = 0;  x < newcolors;  ++x) {
        rgb_pixel px = to_rgb(output_image->gamma, acolormap[x].acolor);

        if (px.a == 255)
            remap[x] = top_idx--;
        else
            remap[x] = bot_idx++;
    }

    verbose_printf("%d entr%s left\n", bot_idx,
          (bot_idx == 1)? "y" : "ies");

    /* sanity check:  top and bottom indices should have just crossed paths */
    if (bot_idx != top_idx + 1) {
        return INTERNAL_LOGIC_ERROR;
    }

    output_image->num_palette = newcolors;
    output_image->num_trans = bot_idx;

    /* GRR TO DO:  if bot_idx == 0, check whether all RGB samples are gray
                   and if so, whether grayscale sample_depth would be same
                   => skip following palette section and go grayscale */


    /*
    ** Step 3.6 [GRR]: (Technically, the actual remapping happens in here)
    */

    for (x = 0; x < newcolors; ++x) {
        rgb_pixel px = to_rgb(output_image->gamma, acolormap[x].acolor);
        acolormap[x].acolor = to_f(output_image->gamma, px); /* saves rounding error introduced by to_rgb, which makes remapping & dithering more accurate */

        output_image->palette[remap[x]].red   = px.r;
        output_image->palette[remap[x]].green = px.g;
        output_image->palette[remap[x]].blue  = px.b;
        output_image->trans[remap[x]]         = px.a;
    }

    return 0;
}

inline static float colordifference(f_pixel px, f_pixel py)
{
    // original, unoptimized version:
//    float colorimp = MAX(px.a, py.a);
//
//    return (px.a - py.a) * (px.a - py.a) +
//           (px.r - py.r) * (px.r - py.r) * colorimp +
//           (px.g - py.g) * (px.g - py.g) * colorimp +
//           (px.b - py.b) * (px.b - py.b) * colorimp;
    // optimizations: 
    // for screenshots, alpha will always be one, so that's been removed.
    // removed the colorimp factor- that's always one because alpha's always one.
    
    return (px.r - py.r) * (px.r - py.r) +
    (px.g - py.g) * (px.g - py.g) +
    (px.b - py.b) * (px.b - py.b);
}

int best_color_index(f_pixel px, hist_item* acolormap, int numcolors, float min_opaque_val);
int best_color_index(f_pixel px, hist_item* acolormap, int numcolors, float min_opaque_val)
{
    int ind=0;
    float dist = colordifference(px,acolormap[0].acolor);

    for(int i = 1; i < numcolors; i++) {
        float newdist = colordifference(px,acolormap[i].acolor);

//        optimized out:
//        /* penalty for making holes in IE */
//        if (px.a > min_opaque_val && acolormap[i].acolor.a < 1) newdist += 1.0;

        if (newdist < dist) {
            ind = i;
            dist = newdist;
        }
    }
    return ind;
}

int remap_to_palette(read_info *input_image, write_info *output_image, int floyd, float min_opaque_val, int ie_bug, int newcolors, int* remap, hist_item acolormap[]);
int remap_to_palette(read_info *input_image, write_info *output_image, int floyd, float min_opaque_val, int ie_bug, int newcolors, int* remap, hist_item acolormap[])
{
    uch *pQ;
    rgb_pixel *pP;
    int ind=0;
    int limitcol;
    uch *outrow;

    rgb_pixel **input_pixels = (rgb_pixel **)input_image->row_pointers;
    uch **row_pointers = output_image->row_pointers;
    int rows = input_image->height, cols = input_image->width;
    double gamma = input_image->gamma;

    f_pixel *thiserr = NULL;
    f_pixel *nexterr = NULL;
    f_pixel *temperr;
    float sr=0, sg=0, sb=0, sa=0, err;
    int fs_direction = 0;

    if (floyd) {
        /* Initialize Floyd-Steinberg error vectors. */
        thiserr = malloc((cols + 2) * sizeof(*thiserr));
        nexterr = malloc((cols + 2) * sizeof(*thiserr));
        srandom(12345); /** deterministic dithering is better for comparing results */

        for (int col = 0; col < cols + 2; ++col) {
            const double rand_max = RAND_MAX;
            thiserr[col].r = ((double)random() - rand_max/2.0)/rand_max/255.0;
            thiserr[col].g = ((double)random() - rand_max/2.0)/rand_max/255.0;
            thiserr[col].b = ((double)random() - rand_max/2.0)/rand_max/255.0;
            thiserr[col].a = ((double)random() - rand_max/2.0)/rand_max/255.0;
        }
        fs_direction = 1;
    }
    for (int row = 0; row < rows; ++row) {
        int col;
        outrow = row_pointers[row];

        if (floyd) {
            for (col = 0; col < cols + 2; ++col) {
                nexterr[col].r = nexterr[col].g =
                nexterr[col].b = nexterr[col].a = 0;
            }
        }

        if ((!floyd) || fs_direction) {
            col = 0;
            limitcol = cols;
            pP = input_pixels[row];
            pQ = outrow;
        } else {
            col = cols - 1;
            limitcol = -1;
            pP = &(input_pixels[row][col]);
            pQ = &(outrow[col]);
        }

        do {
            f_pixel px = to_f(gamma, *pP);

            if (floyd) {
                /* Use Floyd-Steinberg errors to adjust actual color. */
                sr = px.r + thiserr[col + 1].r;
                sg = px.g + thiserr[col + 1].g;
                sb = px.b + thiserr[col + 1].b;
                sa = px.a + thiserr[col + 1].a;

                if (sr < 0) sr = 0;
                else if (sr > 1) sr = 1;
                if (sg < 0) sg = 0;
                else if (sg > 1) sg = 1;
                if (sb < 0) sb = 0;
                else if (sb > 1) sb = 1;
                if (sa < 0) sa = 0;
                /* when fighting IE bug, dithering must not make opaque areas transparent */
                else if (sa > 1 || (ie_bug && px.a > 0.999)) sa = 1;

                px = (f_pixel){sr, sg, sb, sa};
            }

            ind = best_color_index(px,acolormap,newcolors,min_opaque_val);

            if (floyd) {
                float colorimp = (1.0/256.0) + acolormap[ind].acolor.a;

                /* Propagate Floyd-Steinberg error terms. */
                if (fs_direction) {
                    err = (sr - acolormap[ind].acolor.r) * colorimp;
                    thiserr[col + 2].r += (err * 7.0f) / 16.0f;
                    nexterr[col    ].r += (err * 3.0f) / 16.0f;
                    nexterr[col + 1].r += (err * 5.0f) / 16.0f;
                    nexterr[col + 2].r += (err    ) / 16.0f;
                    err = (sg - acolormap[ind].acolor.g) * colorimp;
                    thiserr[col + 2].g += (err * 7.0f) / 16.0f;
                    nexterr[col    ].g += (err * 3.0f) / 16.0f;
                    nexterr[col + 1].g += (err * 5.0f) / 16.0f;
                    nexterr[col + 2].g += (err    ) / 16.0f;
                    err = (sb - acolormap[ind].acolor.b) * colorimp;
                    thiserr[col + 2].b += (err * 7.0f) / 16.0f;
                    nexterr[col    ].b += (err * 3.0f) / 16.0f;
                    nexterr[col + 1].b += (err * 5.0f) / 16.0f;
                    nexterr[col + 2].b += (err    ) / 16.0f;
                    err = (sa - acolormap[ind].acolor.a);
                    thiserr[col + 2].a += (err * 7.0f) / 16.0f;
                    nexterr[col    ].a += (err * 3.0f) / 16.0f;
                    nexterr[col + 1].a += (err * 5.0f) / 16.0f;
                    nexterr[col + 2].a += (err    ) / 16.0f;
                } else {
                    err = (sr - acolormap[ind].acolor.r) * colorimp;
                    thiserr[col    ].r += (err * 7.0f) / 16.0f;
                    nexterr[col + 2].r += (err * 3.0f) / 16.0f;
                    nexterr[col + 1].r += (err * 5.0f) / 16.0f;
                    nexterr[col    ].r += (err    ) / 16.0f;
                    err = (sg - acolormap[ind].acolor.g) * colorimp;
                    thiserr[col    ].g += (err * 7.0f) / 16.0f;
                    nexterr[col + 2].g += (err * 3.0f) / 16.0f;
                    nexterr[col + 1].g += (err * 5.0f) / 16.0f;
                    nexterr[col    ].g += (err    ) / 16.0f;
                    err = (sb - acolormap[ind].acolor.b) * colorimp;
                    thiserr[col    ].b += (err * 7.0f) / 16.0f;
                    nexterr[col + 2].b += (err * 3.0f) / 16.0f;
                    nexterr[col + 1].b += (err * 5.0f) / 16.0f;
                    nexterr[col    ].b += (err    ) / 16.0f;
                    err = (sa - acolormap[ind].acolor.a);
                    thiserr[col    ].a += (err * 7.0f) / 16.0f;
                    nexterr[col + 2].a += (err * 3.0f) / 16.0f;
                    nexterr[col + 1].a += (err * 5.0f) / 16.0f;
                    nexterr[col    ].a += (err    ) / 16.0f;
                }
            }

            *pQ = (uch)remap[ind];

            if ((!floyd) || fs_direction) {
                ++col;
                ++pP;
                ++pQ;
            } else {
                --col;
                --pP;
                --pQ;
            }
        }
        while (col != limitcol);

        if (floyd) {
            temperr = thiserr;
            thiserr = nexterr;
            nexterr = temperr;
            fs_direction = !fs_direction;
        }
    }
    return 0;
}

char *add_filename_extension(const char *filename, const char *newext);
char *add_filename_extension(const char *filename, const char *newext)
{
    int x = (int)strlen(filename);

    char* outname = malloc(x+4+strlen(newext)+1);

    strncpy(outname, filename, x);
    if (strncmp(outname+x-4, ".png", 4) == 0)
        strcpy(outname+x-4, newext);
    else
        strcpy(outname+x, newext);

    return outname;
}

static void set_binary_mode(FILE *fp)
{
#if defined(MSDOS) || defined(FLEXOS) || defined(OS2) || defined(WIN32)
#if (defined(__HIGHC__) && !defined(FLEXOS))
    setmode(fp, _BINARY);
#else
    setmode(fp == stdout ? 1 : 0, O_BINARY);
#endif
#endif
}

pngquant_error write_image(write_info *output_image, NSData **buffer);
pngquant_error write_image(write_info *output_image, NSData **buffer) {

    pngquant_error retval = rwpng_write_image_init_to_buffer(buffer, output_image);
    if (retval) {
        fprintf(stderr, "  rwpng_write_image_init() error\n");
        return retval;
    }

    /* write entire interlaced palette PNG */
    retval = rwpng_write_image_whole_to_buffer(output_image);

    /* now we're done with the OUTPUT data and row_pointers, too */
    return retval;
}

hist_item *histogram(read_info *input_image, int reqcolors, int *colors);
hist_item *histogram(read_info *input_image, int reqcolors, int *colors)
{
    hist_item *achv;
    int ignorebits=0;
    rgb_pixel **input_pixels = (rgb_pixel **)input_image->row_pointers;
    int cols = input_image->width, rows = input_image->height;
    double gamma = input_image->gamma;
    assert(gamma > 0); assert(colors);

   /*
    ** Step 2: attempt to make a histogram of the colors, unclustered.
    ** If at first we don't succeed, increase ignorebits to increase color
    ** coherence and try again.
    */

    verbose_printf("  making histogram...");
    for (; ;) {

        achv = pam_computeacolorhist(input_pixels, cols, rows, gamma, MAXCOLORS, ignorebits, colors);
        if (achv) break;

        ignorebits++;
        verbose_printf("too many colors!\n  scaling colors to improve clustering...\n");
    }

    verbose_printf("%d colors found\n", *colors);
    return achv;
}

float modify_alpha(read_info *input_image, int ie_bug);
float modify_alpha(read_info *input_image, int ie_bug)
{
    /* IE6 makes colors with even slightest transparency completely transparent,
       thus to improve situation in IE, make colors that are less than ~10% transparent
       completely opaque */

    rgb_pixel **input_pixels = (rgb_pixel **)input_image->row_pointers;
    rgb_pixel *pP;
    int rows= input_image->height, cols = input_image->width;
    double gamma = input_image->gamma;
    float min_opaque_val, almost_opaque_val;

    if (ie_bug) {
        min_opaque_val = 0.93; /* rest of the code uses min_opaque_val rather than checking for ie_bug */
        almost_opaque_val = min_opaque_val * 0.66;

        verbose_printf("  Working around IE6 bug by making image less transparent...\n");
    } else {
        min_opaque_val = almost_opaque_val = 1;
    }

    for(int row = 0; row < rows; ++row) {
        pP = input_pixels[row];
        for(int col = 0; col < cols; ++col, ++pP) {

            f_pixel px = to_f(gamma, *pP);
            rgb_pixel rgbcheck = to_rgb(gamma, px);


            if (pP->a && (pP->r != rgbcheck.r || pP->g != rgbcheck.g || pP->b != rgbcheck.b || pP->a != rgbcheck.a)) {
                fprintf(stderr, "Conversion error: expected %d,%d,%d,%d got %d,%d,%d,%d\n",
                        pP->r,pP->g,pP->b,pP->a, rgbcheck.r,rgbcheck.g,rgbcheck.b,rgbcheck.a);
                return 0;
            }

            /* set all completely transparent colors to black */
            if (!pP->a) {
                *pP = (rgb_pixel){0,0,0,pP->a};
            }
            /* ie bug: to avoid visible step caused by forced opaqueness, linearily raise opaqueness of almost-opaque colors */
            else if (pP->a < 255 && px.a > almost_opaque_val) {
                assert((min_opaque_val-almost_opaque_val)>0);

                float al = almost_opaque_val + (px.a-almost_opaque_val) * (1-almost_opaque_val) / (min_opaque_val-almost_opaque_val);
                if (al > 1) al = 1;
                px.a = al;
                pP->a = to_rgb(gamma, px).a;
            }
        }
    }

    return min_opaque_val;
}

#pragma mark - new_pngquant


pngquant_error new_pngquant(const void *image, NSData **buffer, int floyd, int reqcolors, int ie_bug) {
    read_info input_image = {0};
    float min_opaque_val;
    
    /*
     ** Step 1: read in the alpha-channel image.
     */
    /* GRR:  returns RGBA (4 channels), 8 bps */
    pngquant_error retval = rwpng_read_image_from_buffer((void *)image, &input_image);    
    if (retval) {
        fprintf(stderr, "  rwpng_read_image() error\n");
        return retval;
    }
    
    verbose_printf("  Reading file corrected for gamma %2.1f\n", 1.0/input_image.gamma);
    
    min_opaque_val = modify_alpha(&input_image,ie_bug);
    if (0==min_opaque_val) {
        return INTERNAL_LOGIC_ERROR;
    }
    
    int colors=0;
    hist_item *achv = histogram(&input_image, reqcolors, &colors);
    int newcolors = MIN(colors, reqcolors);
    
    // backup numbers in achv
    for(int i=0; i < colors; i++) {
        achv[i].num_pixels = achv[i].value;
    }
    
    hist_item *acolormap = NULL;
    float least_error = -1;
    int maxmaps = 1;
    do
    {
        verbose_printf("  selecting colors");
        
        hist_item *newmap = mediancut(achv, min_opaque_val, colors, newcolors);
        
        verbose_printf("...");
        
        float total_error=0;
        
        for(int i=0; i < colors; i++) {
            
            int match = best_color_index(achv[i].acolor, newmap, newcolors, min_opaque_val);
            float diff = colordifference(achv[i].acolor, newmap[match].acolor);
            assert(diff >= 0);
            assert(achv[i].num_pixels > 0);
            total_error += (diff * diff) * (diff * diff) * achv[i].num_pixels;
            
            achv[i].value = (achv[i].num_pixels+achv[i].value) * (1.0+sqrtf(diff));
        }
        
        if (total_error < least_error || !acolormap) {
            if (acolormap) free(acolormap);
            acolormap = newmap;
            least_error = total_error;
            maxmaps -= 1; // asymptotic improvement could make it go on forever
        } else {
            maxmaps -= 7;
            free(newmap);
        }
        
        verbose_printf(" %d%%\n",100-MAX(0,(int)(maxmaps/0.3)));
    }
    while(maxmaps > 0);
    
    pam_freeacolorhist(achv);
    
    write_info output_image = {0};
    output_image.width = input_image.width;
    output_image.height = input_image.height;
    output_image.gamma = 0.45455;
    
    int remap[256];
    if (set_palette(&output_image, newcolors, remap, acolormap)) {
        return INTERNAL_LOGIC_ERROR;
    }
    
    /*
     ** Step 3.7 [GRR]: allocate memory for the entire indexed image
     ** note that rwpng_info.row_pointers
     ** is still in use via apixels (INPUT data).
     */
    
    output_image.indexed_data = malloc(output_image.height * output_image.width);
    output_image.row_pointers = malloc(output_image.height * sizeof(output_image.row_pointers[0]));
    
    if (!output_image.indexed_data || !output_image.row_pointers) {
        fprintf(stderr, "  insufficient memory for indexed data and/or row pointers\n");
        return OUT_OF_MEMORY_ERROR;
    }
    
    for (int row = 0;  row < output_image.height;  ++row) {
        output_image.row_pointers[row] = output_image.indexed_data + row*output_image.width;
    }
    
    
    /*
     ** Step 4: map the colors in the image to their closest match in the
     ** new colormap, and write 'em out.
     */
    verbose_printf("  mapping image to new colors...\n" );
    
    if (remap_to_palette(&input_image,&output_image,floyd,min_opaque_val,ie_bug,newcolors,remap,acolormap)) {
        return OUT_OF_MEMORY_ERROR;
    }
    
    /* now we're done with the INPUT data and row_pointers, so free 'em */
    
    if (input_image.rgba_data) {
        free(input_image.rgba_data);
    }
    if (input_image.row_pointers) {
        free(input_image.row_pointers);
    }
    
    retval = write_image(&output_image,buffer);
    
    free(acolormap);
    
    if (output_image.indexed_data) {
        free(output_image.indexed_data);
    }
    if (output_image.row_pointers) {
        free(output_image.row_pointers);
    }
    
    return retval;
}

typedef struct {
    int chan; float weight;
} channelweight;

static int compareweight(const void *ch1, const void *ch2)
{
    return ((channelweight*)ch1)->weight > ((channelweight*)ch2)->weight ? -1 :
    (((channelweight*)ch1)->weight < ((channelweight*)ch2)->weight ? 1 : 0);
};

static channelweight channel_sort_order[4];

static int weightedcompare_r(const void *ch1, const void *ch2)
{
    const float *c1p = (const float *)&((hist_item*)ch1)->acolor;
    const float *c2p = (const float *)&((hist_item*)ch2)->acolor;

    if (c1p[0] > c2p[0]) return 1;
    if (c1p[0] < c2p[0]) return -1;

    // other channels are sorted backwards
    if (c1p[channel_sort_order[1].chan] > c2p[channel_sort_order[1].chan]) return -1;
    if (c1p[channel_sort_order[1].chan] < c2p[channel_sort_order[1].chan]) return 1;

    if (c1p[channel_sort_order[2].chan] > c2p[channel_sort_order[2].chan]) return -1;
    if (c1p[channel_sort_order[2].chan] < c2p[channel_sort_order[2].chan]) return 1;

    if (c1p[channel_sort_order[3].chan] > c2p[channel_sort_order[3].chan]) return -1;
    if (c1p[channel_sort_order[3].chan] < c2p[channel_sort_order[3].chan]) return 1;

    return 0;
}

static int weightedcompare_g(const void *ch1, const void *ch2)
{
    const float *c1p = (const float *)&((hist_item*)ch1)->acolor;
    const float *c2p = (const float *)&((hist_item*)ch2)->acolor;

    if (c1p[1] > c2p[1]) return 1;
    if (c1p[1] < c2p[1]) return -1;

    // other channels are sorted backwards
    if (c1p[channel_sort_order[1].chan] > c2p[channel_sort_order[1].chan]) return -1;
    if (c1p[channel_sort_order[1].chan] < c2p[channel_sort_order[1].chan]) return 1;

    if (c1p[channel_sort_order[2].chan] > c2p[channel_sort_order[2].chan]) return -1;
    if (c1p[channel_sort_order[2].chan] < c2p[channel_sort_order[2].chan]) return 1;

    if (c1p[channel_sort_order[3].chan] > c2p[channel_sort_order[3].chan]) return -1;
    if (c1p[channel_sort_order[3].chan] < c2p[channel_sort_order[3].chan]) return 1;

    return 0;
}

static int weightedcompare_b(const void *ch1, const void *ch2)
{
    const float *c1p = (const float *)&((hist_item*)ch1)->acolor;
    const float *c2p = (const float *)&((hist_item*)ch2)->acolor;

    if (c1p[2] > c2p[2]) return 1;
    if (c1p[2] < c2p[2]) return -1;

    // other channels are sorted backwards
    if (c1p[channel_sort_order[1].chan] > c2p[channel_sort_order[1].chan]) return -1;
    if (c1p[channel_sort_order[1].chan] < c2p[channel_sort_order[1].chan]) return 1;

    if (c1p[channel_sort_order[2].chan] > c2p[channel_sort_order[2].chan]) return -1;
    if (c1p[channel_sort_order[2].chan] < c2p[channel_sort_order[2].chan]) return 1;

    if (c1p[channel_sort_order[3].chan] > c2p[channel_sort_order[3].chan]) return -1;
    if (c1p[channel_sort_order[3].chan] < c2p[channel_sort_order[3].chan]) return 1;

    return 0;
}

static int weightedcompare_a(const void *ch1, const void *ch2)
{
    const float *c1p = (const float *)&((hist_item*)ch1)->acolor;
    const float *c2p = (const float *)&((hist_item*)ch2)->acolor;

    if (c1p[3] > c2p[3]) return 1;
    if (c1p[3] < c2p[3]) return -1;

    // other channels are sorted backwards
    if (c1p[channel_sort_order[1].chan] > c2p[channel_sort_order[1].chan]) return -1;
    if (c1p[channel_sort_order[1].chan] < c2p[channel_sort_order[1].chan]) return 1;

    if (c1p[channel_sort_order[2].chan] > c2p[channel_sort_order[2].chan]) return -1;
    if (c1p[channel_sort_order[2].chan] < c2p[channel_sort_order[2].chan]) return 1;

    if (c1p[channel_sort_order[3].chan] > c2p[channel_sort_order[3].chan]) return -1;
    if (c1p[channel_sort_order[3].chan] < c2p[channel_sort_order[3].chan]) return 1;

    return 0;
}

/*
** Here is the fun part, the median-cut colormap generator.  This is based
** on Paul Heckbert's paper, "Color Image Quantization for Frame Buffer
** Display," SIGGRAPH 1982 Proceedings, page 297.
*/

static hist_item *mediancut(hist_item achv[], float min_opaque_val, int colors, int newcolors)
{
    box_vector bv = malloc(sizeof(struct box) * newcolors);
    hist_item *acolormap = calloc(newcolors, sizeof(hist_item));
    if (!bv || !acolormap) {
        return 0;
    }

    /*
    ** Set up the initial box.
    */
    bv[0].ind = 0;
    bv[0].colors = colors;
    bv[0].weight = 1.0;

    int allcolors=0;
    for(int i=0; i < colors; i++) allcolors += achv[i].value;
    bv[0].sum = allcolors;

    int boxes = 1;

    /*
    ** Main loop: split boxes until we have enough.
    */
    while (boxes < newcolors) {
        int bi, indx, clrs;
        int sm;


        /*
        ** Find the first splittable box.
        */
        for (bi = 0; bi < boxes; ++bi)
            if (bv[bi].colors >= 2)
                break;
        if (bi == boxes)
            break;        /* ran out of colors! */
        indx = bv[bi].ind;
        clrs = bv[bi].colors;
        sm = bv[bi].sum;

        /*
        ** Go through the box finding the minimum and maximum of each
        ** component - the boundaries of the box.
        */

        /* colors are blended with background color, to prevent transparent colors from widening range unneccesarily */
        /* background is global - used when sorting too */
        f_pixel background = averagepixels(bv[bi].ind, bv[bi].colors, achv, min_opaque_val);

        float varr = 0;
        float varg = 0;
        float varb = 0;
        float vara = 0;

        for (int i = 0; i < clrs; ++i) {
            float v = achv[indx + i].acolor.a;
            vara += (background.a - v)*(background.a - v);
            v = achv[indx + i].acolor.r;
            varr += (background.r - v)*(background.r - v);
            v = achv[indx + i].acolor.g;
            varg += (background.g - v)*(background.g - v);
            v = achv[indx + i].acolor.b;
            varb += (background.b - v)*(background.b - v);
        }

        /*
        ** Find the largest dimension, and sort by that component
        ** by simply comparing the range in RGB space
        */

        channel_sort_order[0] = (channelweight){offsetof(f_pixel,r)/sizeof(float), varr};
        channel_sort_order[1] = (channelweight){offsetof(f_pixel,g)/sizeof(float), varg};
        channel_sort_order[2] = (channelweight){offsetof(f_pixel,b)/sizeof(float), varb};
        channel_sort_order[3] = (channelweight){offsetof(f_pixel,a)/sizeof(float), vara};

        qsort(channel_sort_order, 4, sizeof(channel_sort_order[0]), compareweight);


        comparefunc comp;
        if (channel_sort_order[0].chan == 0) comp = weightedcompare_r;
        else if (channel_sort_order[0].chan == 1) comp = weightedcompare_g;
        else if (channel_sort_order[0].chan == 2) comp = weightedcompare_b;
        else comp = weightedcompare_a;

        if (!USE_MERGESORT || clrs < 1<<10) {
            qsort(&(achv[indx]), clrs, sizeof(achv[0]), comp);
        } else {
            mergesort(&(achv[indx]), clrs, sizeof(achv[0]), comp);
        }

        /*
            Classic implementation tries to get even number of colors or pixels in each subdivision.

            Here, instead of popularity I use (sqrt(popularity)*variance) metric.
            Each subdivision balances number of pixels (popular colors) and low variance -
            boxes can be large if they have similar colors. Later boxes with high variance
            will be more likely to be split.

            Median used as expected value gives much better results than mean.
        */

        f_pixel median = averagepixels(indx+(clrs-1)/2, clrs&1 ? 1 : 2, achv, min_opaque_val);

        int lowersum = 0;
        float halfvar = 0, lowervar = 0;
        for(int i=0; i < clrs -1; i++) {
            halfvar += sqrtf(colordifference(median, achv[indx+i].acolor)) * sqrtf(achv[indx+i].value);
        }
        halfvar /= 2.0f;

        int break_at;
        for (break_at = 0; break_at < clrs - 1; ++break_at) {
            if (lowervar >= halfvar)
                break;

            lowervar += sqrtf(colordifference(median, achv[indx+break_at].acolor)) * sqrtf(achv[indx+break_at].value);
            lowersum += achv[indx + break_at].value;
        }

        /*
        ** Split the box, and sort to bring the biggest and/or very varying boxes to the top.
        */
        bv[bi].colors = break_at;
        bv[bi].sum = lowersum;
        bv[bi].weight = powf(colordifference(background, averagepixels(bv[bi].ind, bv[bi].colors, achv, min_opaque_val)),0.25f);
        bv[boxes].ind = indx + break_at;
        bv[boxes].colors = clrs - break_at;
        bv[boxes].sum = sm - lowersum;
        bv[boxes].weight = powf(colordifference(background, averagepixels(bv[boxes].ind, bv[boxes].colors, achv, min_opaque_val)),0.25f);
        ++boxes;
        mergesort(bv, boxes, sizeof(struct box), sumcompare);
    }

    /*
    ** Ok, we've got enough boxes.  Now choose a representative color for
    ** each box.  There are a number of possible ways to make this choice.
    ** One would be to choose the center of the box; this ignores any structure
    ** within the boxes.  Another method would be to average all the colors in
    ** the box - this is the method specified in Heckbert's paper.  A third
    ** method is to average all the pixels in the box.  You can switch which
    ** method is used by switching the commenting on the REP_ defines at
    ** the beginning of this source file.
    */
    for (int bi = 0; bi < boxes; ++bi) {
        acolormap[bi].acolor = averagepixels(bv[bi].ind, bv[bi].colors, achv, min_opaque_val);

        for(int i=0; i < bv[bi].colors; i++) {
            achv[bv[bi].ind + i].value *= 2.0 + sqrt(colordifference(acolormap[bi].acolor, achv[bv[bi].ind + i].acolor));
        }

        /* store total color popularity */
        for(int i=0; i < bv[bi].colors; i++) {
            acolormap[bi].value += achv[bv[bi].ind + i].value;
        }
    }

    /*
    ** All done.
    */
    return acolormap;
}

static f_pixel averagepixels(int indx, int clrs, hist_item achv[], float min_opaque_val)
{
    float r = 0, g = 0, b = 0, a = 0, sum = 0;
    float maxa = 0;
    int i;

    for (i = 0; i < clrs; ++i) {
        float weight = 1.0f;
        float tmp;

        /* give more weight to colors that are further away from average
            this is intended to prevent desaturation of images and fading of whites
         */
        tmp = (0.5f - achv[indx + i].acolor.r);
        weight += tmp*tmp;
        tmp = (0.5f - achv[indx + i].acolor.g);
        weight += tmp*tmp;
        tmp = (0.5f - achv[indx + i].acolor.b);
        weight += tmp*tmp;

        weight *= achv[indx + i].value;
        sum += weight;

        r += achv[indx + i].acolor.r * weight;
        g += achv[indx + i].acolor.g * weight;
        b += achv[indx + i].acolor.b * weight;
        a += achv[indx + i].acolor.a * weight;

        /* find if there are opaque colors, in case we're supposed to preserve opacity exactly (ie_bug) */
        if (achv[indx + i].acolor.a > maxa) maxa = achv[indx + i].acolor.a;
    }

    /* Colors are in premultiplied alpha colorspace, so they'll blend OK
       even if different opacities were mixed together */
    if (!sum) sum=1;
    a /= sum;
    r /= sum;
    g /= sum;
    b /= sum;


    /** if there was at least one completely opaque color, "round" final color to opaque */
    if (a >= min_opaque_val && maxa >= (255.0/256.0)) a = 1;

    return (f_pixel){r, g, b, a};
}


static int sumcompare(const void *b1, const void *b2)
{
    return ((box_vector)b2)->sum*((box_vector)b2)->weight -
           ((box_vector)b1)->sum*((box_vector)b1)->weight;
}



