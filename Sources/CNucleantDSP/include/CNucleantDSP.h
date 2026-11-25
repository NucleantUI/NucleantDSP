// CNucleantDSP.h — the C processors under NucleantDSP.
//
// Plain C, and all Swift sees of this target: the Vult processors are C++
// (Vult writes C++), compiled behind vult_api.cpp, which gives them the C
// API below. So importing this needs no C++ interop.
//
// Every processor works in place on interleaved samples: `frames` frames of
// the channel count it was made for, one state per channel. Those with state
// are opaque: made with *_create, duplicated with *_copy (a copy goes on from
// the same state, independently), and freed with *_destroy.

#ifndef CNUCLEANTDSP_H
#define CNUCLEANTDSP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Vult (vult_api.cpp)

/// Vult's state variable filter (Vult/filters/svf.vult).
typedef struct ndsp_svf ndsp_svf;

ndsp_svf *ndsp_svf_create(int channels);
ndsp_svf *ndsp_svf_copy(const ndsp_svf *filter);
void ndsp_svf_destroy(ndsp_svf *filter);
/// `cv` 0…0.9 sets the cutoff (Vult's pitch scale, at 44.1 kHz), `q` 0 and
/// up the resonance (Q = 0.5 + q), `mode` 0 low-pass, 1 high-pass, 2
/// band-pass, 3 notch. The output goes through Vult's soft saturation.
void ndsp_svf_process(ndsp_svf *filter, float *samples, size_t frames, float cv, float q, int mode);

/// Vult's ladder filter (Vult/filters/ladder.vult).
typedef struct ndsp_ladder ndsp_ladder;

ndsp_ladder *ndsp_ladder_create(int channels);
ndsp_ladder *ndsp_ladder_copy(const ndsp_ladder *filter);
void ndsp_ladder_destroy(ndsp_ladder *filter);
/// `cut` 0…1 sets the cutoff (Vult's pitch scale, at 44.1 kHz), `resonance`
/// 0…1 the feedback, which self-oscillates near 1.
void ndsp_ladder_process(ndsp_ladder *filter, float *samples, size_t frames, float cut, float resonance);

/// Vult's soft saturation (Vult/effects/saturate_soft.vult): 16·tanh(x/16),
/// for x held within ±24, the range its table covers.
void ndsp_saturate_soft(float *samples, size_t count);
/// Vult's cubic clipper (Vult/effects/clipper.vult): x − x³/3, held at ±2/3.
void ndsp_cubic_clip(float *samples, size_t count);
/// Vult's wave folder (Vult/effects/fold.vult): `level` 0…1 folds the
/// signal back on itself up to 9 times.
void ndsp_fold(float *samples, size_t count, float level);
/// Vult's bit crusher (Vult/effects/bitcrush.vult): `amount` 0…1 quantizes
/// ever coarser; 0 leaves the signal as it is.
void ndsp_bitcrush(float *samples, size_t count, float amount);

// MARK: - C (delay.c, reverb.c)

/// A feedback delay line per channel, up to `max_frames` frames long.
typedef struct ndsp_delay ndsp_delay;

ndsp_delay *ndsp_delay_create(int channels, size_t max_frames);
ndsp_delay *ndsp_delay_copy(const ndsp_delay *delay);
void ndsp_delay_destroy(ndsp_delay *delay);
size_t ndsp_delay_max_frames(const ndsp_delay *delay);
/// `delay_frames` 1…max_frames, fractional (read between two samples),
/// `feedback` 0…<1, `mix` 0 dry … 1 the delayed signal alone.
void ndsp_delay_process(ndsp_delay *delay, float *samples, size_t frames, float delay_frames, float feedback, float mix);

/// Freeverb (Jezar at Dreampoint's public domain design): eight parallel
/// comb filters into four allpasses, for a left and a right side.
typedef struct ndsp_reverb ndsp_reverb;

/// The comb and allpass lengths are Freeverb's at 44.1 kHz, scaled to
/// `sample_rate`.
ndsp_reverb *ndsp_reverb_create(int channels, double sample_rate);
ndsp_reverb *ndsp_reverb_copy(const ndsp_reverb *reverb);
void ndsp_reverb_destroy(ndsp_reverb *reverb);
/// The channels are summed into the reverb; even channels take its left
/// side, odd ones its right. `room_size` and `damping` 0…1, `width` 0 mono
/// … 1 the sides apart, `mix` 0 dry … 1 the reverb alone.
void ndsp_reverb_process(ndsp_reverb *reverb, float *samples, size_t frames,
                         float room_size, float damping, float width, float mix);

#ifdef __cplusplus
}
#endif

#endif
