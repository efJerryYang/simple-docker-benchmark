#!/bin/bash

set -e
trap 'echo "Error on line $LINENO: command -> $BASH_COMMAND"' ERR

# For macOS, GNU coreutils may be required (e.g., install coreutils via Homebrew)
echo "Starting host benchmark..."
echo "=========================="
echo "System Information:"
uname -a

echo "CPU Info:"
sysctl -n machdep.cpu.brand_string
sysctl -n hw.ncpu

echo "Memory Info:"
vm_stat

echo "Disk Info:"
df -h

echo "Network Info:"
ifconfig
echo "=========================="

echo "Running CPU benchmark..."

echo "1. Hash computation test (3 iterations):"
for i in {1..3}; do
    START=$(gdate +%s%N 2>/dev/null || date +%s%N)
    dd if=/dev/urandom bs=1m count=1200 2>/dev/null | shasum >/dev/null
    END=$(gdate +%s%N 2>/dev/null || date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    echo "  Iteration $i: ${DURATION}ms"
done

echo "2. Compression test (3 iterations):"
for i in {1..3}; do
    START=$(gdate +%s%N 2>/dev/null || date +%s%N)
    dd if=/dev/urandom bs=1m count=128 2>/dev/null | gzip > /dev/null
    END=$(gdate +%s%N 2>/dev/null || date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    echo "  Iteration $i: ${DURATION}ms"
done

echo "3. Pi calculation test (3 iterations):"
for i in {1..3}; do
    START=$(gdate +%s%N 2>/dev/null || date +%s%N)
    echo "scale=2500; 4*a(1)" | bc -l >/dev/null
    END=$(gdate +%s%N 2>/dev/null || date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    echo "  Iteration $i: ${DURATION}ms"
done

echo -e "\nRunning memory benchmark..."
# macOS does not provide free(1); this is a placeholder.
echo "Initial memory usage: N/A"
SIZE_LIST=(512 1024 2048)
for SIZE in "${SIZE_LIST[@]}"; do
    echo "Testing ${SIZE}MB:"
    START=$(gdate +%s%N 2>/dev/null || date +%s%N)
    for j in {1..4}; do
        dd if=/dev/zero of=/tmp/host_test_write_${j} bs=1m count=$SIZE 2>/dev/null
        sync
    done
    END=$(gdate +%s%N 2>/dev/null || date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    echo "  Write test: ${DURATION}ms"
    rm -f /tmp/host_test_write_*
    for j in {1..4}; do
        dd if=/dev/zero of=/tmp/host_test_read_${j} bs=1m count=$SIZE 2>/dev/null
    done
    START=$(gdate +%s%N 2>/dev/null || date +%s%N)
    for j in {1..4}; do
        dd if=/tmp/host_test_read_${j} of=/dev/null bs=1m 2>/dev/null
    done
    END=$(gdate +%s%N 2>/dev/null || date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    echo "  Read test: ${DURATION}ms"
    rm -f /tmp/host_test_read_*
done

echo -e "\nRunning disk I/O benchmark..."
echo "Sequential write test (3 iterations):"
for i in {1..3}; do
    START=$(gdate +%s%N 2>/dev/null || date +%s%N)
    # Using "oflag=sync" instead of conv=fdatasync and "bs=1m"
    dd if=/dev/zero of=/tmp/host_test_seq bs=1m count=4096 oflag=sync 2>/dev/null
    END=$(gdate +%s%N 2>/dev/null || date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    echo "  Iteration $i: ${DURATION}ms"
    rm -f /tmp/host_test_seq
done

echo "Random write test (3 iterations):"
for i in {1..3}; do
    START=$(gdate +%s%N 2>/dev/null || date +%s%N)
    # For random writes, use /dev/urandom and oflag=sync
    dd if=/dev/urandom of=/tmp/host_test_rand bs=8k count=32768 oflag=sync 2>/dev/null
    END=$(gdate +%s%N 2>/dev/null || date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    echo "  Iteration $i: ${DURATION}ms"
    rm -f /tmp/host_test_rand
done

echo "Mixed read/write test (3 iterations):"
for i in {1..3}; do
    dd if=/dev/zero of=/tmp/host_test_mixed bs=1m count=2048 2>/dev/null
    sync
    START=$(gdate +%s%N 2>/dev/null || date +%s%N)
    ( for j in {1..2}; do
          dd if=/tmp/host_test_mixed of=/dev/null bs=1m count=2048 2>/dev/null &
          dd if=/dev/zero of=/tmp/host_test_mixed2_${j} bs=1m count=1024 oflag=sync 2>/dev/null &
      done
      wait )
    END=$(gdate +%s%N 2>/dev/null || date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    echo "  Iteration $i: ${DURATION}ms"
    rm -f /tmp/host_test_mixed /tmp/host_test_mixed2_*
done

echo -e "\nRunning network benchmark..."
ENDPOINTS=("https://www.google.com" "https://www.cloudflare.com" "https://www.amazon.com")
for endpoint in "${ENDPOINTS[@]}"; do
    echo "Testing endpoint: $endpoint"
    for i in {1..3}; do
        START=$(gdate +%s%N 2>/dev/null || date +%s%N)
        for j in {1..20}; do
            curl -s -o /dev/null "$endpoint" &
        done
        wait
        END=$(gdate +%s%N 2>/dev/null || date +%s%N)
        DURATION=$(( (END - START) / 1000000 ))
        echo "  Iteration $i: ${DURATION}ms"
    done
done

echo "Network latency test:"
for i in {1..3}; do
    LATENCY=$(ping -c 1 8.8.8.8 | grep -Eo '([0-9]*\.[0-9]+)' | sed -n '3p')
    [ -z "$LATENCY" ] && LATENCY=0
    echo "  Iteration $i: ${LATENCY}ms"
done

echo -e "\nBenchmark Summary:"
echo "===================="
echo "CPU Performance:"
if [ ${#cpu_hash_times[@]} -eq 3 ]; then
    sum=0
    for t in "${cpu_hash_times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    hash_avg=$(echo "scale=2; $sum / 3" | bc)
    # 1200 MB processed for each iteration in dd command
    hash_speed=$(echo "scale=2; 1200 / $hash_avg * 1000" | bc)
    echo "  - SHA256 Hash: ${hash_avg}ms (${hash_speed} MB/s)"
fi
if [ ${#cpu_comp_times[@]} -eq 3 ]; then
    sum=0
    for t in "${cpu_comp_times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    comp_avg=$(echo "scale=2; $sum / 3" | bc)
    comp_speed=$(echo "scale=2; 128 / $comp_avg * 1000" | bc)
    echo "  - Compression: ${comp_avg}ms (${comp_speed} MB/s)"
fi

echo "  - Pi Calculation: Average over 3 iterations:"
if [ ${#cpu_pi_times[@]} -eq 3 ]; then
    sum=0
    for t in "${cpu_pi_times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    pi_avg=$(echo "scale=2; $sum / 3" | bc)
    echo "      Average time: ${pi_avg}ms"
fi

echo -e "\nMemory Performance:"
if [ ${#mem_write_times[@]} -gt 0 ]; then
    total_write_time=0
    total_write_data=0
    for i in "${!mem_write_times[@]}"; do
        total_write_time=$(echo "$total_write_time + ${mem_write_times[$i]}" | bc)
        total_write_data=$(echo "$total_write_data + ${mem_sizes[$i]}" | bc)
    done
    write_throughput=$(echo "scale=2; $total_write_data / $total_write_time * 1000" | bc)
    echo "  - Write throughput: ${write_throughput} MB/s"
fi
if [ ${#mem_read_times[@]} -gt 0 ]; then
    total_read_time=0
    total_read_data=0
    for i in "${!mem_read_times[@]}"; do
        total_read_time=$(echo "$total_read_time + ${mem_read_times[$i]}" | bc)
        total_read_data=$(echo "$total_read_data + ${mem_sizes[$i]}" | bc)
    done
    read_throughput=$(echo "scale=2; $total_read_data / $total_read_time * 1000" | bc)
    echo "  - Read throughput: ${read_throughput} MB/s"
fi

echo -e "\nDisk Performance:"
if [ ${#disk_seq_times[@]} -eq 3 ]; then
    sum=0
    for t in "${disk_seq_times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    seq_avg=$(echo "scale=2; $sum / 3" | bc)
    seq_speed=$(echo "scale=2; 4096 / $seq_avg * 1000" | bc)
    echo "  - Sequential write: ${seq_speed} MB/s"
fi
if [ ${#disk_rand_times[@]} -eq 3 ]; then
    sum=0
    for t in "${disk_rand_times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    rand_avg=$(echo "scale=2; $sum / 3" | bc)
    # 32768 blocks * 8k = 256 MB per iteration
    rand_speed=$(echo "scale=2; 256 / $rand_avg * 1000" | bc)
    echo "  - Random write: ${rand_speed} MB/s"
fi
if [ ${#disk_mixed_times[@]} -eq 3 ]; then
    sum=0
    for t in "${disk_mixed_times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    mixed_avg=$(echo "scale=2; $sum / 3" | bc)
    # Mixed test: read: 2048MB*2 = 4096MB; write: 1024MB*2 = 2048MB
    mixed_read_speed=$(echo "scale=2; 4096 / $mixed_avg * 1000" | bc)
    mixed_write_speed=$(echo "scale=2; 2048 / $mixed_avg * 1000" | bc)
    echo "  - Mixed I/O: ${mixed_read_speed} MB/s read, ${mixed_write_speed} MB/s write"
fi

echo -e "\nNetwork Performance:"
if [ ${#network_latency_times[@]} -eq 3 ]; then
    sum=0
    for t in "${network_latency_times[@]}"; do
        sum=$(echo "$sum + $t" | bc)
    done
    net_latency_avg=$(echo "scale=2; $sum / 3" | bc)
    echo "  - Average latency: ${net_latency_avg}ms"
fi

echo -e "\nBenchmark completed!"

