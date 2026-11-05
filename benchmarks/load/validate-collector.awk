#===----------------------------------------------------------------------===#
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#===----------------------------------------------------------------------===#
# Validation tooling only; the collector and scheduling remain Briev.
function fail(reason) {
    print "FAIL collector row " NR ": " reason > "/dev/stderr"
    failed = 1
    exit 1
}
BEGIN {
    FS = ","
    if (rows <= warmup || warmup < 1 || rss_limit < 0 || vm_limit < 0)
        fail("invalid validation geometry")
}
NR == 1 {
    expected = "kind,sample,arrival,missed,scheduled_ns,before_ns,after_ns,error,pid,start_ticks,user_ticks,system_ticks,minor_faults,major_faults,threads,virtual_bytes,resident_pages,page_bytes,ticks_per_second"
    if ($0 != expected) fail("unexpected schema")
    next
}
{
    if (NF != 19 || $1 != "sample") fail("missing or failed observation")
    for (column = 2; column <= 19; column++)
        if ($column !~ /^[0-9]+$/) fail("noninteger field")
    if ($2 != NR - 2 || $8 != 0 || $9 < 1 || $15 < 1 || $17 < 1)
        fail("sample index, status or process fields")
    if ($6 < $5 || $7 < $6 || $18 != pages || $19 != ticks)
        fail("timestamp order or host units")
    if (NR > 2) {
        if ($9 != pid || $10 != started) fail("process identity changed")
        if ($3 != arrival + missed + 1) fail("arrival accounting")
        if ($5 < scheduled || $6 < ended) fail("time moved backward")
        if ($11 < user_ticks || $12 < system_ticks || $13 < minor || $14 < major)
            fail("process counters decreased")
    }
    pid = $9; started = $10; arrival = $3; missed = $4
    scheduled = $5; ended = $7
    user_ticks = $11; system_ticks = $12; minor = $13; major = $14
    total_missed += $4
    if ($2 == warmup) {
        rss_min = rss_max = $17
        vm_min = vm_max = $16
    }
    if ($2 >= warmup) {
        if ($17 < rss_min) rss_min = $17
        if ($17 > rss_max) rss_max = $17
        if ($16 < vm_min) vm_min = $16
        if ($16 > vm_max) vm_max = $16
    }
}
END {
    if (failed) exit 1
    if (NR != rows + 1) fail("incomplete sample count")
    if (rss_max - rss_min > rss_limit) fail("post-warmup RSS range exceeded")
    if (vm_max - vm_min > vm_limit) fail("post-warmup virtual-memory range exceeded")
    print "samples,warmup,missed,rss_min_pages,rss_max_pages,vm_min_bytes,vm_max_bytes,page_bytes,ticks_per_second"
    printf "%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f\n", rows,warmup,total_missed,rss_min,rss_max,vm_min,vm_max,pages,ticks
}
