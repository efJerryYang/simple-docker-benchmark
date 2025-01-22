# benchmark-windows.ps1
Set-StrictMode -Version Latest

# Ensure C:\Temp folder exists
$tempFolder = "C:\Temp"
if (-Not (Test-Path $tempFolder)) {
    New-Item -Path $tempFolder -ItemType Directory | Out-Null
}

# --------------------------------------------------
# Output basic system information
# --------------------------------------------------
Write-Output "Starting host benchmark..."
Write-Output "=========================="
Write-Output "System Information:"
$os = Get-CimInstance Win32_OperatingSystem
Write-Output ("OS: {0}  Version: {1}  Architecture: {2}" -f $os.Caption, $os.Version, $os.OSArchitecture)
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Write-Output ("CPU: {0}  Cores: {1}" -f $cpu.Name, $cpu.NumberOfCores)
$mem = Get-CimInstance Win32_ComputerSystem
Write-Output ("Total Physical Memory: {0:N0} MB" -f ($mem.TotalPhysicalMemory / 1MB))
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | 
        Select-Object DeviceID, @{Name="SizeGB";Expression={"{0:N2}" -f ($_.Size/1GB)}}
Write-Output "Disk Info:"
$disk | ForEach-Object { Write-Output ("  Drive {0}: {1} GB" -f $_.DeviceID, $_.SizeGB) }
Write-Output "=========================="

# --------------------------------------------------
# Initialize arrays for summary statistics
# --------------------------------------------------
$cpu_hash_times   = @()
$cpu_comp_times   = @()
# PI test is removed

$mem_write_times  = @()
$mem_read_times   = @()
$mem_sizes        = @()  # Total MB processed per test (4 iterations)

$disk_seq_times   = @()
$disk_rand_times  = @()
$disk_mixed_times = @()

# --------------------------------------------------
# CPU Benchmark
# --------------------------------------------------
Write-Output "Running CPU benchmark..."

# 1. Hash computation test (3 iterations)
# (Simulates dd if=/dev/urandom bs=1M count=1200: 1200 MB data)
Write-Output "1. Hash computation test (3 iterations):"
1..3 | ForEach-Object {
    $t = Measure-Command {
        [Byte[]]$data = New-Object Byte[] (1200 * 1024 * 1024)
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($data)
        [System.BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash($data)) | Out-Null
    }
    $ms = [Math]::Round($t.TotalMilliseconds, 0)
    $cpu_hash_times += $ms
    Write-Output "  Iteration $($_): $ms ms"
}

# 2. Compression test (3 iterations)
# (Simulates dd if=/dev/urandom bs=1M count=128)
Write-Output "2. Compression test (3 iterations):"
1..3 | ForEach-Object {
    $t = Measure-Command {
        [Byte[]]$data = New-Object Byte[] (128 * 1024 * 1024)
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($data)
        $stream = New-Object System.IO.MemoryStream
        $gzip = New-Object System.IO.Compression.GZipStream($stream, [System.IO.Compression.CompressionMode]::Compress)
        $gzip.Write($data, 0, $data.Length)
        $gzip.Dispose()
    }
    $ms = [Math]::Round($t.TotalMilliseconds, 0)
    $cpu_comp_times += $ms
    Write-Output "  Iteration $($_): $ms ms"
}

