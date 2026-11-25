// reverb.c — Freeverb, after Jezar at Dreampoint's public domain design
// (2000): the input summed to mono, eight lowpass-feedback comb filters in
// parallel, then four allpasses in series, for each of two sides whose
// lengths differ by a stereo spread.

#include "CNucleantDSP.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

enum {
    COMBS = 8,
    ALLPASSES = 4,
    SIDES = 2,
};

// Freeverb's lengths in frames at 44.1 kHz; the right side's are SPREAD
// longer.
static const int comb_tuning[COMBS] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
static const int allpass_tuning[ALLPASSES] = {556, 441, 341, 225};
static const int SPREAD = 23;

static const float FIXED_GAIN = 0.015f;
static const float SCALE_DAMP = 0.4f;
static const float SCALE_ROOM = 0.28f;
static const float OFFSET_ROOM = 0.7f;
static const float ALLPASS_FEEDBACK = 0.5f;

typedef struct {
    float *buffer;
    int length;
    int index;
    float store;  // a comb's lowpass state; unused by an allpass
} line;

struct ndsp_reverb {
    int channels;
    line combs[SIDES][COMBS];
    line allpasses[SIDES][ALLPASSES];
    float *memory;  // every line's buffer, one block
    size_t memory_count;
};

// Too small to hear, and slow on some CPUs as a denormal: zero.
static inline float flushed(float x) { return fabsf(x) < 1e-20f ? 0.0f : x; }

static inline float comb_process(line *comb, float input, float feedback, float damp) {
    float output = comb->buffer[comb->index];
    comb->store = flushed(output * (1.0f - damp) + comb->store * damp);
    comb->buffer[comb->index] = input + comb->store * feedback;
    if (++comb->index >= comb->length) comb->index = 0;
    return output;
}

static inline float allpass_process(line *allpass, float input) {
    float buffered = allpass->buffer[allpass->index];
    allpass->buffer[allpass->index] = flushed(input + buffered * ALLPASS_FEEDBACK);
    if (++allpass->index >= allpass->length) allpass->index = 0;
    return buffered - input;
}

static int scaled(int frames, double sample_rate) {
    int length = (int)lround(frames * sample_rate / 44100.0);
    return length < 1 ? 1 : length;
}

// Points every line at its part of `memory`, laid out side by side in order.
static void place_lines(ndsp_reverb *reverb) {
    float *next = reverb->memory;
    for (int side = 0; side < SIDES; side++) {
        for (int i = 0; i < COMBS; i++) {
            reverb->combs[side][i].buffer = next;
            next += reverb->combs[side][i].length;
        }
        for (int i = 0; i < ALLPASSES; i++) {
            reverb->allpasses[side][i].buffer = next;
            next += reverb->allpasses[side][i].length;
        }
    }
}

ndsp_reverb *ndsp_reverb_create(int channels, double sample_rate) {
    if (channels < 1 || !(sample_rate > 0)) return NULL;
    ndsp_reverb *reverb = calloc(1, sizeof(ndsp_reverb));
    if (reverb == NULL) return NULL;
    size_t count = 0;
    for (int side = 0; side < SIDES; side++) {
        for (int i = 0; i < COMBS; i++) {
            reverb->combs[side][i].length = scaled(comb_tuning[i] + side * SPREAD, sample_rate);
            count += (size_t)reverb->combs[side][i].length;
        }
        for (int i = 0; i < ALLPASSES; i++) {
            reverb->allpasses[side][i].length = scaled(allpass_tuning[i] + side * SPREAD, sample_rate);
            count += (size_t)reverb->allpasses[side][i].length;
        }
    }
    reverb->memory = calloc(count, sizeof(float));
    if (reverb->memory == NULL) {
        free(reverb);
        return NULL;
    }
    reverb->memory_count = count;
    reverb->channels = channels;
    place_lines(reverb);
    return reverb;
}

ndsp_reverb *ndsp_reverb_copy(const ndsp_reverb *from) {
    if (from == NULL) return NULL;
    ndsp_reverb *reverb = malloc(sizeof(ndsp_reverb));
    float *memory = malloc(from->memory_count * sizeof(float));
    if (reverb == NULL || memory == NULL) {
        free(reverb);
        free(memory);
        return NULL;
    }
    *reverb = *from;
    memcpy(memory, from->memory, from->memory_count * sizeof(float));
    reverb->memory = memory;
    place_lines(reverb);
    return reverb;
}

void ndsp_reverb_destroy(ndsp_reverb *reverb) {
    if (reverb == NULL) return;
    free(reverb->memory);
    free(reverb);
}

void ndsp_reverb_process(ndsp_reverb *reverb, float *samples, size_t frames,
                         float room_size, float damping, float width, float mix) {
    const int channels = reverb->channels;
    const float feedback = room_size * SCALE_ROOM + OFFSET_ROOM;
    const float damp = damping * SCALE_DAMP;
    // Each side's own reverb, and how much of the other side's goes with it.
    const float own = mix * (width / 2.0f + 0.5f);
    const float other = mix * ((1.0f - width) / 2.0f);
    const float dry = 1.0f - mix;

    for (size_t frame = 0; frame < frames; frame++) {
        float *sample = samples + frame * (size_t)channels;
        float sum = 0.0f;
        for (int channel = 0; channel < channels; channel++) sum += sample[channel];
        // Freeverb sums a left and a right input: as many channels as there
        // are, scaled to two.
        const float input = sum * (2.0f / (float)channels) * FIXED_GAIN;

        float out[SIDES];
        for (int side = 0; side < SIDES; side++) {
            float accumulated = 0.0f;
            for (int i = 0; i < COMBS; i++) accumulated += comb_process(&reverb->combs[side][i], input, feedback, damp);
            for (int i = 0; i < ALLPASSES; i++) accumulated = allpass_process(&reverb->allpasses[side][i], accumulated);
            out[side] = accumulated;
        }
        for (int channel = 0; channel < channels; channel++) {
            const int side = channel % 2;
            sample[channel] = sample[channel] * dry + out[side] * own + out[1 - side] * other;
        }
    }
}
