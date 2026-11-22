# Posterizarr FS — Folder Scan (unofficial fork)

This is an **unofficial modification** of [fscorrupt/posterizarr](https://github.com/fscorrupt/posterizarr), licensed under **GNU GPL-3.0**. Original authors retain their copyright notices. See [LICENSE](LICENSE). The original Plex/Jellyfin/Emby modes are unchanged.

## Scope

The optional `-FolderScan` CLI switch reads **one folder per movie or series** from configured on-disk roots, loads IDs from local NFO files and calls the existing Posterizarr poster-generation functions. It generates **movie/series-level posters only** — no season posters, backgrounds, episodes or title cards. No media-server discovery or upload API calls are made in this mode.

### Paths and asset naming

Media roots **must use container paths**, not host paths. Every immediate subfolder of a root is an item. Directory symlinks are skipped.

- Movies: `movie.nfo` or a uniquely matched `<video basename>.nfo`
- Shows: `tvshow.nfo`
- NFO root XML: `<movie>` or `<tvshow>`
- Provider IDs: typed `<uniqueid type="tmdb|tvdb|imdb">` or legacy `<tmdbid>`, `<tvdbid>`, `<imdbid>`, `<id>`
- Missing, malformed, ambiguous or unusable NFOs are recorded in `/app/Logs/FolderScan_unmatched.txt` (check the application's log mount).

No title-based lookup is performed to identify an item. A show with only an IMDb ID is unmatched because the existing series-poster providers require TMDb/TVDb IDs. **An untyped numeric legacy `<id>` is interpreted as TMDb for movies / TVDb for shows; verify legacy NFO IDs before use.**

Folder Scan uses `LibraryFolders=true` for its invocation. The asset path is:

```text
/assets/<media-root basename>/<media-folder basename>/poster.jpg
```

Example: `/media/Movies/Dune Part Two (2024)/movie.nfo` becomes `/assets/Movies/Dune Part Two (2024)/poster.jpg`. The media-root **basename must match the library name that the Jellyfin Posterizarr plugin expects**, or the plugin will not map the generated artwork.

Already-existing image assets are skipped using the original `Get-AssetHashtable` logic, without any online provider calls for skipped items. There is no automatic overwrite or backup in this limited mode.

## Configuration

Insert these keys into the running container's **existing** `/config/config.json` (do not replace the entire config):

```json
"FolderScan": {
  "MovieRoots": ["/media/Movies"],
  "ShowRoots": ["/media/TV Shows"]
}
```

The fork's `config.example.json` contains empty defaults. The existing upstream configuration migration may not automatically add the new section, so supply it yourself. Retain TMDb/TVDb/Fanart API credentials under `ApiPart` as needed for artwork fetching.

Run against a **separate container** from official Posterizarr:

```sh
docker exec -it posterizarr-fs pwsh /app/Posterizarr.ps1 -FolderScan
```

Suggested NAS mounts (adjust host paths to your actual Synology locations):

```yaml
volumes:
  - /volume1/docker/posterizarr-fs/config:/config
  - /volume1/docker/posterizarr-fs/assets:/assets
  - /volume1/docker/posterizarr-fs/assetsbackup:/assetsbackup
  - /volume1/docker/posterizarr-fs/manualassets:/manualassets
  - /volume1/Movies:/media/Movies:ro
  - /volume1/TV Shows:/media/TV Shows:ro
ports:
  - "8001:8000"
```

Do not mount the official container's `/config` or `/assets` into this fork while testing. The source mounts can be read-only.

## Testing and Docker image

Run the local, no-network smoke tests:

```sh
pwsh -NoProfile -File tests/FolderScan.Smoke.ps1
```

The smoke test **mocks the poster-generation functions**. It checks NFO parsing, unsupported NFOs, special characters, output asset paths and skip on subsequent scans, but **not real artwork fetching**. Test at least one real movie/series and inspect the generated artwork before deploying to production.

The fork's GitHub Actions workflow builds the x86-64 Docker image to `ghcr.io/vanvietit-star/posterizarr-fs:dev` after passing its tests, assuming GitHub Actions and GHCR publishing are enabled on your fork. Do not replace your running official container.

## Modification notes

- Added local Folder Scan mode and NFO reader.
- Added configuration keys for media roots and fork documentation.
- Version and Release.txt changed for the modified fork.
- The standard Posterizarr image-generation functions, media-server modes and dependency list remain unchanged.
