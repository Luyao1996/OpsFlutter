# Minimal Windows Minidump parser: locate module of a crash address and dump thread/exception info.
# Usage: powershell -File parse_minidump.ps1 -DumpPath <path> [-Address 0xNNNN]
param(
    [Parameter(Mandatory=$true)][string]$DumpPath,
    [string]$Address = ""
)

$ErrorActionPreference = "Stop"
$bytes = [System.IO.File]::ReadAllBytes($DumpPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$br = New-Object System.IO.BinaryReader($ms)

# MINIDUMP_HEADER
$sig = $br.ReadUInt32()
if ($sig -ne 0x504D444D) { throw "Not a minidump: sig=0x$($sig.ToString('X'))" }
$ver = $br.ReadUInt32()
$numStreams = $br.ReadUInt32()
$dirRva = $br.ReadUInt32()
$null = $br.ReadUInt32() # checksum
$null = $br.ReadUInt32() # timestamp
$null = $br.ReadUInt64() # flags

Write-Host "Minidump: Streams=$numStreams DirRva=0x$($dirRva.ToString('X'))"

function Read-MiniString([System.IO.BinaryReader]$r, [uint32]$rva) {
    $r.BaseStream.Position = $rva
    $len = $r.ReadUInt32()
    $buf = $r.ReadBytes($len)
    return [System.Text.Encoding]::Unicode.GetString($buf)
}

$ms.Position = $dirRva
$dirs = @()
for ($i = 0; $i -lt $numStreams; $i++) {
    $streamType = $br.ReadUInt32()
    $dataSize = $br.ReadUInt32()
    $rva = $br.ReadUInt32()
    $dirs += [PSCustomObject]@{Type=$streamType; Size=$dataSize; Rva=$rva}
}

$addrU = 0
if ($Address) {
    $addrU = [Convert]::ToUInt64($Address.Replace('0x',''), 16)
    Write-Host ("Query Address: 0x{0:X16}" -f $addrU)
}

foreach ($d in $dirs) {
    switch ($d.Type) {
        4 { # ModuleListStream
            Write-Host "`n=== ModuleListStream (size=$($d.Size)) ==="
            $ms.Position = $d.Rva
            $numMods = $br.ReadUInt32()
            Write-Host "NumberOfModules: $numMods"
            for ($i = 0; $i -lt $numMods; $i++) {
                $base = $br.ReadUInt64()
                $size = $br.ReadUInt32()
                $null = $br.ReadUInt32() # checksum
                $null = $br.ReadUInt32() # timestamp
                $nameRva = $br.ReadUInt32()
                $null = $br.ReadBytes(52) # VS_FIXEDFILEINFO
                $null = $br.ReadUInt32(); $null = $br.ReadUInt32() # CvRecord
                $null = $br.ReadUInt32(); $null = $br.ReadUInt32() # MiscRecord
                $null = $br.ReadUInt64(); $null = $br.ReadUInt64() # reserved
                $pos = $ms.Position
                $name = Read-MiniString $br $nameRva
                $ms.Position = $pos
                $end = $base + $size
                $hit = ""
                if ($addrU -ne 0 -and $addrU -ge $base -and $addrU -lt $end) {
                    $offset = $addrU - $base
                    $hit = "  <==  HIT offset=+0x{0:X}" -f $offset
                }
                $line = "[{0,3}] 0x{1:X16}-0x{2:X16} size=0x{3:X8} {4}{5}" -f $i,$base,$end,$size,$name,$hit
                Write-Host $line
            }
        }
        6 { # ExceptionStream
            Write-Host "`n=== ExceptionStream ==="
            $ms.Position = $d.Rva
            $threadId = $br.ReadUInt32()
            $null = $br.ReadUInt32() # alignment
            $excCode = $br.ReadUInt32()
            $excFlags = $br.ReadUInt32()
            $excRecPtr = $br.ReadUInt64()
            $excAddr = $br.ReadUInt64()
            $numParam = $br.ReadUInt32()
            $null = $br.ReadUInt32() # alignment
            $params = @()
            for ($j = 0; $j -lt 15; $j++) { $params += $br.ReadUInt64() }
            Write-Host ("ThreadId      : {0}" -f $threadId)
            Write-Host ("ExceptionCode : 0x{0:X8}" -f $excCode)
            Write-Host ("ExceptionFlags: 0x{0:X8}" -f $excFlags)
            Write-Host ("ExceptionAddr : 0x{0:X16}" -f $excAddr)
            Write-Host ("NumParameters : {0}" -f $numParam)
            for ($j = 0; $j -lt $numParam; $j++) {
                Write-Host ("  Param[{0}]    : 0x{1:X16}" -f $j, $params[$j])
            }
        }
        3 { # ThreadListStream  -> just count
            $ms.Position = $d.Rva
            $n = $br.ReadUInt32()
            Write-Host "ThreadList: $n threads"
        }
        7 { # SystemInfoStream
            Write-Host "`n=== SystemInfoStream ==="
            $ms.Position = $d.Rva
            $procArch = $br.ReadUInt16()
            $procLevel = $br.ReadUInt16()
            $procRev = $br.ReadUInt16()
            $numCpu = $br.ReadByte()
            $prodType = $br.ReadByte()
            $major = $br.ReadUInt32()
            $minor = $br.ReadUInt32()
            $build = $br.ReadUInt32()
            $platformId = $br.ReadUInt32()
            Write-Host ("ProcessorArch: {0} (0=x86,9=x64,12=ARM64)" -f $procArch)
            Write-Host ("NumberOfCPUs : {0}" -f $numCpu)
            Write-Host ("Windows      : {0}.{1}.{2} platform={3}" -f $major,$minor,$build,$platformId)
        }
    }
}

$br.Close()
$ms.Close()
