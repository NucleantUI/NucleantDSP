# implement more filters

* https://github.com/vinniefalco/DSPFilters/tree/master/shared/DSPFilters/source

maybe this time try rewrite them in swift instead..

moog latter filter

* https://github.com/umnum/dspmini/blob/04710954f57615f0e35436a6f14364215c070208/Moog/Source/PluginProcessor.cpp#L17

* https://www.musicdsp.org/en/latest/Filters/196-moog-filter.html

tons of filters
* https://www.musicdsp.org/en/latest/Filters/index.html



# oscilators
https://www.musicdsp.org/en/latest/Synthesis/8-pulsewidth-modulation.html

supersaw
```c
int24_t saw [7] = {0};
const int24_t detune_table [7] = { 0, 128, -128, 816, -824, 1408, -1440 };

int24_t next(int24_t pitch, int24_t spread, int24_t detune) {
    int24_t sum = 0;
    for (int i = 0; i < 7; i++) {
        int24_t voice_detune = (detune_table[i] (pitch detune)) >> 7;
        saw[i] += pitch + voice_detune;
        if (i == 0)
            sum += saw[i];
        else 
            sum += saw[i] ✶ spread;
    }
    
    return high_pass (sum);
}
```

original roland runs this at 88.2khz, while device itself runs at 44.1 khz
and done to avoid aliasing what i been told.. not sure how we can implement it here..
you welcome to translate it to 32bit float if possible or whatever we can do to make it fit into
our dsp engine


implement upsampler downsampler if needed i guess..