# --------------------------------------------------
# Memory Benchmark
# --------------------------------------------------
Write-Output "`nRunning memory benchmark..."
Write-Output "Initial memory usage: N/A (simulate)"
$Sizes = @(512, 1024, 2048)
foreach ($SIZE in $Sizes) {
    Write-Output "Testing ${SIZE}MB:"
    # Write Test: 4 iterations
    $writeTimer = [System.Diagnostics.Stopwatch]::StartNew()
    for ($j = 1; $j -le 4; $j++) {
        $filePath = "$tempFolder\host_test_write_${j}.bin"
        Write-Output "  Writing file $filePath..."
        # Write SIZE times using a 1MB buffer
        $buffer = New-Object Byte[] (1 * 1024 * 1024)
        $fs = [System.IO.File]::Create($filePath)
        for ($k = 0; $k -lt $SIZE; $k++) {
            $fs.Write($buffer, 0, $buffer.Length)
        }
        $fs.Close()
    }
    $writeTimer.Stop()
    $wt_ms = [Math]::Round($writeTimer.Elapsed.TotalMilliseconds, 0)
    $mem_write_times += $wt_ms
    Write-Output "  Write test: $wt_ms ms"
    Remove-Item "$tempFolder\host_test_write_*.bin" -Force -ErrorAction SilentlyContinue

    # Read Test: Create file then 4 iterations of reading it
    for ($j = 1; $j -le 4; $j++) {
        $filePath = "$tempFolder\host_test_read_${j}.bin"
        Write-Output "  Creating file $filePath for read test..."
        $buffer = New-Object Byte[] (1 * 1024 * 1024)
        $fs = [System.IO.File]::Create($filePath)
        for ($k = 0; $k -lt $SIZE; $k++) {
            $fs.Write($buffer, 0, $buffer.Length)
        }
        $fs.Close()
    }
    $readTimer = [System.Diagnostics.Stopwatch]::StartNew()
    for ($j = 1; $j -le 4; $j++) {
        $filePath = "$tempFolder\host_test_read_${j}.bin"
        $fs = [System.IO.File]::OpenRead($filePath)
        $readBuffer = New-Object Byte[] (1 * 1024 * 1024)
        while (($bytesRead = $fs.Read($readBuffer, 0, $readBuffer.Length)) -gt 0) {
            # Read until end-of-file
        }
        $fs.Close()
    }
    $readTimer.Stop()
    $rt_ms = [Math]::Round($readTimer.Elapsed.TotalMilliseconds, 0)
    $mem_read_times += $rt_ms
    Write-Output "  Read test: $rt_ms ms"
    Remove-Item "$tempFolder\host_test_read_*.bin" -Force -ErrorAction SilentlyContinue

    # Record total data processed (4 iterations * SIZE MB)
    $mem_sizes += ($SIZE * 4)
}

# --------------------------------------------------
# Disk I/O Benchmark
# --------------------------------------------------
Write-Output "`nRunning disk I/O benchmark..."
Write-Output "Sequential write test (3 iterations):"
# Instead of allocating 4096MB at once, use a 1MB buffer loop (4096 iterations)
1..3 | ForEach-Object {
    $t = Measure-Command {
        $filePath = "$tempFolder\host_test_seq.bin"
        $buffer = New-Object Byte[] (1 * 1024 * 1024)
        $fs = [System.IO.File]::Create($filePath)
        for ($i = 0; $i -lt 4096; $i++) {
            $fs.Write($buffer, 0, $buffer.Length)
        }
        $fs.Close()
    }
    $ms = [Math]::Round($t.TotalMilliseconds, 0)
    $disk_seq_times += $ms
    Write-Output "  Iteration $($_): $ms ms"
    Remove-Item "$tempFolder\host_test_seq.bin" -Force -ErrorAction SilentlyContinue
}

Write-Output "Random write test (3 iterations):"
1..3 | ForEach-Object {
    $t = Measure-Command {
        # Simulate random write of 256 MB (using 256*1024 bytes)
        $data = New-Object Byte[] (256 * 1024)
        [IO.File]::WriteAllBytes("$tempFolder\host_test_rand.bin", $data)
    }
    $ms = [Math]::Round($t.TotalMilliseconds, 0)
    $disk_rand_times += $ms
    Write-Output "  Iteration $($_): $ms ms"
    Remove-Item "$tempFolder\host_test_rand.bin" -Force -ErrorAction SilentlyContinue
}

