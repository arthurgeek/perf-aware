#!/usr/bin/env bash
#
# The course listings are (C) Molly Rocket, Inc. and not redistributable, so
# each clone fetches them from Casey Muratori's own public repository.

set -u

base=https://raw.githubusercontent.com/cmuratori/computer_enhance/main/perfaware/part1

files=(
    listing_0037_single_register_mov.asm
    listing_0038_many_register_mov.asm
    listing_0039_more_movs.asm
    listing_0040_challenge_movs.asm
    listing_0041_add_sub_cmp_jnz.asm
    listing_0043_immediate_movs.asm
    listing_0043_immediate_movs.txt
    listing_0044_register_movs.asm
    listing_0044_register_movs.txt
    listing_0046_add_sub_cmp.asm
    listing_0046_add_sub_cmp.txt
    listing_0048_ip_register.asm
    listing_0048_ip_register.txt
)

mkdir -p listings

failed=0

for f in "${files[@]}"; do
    if [ -e "listings/$f" ]; then
        echo "have  $f"
        continue
    fi

    echo "fetch $f"

    if ! curl -sfL "$base/$f" -o "listings/$f"; then
        echo "FAILED $f" >&2
        rm -f "listings/$f"
        failed=1
        continue
    fi

    # GitHub sometimes serves an HTML error page with a 200 status.
    if head -c 100 "listings/$f" | grep -qi '<!DOCTYPE\|<html'; then
        echo "FAILED $f (got an HTML error page, not the listing)" >&2
        rm "listings/$f"
        failed=1
    fi
done

exit $failed
