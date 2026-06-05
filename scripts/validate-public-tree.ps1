$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$claudeRoot = Join-Path $repoRoot ".claude"

$allowedClaudeFiles = @(
    "commands/self-review.md",
    "commands/team-investigate.md",
    "commands/team-review.md",
    "skills/openspec-review-pipeline/SKILL.md",
    "skills/team-apply/SKILL.md"
)

$allowedClaudeDirs = @(
    "commands",
    "skills",
    "skills/openspec-review-pipeline",
    "skills/team-apply"
)

$blockedPublicContentPatterns = @(
    [pscustomobject]@{ Label = "bdd-test skill reference"; Pattern = "\bbdd-test\b" },
    [pscustomobject]@{ Label = "OpenSpec apply skill reference"; Pattern = "\bopenspec-apply-change\b" },
    [pscustomobject]@{ Label = "OpenSpec archive skill reference"; Pattern = "\bopenspec-archive-change\b" },
    [pscustomobject]@{ Label = "OpenSpec explore skill reference"; Pattern = "\bopenspec-explore\b" },
    [pscustomobject]@{ Label = "OpenSpec propose skill reference"; Pattern = "\bopenspec-propose\b" },
    [pscustomobject]@{ Label = "opsx command reference"; Pattern = "\bopsx\b" },
    [pscustomobject]@{ Label = "debug command reference"; Pattern = "\bdebug-explore\b" },
    [pscustomobject]@{ Label = "Codex implement skill reference"; Pattern = "\bcodex-implement\b" },
    [pscustomobject]@{ Label = "Codex review skill reference"; Pattern = "\bcodex-review\b" },
    [pscustomobject]@{ Label = "economy implement skill reference"; Pattern = "\beconomy-implement\b" },
    [pscustomobject]@{ Label = "parallel worktree skill reference"; Pattern = "\bparallel-worktree\b" },
    [pscustomobject]@{ Label = "UI feedback triage skill reference"; Pattern = "\bui-feedback-triage\b" },
    [pscustomobject]@{ Label = "WPF agent reference"; Pattern = "\bwpf-agent\b" },
    [pscustomobject]@{ Label = "WPF skill reference"; Pattern = "\bwpf-(setup|test|ticket|ui)\b" },
    [pscustomobject]@{ Label = "WPF project reference"; Pattern = "\bWPF\b" },
    [pscustomobject]@{ Label = "LLMGame project reference"; Pattern = "\bLLMGame\b" },
    [pscustomobject]@{ Label = "LLMGameApp project reference"; Pattern = "\bLLMGameApp\b" },
    [pscustomobject]@{ Label = "game MCP reference"; Pattern = "\bmcp__game\b" },
    [pscustomobject]@{ Label = "Headless MCP server reference"; Pattern = "\bHeadlessMcpServer\b" },
    [pscustomobject]@{ Label = "project steering docs reference"; Pattern = "docs/steering" },
    [pscustomobject]@{ Label = "LLMGameApp source path"; Pattern = "src/LLMGameApp" },
    [pscustomobject]@{ Label = "LLMGame test path"; Pattern = "test/LLMGame" },
    [pscustomobject]@{ Label = "Windows project path"; Pattern = "D:[\\/](vibe|claude-code-skills)" }
)

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $relativePath = $Path.Substring($Root.Length).TrimStart("\", "/")
    $relativePath -replace "\\", "/"
}

function Assert-SetExactly {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Actual,

        [Parameter(Mandatory = $true)]
        [string[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $unexpected = @($Actual | Where-Object { $Expected -notcontains $_ })
    $missing = @($Expected | Where-Object { $Actual -notcontains $_ })

    if ($unexpected.Count -gt 0 -or $missing.Count -gt 0) {
        $message = @(
            "$Label manifest mismatch.",
            "Unexpected: $($unexpected -join ', ')",
            "Missing: $($missing -join ', ')",
            "Expected: $($Expected -join ', ')"
        ) -join [Environment]::NewLine

        throw $message
    }
}

function Assert-NoBlockedContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [object[]]$BlockedPatterns
    )

    $violations = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $Root -File -Recurse -Force | ForEach-Object {
        $relativePath = Get-RelativePath -Root $Root -Path $_.FullName
        $lineNumber = 0

        Get-Content -LiteralPath $_.FullName | ForEach-Object {
            $lineNumber++
            $line = $_

            foreach ($blockedPattern in $BlockedPatterns) {
                if ($line -match $blockedPattern.Pattern) {
                    $violations.Add("${relativePath}:$lineNumber $($blockedPattern.Label) matched '$($Matches[0])'")
                }
            }
        }
    }

    if ($violations.Count -gt 0) {
        throw "Blocked public content found:$([Environment]::NewLine)$($violations -join [Environment]::NewLine)"
    }
}

function Assert-NoWildcardInstallerCopy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $text = Get-Content -Raw -LiteralPath $Path
    if ($text -match "\.claude/(skills|commands)/[`"']?\*") {
        throw "Wildcard .claude copy is not allowed in $Path"
    }
}

if (-not (Test-Path -LiteralPath $claudeRoot)) {
    throw "Missing .claude directory: $claudeRoot"
}

$resolvedClaudeRoot = (Resolve-Path -LiteralPath $claudeRoot).ProviderPath.TrimEnd("\", "/")
$actualFiles = @(Get-ChildItem -LiteralPath $claudeRoot -File -Recurse -Force | ForEach-Object {
        Get-RelativePath -Root $resolvedClaudeRoot -Path $_.FullName
    })
$actualDirs = @(Get-ChildItem -LiteralPath $claudeRoot -Directory -Recurse -Force | ForEach-Object {
        Get-RelativePath -Root $resolvedClaudeRoot -Path $_.FullName
    })

Assert-SetExactly -Actual $actualFiles -Expected $allowedClaudeFiles -Label ".claude file"
Assert-SetExactly -Actual $actualDirs -Expected $allowedClaudeDirs -Label ".claude directory"
Assert-NoBlockedContent -Root $claudeRoot -BlockedPatterns $blockedPublicContentPatterns
Assert-NoWildcardInstallerCopy -Path (Join-Path $repoRoot "install.sh")
Assert-NoWildcardInstallerCopy -Path (Join-Path $repoRoot "README.md")

Write-Host "Public tree validation passed."
