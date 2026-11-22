#region Folder Scan Mode
# Opt-in, synchronous and sequential. Uses only local NFOs for discovery.
$Mode = 'folderscan'
$global:Mode = 'folderscan'
$global:posterCount = 0
if ($global:runspaceStats) { $global:runspaceStats['posterCount'] = 0 }

# The existing generation functions must not use media-server artwork or upload APIs.
$UsePlex = 'false'
$UseJellyfin = 'false'
$UseEmby = 'false'
$UseSilo = 'false'
$UseOtherMediaServer = 'false'
$Upload2Plex = 'false'
$global:UploadExistingAssets = 'false'
$global:ProviderOrder = @($global:ProviderOrder | Where-Object { $_ -notin @('PLEX', 'JELLYFIN', 'EMBY', 'SILO') })

# Only series/movie posters; all other branches in CoreGeneration stay disabled.
$global:Posters = 'true'
$global:BackgroundPosters = 'false'
$global:SeasonPosters = 'false'
$global:TitleCards = 'false'
$global:AutoCreateSeasonTemplate = 'false'
$LibraryFolders = 'true'

if ((@($FolderScanMovieRoots).Count + @($FolderScanShowRoots).Count) -eq 0) {
    Write-Entry -Message 'FolderScan has no configured MovieRoots or ShowRoots.' -Path $global:configLogging -Color Red -log Error
    if ($CurrentlyRunning -and (Test-Path -LiteralPath $CurrentlyRunning)) {
        Remove-Item -LiteralPath $CurrentlyRunning -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

$global:checkedItems = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
$directoryHashtable = Get-AssetHashtable
$unmatchedFile = Join-Path $global:ScriptRoot 'Logs/FolderScan_unmatched.txt'
[System.IO.File]::WriteAllText($unmatchedFile, '')

$total = 0
$processed = 0
$skipped = 0
$unmatched = 0
$errors = 0
$rootNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

Write-Entry -Message 'FolderScan started (movie / series posters only).' -Path $global:configLogging -Color Cyan -log Info
foreach ($source in @(
    @{ Type = 'Movie'; Roots = @($FolderScanMovieRoots) },
    @{ Type = 'Series'; Roots = @($FolderScanShowRoots) }
)) {
    foreach ($root in $source.Roots) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        try {
            $rootDir = Get-Item -LiteralPath ([string]$root) -ErrorAction Stop
            if (-not $rootDir.PSIsContainer) { throw "Not a directory: $root" }
            $library = $rootDir.Name
            if (-not $rootNames.Add($library)) {
                throw "Duplicate media-root basename '$library'. Asset libraries would collide."
            }
            $folders = @(Get-ChildItem -LiteralPath $rootDir.FullName -Directory -ErrorAction Stop)
        }
        catch {
            $errors++
            Write-Entry -Message "FolderScan root error [$root]: $($_.Exception.Message)" -Path $global:configLogging -Color Red -log Error
            continue
        }

        foreach ($folder in $folders) {
            # Never traverse symlinked directory entries.
            if (($folder.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $total++
            $assetDir = Join-Path (Join-Path $AssetPath $library) $folder.Name
            $posterFile = Join-Path $assetDir 'poster.jpg'
            $assetKey = Join-Path $assetDir 'poster'

            # Do not even read NFOs or call any provider on a repeat run.
            if ($directoryHashtable.ContainsKey($assetKey)) {
                $skipped++
                Write-Entry -Subtext "SKIP [$($source.Type)] $($folder.Name): poster exists" -Path $global:configLogging -Color Yellow -log Info
                continue
            }

            $metadata = Get-FolderScanNfoMetadata -Folder $folder.FullName -Type $source.Type
            if (-not $metadata.Matched) {
                $unmatched++
                $line = "[$($source.Type)] $($folder.FullName) | $($metadata.Reason)"
                Add-Content -LiteralPath $unmatchedFile -Value $line -Encoding utf8
                Write-Entry -Subtext "UNMATCHED $line" -Path $global:configLogging -Color Yellow -log Warning
                continue
            }

            $title = if ($metadata.Title) { $metadata.Title } else { $folder.Name }
            $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($folder.FullName))
            $ratingKey = ([System.BitConverter]::ToString($hash) -replace '-', '').Substring(0, 12)
            $entry = [pscustomobject]@{
                'Library Name' = $library
                'Library Type' = $source.Type
                'Library Language' = 'en'
                title = $title
                originalTitle = $title
                year = $metadata.Year
                tmdbid = $metadata.TmdbId
                tvdbid = $metadata.TvdbId
                imdbid = $metadata.ImdbId
                RootFoldername = $folder.Name
                Path = $rootDir.FullName
                extraFolder = $null
                Labels = ''
                Id = $null
                ratingkey = $ratingKey
            }

            try {
                # Create exact literal target path first; CoreGeneration otherwise uses New-Item -Path.
                [void][System.IO.Directory]::CreateDirectory($assetDir)
                Write-Entry -Message "GENERATE [$($source.Type)] $title ($($metadata.Year)) | $($folder.Name)" -Path $global:configLogging -Color Cyan -log Info
                if ($source.Type -eq 'Movie') { Invoke-MoviePosterCreation -entry $entry }
                else { Invoke-ShowPosterCreation -entry $entry }

                if (Test-Path -LiteralPath $posterFile -PathType Leaf) {
                    $directoryHashtable[$assetKey] = $true
                    $processed++
                }
                else {
                    $errors++
                    Write-Entry -Subtext "ERROR poster not created: $posterFile" -Path $global:configLogging -Color Red -log Error
                }
            }
            catch {
                $errors++
                Write-Entry -Message "FolderScan generation failed for [$($folder.Name)]: $($_.Exception.Message)" -Path $global:configLogging -Color Red -log Error
            }
        }
    }
}

Write-Entry -Message "FolderScan summary: folders=$total processed=$processed skipped=$skipped unmatched=$unmatched errors=$errors" -Path $global:configLogging -Color Green -log Info
Write-Entry -Subtext "Unmatched file: $unmatchedFile" -Path $global:configLogging -Color Cyan -log Info
# Match the other modes: clear the lock created by PrerequisitesCheck.ps1.
if ($CurrentlyRunning -and (Test-Path -LiteralPath $CurrentlyRunning)) {
    Remove-Item -LiteralPath $CurrentlyRunning -Force -ErrorAction SilentlyContinue
}
if ($errors -gt 0) { exit 1 }
#endregion Folder Scan Mode
