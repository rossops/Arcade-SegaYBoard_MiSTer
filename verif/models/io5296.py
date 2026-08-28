"""Sega 315-5296 I/O chip, ported from MAME 315_5296.cpp (0.289).

64 byte registers: 0-7 ports A-H, 8-B read 'S','E','G','A', C/E the CNT
register, D/F the direction register (bit n = port n is an output). A read
of an output port returns its latch, a read of an input port the pin; a
write always updates the latch and only reaches the pin when the port is an
output. Everything else reads FF. Registers 20-3F assert /FMCS (the MSM6253
select on the Y Board)."""


class Io5296:
    def __init__(self):
        self.latch = [0] * 8
        self.dir = 0
        self.cnt = 0
        self.inputs = [0xff] * 8

    def read(self, offset):
        offset &= 0x3f
        if offset < 8:
            if (self.dir >> offset) & 1:
                return self.latch[offset]
            return self.inputs[offset]
        if 8 <= offset <= 0xb:
            return ord("SEGA"[offset - 8])
        if offset in (0xc, 0xe):
            return self.cnt
        if offset in (0xd, 0xf):
            return self.dir
        return 0xff

    def write(self, offset, data):
        offset &= 0x3f
        data &= 0xff
        if offset < 8:
            self.latch[offset] = data
        elif offset == 0xe:
            self.cnt = data
        elif offset == 0xf:
            self.dir = data

    def output(self, port):
        """Pin level the chip drives: the latch when the port is an output,
        0 otherwise (MAME refreshes the callback with 0 on a switch to input)."""
        return self.latch[port] if (self.dir >> port) & 1 else 0

    def fmcs(self, offset):
        return 0x20 <= (offset & 0x3f) <= 0x3f
