param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Install','Uninstall','Revert')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'

# Known versions of THIS controller fix.
$KnownControllerFixHashes = @(
    'A44E14CB12D6199EA07A2CF203EA1F6F521F999CB79E71EF18CD64CEE45DB64E',
    'D52F47942B5BA3CC4380BF75F150637B67ECB8B7F6B36E39F743D45640113C00',
    '95FE31CB82D60B68A8D4D4FE7EDA22CF848667C733CBC202C16724C34F396CA7'
)

function Safe-Hash([string]$Path) {
    try {
        return (Get-FileHash $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    }
    catch {
        Write-Host ''
        Write-Host 'Windows Security blocked access to:' -ForegroundColor Red
        Write-Host "  $Path"
        Write-Host ''
        Write-Host 'Do NOT disable Windows Security.'
        Write-Host 'Open Windows Security > Protection history and send the threat name.'
        exit 1
    }
}

function Is-OurControllerFix([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $h = Safe-Hash $Path
    return $KnownControllerFixHashes -contains $h
}

function Normalize-DawnwalkerPath([string]$PathText) {
    if ([string]::IsNullOrWhiteSpace($PathText)) { return $null }

    $p = $PathText.Trim().Trim('"').Trim("'")

    if (Test-Path $p -PathType Container) {
        $candidate = Join-Path $p 'Dawnwalker.exe'
        if (Test-Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }
        return $null
    }

    if (Test-Path $p -PathType Leaf) {
        $item = Get-Item $p
        if ($item.Name -ieq 'Dawnwalker.exe') {
            return $item.FullName
        }
    }

    return $null
}

function Browse-DawnwalkerExe {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $owner = New-Object System.Windows.Forms.Form
    $owner.Text = 'Dawnwalker Controller Fix'
    $owner.StartPosition = 'CenterScreen'
    $owner.Size = New-Object System.Drawing.Size(1,1)
    $owner.ShowInTaskbar = $false
    $owner.FormBorderStyle = 'None'
    $owner.TopMost = $true
    $owner.Opacity = 0
    $owner.Show()
    $owner.Activate()

    try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select Dawnwalker.exe'
        $dialog.Filter = 'Dawnwalker.exe|Dawnwalker.exe|Executable files (*.exe)|*.exe'
        $dialog.FileName = 'Dawnwalker.exe'
        $dialog.CheckFileExists = $true
        $dialog.Multiselect = $false
        $dialog.RestoreDirectory = $true

        if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
            return Normalize-DawnwalkerPath $dialog.FileName
        }
        return $null
    }
    finally {
        $owner.Close()
        $owner.Dispose()
    }
}

function Choose-DawnwalkerExe {
    Write-Host ''
    Write-Host 'Choose your Dawnwalker location:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  1 = Browse for Dawnwalker.exe'
    Write-Host '  2 = Paste or drag the path here'
    Write-Host '  Q = Cancel'
    Write-Host ''

    while ($true) {
        $choice = (Read-Host 'Choice').Trim()

        if ($choice -ieq 'Q') { return $null }

        if ($choice -eq '1') {
            Write-Host ''
            Write-Host 'Opening file browser...' -ForegroundColor Cyan
            $exe = Browse-DawnwalkerExe
            if ($exe) { return $exe }
            Write-Host 'No Dawnwalker.exe selected. Try again.' -ForegroundColor Yellow
            continue
        }

        if ($choice -eq '2') {
            Write-Host ''
            Write-Host 'Paste or drag Dawnwalker.exe OR its Win64 folder, then press Enter.'
            $exe = Normalize-DawnwalkerPath (Read-Host 'Path')
            if ($exe) { return $exe }
            Write-Host 'Dawnwalker.exe was not found there. Try again.' -ForegroundColor Yellow
            continue
        }

        Write-Host 'Enter 1, 2, or Q.' -ForegroundColor Yellow
    }
}

