// vult_api.cpp — the C API (include/CNucleantDSP.h) around the C++ that
// Vult generates (vult/, from Scripts/generate_vult.py). Nothing here or in
// vult/ is seen by Swift.

#include "CNucleantDSP.h"
#include "vult/vult_processors.h"

#include <stdlib.h>
#include <string.h>

// The opaque types of the header: one Vult context per channel.
struct ndsp_svf {
    int count;
    Svf_process_type *contexts;
};

struct ndsp_ladder {
    int count;
    Ladder_process_type *contexts;
};

namespace {

template <typename Channels, typename Context, void (*Init)(Context &)>
Channels *create(int channels) {
    if (channels < 1) return nullptr;
    auto *made = static_cast<Channels *>(malloc(sizeof(Channels)));
    auto *contexts = static_cast<Context *>(malloc(sizeof(Context) * (size_t)channels));
    if (made == nullptr || contexts == nullptr) {
        free(made);
        free(contexts);
        return nullptr;
    }
    for (int channel = 0; channel < channels; channel++) Init(contexts[channel]);
    made->count = channels;
    made->contexts = contexts;
    return made;
}

template <typename Channels, typename Context>
Channels *copy(const Channels *from) {
    if (from == nullptr) return nullptr;
    auto *made = static_cast<Channels *>(malloc(sizeof(Channels)));
    auto *contexts = static_cast<Context *>(malloc(sizeof(Context) * (size_t)from->count));
    if (made == nullptr || contexts == nullptr) {
        free(made);
        free(contexts);
        return nullptr;
    }
    memcpy(contexts, from->contexts, sizeof(Context) * (size_t)from->count);
    made->count = from->count;
    made->contexts = contexts;
    return made;
}

template <typename Channels>
void destroy(Channels *channels) {
    if (channels == nullptr) return;
    free(channels->contexts);
    free(channels);
}

}  // namespace

extern "C" {

// MARK: - State variable filter

ndsp_svf *ndsp_svf_create(int channels) {
    return create<ndsp_svf, Svf_process_type, Svf_process_init>(channels);
}

ndsp_svf *ndsp_svf_copy(const ndsp_svf *filter) {
    return copy<ndsp_svf, Svf_process_type>(filter);
}

void ndsp_svf_destroy(ndsp_svf *filter) { destroy(filter); }

void ndsp_svf_process(ndsp_svf *filter, float *samples, size_t frames, float cv, float q, int mode) {
    const int channels = filter->count;
    for (size_t frame = 0; frame < frames; frame++) {
        float *sample = samples + frame * (size_t)channels;
        for (int channel = 0; channel < channels; channel++) {
            sample[channel] = Svf_process(filter->contexts[channel], sample[channel], cv, q, mode);
        }
    }
}

// MARK: - Ladder filter

ndsp_ladder *ndsp_ladder_create(int channels) {
    return create<ndsp_ladder, Ladder_process_type, Ladder_process_init>(channels);
}

ndsp_ladder *ndsp_ladder_copy(const ndsp_ladder *filter) {
    return copy<ndsp_ladder, Ladder_process_type>(filter);
}

void ndsp_ladder_destroy(ndsp_ladder *filter) { destroy(filter); }

void ndsp_ladder_process(ndsp_ladder *filter, float *samples, size_t frames, float cut, float resonance) {
    const int channels = filter->count;
    for (size_t frame = 0; frame < frames; frame++) {
        float *sample = samples + frame * (size_t)channels;
        for (int channel = 0; channel < channels; channel++) {
            sample[channel] = Ladder_process(filter->contexts[channel], sample[channel], cut, resonance);
        }
    }
}

// MARK: - Shapers, with no state

void ndsp_saturate_soft(float *samples, size_t count) {
    // saturate_soft.vult's table covers -24...24, and past its ends Vult
    // carries the last segment's curve on: the input is held there instead.
    for (size_t i = 0; i < count; i++) {
        const float x = samples[i] > 24.0f ? 24.0f : (samples[i] < -24.0f ? -24.0f : samples[i]);
        samples[i] = Saturate_soft_process(x);
    }
}

void ndsp_cubic_clip(float *samples, size_t count) {
    for (size_t i = 0; i < count; i++) samples[i] = Clipper_process(samples[i]);
}

void ndsp_fold(float *samples, size_t count, float level) {
    for (size_t i = 0; i < count; i++) samples[i] = Fold_process(samples[i], level);
}

void ndsp_bitcrush(float *samples, size_t count, float amount) {
    for (size_t i = 0; i < count; i++) samples[i] = Bitcrush_process(samples[i], amount);
}

}  // extern "C"
