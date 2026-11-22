# Run with: pwsh -NoProfile -File ./tests/FolderScan.Smoke.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'modules/functions/FolderScan.ps1')
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("FolderScan-[đẹp]-" + [guid]::NewGuid().ToString('N'))
$movies = Join-Path $fixtureRoot 'Movies'
$shows = Join-Path $fixtureRoot 'TV Shows'
$assets = Join-Path $fixtureRoot 'assets'
$movieFolder = Join-Path $movies 'Phim [Đẹp] (2024)'
$showFolder = Join-Path $shows 'Series (2024)'
$withoutNfo = Join-Path $movies 'Missing NFO'
$malformed = Join-Path $movies 'Broken NFO'
foreach ($d in @($movieFolder, $showFolder, $withoutNfo, $malformed, $assets, (Join-Path $fixtureRoot 'Logs'))) {
    [void][System.IO.Directory]::CreateDirectory($d)
}
try {
    [System.IO.File]::WriteAllText((Join-Path $movieFolder 'Phim [Đẹp].mkv'), '')
    [System.IO.File]::WriteAllText((Join-Path $movieFolder 'Phim [Đẹp].nfo'), 'extra text <movie><title>Dune Part Two</title><year>2024</year><uniqueid type="tmdb">693134</uniqueid><uniqueid type="imdb">tt15239678</uniqueid></movie> trailing text')
    [System.IO.File]::WriteAllText((Join-Path $showFolder 'tvshow.nfo'), '<tvshow><title>Example Show</title><year>2024</year><tvdbid>123456</tvdbid></tvshow>')
    [System.IO.File]::WriteAllText((Join-Path $malformed 'movie.nfo'), '<movie><title>bad</title>')

    $m = Get-FolderScanNfoMetadata -Folder $movieFolder -Type Movie
    if (-not $m.Matched -or $m.TmdbId -ne '693134' -or $m.ImdbId -ne 'tt15239678') { throw 'Movie parser failed' }
    $s = Get-FolderScanNfoMetadata -Folder $showFolder -Type Series
    if (-not $s.Matched -or $s.TvdbId -ne '123456') { throw 'Series parser failed' }
    if ((Get-FolderScanNfoMetadata -Folder $withoutNfo -Type Movie).Matched) { throw 'Missing NFO was accepted' }
    if ((Get-FolderScanNfoMetadata -Folder $malformed -Type Movie).Matched) { throw 'Malformed NFO was accepted' }
    $legacyMovie = Join-Path $movies 'Legacy ID'
    [void][System.IO.Directory]::CreateDirectory($legacyMovie)
    [System.IO.File]::WriteAllText((Join-Path $legacyMovie 'movie.nfo'), '<movie><title>Legacy</title><id>55555</id></movie>')
    $legacy = Get-FolderScanNfoMetadata -Folder $legacyMovie -Type Movie
    if (-not $legacy.Matched -or $legacy.TmdbId -ne '55555') { throw 'Legacy <id> failed' }
    Remove-Item -LiteralPath $legacyMovie -Recurse -Force
    $imdbOnlySeries = Join-Path $shows 'IMDb only'
    [void][System.IO.Directory]::CreateDirectory($imdbOnlySeries)
    [System.IO.File]::WriteAllText((Join-Path $imdbOnlySeries 'tvshow.nfo'), '<tvshow><uniqueid type="imdb">tt12345</uniqueid></tvshow>')
    if ((Get-FolderScanNfoMetadata -Folder $imdbOnlySeries -Type Series).Matched) { throw 'IMDb-only series unexpectedly matched' }
    Remove-Item -LiteralPath $imdbOnlySeries -Recurse -Force

    $global:ScriptRoot = $fixtureRoot
    $global:configLogging = Join-Path $fixtureRoot 'Logs/test.log'
    $AssetPath = $assets
    $FolderScanMovieRoots = @($movies)
    $FolderScanShowRoots = @($shows)
    $global:ProviderOrder = @('TMDB', 'FANART', 'TVDB', 'PLEX')
    $script:movieCalls = 0
    $script:showCalls = 0
    $script:cache = @{}
    function Write-Entry { param($Message, $Subtext, $Path, $Color, $log) }
    function Get-AssetHashtable { return $script:cache }
    function Invoke-MoviePosterCreation {
        param($entry)
        $script:movieCalls++
        $target = Join-Path (Join-Path (Join-Path $AssetPath $entry.'Library Name') $entry.RootFoldername) 'poster.jpg'
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        [System.IO.File]::WriteAllText($target, 'mock artwork')
    }
    function Invoke-ShowPosterCreation {
        param($entry)
        $script:showCalls++
        $target = Join-Path (Join-Path (Join-Path $AssetPath $entry.'Library Name') $entry.RootFoldername) 'poster.jpg'
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        [System.IO.File]::WriteAllText($target, 'mock artwork')
    }
    . (Join-Path $repo 'modules/modes/FolderScanMode.ps1')
    if ($script:movieCalls -ne 1 -or $script:showCalls -ne 1) { throw "Bad first run movie=$script:movieCalls show=$script:showCalls" }
    $unmatched = Get-Content -LiteralPath (Join-Path $fixtureRoot 'Logs/FolderScan_unmatched.txt')
    if (@($unmatched).Count -ne 2) { throw 'Unmatched count wrong' }
    . (Join-Path $repo 'modules/modes/FolderScanMode.ps1')
    if ($script:movieCalls -ne 1 -or $script:showCalls -ne 1) { throw 'Repeat run regenerated artwork' }
    Write-Host 'PASS: movie, series, malformed/missing NFO, special chars, repeated scan skips' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
