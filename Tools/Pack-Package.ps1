[CmdletBinding()]
param([string]$Revision = 'HEAD')
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$commit = & git -C $repository rev-parse --verify "$Revision^{commit}"
if ($LASTEXITCODE -ne 0) { throw '配布元のコミットが見つかりません。' }
$json = & git -C $repository show "${commit}:package.json"
if ($LASTEXITCODE -ne 0) { throw 'パッケージ定義が見つかりません。' }
$package = $json -join "`n" | ConvertFrom-Json
if ($package.name -notmatch '^[a-z0-9][a-z0-9.-]*$' -or $package.version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'パッケージ名または版が不正です。'
}
$output = Join-Path $repository '.verification/releases'
New-Item -ItemType Directory -Force $output | Out-Null
$archive = Join-Path $output "$($package.name)-$($package.version).tgz"
$paths = @(
    'package.json', 'package.json.meta', 'README.md', 'README.md.meta',
    'LICENSE', 'LICENSE.meta', 'THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_NOTICES.md.meta',
    'Runtime', 'Runtime.meta', 'Editor', 'Editor.meta', 'Samples~',
    'Native', 'Native.meta', 'Tools', 'Tools.meta', 'Tests~', 'docs.meta',
    'docs/design.md', 'docs/design.md.meta', 'docs/verification.md', 'docs/verification.md.meta',
    'docs/archive', 'docs/archive.meta'
)
& git -C $repository archive --format=tar.gz --prefix=package/ "--output=$archive" $commit -- @paths
if ($LASTEXITCODE -ne 0) { throw 'UPM圧縮に失敗しました。' }
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'), "$hash  $([IO.Path]::GetFileName($archive))`n")
"$commit $hash $archive"
