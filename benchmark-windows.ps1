# benchmark-windows.ps1
Set-StrictMode -Version Latest

Write-Output "Starting host benchmark..."
Write-Output "=========================="
Write-Output "System Information:"
Write-Output (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture)
Write-Output "CPU Info:"
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores
Write-Output "Memory Info:"
Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize, FreePhysicalMemory
Write-Output "Disk Info:"
Get-PSDrive -PSProvider 'FileSystem'
Write-Output "Network Info:"
Get-NetIPConfiguration
Write-Output "=========================="

# The following tests are approximations
# CPU Benchmark (simulate operations with Measure-Command)

Write-Output "Running CPU benchmark..."

Write-Output "1. Hash computation test (3 iterations):"
1..3 | ForEach-Object {
    $t = Measure-Command {
        # Generating random data and computing SHA256 using .NET
        [Byte[]]$data = New-Object Byte[] (1200 * 1024 * 1)
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($data)
        [System.BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash($data)) | Out-Null
    }
    $ms = [Math]::Round($t.TotalMilliseconds,0)
    Write-Output "  Iteration $_: ${ms}ms"
}

Write-Output "2. Compression test (3 iterations):"
1..3 | ForEach-Object {
    $t = Measure-Command {
        # Simulating compression using .NET
        [Byte[]]$data = New-Object Byte[] (128 * 1024 * 1)
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($data)
        $stream = New-Object System.IO.MemoryStream
        $gzip = New-Object System.IO.Compression.GZipStream($stream, [System.IO.Compression.CompressionMode]::Compress)
        $gzip.Write($data,0, $data.Length)
        $gzip.Dispose()
    }
    $ms = [Math]::Round($t.TotalMilliseconds,0)
    Write-Output "  Iteration $_: ${ms}ms"
}

Write-Output "3. Pi calculation test (3 iterations):"
1..3 | ForEach-Object {
    $t = Measure-Command {
        # Approximate pi calculation using the Leibniz formula
        $iterations = 2500
        $pi = 0.0
        for ($i=0; $i -lt $iterations; $i++) {
            $pi += ((-1) ** $i) / (2*$i+1)
        }
        $pi = 4 * $pi
    }
    $ms = [Math]::Round($t.TotalMilliseconds,0)
    Write-Output "  Iteration $_: ${ms}ms"
}

# Memory Benchmark (simulate write and read tests using file operations)
Write-Output "`nRunning memory benchmark..."
Write-Output "Initial memory usage: N/A (simulate)"
$Sizes = @(512,1024,2048)
foreach ($SIZE in $Sizes) {
    Write-Output "Testing ${SIZE}MB:"
    # Write test: write a file with $SIZE MB four times
    $fileData = New-Object Byte[] ($SIZE * 1024 * 1024)
    $writeTimer = [System.Diagnostics.Stopwatch]::StartNew()
    for ($j=1; $j -le 4; $j++) {
        [IO.File]::WriteAllBytes("C:\Temp\host_test_write_$j.bin", $fileData)
    }
    $writeTimer.Stop()
    Write-Output "  Write test: $([Math]::Round($writeTimer.Elapsed.TotalMilliseconds,0))ms"
    Remove-Item C:\Temp\host_test_write_*.bin -Force -ErrorAction SilentlyContinue

    # Read test: read the file four times (simulate by writing then reading)
    for ($j=1; $j -le 4; $j++) {
        [IO.File]::WriteAllBytes("C:\Temp\host_test_read_$j.bin", $fileData)
    }
    $readTimer = [System.Diagnostics.Stopwatch]::StartNew()
    for ($j=1; $j -le 4; $j++) {
        [IO.File]::ReadAllBytes("C:\Temp\host_test_read_$j.bin") | Out-Null
    }
    $readTimer.Stop()
    Write-Output "  Read test: $([Math]::Round($readTimer.Elapsed.TotalMilliseconds,0))ms"
    Remove-Item C:\Temp\host_test_read_*.bin -Force -ErrorAction SilentlyContinue
}

# Disk I/O Benchmark (simulate sequential and random writes)
Write-Output "`nRunning disk I/O benchmark..."
Write-Output "Sequential write test (3 iterations):"
1..3 | ForEach-Object {
    $t = Measure-Command {
        $data = New-Object Byte[] (4096 * 1024 * 1)
        [IO.File]::WriteAllBytes("C:\Temp\host_test_seq.bin", $data)
    }
    $ms = [Math]::Round($t.TotalMilliseconds,0)
    Write-Output "  Iteration $_: ${ms}ms"
    Remove-Item C:\Temp\host_test_seq.bin -Force -ErrorAction SilentlyContinue
}

Write-Output "Random write test (3 iterations):"
1..3 | ForEach-Object {
    $t = Measure-Command {
        $data = New-Object Byte[] (256 * 1024)
        [IO.File]::WriteAllBytes("C:\Temp\host_test_rand.bin", $data)
    }
    $ms = [Math]::Round($t.TotalMilliseconds,0)
    Write-Output "  Iteration $_: ${ms}ms"
    Remove-Item C:\Temp\host_test_rand.bin -Force -ErrorAction SilentlyContinue
}

Write-Output "Mixed read/write test (3 iterations):"
1..3 | ForEach-Object {
    # Create two files and perform read and write in parallel (simulate)
    $data1 = New-Object Byte[] (2048 * 1024)
    $data2 = New-Object Byte[] (1024 * 1024)
    [IO.File]::WriteAllBytes("C:\Temp\host_test_mixed.bin", $data1)
    $t = Measure-Command {
        Start-Job -ScriptBlock { [IO.File]::ReadAllBytes("C:\Temp\host_test_mixed.bin") | Out-Null } | Wait-Job | Out-Null
        Start-Job -ScriptBlock { [IO.File]::WriteAllBytes("C:\Temp\host_test_mixed2_1.bin", $using:data2) } | Wait-Job | Out-Null
        Start-Job -ScriptBlock { [IO.File]::WriteAllBytes("C:\Temp\host_test_mixed2_2.bin", $using:data2) } | Wait-Job | Out-Null
    }
    $ms = [Math]::Round($t.TotalMilliseconds,0)
    Write-Output "  Iteration $_: ${ms}ms"
    Remove-Item C:\Temp\host_test_mixed.bin, C:\Temp\host_test_mixed2_*.bin -Force -ErrorAction SilentlyContinue
}

# Network Benchmark
Write-Output "`nRunning network benchmark..."
$endpoints = @("https://www.google.com", "https://www.cloudflare.com", "https://www.amazon.com")
foreach ($endpoint in $endpoints) {
    Write-Output "Testing endpoint: $endpoint"
    1..3 | ForEach-Object {
        $t = Measure-Command {
            1..20 | ForEach-Object { Invoke-WebRequest -Uri $endpoint -UseBasicParsing | Out-Null }
        }
        $ms = [Math]::Round($t.TotalMilliseconds,0)
        Write-Output "  Iteration $_: ${ms}ms"
    }
}

Write-Output "Network latency test:"
1..3 | ForEach-Object {
    $ping = Test-Connection -Count 1 -ComputerName 8.8.8.8 -ErrorAction SilentlyContinue
    $latency = if ($ping) { [Math]::Round($ping.ResponseTime,0) } else { 0 }
    Write-Output "  Iteration $_: ${latency}ms"
}

Write-Output "`nBenchmark Summary:"
Write-Output "===================="
Write-Output "Benchmark completed!"

