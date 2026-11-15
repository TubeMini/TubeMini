# Smoke test for a running tubemini-server: hits every implemented endpoint and checks status + basic content.
#   powershell -File scripts\smoke.ps1                      # default http://127.0.0.1:8080
#   powershell -File scripts\smoke.ps1 -Base http://192.168.1.10:8080
param(
    [string]$Base = "http://127.0.0.1:8080"
)

$ErrorActionPreference = "Stop"
$failed = 0

function Check([string]$Name, [string]$Path, [int]$Status = 200, [string]$Contains = "", [string]$Method = "GET", [string]$Agent = "YouTube/1.3.0") {
    $url = "$Base$Path"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri $url -Method $Method -UserAgent $Agent -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 60 -ErrorAction Stop
        $code = [int]$r.StatusCode
        # Non-text types (e.g. application/vnd.apple.mpegurl) come back as bytes
        $body = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { $r.Content }
    } catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { $code = 0; $body = "$_" } else { $code = [int]$resp.StatusCode; $body = "" }
    }
    $ms = $sw.ElapsedMilliseconds
    $ok = ($code -eq $Status) -and ($Contains -eq "" -or $body -like "*$Contains*")
    $mark = if ($ok) { "OK  " } else { "FAIL" }
    if (-not $ok) { $script:failed++ }
    $entries = ([regex]::Matches([string]$body, "<entry")).Count
    "{0} {1,-28} {2,3} {3,6} ms  entries={4}" -f $mark, $Name, $code, $ms, $entries
}

Check "debug page"          "/"                                              200 "tubemini-server"
Check "categories"          "/schemas/2007/categories.cat"                   200 "app:categories"
Check "registerDevice"      "/youtube/accounts/registerDevice"               200 "DeviceKey=" "POST"
Check "applelogin1"         "/youtube/accounts/applelogin1"                  200 "hmackr2=" "POST"
Check "home (popular)"      "/feeds/api/standardfeeds/VN/most_popular"       200 "<entry"
Check "home (Music)"        "/feeds/api/standardfeeds/most_popular_Music"    200 "<entry"
Check "search"              "/feeds/api/videos?q=nhac+tre&max-results=10"    200 "rel='next'"
Check "search 720 + filter" "/720/feeds/api/videos?q=hoat+hinh&orderby=viewCount&time=this_week&duration=long" 200 "/720/getvideo/"
Check "search no q"         "/feeds/api/videos"                              404
Check "single video"        "/feeds/player/videos/aqz-KE-bpKQ"               200 "<yt:videoid>aqz-KE-bpKQ</yt:videoid>"
Check "related"             "/feeds/api/videos/aqz-KE-bpKQ/related"          200 "<entry"
Check "channel uploads"     "/feeds/api/users/UCSMOQeBJ2RAnuFungnQOxLg/uploads" 200 "<entry"
Check "channel info"        "/feeds/api/channels/UCSMOQeBJ2RAnuFungnQOxLg"   200 "<yt:channelStatistics"
Check "channel search"      "/feeds/api/channels?q=vtv"                      200 "<yt:channelId>"
Check "channel playlists"   "/feeds/api/users/UCSMOQeBJ2RAnuFungnQOxLg/playlists" 200 "<yt:playlistId>"
Check "playlist search"     "/feeds/api/playlists/snippets?q=nhac+tre"       200 "<yt:playlistId>"
Check "playlist videos"     "/feeds/api/playlists/PLa1F2ddGya_-I9y1nXALrBqrZNdlUE012" 200 "skip=25"
Check "comments"            "/api/videos/aqz-KE-bpKQ/comments"               200 "<yt:replyCount>"
Check "comments (feeds)"    "/feeds/api/videos/aqz-KE-bpKQ/comments"         200 "<entry"
Check "classic app home"    "/feeds/api/standardfeeds/US/recently_featured"  200 "/video/sd/" "GET" "Apple iPad v5.1.1 YouTube v1.0.0.9B206"
Check "getvideo 360p"       "/getvideo/aqz-KE-bpKQ"                          307
Check "getvideo HLS 720"    "/720/getvideo/6C6xOz-6ET4"                      200 "#EXT-X-STREAM-INF"
Check "getvideo bad id"     "/getvideo/xyz"                                  404
# /tm/v1 (server without auth_token); read-only, the POST is rejected before anything is written
Check "tm ping"             "/tm/v1/ping"                                    200 "<tm:ping"
Check "tm streams"          "/tm/v1/videos/aqz-KE-bpKQ/streams"              200 "<tm:stream "
Check "tm streams audio/dl"  "/tm/v1/videos/aqz-KE-bpKQ/streams"              200 "<tm:download "
Check "getaudio"            "/getaudio/aqz-KE-bpKQ"                          200 "mp4a.40"
Check "proxy off"           "/proxy/0000000000000000/aHR0cHM6Ly94.ts"       404
Check "tm subscriptions"    "/tm/v1/subscriptions"                           200 "#channel"
Check "tm feed"             "/tm/v1/feed"                                    200 "tm:feed"
Check "tm history"          "/tm/v1/history"                                 200 "xmlns:tm="
Check "tm history entry"    "/tm/v1/history/aqz-KE-bpKQ"                     200 "<tm:history"
Check "tm history bad POST" "/tm/v1/history"                                 400 "" "POST"

if ($failed -gt 0) { "`n$failed check(s) failed"; exit 1 } else { "`nall checks passed" }
