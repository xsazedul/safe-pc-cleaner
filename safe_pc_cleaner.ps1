# ==============================================================================
# Safe PC Cleaner & Duplicate Finder Assistant
# Repository: https://github.com/xsazedul/safe-pc-cleaner
# ==============================================================================

param (
    [string]$TargetFolder = "$HOME\Downloads",
    [string]$Cutoff = "", # দিন সংখ্যা (যেমন: 180) অথবা নির্দিষ্ট তারিখ (যেমন: 2026-01-01)
    [string]$Mode = "preview" # 'preview' অথবা 'delete'
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Safe PC Cleaner & Duplicate Finder Assistant" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# যদি প্যারামিটারে কাটঅফ না দেওয়া থাকে, তাহলে ব্যবহারকারীকে সরাসরি ইনপুট দিতে বলা হবে
if ([string]::IsNullOrWhiteSpace($Cutoff)) {
    Write-Host "দিন সংখ্যা (যেমন 180, 90) অথবা নির্দিষ্ট তারিখ (যেমন 2026-01-01) লিখুন।" -ForegroundColor Gray
    $inputCutoff = Read-Host "দিন বা তারিখ লিখুন [ডিফল্ট 180 দিন]"
    if ([string]::IsNullOrWhiteSpace($inputCutoff)) {
        $Cutoff = "180"
    } else {
        $Cutoff = $inputCutoff.Trim()
    }
}

# দিন সংখ্যা নাকি তারিখ তা যাচাই ও পার্স করা
$cutoffDate = $null
if ($Cutoff -match '^\d+$') {
    $days = [int]$Cutoff
    $cutoffDate = (Get-Date).AddDays(-$days)
    $thresholdText = "$days days old (Files older than $($cutoffDate.ToString('yyyy-MM-dd')))"
} else {
    try {
        $cutoffDate = [datetime]::Parse($Cutoff)
        $thresholdText = "Files older than $($cutoffDate.ToString('yyyy-MM-dd'))"
    } catch {
        Write-Host "[WARNING] Invalid date format '$Cutoff'. Using default 180 days." -ForegroundColor DarkYellow
        $cutoffDate = (Get-Date).AddDays(-180)
        $thresholdText = "180 days old (Files older than $($cutoffDate.ToString('yyyy-MM-dd')))"
    }
}

Write-Host "Target Directory : $TargetFolder" -ForegroundColor Yellow
Write-Host "Cutoff Threshold : $thresholdText" -ForegroundColor Yellow
Write-Host "Running Mode     : $(if ($Mode -eq 'delete') { 'DELETE (Send to Recycle Bin)' } else { 'PREVIEW (Safe - No Deletion)' })" -ForegroundColor Yellow

if (-not (Test-Path $TargetFolder)) {
    Write-Host "[ERROR] Target directory does not exist: $TargetFolder" -ForegroundColor Red
    exit
}

# যে শব্দ বা এক্সটেনশনগুলো পাসওয়ার্ড বা সংবেদনশীল কি হতে পারে
$SensitiveKeywords = @("pass", "password", "key", "secret", "credential", "token", "backup", "pin", "wallet", "seed")
$SensitiveExtensions = @(".kdbx", ".key", ".pem", ".ppk", ".pfx", ".p12", ".crt", ".env", ".ovpn", ".wallet", ".seed")

function Is-SensitiveFile($file) {
    $name = $file.Name.ToLower()
    $ext = $file.Extension.ToLower()

    if ($SensitiveExtensions -contains $ext) {
        return $true
    }
    foreach ($kw in $SensitiveKeywords) {
        if ($name -like "*$kw*") {
            return $true
        }
    }
    return $false
}

Write-Host "`nScanning files... Please wait..." -ForegroundColor Gray
$allFiles = Get-ChildItem -Path $TargetFolder -File -Recurse -ErrorAction SilentlyContinue

$safeFiles = @()
$skippedSensitive = @()

foreach ($file in $allFiles) {
    if (Is-SensitiveFile $file) {
        $skippedSensitive += $file
    } else {
        $safeFiles += $file
    }
}

if ($skippedSensitive.Count -gt 0) {
    Write-Host "`n[PROTECTION] Skipped $($skippedSensitive.Count) files matching password/key/sensitive patterns:" -ForegroundColor Magenta
    foreach ($sf in $skippedSensitive) {
        Write-Host "  [SKIPPED] $($sf.FullName)" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------------
# 1. পুরনো ফাইল ফিল্টারিং
# -------------------------------------------------------------
$oldFiles = $safeFiles | Where-Object { $_.LastWriteTime -lt $cutoffDate }

Write-Host "`n----------------------------------------------------------" -ForegroundColor Cyan
Write-Host " 1. Files older than threshold ($($cutoffDate.ToString('yyyy-MM-dd'))): $($oldFiles.Count)" -ForegroundColor Green
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

foreach ($of in $oldFiles) {
    $mb = [math]::Round($of.Length / 1MB, 2)
    Write-Host " [OLD] $($of.LastWriteTime.ToString('yyyy-MM-dd')) | $mb MB | $($of.FullName)" -ForegroundColor DarkYellow
}

# -------------------------------------------------------------
# 2. ডুপ্লিকেট ফাইল খোঁজা (SHA256 হ্যাশ চেক করে)
# -------------------------------------------------------------
Write-Host "`n----------------------------------------------------------" -ForegroundColor Cyan
Write-Host " 2. Checking for duplicate files (Hash verification)..." -ForegroundColor Green
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

$potentialDupes = $safeFiles | Group-Object -Property Length | Where-Object { $_.Count -gt 1 -and $_.Name -gt 0 }

$duplicateFiles = @()
foreach ($group in $potentialDupes) {
    $hashMap = @{}
    foreach ($file in $group.Group) {
        try {
            $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            if ($hash) {
                if ($hashMap.ContainsKey($hash)) {
                    $original = $hashMap[$hash]
                    $duplicateFiles += [PSCustomObject]@{
                        DuplicatePath = $file.FullName
                        OriginalPath  = $original.FullName
                        SizeMB        = [math]::Round($file.Length / 1MB, 2)
                        FileItem      = $file
                    }
                } else {
                    $hashMap[$hash] = $file
                }
            }
        } catch {}
    }
}

Write-Host "Total duplicate files found: $($duplicateFiles.Count)" -ForegroundColor Yellow
foreach ($df in $duplicateFiles) {
    Write-Host " [DUPLICATE] $($df.SizeMB) MB | $($df.DuplicatePath)" -ForegroundColor Red
    Write-Host "    |--> Matches: $($df.OriginalPath)" -ForegroundColor Gray
}

# -------------------------------------------------------------
# 3. অ্যাকশন এক্সিকিউশন
# -------------------------------------------------------------
Write-Host "`n==========================================================" -ForegroundColor Cyan
if ($Mode -ne "delete") {
    Write-Host "[STATUS] PREVIEW MODE: No files were touched or deleted." -ForegroundColor Green
    Write-Host "Review the list above. To actually move files to Recycle Bin, run with -Mode delete:" -ForegroundColor Yellow
    Write-Host "powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TargetFolder `"$TargetFolder`" -Cutoff `"$Cutoff`" -Mode delete" -ForegroundColor Cyan
} else {
    Add-Type -AssemblyName Microsoft.VisualBasic
    Write-Host "[WARNING] The identified duplicate & old files will be sent to Recycle Bin." -ForegroundColor Red
    $confirm = Read-Host "Are you sure you want to send these files to the Recycle Bin? (Y/N)"
    if ($confirm -eq 'Y' -or $confirm -eq 'y') {
        foreach ($df in $duplicateFiles) {
            Write-Host "Sending duplicate to Recycle Bin: $($df.DuplicatePath)" -ForegroundColor Gray
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($df.DuplicatePath, 'OnlyErrorDialogs', 'SendToRecycleBin')
        }
        foreach ($of in $oldFiles) {
            if (Test-Path $of.FullName) {
                Write-Host "Sending old file to Recycle Bin: $($of.FullName)" -ForegroundColor Gray
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($of.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
            }
        }
        Write-Host "`nClean-up complete! Files were safely moved to Recycle Bin." -ForegroundColor Green
    } else {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    }
}
