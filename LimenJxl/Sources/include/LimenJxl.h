// JPEG XL's lossless JPEG recompression, for the photographs in a backup. JpegPacker.swift says
// why. A thin C shim over libjxl's own C API, so Swift sees two calls and a free.
#ifndef LIMEN_JXL_H
#define LIMEN_JXL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Repacks `jpeg` losslessly as JPEG XL with its reconstruction data. On success returns 1 and
/// hands back a buffer in `out` and its length, to be released with limen_jxl_free; returns 0 when
/// libjxl refuses the input, which its maintainers count at about one JPEG in a hundred.
int limen_jxl_pack(const uint8_t *jpeg, size_t length, uint8_t **out, size_t *out_length);

/// Rebuilds the original JPEG from a file limen_jxl_pack wrote. Returns 0 for a file without
/// reconstruction data, or any error, and 1 with the bytes otherwise.
int limen_jxl_unpack(const uint8_t *jxl, size_t length, uint8_t **out, size_t *out_length);

void limen_jxl_free(uint8_t *bytes);

#ifdef __cplusplus
}
#endif

#endif
