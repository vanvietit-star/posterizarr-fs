# Helpers for the opt-in FolderScan mode. No media-server requests.
function Get-FolderScanNfoMetadata {
    param (
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][ValidateSet('Movie', 'Series')][string]$Type
    )

    $result = [ordered]@{
        Matched = $false
        Reason = ''
        Title = ''
        Year = $null
        TmdbId = $null
        TvdbId = $null
        ImdbId = $null
        Nfo = $null
    }
    $file = $null
    try {
        if ($Type -eq 'Series') {
            $file = Get-Item -LiteralPath (Join-Path $Folder 'tvshow.nfo') -ErrorAction SilentlyContinue
        }
        else {
            $file = Get-Item -LiteralPath (Join-Path $Folder 'movie.nfo') -ErrorAction SilentlyContinue
            if (-not $file) {
                $videos = @(Get-ChildItem -LiteralPath $Folder -File -ErrorAction Stop | Where-Object {
                    $_.Extension.ToLowerInvariant() -in @('.mkv', '.mp4', '.avi', '.m4v', '.mov', '.ts', '.wmv')
                })
                $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($video in $videos) { [void]$names.Add($video.BaseName) }
                $candidates = @(Get-ChildItem -LiteralPath $Folder -File -Filter '*.nfo' -ErrorAction Stop | Where-Object {
                    $names.Contains($_.BaseName)
                })
                if ($candidates.Count -eq 1) { $file = $candidates[0] }
                elseif ($candidates.Count -gt 1) {
                    $result.Reason = 'Multiple video-matched NFO files (ambiguous)'
                    return [pscustomobject]$result
                }
            }
        }
        if (-not $file -or $file.PSIsContainer) {
            $result.Reason = 'NFO missing'
            return [pscustomobject]$result
        }
        $result.Nfo = $file.FullName
        $content = (Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop).TrimStart([char]0xFEFF)
        $tag = if ($Type -eq 'Movie') { 'movie' } else { 'tvshow' }
        try { [xml]$xml = $content }
        catch {
            # Some NFOs begin/end with a URL or other plain text outside the XML root.
            $pattern = '(?is)<' + $tag + '\b[^>]*>.*?</' + $tag + '\s*>'
            $match = [regex]::Match($content, $pattern)
            if (-not $match.Success) { throw }
            [xml]$xml = $match.Value
        }
        if (-not $xml.DocumentElement -or $xml.DocumentElement.LocalName -ne $tag) {
            $result.Reason = "Expected <$tag> XML root"
            return [pscustomobject]$result
        }

        $root = $xml.DocumentElement
        $titleNode = $root.SelectSingleNode('./title')
        $yearNode = $root.SelectSingleNode('./year')
        if ($titleNode) { $result.Title = $titleNode.InnerText.Trim() }
        if ($yearNode -and $yearNode.InnerText.Trim() -match '^\d{4}$') {
            $result.Year = [int]$yearNode.InnerText.Trim()
        }

        # Prefer typed <uniqueid> values, then legacy provider-specific tags.
        foreach ($node in $root.SelectNodes('./uniqueid')) {
            $idType = ([string]$node.GetAttribute('type')).Trim().ToLowerInvariant()
            $value = $node.InnerText.Trim()
            switch ($idType) {
                'tmdb' { if (-not $result.TmdbId -and $value -match '^[1-9]\d*$') { $result.TmdbId = $value } }
                'tvdb' { if (-not $result.TvdbId -and $value -match '^[1-9]\d*$') { $result.TvdbId = $value } }
                'imdb' { if (-not $result.ImdbId -and $value -match '^tt\d+$') { $result.ImdbId = $value } }
            }
        }
        foreach ($idType in @('tmdb', 'tvdb', 'imdb')) {
            $key = @{ tmdb = 'TmdbId'; tvdb = 'TvdbId'; imdb = 'ImdbId' }[$idType]
            if ($result[$key]) { continue }
            $legacy = $root.SelectSingleNode("./${idType}id")
            if (-not $legacy) { continue }
            $value = $legacy.InnerText.Trim()
            if (($idType -eq 'imdb' -and $value -match '^tt\d+$') -or
                ($idType -ne 'imdb' -and $value -match '^[1-9]\d*$')) {
                $result[$key] = $value
            }
        }
        if (-not ($result.TmdbId -or $result.TvdbId -or $result.ImdbId)) {
            $legacy = $root.SelectSingleNode('./id')
            if ($legacy) {
                $value = $legacy.InnerText.Trim()
                if ($value -match '^tt\d+$') { $result.ImdbId = $value }
                elseif ($value -match '^[1-9]\d*$') {
                    if ($Type -eq 'Movie') { $result.TmdbId = $value }
                    else { $result.TvdbId = $value }
                }
            }
        }

        if (-not ($result.TmdbId -or $result.TvdbId -or $result.ImdbId)) {
            $result.Reason = 'No usable provider ID in NFO'
        }
        elseif ($Type -eq 'Series' -and -not ($result.TmdbId -or $result.TvdbId)) {
            # Existing show-poster providers cannot fetch series artwork by IMDb ID alone.
            $result.Reason = 'Series has only IMDb ID; TMDb or TVDb ID required'
        }
        else { $result.Matched = $true }
    }
    catch {
        $result.Reason = "Unreadable or malformed NFO: $($_.Exception.Message)"
    }
    return [pscustomobject]$result
}
