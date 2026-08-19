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

# Strip incidentals before comparing simulation transcripts: CRLF endings,
# the "--- ... execution ---" banner, trailing whitespace, and blank lines.
# Clock-era transcripts also carry asterisk banners, a boilerplate warning,
# and a whole 8088 section; we only simulate the 8086, so those go too.
normalize_transcript() {
    tr -d '\r' | sed \
        -e '/^\*\*\*\* 8088 \*\*\*\*$/,$d' \
        -e '/^\*\+$/d' \
        -e '/^\*\*\*\* 8086 \*\*\*\*$/d' \
        -e '/^WARNING: Clocks/,+2d' \
        -e '/^--- .*---$/d' \
        -e 's/[[:space:]]*$//' \
        -e '/^$/d'
}

# Course transcripts from before listing 48 predate ip tracking; drop our ip
# output when comparing against them (trace segments and the final dump line).
strip_ip() {
    sed -e 's/ ip:0x[0-9a-f]*->0x[0-9a-f]*//' -e '/^[[:space:]]*ip: 0x/d'
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

    # Simulation check: only for listings that ship a reference transcript.
    txt=$listings_dir/$name.txt
    if [ -f "$txt" ]; then
        expected=$build/$name.expected.txt
        actual=$build/$name.actual.txt

        # Clock-era transcripts (listing 56 onward) were generated with cycle
        # estimates; the golden's own dialect tells us which flags to pass.
        exec_flags=(-exec)
        if grep -q 'Clocks:' "$txt"; then
            exec_flags+=(-explainclocks)
        fi

        "$DECODER" "${exec_flags[@]}" "$ref" | normalize_transcript >"$actual"
        normalize_transcript <"$txt" >"$expected"

        if ! grep -q 'ip:' "$expected"; then
            strip_ip <"$actual" >"$actual.noip"
            actual=$actual.noip
        fi

        if diff -q "$expected" "$actual" >/dev/null; then
            echo "PASS $name (exec)"
            passed=$((passed + 1))
        else
            echo "FAIL $name (exec)"
            diff -u -L expected -L simulated "$expected" "$actual" \
                | tail -n +3 | sed 's/^/    /'
            failed=$((failed + 1))
        fi
    fi
done

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
