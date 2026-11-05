#!/usr/bin/env bash
#===----------------------------------------------------------------------===#
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#===----------------------------------------------------------------------===#
set -euo pipefail
cd "$(dirname "$0")/../.."
output="$PWD/target/load-validator-tests"
mkdir -p "$output"
header='kind,sample,arrival,missed,scheduled_ns,before_ns,after_ns,error,pid,start_ticks,user_ticks,system_ticks,minor_faults,major_faults,threads,virtual_bytes,resident_pages,page_bytes,ticks_per_second'
printf '%s\n' "$header" \
    'sample,0,0,2,100,101,102,0,42,7,1,2,3,4,1,4096,1,4096,100' \
    'sample,1,3,0,200,201,202,0,42,7,2,3,4,5,1,4096,1,4096,100' \
    'sample,2,4,0,300,301,302,0,42,7,3,4,5,6,1,4096,1,4096,100' > "$output/good.csv"
validate() {
    awk -v rows=3 -v warmup=1 -v pages=4096 -v ticks=100 \
        -v rss_limit=0 -v vm_limit=0 -f benchmarks/load/validate-collector.awk "$1"
}
validate "$output/good.csv" > "$output/good.summary"
grep -Fxq '3,1,2,1,1,4096,4096,4096,100' "$output/good.summary"
for field in 1 2 3 5 6 7 8 9 10 11 16 17 18 19; do
    awk -F, -v OFS=, -v field="$field" 'NR == 4 { $field = "999999" } { print }' \
        "$output/good.csv" > "$output/bad.csv"
    # Counter increases are legal; this case must exercise a reset instead.
    if [[ "$field" == 11 ]]; then
        awk -F, -v OFS=, 'NR == 4 { $11 = 0 } { print }' "$output/good.csv" > "$output/bad.csv"
    fi
    # A later after_ns is legal; exercise a timestamp before before_ns.
    if [[ "$field" == 7 ]]; then
        awk -F, -v OFS=, 'NR == 4 { $7 = 0 } { print }' "$output/good.csv" > "$output/bad.csv"
    fi
    if validate "$output/bad.csv" > /dev/null 2> "$output/bad-$field.stderr"; then
        echo "FAIL validator accepted corruption in field $field" >&2; exit 1;
    fi
done
head -n 3 "$output/good.csv" > "$output/truncated.csv"
if validate "$output/truncated.csv" > /dev/null 2> "$output/truncated.stderr"; then
    echo 'FAIL validator accepted missing samples' >&2; exit 1;
fi
echo 'PASS collector validator: valid missed arrivals and 15 corruptions'
