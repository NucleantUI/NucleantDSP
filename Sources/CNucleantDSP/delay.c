// delay.c — a feedback delay line per channel.

#include "CNucleantDSP.h"

#include <stdlib.h>
#include <string.h>

struct ndsp_delay {
    int channels;
    size_t length;   // frames per channel's line: max_frames + 2, for reading between two
    size_t write;    // the frame written next, the same in every line
    float *lines;    // channels × length, channel-major
};

ndsp_delay *ndsp_delay_create(int channels, size_t max_frames) {
    if (channels < 1 || max_frames < 1) return NULL;
    ndsp_delay *delay = malloc(sizeof(ndsp_delay));
    size_t length = max_frames + 2;
    float *lines = calloc((size_t)channels * length, sizeof(float));
    if (delay == NULL || lines == NULL) {
        free(delay);
        free(lines);
        return NULL;
    }
    delay->channels = channels;
    delay->length = length;
    delay->write = 0;
    delay->lines = lines;
    return delay;
}

ndsp_delay *ndsp_delay_copy(const ndsp_delay *from) {
    if (from == NULL) return NULL;
    ndsp_delay *delay = malloc(sizeof(ndsp_delay));
    size_t count = (size_t)from->channels * from->length;
    float *lines = malloc(count * sizeof(float));
    if (delay == NULL || lines == NULL) {
        free(delay);
        free(lines);
        return NULL;
    }
    memcpy(lines, from->lines, count * sizeof(float));
    *delay = *from;
    delay->lines = lines;
    return delay;
}

void ndsp_delay_destroy(ndsp_delay *delay) {
    if (delay == NULL) return;
    free(delay->lines);
    free(delay);
}

size_t ndsp_delay_max_frames(const ndsp_delay *delay) { return delay->length - 2; }

void ndsp_delay_process(ndsp_delay *delay, float *samples, size_t frames, float delay_frames, float feedback, float mix) {
    const int channels = delay->channels;
    const size_t length = delay->length;
    const float longest = (float)(length - 2);
    if (delay_frames < 1.0f) delay_frames = 1.0f;
    if (delay_frames > longest) delay_frames = longest;
    // Read `delay_frames` behind the write position: `whole` frames back,
    // and `fraction` of the way to the one before that.
    const size_t whole = (size_t)delay_frames;
    const float fraction = delay_frames - (float)whole;
    const float dry = 1.0f - mix;

    size_t write = delay->write;
    for (size_t frame = 0; frame < frames; frame++) {
        const size_t newer = (write + length - whole) % length;
        const size_t older = (newer + length - 1) % length;
        float *sample = samples + frame * (size_t)channels;
        for (int channel = 0; channel < channels; channel++) {
            float *line = delay->lines + (size_t)channel * length;
            const float delayed = line[newer] + (line[older] - line[newer]) * fraction;
            const float input = sample[channel];
            line[write] = input + delayed * feedback;
            sample[channel] = input * dry + delayed * mix;
        }
        write = write + 1 == length ? 0 : write + 1;
    }
    delay->write = write;
}
