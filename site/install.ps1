# Ruby4Lich5 installer for Windows (PROTOTYPE, fork evaluation only).
#
#   irm https://ruby4lich5.elanthia.online/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://ruby4lich5.elanthia.online/install.ps1))) -Dir C:\Games\Lich5
#
# 1. rv installs the RubyInstaller Ruby that the live Ruby4Lich5 gem manifest
#    was built for (no DevKit, no MSYS2).
# 2. Lich's gems come prebuilt from that manifest: each artifact is downloaded,
#    checked against its SHA-256, and gem-installed in the manifest's order.
#    That is the same set Lich's own startup check enforces, so Lich starts
#    without a repair.
# 3. The latest Lich release is downloaded and checked against its SHA-256.
param(
  [string]$Dir = (Join-Path $HOME 'Lich5'),
  [switch]$NoModifyPath
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "    ok $m" -ForegroundColor Green }
function Fail($m) { throw "Error: $m" }

function Get-Sha256($path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() }

function Save-Verified($url, $path, $expected) {
  $expected = $expected -replace '^sha256:', ''
  Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
  $actual = Get-Sha256 $path
  if ($actual -ne $expected) { Fail "SHA-256 mismatch for $(Split-Path $path -Leaf): expected $expected, got $actual" }
}

# A release's asset digest, from the API or (when the API refuses) from
# github.com's assets page, like the macOS/Linux script and fetch-lich.ps1.
function Get-ReleaseAsset($repo, $tag, $asset) {
  try {
    $rel = if ($tag) { Invoke-RestMethod "https://api.github.com/repos/$repo/releases/tags/$tag" } else { Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" }
    $a = $rel.assets | Where-Object name -eq $asset | Select-Object -First 1
    if ($a -and $a.digest) { return @{ Tag = $rel.tag_name; Url = $a.browser_download_url; Digest = $a.digest } }
  } catch { }
  if (-not $tag) {
    $r = Invoke-WebRequest "https://github.com/$repo/releases/latest" -UseBasicParsing
    $tag = ($r.BaseResponse.ResponseUri, $r.BaseResponse.RequestMessage.RequestUri | Where-Object { $_ } | Select-Object -First 1).AbsoluteUri -replace '.*/releases/tag/', ''
  }
  $html = (Invoke-WebRequest "https://github.com/$repo/releases/expanded_assets/$tag" -UseBasicParsing).Content
  $digests = [regex]::Matches($html, '<clipboard-copy\b[^>]*>') | ForEach-Object { $_.Value } |
    Where-Object { $_ -match "aria-label=`"Copy to clipboard digest for $([regex]::Escape($asset))`"" } |
    ForEach-Object { if ($_ -match 'value="(sha256:[0-9a-f]{64})"') { $Matches[1] } } | Sort-Object -Unique
  if (@($digests).Count -ne 1) { Fail "No single SHA-256 published for $asset in $repo $tag" }
  return @{ Tag = $tag; Url = "https://github.com/$repo/releases/download/$tag/$asset"; Digest = $digests }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ruby4lich5-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Step "Checking platform and the live gem manifest"
  $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  switch ($arch) {
    'X64'   { $platform = 'x64-mingw-ucrt'; $riArch = 'x64' }
    'Arm64' { $platform = 'aarch64-mingw-ucrt'; $riArch = 'arm' }
    default { Fail "Unsupported Windows architecture: $arch" }
  }
  $manifestUrl = "https://github.com/elanthia-online/Ruby4Lich5/releases/download/R4L5-gem-bundle-$platform/R4L5-gem-manifest.json"
  $manifestPath = Join-Path $tmp 'manifest.json'
  Invoke-WebRequest -Uri $manifestUrl -OutFile $manifestPath -UseBasicParsing
  $target = ((Get-Content -Raw $manifestPath | ConvertFrom-Json).targets | Where-Object platform -eq $platform | Select-Object -First 1)
  if (-not $target) { Fail "The live manifest has no $platform target." }
  $riVersion = $target.contract.ruby_installer_version          # e.g. 4.0.9-1
  $rubyVersion = $riVersion.Split('-')[0]
  Ok "$platform, manifest sha256 $((Get-Sha256 $manifestPath).Substring(0,12))..., RubyInstaller $riVersion"

  Step "Setting up rv"
  $rv = (Get-Command rv.exe -ErrorAction SilentlyContinue).Source
  if (-not $rv) { $rv = Join-Path $HOME '.local\bin\rv.exe' }
  if (-not (Test-Path $rv)) {
    $env:RV_NO_MODIFY_PATH = '1'
    Invoke-RestMethod https://rv.dev/install.ps1 | Invoke-Expression
    if (-not (Test-Path $rv)) { Fail "rv's installer finished but $rv is missing." }
  }
  Ok (& $rv --version)

  Step "Installing Ruby $rubyVersion (RubyInstaller $riVersion)"
  $rubies = (& $rv ruby dir).Trim()
  $rubyDir = Join-Path $rubies "ruby-$rubyVersion"
  if (-not (Test-Path (Join-Path $rubyDir 'bin\ruby.exe'))) {
    $asset = "rubyinstaller-$riVersion-$riArch.7z"
    $ri = Get-ReleaseAsset 'oneclick/rubyinstaller2' "RubyInstaller-$riVersion" $asset
    $archive = Join-Path $tmp $asset
    Save-Verified $ri.Url $archive $ri.Digest
    Ok "Verified $asset"
    & $rv ruby install $rubyVersion --tarball-path $archive
    if ($LASTEXITCODE -ne 0) { Fail "rv couldn't install Ruby $rubyVersion." }
  }
  $rubyBin = Join-Path $rubyDir 'bin'
  if (-not (Test-Path (Join-Path $rubyBin 'ruby.exe'))) { Fail "Ruby is missing from $rubyBin." }
  $env:Path = "$rubyBin;$env:Path"
  Ok (& (Join-Path $rubyBin 'ruby.exe') -v)

  Step "Installing Lich's prebuilt gems from the manifest"
  $gem = Join-Path $rubyBin 'gem.cmd'
  $downloads = @{}
  foreach ($unit in $target.units) {
    if ($unit.lich_versions) { continue }   # ranged units are for older Lich releases
    $art = $unit.artifact
    if (-not $downloads.ContainsKey($art.url)) {
      $file = Join-Path $tmp ("{0}-{1}" -f $downloads.Count, $art.filename)
      Save-Verified $art.url $file $art.sha256
      if ($art.archive -eq 'zip') {
        $dest = "$file.d"; Expand-Archive -LiteralPath $file -DestinationPath $dest
        $downloads[$art.url] = $dest
      } else {
        $downloads[$art.url] = Split-Path $file
        Copy-Item $file (Join-Path (Split-Path $file) $art.filename)
      }
    }
    $from = $downloads[$art.url]
    foreach ($name in $unit.install_order) {
      $pkg = $unit.packages | Where-Object name -eq $name | Select-Object -First 1
      $path = Join-Path $from $pkg.filename
      if ((Get-Sha256 $path) -ne ($pkg.sha256 -replace '^sha256:', '')) { Fail "SHA-256 mismatch for $($pkg.filename)" }
      & $gem list -i $pkg.name -v $pkg.version *> $null
      if ($LASTEXITCODE -eq 0) { continue }
      & $gem install --local --ignore-dependencies --no-document $path
      if ($LASTEXITCODE -ne 0) { Fail "gem install failed for $($pkg.filename)" }
    }
  }
  Ok "Gems are installed"

  Step "Installing Lich"
  if (Test-Path (Join-Path $Dir 'lich.rbw')) {
    Ok "Found Lich in $Dir. Leaving it as it is."
  } else {
    if ((Test-Path $Dir) -and (Get-ChildItem -Force $Dir | Select-Object -First 1)) { Fail "$Dir exists, isn't empty and isn't a Lich folder." }
    $lich = Get-ReleaseAsset 'elanthia-online/lich-5' $null 'lich-5.zip'
    $zip = Join-Path $tmp 'lich-5.zip'
    Save-Verified $lich.Url $zip $lich.Digest
    $stage = Join-Path (Split-Path $Dir) (".lich-staging-" + [guid]::NewGuid())
    Expand-Archive -LiteralPath $zip -DestinationPath $stage
    if (-not (Test-Path (Join-Path $stage 'Lich5\lich.rbw'))) { Fail "The Lich archive didn't contain Lich5\lich.rbw." }
    if (Test-Path $Dir) { Remove-Item $Dir }
    Move-Item (Join-Path $stage 'Lich5') $Dir
    Remove-Item $stage -Recurse -Force
    Ok "Lich $($lich.Tag) is in $Dir"
  }

  if (-not $NoModifyPath) {
    Step "Putting Lich's Ruby on your PATH"
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($userPath -split ';' | Where-Object { $_ -and ($_ -notlike "$rubies\ruby-*\bin") })
    [Environment]::SetEnvironmentVariable('Path', (@($rubyBin) + $parts) -join ';', 'User')
    Ok "Added $rubyBin to your user PATH (new terminals)"
  }

  Write-Host "`nDone. Start Lich with:`n    & '$rubyBin\rubyw.exe' '$Dir\lich.rbw'`n"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
