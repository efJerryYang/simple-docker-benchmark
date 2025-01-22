#!/bin/bash

set -e
# Trap errors, printing the command that failed along with its line number
trap 'echo "Error on line $LINENO: command -> $BASH_COMMAND"' ERR

# Initialize arrays for storing results
declare -a hash_times=()
declare -a comp_times=()
declare -a mem_write_times=()
declare -a mem_read_times=()
declare -a disk_seq_write_times=()
declare -a disk_rand_write_times=()
declare -a disk_mixed_times=()
declare -a network_latency_times=()

validate_result() {
    local duration=$1
    local test_name=$2
    local threshold=$3
    if [ $duration -lt $threshold ]; then
        echo "Warning: $test_name completed too quickly ($duration ms), results may be unreliable"
    fi
}

# System info section
echo "Starting container benchmark..."
echo "=========================="
echo "System Information:"
uname -a

echo "CPU Info:"
# Check for both 'model name' (x86) or 'Processor' (ARM) and display unique info.
if grep -q "model name" /proc/cpuinfo; then
    grep "model name" /proc/cpuinfo | uniq
elif grep -q "Processor" /proc/cpuinfo; then
    grep "Processor" /proc/cpuinfo | uniq
fi
nproc

echo "Memory Info:"
free -h

echo "Disk Info:"
df -h

echo "Network Info:"
ip addr show
echo "=========================="

# CPU Test - Adjusted for target duration
echo "Running CPU benchmark..."

# 1. Hash computation test (3 iterations)
echo "1. Hash computation test (3 iterations):"
for i in {1..3}; do
    START_TIME=$(date +%s%N)
    dd if=/dev/urandom bs=1M count=1200 2>/dev/null | sha256sum >/dev/null
    END_TIME=$(date +%s%N)
    DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
    hash_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
done

# 2. Compression test (3 iterations)
echo "2. Compression test (3 iterations):"
for i in {1..3}; do
    START_TIME=$(date +%s%N)
    dd if=/dev/urandom bs=1M count=128 2>/dev/null | gzip > /dev/null
    END_TIME=$(date +%s%N)
    DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
    comp_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
done

# 3. Pi calculation test (3 iterations)
echo "3. Pi calculation test (3 iterations):"
for i in {1..3}; do
    START_TIME=$(date +%s%N)
    echo "scale=2500; 4*a(1)" | bc -l >/dev/null
    END_TIME=$(date +%s%N)
    DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
    echo "  Iteration $i: ${DURATION}ms"
done

# Memory Test - Using a size array so summary calculations are explicit.
echo -e "\nRunning memory benchmark..."
FREE_MEM=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2 }')
echo "Initial memory usage: ${FREE_MEM}%"

# Define the sizes to test in MB
SIZE_LIST=(512 1024 2048)

# Store throughput data for summary (we assume 4 iterations per size)
declare -a mem_sizes=()  # This will store total MB per each size test (size * 4)
for SIZE in "${SIZE_LIST[@]}"; do
    echo "Testing ${SIZE}MB:"
    # Write test with 4 iterations
    START_TIME=$(date +%s%N)
    for j in {1..4}; do
        dd if=/dev/zero of=/tmp/test_write_${j} bs=1M count=$SIZE 2>/dev/null
        sync
    done
    END_TIME=$(date +%s%N)
    DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
    mem_write_times+=($DURATION)
    echo "  Write test: ${DURATION}ms"
    rm -f /tmp/test_write_*

    # Read test with 4 iterations
    # Note: The file is created and then read; caching may affect these results.
    for j in {1..4}; do
        dd if=/dev/zero of=/tmp/test_read_${j} bs=1M count=$SIZE 2>/dev/null
    done
    START_TIME=$(date +%s%N)
    for j in {1..4}; do
        dd if=/tmp/test_read_${j} of=/dev/null bs=1M 2>/dev/null
    done
    END_TIME=$(date +%s%N)
    DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
    mem_read_times+=($DURATION)
    echo "  Read test: ${DURATION}ms"
    rm -f /tmp/test_read_*
    
    # Save total data processed for this SIZE (MB) is SIZE * 4 iterations
    mem_sizes+=($((SIZE * 4)))
done

# Memory latency test
echo "Memory latency test:"
for SIZE in 16 32 64; do
    dd if=/dev/zero of=/tmp/test_latency bs=1M count=1024 2>/dev/null
    START_TIME=$(date +%s%N)
    for j in {1..2000}; do
        dd if=/tmp/test_latency of=/dev/null bs=${SIZE}k count=1 skip=$((RANDOM % 1024)) 2>/dev/null
    done
    END_TIME=$(date +%s%N)
    DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
    echo "Random access latency (${SIZE}K blocks): ${DURATION}ms"
    rm -f /tmp/test_latency
done

# Disk I/O Test - Adjusted for target duration
echo -e "\nRunning disk I/O benchmark..."
echo "Sequential write test (3 iterations):"
for i in {1..3}; do
    START_TIME=$(date +%s%N)
    dd if=/dev/zero of=/tmp/test_seq bs=1M count=4096 conv=fdatasync 2>/dev/null
    END_TIME=$(date +%s%N)
    DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
    disk_seq_write_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
    rm -f /tmp/test_seq
done

echo "Random write test (3 iterations):"
for i in {1..3}; do
    START_TIME=$(date +%s%N)
    dd if=/dev/urandom of=/tmp/test_rand bs=8k count=32768 conv=fdatasync 2>/dev/null
    END_TIME=$(date +%s%N)
    DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
    disk_rand_write_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
    rm -f /tmp/test_rand
