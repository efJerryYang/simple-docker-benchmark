#!/bin/bash

set -e
trap 'echo "Error on line $LINENO: command -> $BASH_COMMAND"' ERR

# Use GNU date if available
DATE_CMD() {
    gdate +%s%N 2>/dev/null || date +%s%N
}

# ------------------------
# Initialize timing arrays
# ------------------------
declare -a cpu_hash_times=()
declare -a cpu_comp_times=()
declare -a cpu_pi_times=()

declare -a mem_write_times=()
declare -a mem_read_times=()
declare -a mem_sizes=()

declare -a disk_seq_times=()
declare -a disk_rand_times=()
declare -a disk_mixed_times=()

declare -a network_latency_times=()

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

# ------------------------
# CPU Benchmark
# ------------------------
echo "Running CPU benchmark..."

echo "1. Hash computation test (3 iterations):"
for i in {1..3}; do
    START=$(DATE_CMD)
    dd if=/dev/urandom bs=1m count=1200 status=none | shasum >/dev/null
    END=$(DATE_CMD)
    DURATION=$(( (END - START) / 1000000 ))
    cpu_hash_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
done

echo "2. Compression test (3 iterations):"
for i in {1..3}; do
    START=$(DATE_CMD)
    dd if=/dev/urandom bs=1m count=128 status=none | gzip > /dev/null
    END=$(DATE_CMD)
    DURATION=$(( (END - START) / 1000000 ))
    cpu_comp_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
done

echo "3. Pi calculation test (3 iterations):"
for i in {1..3}; do
    START=$(DATE_CMD)
    echo "scale=2500; 4*a(1)" | bc -l >/dev/null
    END=$(DATE_CMD)
    DURATION=$(( (END - START) / 1000000 ))
    cpu_pi_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
done

# ------------------------
# Memory Benchmark
# ------------------------
echo -e "\nRunning memory benchmark..."
echo "Initial memory usage: N/A"
SIZE_LIST=(512 1024 2048)
for SIZE in "${SIZE_LIST[@]}"; do
    echo "Testing ${SIZE}MB:"
    # Write test: write a file (4 iterations)
    START=$(DATE_CMD)
    for j in {1..4}; do
        dd if=/dev/zero of=/tmp/host_test_write_${j} bs=1m count=$SIZE status=none
        sync
    done
    END=$(DATE_CMD)
    DURATION=$(( (END - START) / 1000000 ))
    mem_write_times+=($DURATION)
    echo "  Write test: ${DURATION}ms"
    rm -f /tmp/host_test_write_*

    # Read test: create and then read the file (4 iterations)
    for j in {1..4}; do
        dd if=/dev/zero of=/tmp/host_test_read_${j} bs=1m count=$SIZE status=none
    done
    START=$(DATE_CMD)
    for j in {1..4}; do
        dd if=/tmp/host_test_read_${j} of=/dev/null bs=1m status=none
    done
    END=$(DATE_CMD)
    DURATION=$(( (END - START) / 1000000 ))
    mem_read_times+=($DURATION)
    echo "  Read test: ${DURATION}ms"
    rm -f /tmp/host_test_read_*

    # Save total MB processed in 4 iterations
    mem_sizes+=($(( SIZE * 4 )))
done

# ------------------------
# Disk I/O Benchmark
# ------------------------
echo -e "\nRunning disk I/O benchmark..."
echo "Sequential write test (3 iterations):"
for i in {1..3}; do
    START=$(DATE_CMD)
    dd if=/dev/zero of=/tmp/host_test_seq bs=1m count=4096 oflag=sync status=none
    END=$(DATE_CMD)
    DURATION=$(( (END - START) / 1000000 ))
    disk_seq_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
    rm -f /tmp/host_test_seq
done

echo "Random write test (3 iterations):"
for i in {1..3}; do
    START=$(DATE_CMD)
    dd if=/dev/urandom of=/tmp/host_test_rand bs=8k count=32768 oflag=sync status=none
    END=$(DATE_CMD)
    DURATION=$(( (END - START) / 1000000 ))
    disk_rand_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
    rm -f /tmp/host_test_rand
done

echo "Mixed read/write test (3 iterations):"
for i in {1..3}; do
    dd if=/dev/zero of=/tmp/host_test_mixed bs=1m count=2048 status=none
    sync
    START=$(DATE_CMD)
    ( for j in {1..2}; do
          dd if=/tmp/host_test_mixed of=/dev/null bs=1m count=2048 status=none &
          dd if=/dev/zero of=/tmp/host_test_mixed2_${j} bs=1m count=1024 oflag=sync status=none &
      done
      wait )
    END=$(DATE_CMD)
    DURATION=$(( (END - START) / 1000000 ))
    disk_mixed_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
    rm -f /tmp/host_test_mixed /tmp/host_test_mixed2_*
done