function Add-EngineSetting {
    $configDir = Join-Path $env:LOCALAPPDATA 'Dawnwalker\Saved\Config\Windows'
    $engineIni = Join-Path $configDir 'Engine.ini'
    $backupIni = Join-Path $configDir 'Engine.ini.DWControllerFixBackup'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null

    $wasReadOnly = $false
    if (Test-Path $engineIni) {
        $item = Get-Item $engineIni
        $wasReadOnly = $item.IsReadOnly
        if ($wasReadOnly) { $item.IsReadOnly = $false }
        if (-not (Test-Path $backupIni)) { Copy-Item $engineIni $backupIni }
        $text = Get-Content $engineIni -Raw
    } else {
        $text = ''
    }

    $text = [regex]::Replace(
        $text,
        '(?im)^\s*Slate\.EnableSyntheticCursorMoves\s*=\s*[^\r\n]*\r?\n?',
        ''
    )

    if ([regex]::IsMatch($text, '(?im)^\s*\[ConsoleVariables\]\s*$')) {
        $text = [regex]::Replace(
            $text,
            '(?im)^\s*\[ConsoleVariables\]\s*$',
            { param($m) $m.Value + "`r`nSlate.EnableSyntheticCursorMoves=0" },
            1
        )
    } else {
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`r`n" }
        $text += "`r`n[ConsoleVariables]`r`nSlate.EnableSyntheticCursorMoves=0`r`n"
    }

    Set-Content -Path $engineIni -Value $text -Encoding UTF8
    if ($wasReadOnly) { (Get-Item $engineIni).IsReadOnly = $true }
}

function Remove-EngineSetting {
    $configDir = Join-Path $env:LOCALAPPDATA 'Dawnwalker\Saved\Config\Windows'
    $engineIni = Join-Path $configDir 'Engine.ini'
    if (-not (Test-Path $engineIni)) { return }

    $item = Get-Item $engineIni
    $wasReadOnly = $item.IsReadOnly
    if ($wasReadOnly) { $item.IsReadOnly = $false }

    $text = Get-Content $engineIni -Raw
    $text = [regex]::Replace(
        $text,
        '(?im)^\s*Slate\.EnableSyntheticCursorMoves\s*=\s*0\s*\r?\n?',
        ''
    )
    Set-Content -Path $engineIni -Value $text -Encoding UTF8
    if ($wasReadOnly) { (Get-Item $engineIni).IsReadOnly = $true }
}

function Get-SavedOrChosenExe([string]$LocationFile) {
    $exe = $null
    if (Test-Path $LocationFile) {
        $saved = (Get-Content $LocationFile -Raw).Trim()
        $exe = Normalize-DawnwalkerPath $saved
    }
    if (-not $exe) { $exe = Browse-DawnwalkerExe }
    return $exe
}

if (Get-Process -Name 'Dawnwalker' -ErrorAction SilentlyContinue) {
    Write-Host ''
    Write-Host 'Dawnwalker is still running.' -ForegroundColor Red
    Write-Host 'Close the game and try again.'
    exit 1
}

$locationFile = Join-Path $PSScriptRoot 'install_location.txt'
$payloadDll = Join-Path $PSScriptRoot 'DawnwalkerControllerFix.dll'

