# Naive stack walker: for a target thread, scan its stack memory for QWORDs that fall inside
# any loaded module's code range, and print unique hits in stack order. Good enough to tell
# "which DLLs are on the call chain" without PDBs.
param(
    [Parameter(Mandatory=$true)][string]$DumpPath,
    [Parameter(Mandatory=$true)][int]$ThreadId
)

$ErrorActionPreference = "Stop"
$bytes = [System.IO.File]::ReadAllBytes($DumpPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$br = New-Object System.IO.BinaryReader($ms)

$sig = $br.ReadUInt32()
if ($sig -ne 0x504D444D) { throw "not a minidump" }
$null = $br.ReadUInt32()
$numStreams = $br.ReadUInt32()
$dirRva = $br.ReadUInt32()
$null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $null = $br.ReadUInt64()

$ms.Position = $dirRva
$dirs = @()
for ($i=0;$i -lt $numStreams;$i++){
    $t=$br.ReadUInt32(); $sz=$br.ReadUInt32(); $rva=$br.ReadUInt32()
    $dirs += [PSCustomObject]@{Type=$t;Size=$sz;Rva=$rva}
}

function Read-MiniString([System.IO.BinaryReader]$r,[uint32]$rva){
    $r.BaseStream.Position=$rva; $len=$r.ReadUInt32(); $buf=$r.ReadBytes($len)
    return [System.Text.Encoding]::Unicode.GetString($buf)
}

# Gather modules
$mods = @()
foreach($d in $dirs){
    if($d.Type -eq 4){
        $ms.Position=$d.Rva
        $n=$br.ReadUInt32()
        for($i=0;$i -lt $n;$i++){
            $base=$br.ReadUInt64(); $size=$br.ReadUInt32()
            $null=$br.ReadUInt32(); $null=$br.ReadUInt32(); $nameRva=$br.ReadUInt32()
            $null=$br.ReadBytes(52); $null=$br.ReadUInt32();$null=$br.ReadUInt32()
            $null=$br.ReadUInt32();$null=$br.ReadUInt32();$null=$br.ReadUInt64();$null=$br.ReadUInt64()
            $pos=$ms.Position
            $name=Read-MiniString $br $nameRva
            $ms.Position=$pos
            $mods += [PSCustomObject]@{Base=$base;End=$base+$size;Name=$name}
        }
    }
}

function Find-Module([uint64]$addr,$mods){
    foreach($m in $mods){ if($addr -ge $m.Base -and $addr -lt $m.End){ return $m } }
    return $null
}

# Find thread list
$targetStackBase=$null; $targetStackSize=$null; $targetCtxRva=$null; $targetCtxSize=$null
foreach($d in $dirs){
    if($d.Type -eq 3){
        $ms.Position=$d.Rva
        $n=$br.ReadUInt32()
        for($i=0;$i -lt $n;$i++){
            $tid=$br.ReadUInt32()
            $null=$br.ReadUInt32(); $null=$br.ReadUInt32(); $null=$br.ReadUInt32()
            $null=$br.ReadUInt64() # Teb
            $stackStart=$br.ReadUInt64()
            $stackDataSize=$br.ReadUInt32(); $stackRva=$br.ReadUInt32()
            $ctxDataSize=$br.ReadUInt32(); $ctxRva=$br.ReadUInt32()
            if($tid -eq $ThreadId){
                $targetStackBase=$stackStart
                $targetStackSize=$stackDataSize
                $targetStackRva=$stackRva
                $targetCtxRva=$ctxRva
                $targetCtxSize=$ctxDataSize
            }
        }
    }
}

if(-not $targetStackBase){ throw "Thread $ThreadId not found" }

Write-Host ("Thread {0}: StackBase=0x{1:X16} StackSize=0x{2:X} CtxRva=0x{3:X} CtxSize=0x{4:X}" -f $ThreadId,$targetStackBase,$targetStackSize,$targetCtxRva,$targetCtxSize)

# x64 CONTEXT: Rip at offset 0xF8, Rsp at 0x98
$ms.Position = $targetCtxRva + 0xF8
$rip = $br.ReadUInt64()
$ms.Position = $targetCtxRva + 0x98
$rsp = $br.ReadUInt64()
Write-Host ("RIP = 0x{0:X16}" -f $rip)
Write-Host ("RSP = 0x{0:X16}" -f $rsp)
$m = Find-Module $rip $mods
if($m){ Write-Host ("RIP in module: {0} (base=0x{1:X} off=+0x{2:X})" -f $m.Name,$m.Base,($rip-$m.Base)) }

# Read stack
$ms.Position = $targetStackRva
$stack = $br.ReadBytes($targetStackSize)

# RSP-relative start
$offInStack = [int]($rsp - $targetStackBase)
if($offInStack -lt 0){ $offInStack = 0 }
if($offInStack -ge $stack.Length){ $offInStack = 0 }
Write-Host ("Scanning from RSP offset +0x{0:X} in stack ({1} bytes)" -f $offInStack,($stack.Length-$offInStack))

$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$hits = @()
for($p = $offInStack; $p -lt $stack.Length - 7; $p += 8){
    $val = [BitConverter]::ToUInt64($stack, $p)
    if($val -lt 0x10000) { continue }
    $mm = Find-Module $val $mods
    if($mm){
        $off = $val - $mm.Base
        $key = "{0}+0x{1:X}" -f $mm.Name,$off
        if(-not $seen.Contains($key)){
            [void]$seen.Add($key)
            $hits += [PSCustomObject]@{StackOff=($p-$offInStack); Addr=$val; Module=$mm.Name; ModOff=$off}
        }
    }
}

Write-Host "`n=== Stack return-address candidates (unique, in stack order) ==="
foreach($h in $hits){
    Write-Host ("  [+0x{0:X6}]  0x{1:X16}  {2}+0x{3:X}" -f $h.StackOff,$h.Addr,$h.Module,$h.ModOff)
}

Write-Host "`n=== Module hit counts (top 20) ==="
$hits | Group-Object Module | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object {
    Write-Host ("  {0,4}x  {1}" -f $_.Count, $_.Name)
}

$br.Close(); $ms.Close()
