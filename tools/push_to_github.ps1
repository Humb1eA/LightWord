#Requires -Version 5.1
<#
.SYNOPSIS
  Push this project to GitHub without installing git.

.DESCRIPTION
  Creates the repo if needed, uploads every file as a base64 blob through the
  GitHub REST API, then creates a tree, a commit and the branch ref. Intended for
  "I just want CI to build me an IPA once".

  Token scopes:
    - Fine-grained PAT: Contents = Read and write (+ Administration to create a repo)
    - Classic PAT: repo

  Works on Windows PowerShell 5.1 and PowerShell 7. This script is ASCII-only on
  purpose: 5.1 reads BOM-less .ps1 files as ANSI, which corrupts non-ASCII text.

.EXAMPLE
  $env:GITHUB_TOKEN = "github_pat_xxx"
  powershell -ExecutionPolicy Bypass -File tools\push_to_github.ps1 -Repo "yourname/lightword" -Private

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\push_to_github.ps1 -Repo "yourname/lightword" -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [string]$Token = $env:GITHUB_TOKEN,

    [string]$Branch = "main",

    [string]$Message = "Add LightWord iOS app",

    [switch]$Private,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# tools/ -> repository root
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $root "Package.swift"))) {
    throw "Cannot find repo root (no Package.swift under $root)"
}

$separator = [IO.Path]::DirectorySeparatorChar
$rootPrefix = $root.TrimEnd([char[]]@('\', '/')) + $separator
$skipTopDirs = @("build", ".git", ".swiftpm", "node_modules", "DerivedData", ".build")
$maxFileBytes = 40MB

$files = New-Object System.Collections.ArrayList
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
    if (-not $file.FullName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }

    $relative = $file.FullName.Substring($rootPrefix.Length) -replace '\\', '/'
    $top = ($relative -split '/')[0]

    if ($skipTopDirs -contains $top) { continue }
    if ($relative -match '\.(ipa|dSYM|pyc)$') { continue }
    if ($relative -match '(^|/)__pycache__(/|$)') { continue }
    if ($file.Name -eq '.DS_Store') { continue }
    if ($file.Length -gt $maxFileBytes) {
        Write-Warning "skipping large file: $relative"
        continue
    }

    [void]$files.Add([pscustomobject]@{
        Path     = $relative
        FullName = $file.FullName
        Size     = $file.Length
    })
}

if ($files.Count -eq 0) { throw "Nothing to upload" }

$totalKb = [math]::Round((($files | Measure-Object -Property Size -Sum).Sum) / 1KB, 1)

if ($DryRun) {
    "Dry run - target $Repo (branch $Branch)"
    "files: $($files.Count), total: $totalKb KB"
    ""
    $files | Sort-Object Path | ForEach-Object { '  {0,8}  {1}' -f $_.Size, $_.Path }
    return
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "Missing token: set `$env:GITHUB_TOKEN or pass -Token"
}

$headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = "application/vnd.github+json"
    'X-GitHub-Api-Version' = "2022-11-28"
    'User-Agent'           = "LightWord-pusher"
}
$apiBase = "https://api.github.com"

function Invoke-GitHub {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body
    )

    $call = @{
        Method     = $Method
        Uri        = "$apiBase$Path"
        Headers    = $headers
        TimeoutSec = 90
    }
    if ($null -ne $Body) {
        $call.Body = $Body | ConvertTo-Json -Depth 10 -Compress
        $call.ContentType = "application/json; charset=utf-8"
    }

    try {
        return Invoke-RestMethod @call
    }
    catch {
        $detail = $_.ErrorDetails.Message
        if (-not $detail) { $detail = $_.Exception.Message }
        throw "GitHub API $Method $Path failed: $detail"
    }
}

# 1. create the repo when it does not exist yet
try {
    $null = Invoke-GitHub -Method GET -Path "/repos/$Repo"
    "repo exists: $Repo"
}
catch {
    $name = $Repo.Split('/')[-1]
    $null = Invoke-GitHub -Method POST -Path "/user/repos" -Body @{
        name      = $name
        private   = [bool]$Private
        auto_init = $false
    }
    "created repo: $Repo"
}

# 2. upload blobs one by one
$tree = New-Object System.Collections.ArrayList
$index = 0
foreach ($file in $files) {
    $index++
    $base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
    $blob = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/blobs" -Body @{
        content  = $base64
        encoding = "base64"
    }
    [void]$tree.Add(@{
        path = $file.Path
        mode = "100644"
        type = "blob"
        sha  = $blob.sha
    })

    if ($index % 10 -eq 0 -or $index -eq $files.Count) {
        "uploaded $index/$($files.Count)"
    }
}

# 3. tree, commit, ref
$newTree = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/trees" -Body @{ tree = $tree.ToArray() }

$parents = @()
try {
    $ref = Invoke-GitHub -Method GET -Path "/repos/$Repo/git/ref/heads/$Branch"
    $parents = @($ref.object.sha)
}
catch {
    $parents = @()
}

$commit = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/commits" -Body @{
    message = $Message
    tree    = $newTree.sha
    parents = $parents
}

if ($parents.Count -gt 0) {
    $null = Invoke-GitHub -Method PATCH -Path "/repos/$Repo/git/refs/heads/$Branch" -Body @{
        sha   = $commit.sha
        force = $false
    }
}
else {
    $null = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/refs" -Body @{
        ref = "refs/heads/$Branch"
        sha = $commit.sha
    }
}

""
"done: $($files.Count) files, commit $($commit.sha.Substring(0, 7))"
"CI runs (about 3-6 min): https://github.com/$Repo/actions"