if ($Mode -eq 'Install') {
    $exe = Choose-DawnwalkerExe
    if (-not $exe) {
        Write-Host 'Cancelled. Nothing was changed.'
        exit 0
    }

    Write-Host ''
    Write-Host "Game: $exe" -ForegroundColor Green
    $confirm = (Read-Host 'Install here? Y/N').Trim()
    if ($confirm -notmatch '^(?i)y(es)?$') {
        Write-Host 'Cancelled. Nothing was changed.'
        exit 0
    }

    if (-not (Test-Path $payloadDll)) {
        Write-Host 'Install failed: DawnwalkerControllerFix.dll is missing.' -ForegroundColor Red
        exit 1
    }

    $gameDir = Split-Path $exe -Parent
    $targetDll = Join-Path $gameDir 'version.dll'
    $chainDll = Join-Path $gameDir 'version_chain.dll'
    $backupDll = Join-Path $gameDir 'version.dll.DWControllerFixBackup'
    $noOriginalMarker = Join-Path $gameDir 'DWControllerFix_NoOriginalVersion.marker'
    $ourHash = Safe-Hash $payloadDll

    # -------- Upgrade an older release of THIS mod --------
    if ((Test-Path $targetDll) -and (Is-OurControllerFix $targetDll)) {
        $oldHash = Safe-Hash $targetDll

        if ($oldHash -eq $ourHash) {
            Write-Host ''
            Write-Host 'This controller fix is already installed.' -ForegroundColor Green
            Add-EngineSetting
            Set-Content -Path $locationFile -Value $exe -Encoding UTF8
            exit 0
        }

        Write-Host ''
        Write-Host 'Previous Controller Fix found - upgrading it.' -ForegroundColor Cyan

        # New security-friendlier proxy requires a version_chain.dll.
        # If an older Compatibility Mode already created one, keep it.
        # Otherwise use the user's own Microsoft version.dll as the chain target.
        if (-not (Test-Path $chainDll)) {
            $systemVersion = Join-Path $env:WINDIR 'System32\version.dll'
            if (-not (Test-Path $systemVersion)) {
                Write-Host 'Windows system version.dll could not be found.' -ForegroundColor Red
                exit 1
            }
            Copy-Item $systemVersion $chainDll -Force
            Set-Content -Path $noOriginalMarker -Value 'Previous controller fix had no chained version.dll.' -Encoding ASCII
        }

        Copy-Item $payloadDll $targetDll -Force

        if ((Safe-Hash $targetDll) -ne $ourHash) {
            Write-Host 'Upgrade verification failed.' -ForegroundColor Red
            exit 1
        }

        Add-EngineSetting
        Set-Content -Path $locationFile -Value $exe -Encoding UTF8

        Write-Host ''
        Write-Host 'UPGRADED SUCCESSFULLY' -ForegroundColor Green
        Write-Host 'F8 = Toggle mouse ON / OFF.'
        exit 0
    }

    # -------- Fresh install / genuine other version.dll --------
    $hadOriginal = Test-Path $targetDll

    try {
        if ($hadOriginal) {
            $existingHash = Safe-Hash $targetDll

            Write-Host ''
            Write-Host 'Another mod uses version.dll.' -ForegroundColor Yellow
            Write-Host 'It will be backed up and chain-loaded.'
            Write-Host ''

            if (Test-Path $chainDll) {
                Write-Host 'Install stopped: version_chain.dll already exists.' -ForegroundColor Red
                Write-Host 'Nothing was overwritten.'
                exit 1
            }

            Copy-Item $targetDll $backupDll -Force
            Copy-Item $targetDll $chainDll -Force

            if ((Safe-Hash $backupDll) -ne $existingHash) { throw 'Backup verification failed.' }
            if ((Safe-Hash $chainDll) -ne $existingHash) { throw 'Chain-copy verification failed.' }

            if (Test-Path $noOriginalMarker) {
                Remove-Item $noOriginalMarker -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            $systemVersion = Join-Path $env:WINDIR 'System32\version.dll'
            if (-not (Test-Path $systemVersion)) { throw 'Windows system version.dll could not be found.' }

            Copy-Item $systemVersion $chainDll -Force
            Set-Content -Path $noOriginalMarker -Value 'No original game-folder version.dll existed before install.' -Encoding ASCII

            if (Test-Path $backupDll) {
                Remove-Item $backupDll -Force -ErrorAction SilentlyContinue
            }
        }

        Copy-Item $payloadDll $targetDll -Force
        if ((Safe-Hash $targetDll) -ne $ourHash) { throw 'Installed DLL verification failed.' }

        Add-EngineSetting
        Set-Content -Path $locationFile -Value $exe -Encoding UTF8
    }
    catch {
        Write-Host ''
        Write-Host 'INSTALL FAILED - restoring previous setup...' -ForegroundColor Red

        if ($hadOriginal -and (Test-Path $backupDll)) {
            Copy-Item $backupDll $targetDll -Force
        }
        elseif (-not $hadOriginal -and (Test-Path $targetDll)) {
            Remove-Item $targetDll -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path $chainDll) {
            Remove-Item $chainDll -Force -ErrorAction SilentlyContinue
        }

        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }

    Write-Host ''
    Write-Host 'INSTALLED SUCCESSFULLY' -ForegroundColor Green
    Write-Host 'F8 = Toggle mouse ON / OFF.'
    exit 0
}

# -------- Uninstall / Revert --------
# -------- UNINSTALL THIS FIX --------
if ($Mode -eq 'Uninstall') {
    $exe = Get-SavedOrChosenExe $locationFile

    if (-not $exe) {
        Write-Host 'Uninstall cancelled.'
        exit 0
    }

    $gameDir = Split-Path $exe -Parent
    $targetDll = Join-Path $gameDir 'version.dll'
    $chainDll = Join-Path $gameDir 'version_chain.dll'
    $backupDll = Join-Path $gameDir 'version.dll.DWControllerFixBackup'
    $noOriginalMarker = Join-Path $gameDir 'DWControllerFix_NoOriginalVersion.marker'

    $targetIsOurs = (Test-Path $targetDll) -and (Is-OurControllerFix $targetDll)
    $chainExists = Test-Path $chainDll

    if ($chainExists -and $targetIsOurs) {
        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Yellow
        Write-Host ' COMPATIBILITY / CHAIN WARNING' -ForegroundColor Yellow
        Write-Host '============================================================' -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'Another DLL is currently being loaded through:'
        Write-Host '  version_chain.dll'
        Write-Host ''
        Write-Host 'To uninstall THIS controller fix without breaking that mod,'
        Write-Host 'Setup must:'
        Write-Host ''
        Write-Host '  1. Remove this controller fix from version.dll'
        Write-Host '  2. Restore version_chain.dll back to version.dll'
        Write-Host '  3. Remove version_chain.dll'
        Write-Host ''
        Write-Host 'The other mod itself will NOT be deleted.'
        Write-Host ''
        $confirm = (Read-Host 'Continue with uninstall? Y/N').Trim()

        if ($confirm -notmatch '^(?i)y(es)?$') {
            Write-Host ''
            Write-Host 'Uninstall cancelled. Nothing was changed.'
            exit 0
        }
    }

    if ($targetIsOurs) {
        if ($chainExists) {
            # Restore the currently chained DLL so the other mod keeps working.
            Copy-Item $chainDll $targetDll -Force

            if ((Safe-Hash $chainDll) -ne (Safe-Hash $targetDll)) {
                Write-Host ''
                Write-Host 'UNINSTALL STOPPED: restoration could not be verified.' -ForegroundColor Red
                Write-Host 'version_chain.dll was left in place.'
                exit 1
            }

            Remove-Item $chainDll -Force

            Write-Host ''
            Write-Host 'Other chained mod restored to version.dll.' -ForegroundColor Green
        }
        else {
            Remove-Item $targetDll -Force
            Write-Host ''
            Write-Host 'Controller Fix version.dll removed.' -ForegroundColor Green
        }
    }
    elseif (Test-Path $targetDll) {
        Write-Host ''
        Write-Host 'The current version.dll is NOT this controller fix.' -ForegroundColor Yellow
        Write-Host 'It was left completely alone.'
    }
    else {
        Write-Host ''
        Write-Host 'No Controller Fix version.dll was found in the game folder.'
    }

    # Uninstall removes only this mod's config override.
    Remove-EngineSetting

    if (Test-Path $locationFile) {
        Remove-Item $locationFile -Force
    }

    if (Test-Path $noOriginalMarker) {
        Remove-Item $noOriginalMarker -Force
    }

    # Intentionally KEEP version.dll.DWControllerFixBackup.
    # Revert remains available as a separate recovery action.
    Write-Host ''
    Write-Host 'UNINSTALLED SUCCESSFULLY' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Only this controller fix was removed.'
    Write-Host 'A Revert backup is kept if one exists.'
    exit 0
}

# -------- REVERT TO PRE-INSTALL SETUP --------
if ($Mode -eq 'Revert') {
    $exe = Get-SavedOrChosenExe $locationFile

    if (-not $exe) {
        Write-Host 'Revert cancelled.'
        exit 0
    }

    $gameDir = Split-Path $exe -Parent
    $targetDll = Join-Path $gameDir 'version.dll'
    $chainDll = Join-Path $gameDir 'version_chain.dll'
    $backupDll = Join-Path $gameDir 'version.dll.DWControllerFixBackup'
    $noOriginalMarker = Join-Path $gameDir 'DWControllerFix_NoOriginalVersion.marker'

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host ' REVERT WARNING' -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Revert is NOT the same as normal uninstall.'
    Write-Host ''
    Write-Host 'It attempts to restore the exact DLL setup saved BEFORE'
    Write-Host 'this controller fix was installed.'
    Write-Host ''
    Write-Host 'This may overwrite the CURRENT version.dll with the saved'
    Write-Host 'pre-install version.'
    Write-Host ''
    Write-Host 'Use Revert if chaining/Compatibility Mode caused trouble.'
    Write-Host ''
    $confirm = (Read-Host 'Restore the saved pre-install setup? Y/N').Trim()

    if ($confirm -notmatch '^(?i)y(es)?$') {
        Write-Host ''
        Write-Host 'Revert cancelled. Nothing was changed.'
        exit 0
    }

    if (Test-Path $backupDll) {
        # Exact pre-install DLL is available.
        Copy-Item $backupDll $targetDll -Force

        if ((Safe-Hash $backupDll) -ne (Safe-Hash $targetDll)) {
            Write-Host ''
            Write-Host 'REVERT FAILED: restored version.dll could not be verified.' -ForegroundColor Red
            exit 1
        }

        if (Test-Path $chainDll) {
            Remove-Item $chainDll -Force
        }

        Write-Host ''
        Write-Host 'Saved pre-install version.dll restored.' -ForegroundColor Green
    }
    elseif (Test-Path $noOriginalMarker) {
        # There was no game-folder version.dll before this fix.
        if ((Test-Path $targetDll) -and (Is-OurControllerFix $targetDll)) {
            Remove-Item $targetDll -Force
        }
        elseif (Test-Path $targetDll) {
            Write-Host ''
            Write-Host 'Current version.dll is not this controller fix.' -ForegroundColor Yellow
            Write-Host 'It was left alone instead of being deleted.'
        }

        if (Test-Path $chainDll) {
            Remove-Item $chainDll -Force
        }

        Write-Host ''
        Write-Host 'No version.dll existed before installation.' -ForegroundColor Green
        Write-Host 'The controller-fix DLL setup was removed.'
    }
    else {
        Write-Host ''
        Write-Host 'NO PRE-INSTALL BACKUP WAS FOUND.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'Revert cannot safely guess what version.dll used to be.'
        Write-Host 'Nothing unknown will be overwritten or deleted.'
        Write-Host ''
        Write-Host 'If an old release overwrote another mod before a backup existed,'
        Write-Host 'reinstall that other mod to restore its DLL.'
        Remove-EngineSetting
        exit 1
    }

    Remove-EngineSetting

    if (Test-Path $locationFile) {
        Remove-Item $locationFile -Force
    }

    if (Test-Path $noOriginalMarker) {
        Remove-Item $noOriginalMarker -Force
    }

    Write-Host ''
    Write-Host 'REVERT COMPLETED SUCCESSFULLY' -ForegroundColor Green
    Write-Host 'The saved pre-install DLL setup was restored.'
    exit 0
}
