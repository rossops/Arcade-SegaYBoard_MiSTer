#!/bin/sh
# Keep the SMB share's drive awake during long simulations: it spins down
# after a while of no writes and a bench run that takes half an hour has been
# killed by that. Writes a file of random numbers (DELETE_ME) into the given
# directory (default: the current one), removes it 5 s later, every 30 s,
# until killed. verif/board/Makefile starts it around every run; to use it by
# hand: sh tools/keepalive.sh [dir] & ... kill $!
DIR=${1:-.}
trap 'rm -f "$DIR/DELETE_ME"; exit 0' INT TERM
while :; do
    head -c 256 /dev/urandom | od -An -tu4 > "$DIR/DELETE_ME" 2>/dev/null
    sync
    sleep 5
    rm -f "$DIR/DELETE_ME"
    sleep 25
done
