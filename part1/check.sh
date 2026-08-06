#!/usr/bin/env bash
#
# Round-trip test for the 8086 decoder.
#
# For each listing:  foo.asm --nasm--> foo.ref --decoder--> foo.out.asm --nasm--> foo.out
# then compares foo.ref with foo.out. Byte-identical means the decoder read the
# real bits; anything else is a bug (or an encoding tie — see README note on the
# `d` bit, where nasm may legitimately pick the other of two valid encodings).
#
# Usage: ./check.sh [listings-dir]

set -u

listings_dir=${1:-listings}

# Override with e.g. `DECODER=./build/sim86 ./check.sh` if your binary lands elsewhere.
DECODER=${DECODER:-./build/sim8086}

build=build/check

if [ ! -x "$DECODER" ]; then
    echo "no decoder at $DECODER (set \$DECODER to override)" >&2
    exit 2
fi

shopt -s nullglob
listings=("$listings_dir"/*.asm)
if [ "${#listings[@]}" -eq 0 ]; then
    echo "no .asm files in $listings_dir/" >&2
    exit 2
fi

mkdir -p "$build"

# Report a single failing listing. Called with the listing name and the paths to
# the reference and round-tripped binaries.
#
# Hex-dump both sides and diff them: `cmp` alone gives you the first bad byte,
# but what you actually need is the surrounding bytes to tell which instruction
# you mis-decoded. -L labels the sides, since process substitution names are noise.
report_failure() {
    echo "FAIL $1"
    diff -u -L expected -L decoded <(xxd "$2") <(xxd "$3") \
        | tail -n +3 | sed 's/^/    /'
}

passed=0
failed=0

for asm in "${listings[@]}"; do
    name=$(basename "$asm" .asm)
    ref=$build/$name.ref
    out=$build/$name.out

    # Reference: the listing as the course author assembled it.
    if ! nasm -f bin "$asm" -o "$ref" 2>/dev/null; then
        echo "SKIP $name (nasm failed on the source listing)"
        continue
    fi

    # Round trip: decode the bytes back to text, then re-assemble that text.
    "$DECODER" "$ref" >"$build/$name.out.asm"
    if ! nasm -f bin "$build/$name.out.asm" -o "$out" 2>/dev/null; then
        echo "FAIL $name (decoder emitted asm nasm won't assemble)"
        failed=$((failed + 1))
        continue
    fi

    if cmp -s "$ref" "$out"; then
        echo "PASS $name"
        passed=$((passed + 1))
    else
        report_failure "$name" "$ref" "$out"
        failed=$((failed + 1))
    fi
done

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
