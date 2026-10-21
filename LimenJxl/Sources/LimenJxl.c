// JPEG XL's lossless JPEG recompression, for the photographs in a backup. JpegPacker.swift says why.
//
// Single-threaded on purpose: no parallel runner is handed to libjxl, so it runs on the calling
// thread, which the archive export keeps off the main actor. With libjxl's thread pool spread over
// a phone's big and little cores, the thirty test photographs took 35 s to pack on a Pixel 10; on
// one thread, which the scheduler keeps on a big core, 8.4 s.

#include "LimenJxl.h"

#include <stdlib.h>
#include <string.h>

#include <jxl/decode.h>
#include <jxl/encode.h>

// libjxl's default. Effort 9 saved 0.3 percent more of the thirty photographs and took 19 times as long.
static const int kEffort = 7;

static int grow(uint8_t **buffer, size_t *size, size_t used) {
    size_t larger = *size * 2;
    uint8_t *next = realloc(*buffer, larger);
    if (next == NULL) return 0;
    *buffer = next;
    *size = larger;
    (void)used;
    return 1;
}

int limen_jxl_pack(const uint8_t *jpeg, size_t length, uint8_t **out, size_t *out_length) {
    *out = NULL;
    *out_length = 0;
    JxlEncoder *encoder = JxlEncoderCreate(NULL);
    if (encoder == NULL) return 0;
    int ok = 0;
    uint8_t *buffer = NULL;
    // The reconstruction data: everything a byte-identical JPEG needs beyond the pixels.
    if (JxlEncoderStoreJPEGMetadata(encoder, JXL_TRUE) != JXL_ENC_SUCCESS) goto done;
    JxlEncoderFrameSettings *settings = JxlEncoderFrameSettingsCreate(encoder, NULL);
    if (settings == NULL) goto done;
    if (JxlEncoderFrameSettingsSetOption(settings, JXL_ENC_FRAME_SETTING_EFFORT, kEffort) != JXL_ENC_SUCCESS) goto done;
    if (JxlEncoderAddJPEGFrame(settings, jpeg, length) != JXL_ENC_SUCCESS) goto done;
    JxlEncoderCloseInput(encoder);
    size_t size = length / 2 + 4096;
    buffer = malloc(size);
    if (buffer == NULL) goto done;
    uint8_t *next = buffer;
    size_t available = size;
    while (1) {
        JxlEncoderStatus status = JxlEncoderProcessOutput(encoder, &next, &available);
        if (status == JXL_ENC_SUCCESS) break;
        if (status != JXL_ENC_NEED_MORE_OUTPUT) goto done;
        size_t used = (size_t)(next - buffer);
        if (!grow(&buffer, &size, used)) goto done;
        next = buffer + used;
        available = size - used;
    }
    *out_length = (size_t)(next - buffer);
    *out = buffer;
    buffer = NULL;
    ok = 1;
done:
    free(buffer);
    JxlEncoderDestroy(encoder);
    return ok;
}

int limen_jxl_unpack(const uint8_t *jxl, size_t length, uint8_t **out, size_t *out_length) {
    *out = NULL;
    *out_length = 0;
    JxlDecoder *decoder = JxlDecoderCreate(NULL);
    if (decoder == NULL) return 0;
    int ok = 0;
    uint8_t *buffer = NULL;
    size_t size = 0;
    int reconstructing = 0;
    if (JxlDecoderSubscribeEvents(decoder, JXL_DEC_JPEG_RECONSTRUCTION | JXL_DEC_FULL_IMAGE) != JXL_DEC_SUCCESS) goto done;
    if (JxlDecoderSetInput(decoder, jxl, length) != JXL_DEC_SUCCESS) goto done;
    JxlDecoderCloseInput(decoder);
    while (1) {
        JxlDecoderStatus status = JxlDecoderProcessInput(decoder);
        if (status == JXL_DEC_JPEG_RECONSTRUCTION) {
            reconstructing = 1;
            size = length * 2 + 65536;
            buffer = malloc(size);
            if (buffer == NULL) goto done;
            if (JxlDecoderSetJPEGBuffer(decoder, buffer, size) != JXL_DEC_SUCCESS) goto done;
        } else if (status == JXL_DEC_JPEG_NEED_MORE_OUTPUT) {
            size_t used = size - JxlDecoderReleaseJPEGBuffer(decoder);
            if (!grow(&buffer, &size, used)) goto done;
            if (JxlDecoderSetJPEGBuffer(decoder, buffer + used, size - used) != JXL_DEC_SUCCESS) goto done;
        } else if (status == JXL_DEC_FULL_IMAGE && reconstructing) {
            *out_length = size - JxlDecoderReleaseJPEGBuffer(decoder);
            *out = buffer;
            buffer = NULL;
            ok = 1;
            goto done;
        } else {
            // An error, or a file without reconstruction data asking for a pixel buffer instead.
            goto done;
        }
    }
done:
    free(buffer);
    JxlDecoderDestroy(decoder);
    return ok;
}

void limen_jxl_free(uint8_t *bytes) {
    free(bytes);
}