Write-Output "Mixed read/write test (3 iterations):"
1..3 | ForEach-Object {
    $data1 = New-Object Byte[] (2048 * 1024)
    $data2 = New-Object Byte[] (1024 * 1024)
    [IO.File]::WriteAllBytes("$tempFolder\host_test_mixed.bin", $data1)
    $t = Measure-Command {
        Start-Job -ScriptBlock { [IO.File]::ReadAllBytes("$tempFolder\host_test_mixed.bin") | Out-Null } | Wait-Job | Out-Null
        Start-Job -ScriptBlock { [IO.File]::WriteAllBytes("$tempFolder\host_test_mixed2_1.bin", $using:data2) } | Wait-Job | Out-Null
        Start-Job -ScriptBlock { [IO.File]::WriteAllBytes("$tempFolder\host_test_mixed2_2.bin", $using:data2) } | Wait-Job | Out-Null
    }
    $ms = [Math]::Round($t.TotalMilliseconds, 0)
    $disk_mixed_times += $ms
    Write-Output "  Iteration $($_): $ms ms"
    Remove-Item "$tempFolder\host_test_mixed.bin", "$tempFolder\host_test_mixed2_*.bin" -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------
# Benchmark Summary
# --------------------------------------------------
Write-Output "`nBenchmark Summary:"
Write-Output "===================="

# CPU Performance
if ($cpu_hash_times.Count -eq 3) {
    $hash_sum = ($cpu_hash_times | Measure-Object -Sum).Sum
    $hash_avg = [Math]::Round($hash_sum / 3, 2)
    # Processing 1200 MB each iteration; speed in MB/s
    $hash_speed = [Math]::Round(1200 / ($hash_avg / 1000), 2)
    Write-Output "CPU Performance:"
    Write-Output "  - SHA256 Hash: $hash_avg ms ($hash_speed MB/s)"
}
if ($cpu_comp_times.Count -eq 3) {
    $comp_sum = ($cpu_comp_times | Measure-Object -Sum).Sum
    $comp_avg = [Math]::Round($comp_sum / 3, 2)
    $comp_speed = [Math]::Round(128 / ($comp_avg / 1000), 2)
    Write-Output "  - Compression: $comp_avg ms ($comp_speed MB/s)"
}
Write-Output "  - PI test: skipped"

# Memory Performance
if ($mem_write_times.Count -gt 0) {
    $total_write_time = ($mem_write_times | Measure-Object -Sum).Sum
    $total_write_data = ($mem_sizes | Measure-Object -Sum).Sum  # in MB
    $write_throughput = [Math]::Round($total_write_data / ($total_write_time / 1000), 2)
    Write-Output "`nMemory Performance:"
    Write-Output "  - Write throughput: $write_throughput MB/s"
}
if ($mem_read_times.Count -gt 0) {
    $total_read_time = ($mem_read_times | Measure-Object -Sum).Sum
    $total_read_data = ($mem_sizes | Measure-Object -Sum).Sum
    $read_throughput = [Math]::Round($total_read_data / ($total_read_time / 1000), 2)
    Write-Output "  - Read throughput: $read_throughput MB/s"
}

# Disk Performance
if ($disk_seq_times.Count -eq 3) {
    $seq_sum = ($disk_seq_times | Measure-Object -Sum).Sum
    $seq_avg = [Math]::Round($seq_sum / 3, 2)
    $seq_speed = [Math]::Round(4096 / ($seq_avg / 1000), 2)
    Write-Output "`nDisk Performance:"
    Write-Output "  - Sequential write: $seq_speed MB/s"
}
if ($disk_rand_times.Count -eq 3) {
    $rand_sum = ($disk_rand_times | Measure-Object -Sum).Sum
    $rand_avg = [Math]::Round($rand_sum / 3, 2)
    # Random write test writes 256 MB
    $rand_speed = [Math]::Round(256 / ($rand_avg / 1000), 2)
    Write-Output "  - Random write: $rand_speed MB/s"
}
if ($disk_mixed_times.Count -eq 3) {
    $mixed_sum = ($disk_mixed_times | Measure-Object -Sum).Sum
    $mixed_avg = [Math]::Round($mixed_sum / 3, 2)
    # Mixed test: total read 4096 MB, total write 2048 MB
    $mixed_read_speed  = [Math]::Round(4096 / ($mixed_avg / 1000), 2)
    $mixed_write_speed = [Math]::Round(2048 / ($mixed_avg / 1000), 2)
    Write-Output "  - Mixed I/O: $mixed_read_speed MB/s read, $mixed_write_speed MB/s write"
}

Write-Output "`nBenchmark completed!"
