"""OKI MSM6253 4-channel ADC as MAME models it (msm6253.cpp, 0.289) with
the Y Board's wiring: a write to register n (address bits 2:1) loads the
shift register from channel n, each read returns the MSB on D7 and shifts
left with zero fill. Channel 3 goes through the 74HC4052 selected by port E
bits 1:0 (MAME ADC.3..ADC.6); the descriptor's reverse mask is applied per
MAME channel (0-2 direct, 3-6 the mux inputs) as PORT_REVERSE does.
MAME converts instantly; the real chip's conversion time is open question 8."""


class Msm6253:
    def __init__(self):
        self.channels = [0x80] * 7     # MAME ADC.0 .. ADC.6
        self.mux = 0                   # port E bits 1:0
        self.reverse = 0               # descriptor: bit n = channel n reversed
        self.shift = 0

    def sample(self, n):
        ch = n if n < 3 else 3 + self.mux
        v = self.channels[ch]
        if (self.reverse >> ch) & 1:
            v = 0xFF if v == 0 else (0x100 - v) & 0xFF   # MAME: (max + min) - value on a 1..FF range
        return v

    def write(self, n):
        self.shift = self.sample(n & 3)

    def read(self):
        msb = (self.shift >> 7) & 1
        self.shift = (self.shift << 1) & 0xff
        return msb