done

echo "Mixed read/write test (3 iterations):"
for i in {1..3}; do
    dd if=/dev/zero of=/tmp/test_mixed bs=1M count=2048 2>/dev/null
    sync
    START_TIME=$(date +%s%N)
    ( for j in {1..2}; do
          dd if=/tmp/test_mixed of=/dev/null bs=1M count=2048 2>/dev/null &
          dd if=/dev/zero of=/tmp/test_mixed2_${j} bs=1M count=1024 conv=fdatasync 2>/dev/null &
      done
      wait )
    END_TIME=$(date +%s%N)
    DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
    disk_mixed_times+=($DURATION)
    echo "  Iteration $i: ${DURATION}ms"
    rm -f /tmp/test_mixed /tmp/test_mixed2_*
done

# Network Test - Multiple requests per iteration
echo -e "\nRunning network benchmark..."
ENDPOINTS=(
    "https://www.google.com"
    "https://www.cloudflare.com"
    "https://www.amazon.com"
)

for endpoint in "${ENDPOINTS[@]}"; do
    echo "Testing endpoint: $endpoint"
    for i in {1..3}; do
        START_TIME=$(date +%s%N)
        for j in {1..20}; do
            curl -s -o /dev/null "$endpoint" &
        done
        wait
        END_TIME=$(date +%s%N)
        DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
        echo "  Iteration $i: ${DURATION}ms"
    done
done

# Network latency test using ping
echo "Network latency test:"
for i in {1..3}; do
    # Using grep to extract the avg latency from ping output
    LATENCY=$(ping -c 1 8.8.8.8 | grep -Eo '([0-9]*\.[0-9]+)' | sed -n '3p')
    # Fallback in case parsing fails
    if [ -z "$LATENCY" ]; then
        LATENCY=0
    fi
    network_latency_times+=("$LATENCY")
    echo "  Iteration $i: ${LATENCY}ms"
done

# Summary section
echo -e "\nBenchmark Summary:"
echo "===================="
echo "CPU Performance:"
if [ ${#hash_times[@]} -eq 3 ]; then
    hash_sum=0
    for t in "${hash_times[@]}"; do
        hash_sum=$(echo "$hash_sum + $t" | bc)
    done
    hash_avg=$(echo "scale=2; $hash_sum / 3" | bc)
    hash_speed=$(echo "scale=2; 1200 / $hash_avg * 1000" | bc)
    echo "  - SHA256 Hash: ${hash_avg}ms (${hash_speed} MB/s)"
fi
if [ ${#comp_times[@]} -eq 3 ]; then
    comp_sum=0
    for t in "${comp_times[@]}"; do
        comp_sum=$(echo "$comp_sum + $t" | bc)
    done
    comp_avg=$(echo "scale=2; $comp_sum / 3" | bc)
    comp_speed=$(echo "scale=2; 128 / $comp_avg * 1000" | bc)
    echo "  - Compression: ${comp_avg}ms (${comp_speed} MB/s)"
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
if [ ${#disk_seq_write_times[@]} -eq 3 ]; then
    disk_seq_sum=0
    for t in "${disk_seq_write_times[@]}"; do
        disk_seq_sum=$(echo "$disk_seq_sum + $t" | bc)
    done
    disk_seq_avg=$(echo "scale=2; $disk_seq_sum / 3" | bc)
    seq_speed=$(echo "scale=2; 4096 / $disk_seq_avg * 1000" | bc)
    echo "  - Sequential write: ${seq_speed} MB/s"
fi
if [ ${#disk_rand_write_times[@]} -eq 3 ]; then
    disk_rand_sum=0
    for t in "${disk_rand_write_times[@]}"; do
        disk_rand_sum=$(echo "$disk_rand_sum + $t" | bc)
    done
    disk_rand_avg=$(echo "scale=2; $disk_rand_sum / 3" | bc)
    # 32768 blocks * 8K = 32768*8/1024 = 256 MB written per iteration.
    rand_speed=$(echo "scale=2; 256 / $disk_rand_avg * 1000" | bc)
    echo "  - Random write: ${rand_speed} MB/s"
fi
if [ ${#disk_mixed_times[@]} -eq 3 ]; then
    disk_mixed_sum=0
    for t in "${disk_mixed_times[@]}"; do
        disk_mixed_sum=$(echo "$disk_mixed_sum + $t" | bc)
    done
    disk_mixed_avg=$(echo "scale=2; $disk_mixed_sum / 3" | bc)
    # For the mixed test: read: 2048MB*2 = 4096MB total, write: 1024MB*2 = 2048MB total.
    read_throughput=$(echo "scale=2; 4096 / $disk_mixed_avg * 1000" | bc)
    write_throughput=$(echo "scale=2; 2048 / $disk_mixed_avg * 1000" | bc)
    echo "  - Mixed I/O: ${read_throughput} MB/s read, ${write_throughput} MB/s write"
fi

echo -e "\nNetwork Performance:"
if [ ${#network_latency_times[@]} -eq 3 ]; then
    net_latency_sum=0
    for t in "${network_latency_times[@]}"; do
        net_latency_sum=$(echo "$net_latency_sum + $t" | bc)
    done
    net_latency_avg=$(echo "scale=2; $net_latency_sum / 3" | bc)
    echo "  - Average latency: ${net_latency_avg}ms"
fi

echo -e "\nBenchmark completed!"

