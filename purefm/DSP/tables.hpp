//
//  Tables.hpp
//  purefm
//
//  Created by Paul Forgey on 4/15/20.
//  Copyright © 2020 Paul Forgey. All rights reserved.
//

#ifndef tables_hpp
#define tables_hpp

#include <algorithm>

const int eg_max = 0x7fffff;
const int eg_mid = 0x000000;
const int eg_min = -0x800000;

class tables {
    private:
        int _logsin[0x4000];
        int _exp[0x4000];
        int _log[0x4000];
        long _notes[0x1000];
        int _scale[12];

    public:
        tables() {}
        virtual ~tables() {}

        void init(double sampleRate);

        inline int logsin(int phase) const {
            return _logsin[phase];
        }

        inline int log(int phase) const {
            return _log[phase];
        }

        inline int exp(int l) const {
            int n = _exp[l & 0x3fff];
            return n >> (l >> 14);
        }

        // frequency (in pitch units) to actual pitch
        inline long pitch(int frequency) const {
            long p = _notes[frequency & 0xfff];
            int shift = (frequency >> 12);
            if (shift < 0) {
                p >>= -shift;
            } else {
                p <<= shift;
            }

            return p;
        }

        // signed note value to pitch units; 0 is middle C
        inline int scale(int note) const {
            bool neg = false;
            if (note < 0) {
                note = -note;
                neg = true;
            }
            int n = _scale[note % 12] + 4096 * (note / 12);
            return neg ? -n : n;
        }


        // return linear output of log input and envelope value
        // output is in 24 bit signed positive range
        inline int output(int input, int envelope) const {
            if (envelope < eg_min) {
                envelope = 0x1000000;
            } else if (envelope > eg_max) {
                envelope = 0;
            } else {
                envelope = -eg_min - envelope;
            }

            envelope >>= 6; // [0-16] << 14 + [0-16384)
            input += envelope;
            int out = _exp[input & 0x3fff];
            out >>= (input >> 14);
            return out << 7; // signed 24 bit value (in positive range)
        }

        // envelope setting to counter increment
        static int duration_param(int value);
        // envelope setting to 24 bit level (actually in range >0 to 0x100000)
        static int level_param(int value);
        // pitch envelope setting to level
        static int pitch_param(int value, int scale);

        static constexpr double middleC = 261.625565;
};

#endif /* tables_hpp */
