# Sega Y Board core — design notes

To be written with the plan before the first milestone. Sections to fill:

1. What came from the X Board core and what is new (three 68000s, the 315-5305 sprite
   generator with the 315-5306 rotation, the 16B sprite layer, the 315-5296 I/O chip,
   no tilemap, no road).
2. Clocks and memory placement (BRAM / SDRAM / DDR3 budget; the X Board ended at
   488/553 M10K, so count blocks from the first build).
3. Per-chip references and where MAME is the authority.
4. Milestones with pass criteria, one gate script each (`verif/board/check_mN.sh`).
