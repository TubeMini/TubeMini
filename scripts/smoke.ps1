# Smoke test for a running tubemini-server: hits every implemented endpoint and checks status + basic content.
#   powershell -File scripts\smoke.ps1                      # default http://127.0.0.1:8080
#   powershell -File scripts\smoke.ps1 -Base http://192.168.1.10:8080
param(
    [string]$Base = "http://127.0.0.1:8080"
)

$ErrorActionPreference = "Stop"
$failed = 0

function Check([string]$Name, [string]$Path, [int]$Status = 200, [string]$Contains = "", [string]$Method = "GET") {
    $url = "$Base$Path"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri $url -Method $Method -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 60 -ErrorAction Stop
        $code = [int]$r.StatusCode
        $body = $r.Content
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
Check "getvideo 360p"       "/getvideo/aqz-KE-bpKQ"                          307
Check "getvideo HLS"        "/720/getvideo/aqz-KE-bpKQ"                      307
Check "getvideo bad id"     "/getvideo/xyz"                                  404

if ($failed -gt 0) { "`n$failed check(s) failed"; exit 1 } else { "`nall checks passed" }