# ------------------------
# Network Benchmark
# ------------------------
echo -e "\nRunning network benchmark..."
ENDPOINTS=("https://www.google.com" "https://www.cloudflare.com" "https://www.amazon.com")
for endpoint in "${ENDPOINTS[@]}"; do
    echo "Testing endpoint: $endpoint"
    for i in {1..3}; do
        START=$(DATE_CMD)
        for j in {1..20}; do
            curl -s -o /dev/null "$endpoint" &
        done
        wait
        END=$(DATE_CMD)
        DURATION=$(( (END - START) / 1000000 ))
        echo "  Iteration $i: ${DURATION}ms"
    done
done

echo "Network latency test:"
for i in {1..3}; do
    LATENCY=$(ping -c 1 8.8.8.8 | grep -Eo '([0-9]*\.[0-9]+)' | sed -n '3p')
    [ -z "$LATENCY" ] && LATENCY=0
    network_latency_times+=("$LATENCY")
    echo "  Iteration $i: ${LATENCY}ms"
done

# ------------------------
# Summary Section
# ------------------------
echo -e "\nBenchmark Summary:"
echo "===================="
echo "CPU Performance:"
if [ ${#cpu_hash_times[@]} -eq 3 ]; then
    hash_sum=0
    for t in "${cpu_hash_times[@]}"; do
        hash_sum=$(( hash_sum + t ))
    done
    hash_avg=$(echo "scale=2; $hash_sum / 3" | bc)
    # 1200MB processed in each iteration
    hash_speed=$(echo "scale=2; 1200 / $hash_avg * 1000" | bc)
    echo "  - SHA256 Hash: ${hash_avg}ms (${hash_speed} MB/s)"
fi
if [ ${#cpu_comp_times[@]} -eq 3 ]; then
    comp_sum=0
    for t in "${cpu_comp_times[@]}"; do
        comp_sum=$(( comp_sum + t ))
    done
    comp_avg=$(echo "scale=2; $comp_sum / 3" | bc)
    comp_speed=$(echo "scale=2; 128 / $comp_avg * 1000" | bc)
    echo "  - Compression: ${comp_avg}ms (${comp_speed} MB/s)"
fi
if [ ${#cpu_pi_times[@]} -eq 3 ]; then
    pi_sum=0
    for t in "${cpu_pi_times[@]}"; do
        pi_sum=$(( pi_sum + t ))
    done
    pi_avg=$(echo "scale=2; $pi_sum / 3" | bc)
    echo "  - Pi Calculation: Average time: ${pi_avg}ms"
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
    disk_seq_sum=0
    for t in "${disk_seq_times[@]}"; do
        disk_seq_sum=$(( disk_seq_sum + t ))
    done
    disk_seq_avg=$(echo "scale=2; $disk_seq_sum / 3" | bc)
    seq_speed=$(echo "scale=2; 4096 / $disk_seq_avg * 1000" | bc)
    echo "  - Sequential write: ${seq_speed} MB/s"
fi
if [ ${#disk_rand_times[@]} -eq 3 ]; then
    disk_rand_sum=0
    for t in "${disk_rand_times[@]}"; do
        disk_rand_sum=$(( disk_rand_sum + t ))
    done
    disk_rand_avg=$(echo "scale=2; $disk_rand_sum / 3" | bc)
    # 32768 blocks * 8K = 256 MB written per iteration
    rand_speed=$(echo "scale=2; 256 / $disk_rand_avg * 1000" | bc)
    echo "  - Random write: ${rand_speed} MB/s"
fi
if [ ${#disk_mixed_times[@]} -eq 3 ]; then
    disk_mixed_sum=0
    for t in "${disk_mixed_times[@]}"; do
        disk_mixed_sum=$(( disk_mixed_sum + t ))
    done
    disk_mixed_avg=$(echo "scale=2; $disk_mixed_sum / 3" | bc)
    # Mixed test: read: 2048MB*2 = 4096MB total, write: 1024MB*2 = 2048MB total.
    read_throughput=$(echo "scale=2; 4096 / $disk_mixed_avg * 1000" | bc)
    write_throughput=$(echo "scale=2; 2048 / $disk_mixed_avg * 1000" | bc)
    echo "  - Mixed I/O: ${read_throughput} MB/s read, ${write_throughput} MB/s write"
fi

echo -e "\nNetwork Performance:"
if [ ${#network_latency_times[@]} -eq 3 ]; then
    net_latency_sum=0
    for t in "${network_latency_times[@]}"; do
        # Use bc for floating point arithmetic
        net_latency_sum=$(echo "$net_latency_sum + $t" | bc)
    done
    net_latency_avg=$(echo "scale=2; $net_latency_sum / 3" | bc)
    echo "  - Average latency: ${net_latency_avg}ms"
fi

echo -e "\nBenchmark completed!"

