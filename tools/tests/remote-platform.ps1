#Requires -Version 5.1
# Offline remote-workstation contract; no platform, credentials or network needed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$installer = Join-Path $repo 'install.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ('remote-1c-' + [guid]::NewGuid().ToString('N'))
$project = Join-Path $work 'project with spaces'
$source = Join-Path $work 'source'
$utf8 = New-Object Text.UTF8Encoding $false
function Write-Fixture($Path, $Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Assert-True($Value, $Message) { if (-not $Value) { throw $Message } }
function Run-Installer([string[]]$Arguments) {
    $log = Join-Path $work 'installer.log'
    & (Get-Process -Id $PID).Path -NoProfile -File $installer @Arguments -ProjectRoot $project -Source $source -NonInteractive -McpMode managed *> $log
    Assert-True ($LASTEXITCODE -eq 0) "Installer failed: $([IO.File]::ReadAllText($log))"
    return [IO.File]::ReadAllText($log)
}
try {
    [void][IO.Directory]::CreateDirectory($project)
    $errors = $null; $tokens = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) 'Installer parse failed'
    foreach ($name in @('Get-PlatformMode', 'Read-DevEnvKeys', 'Get-InfobasePublishUrlBase',
        'Resolve-ProjectMcpServers', 'Resolve-McpServerPlaceholders', 'Invoke-InitialSourceDump')) {
        $fn = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name}, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $script:DevEnvFileName = '.dev.env'
    $script:KnownInfobaseLocales = @('ru', 'en')
    function Write-Info($Message) { }
    function Write-Warn($Message) { }
    function Read-YesNo { throw 'Remote mode prompted for a local dump' }
    function Catalogue {
        @(
            [pscustomobject]@{id='1c-code-metadata-mcp'; url='http://localhost:8000/mcp'},
            [pscustomobject]@{id='1C-docs-mcp'; url='http://localhost:8003/mcp'},
            [pscustomobject]@{id='1c-data-mcp'; url='{INFOBASE_PUBLISH_URL}/hs/mcp'}
        )
    }
    $envPath = Join-Path $project '.dev.env'
    Assert-True ((Get-PlatformMode $project) -eq 'local') 'Legacy mode changed'
    Assert-True (@(Resolve-ProjectMcpServers (Catalogue) $project).Count -eq 3) 'Legacy catalogue changed'
    Write-Fixture $envPath "PLATFORM_MODE=remote`nINFOBASE_PATH=remote/base`n"
    Assert-True (@(Resolve-ProjectMcpServers (Catalogue) $project).Count -eq 0) 'Remote default leaked localhost'
    Invoke-InitialSourceDump -Root $project -SourceRoot $source -Manifest @{}
    Write-Host 'OK  remote mode skips unconfigured services and local dump before prompting'

    Write-Fixture $envPath @'
PLATFORM_MODE="remote"
MCP_URL_1C_CODE_METADATA_MCP="https://mcp.example.invalid:8443/project/metadata/mcp"
MCP_URL_1C_DOCS_MCP=http://127.0.0.1:18003/mcp
INFOBASE_PUBLISH_URL=https://onec.example.invalid/base/ru/
'@
    $servers = @(Resolve-ProjectMcpServers (Catalogue) $project)
    $null = Resolve-McpServerPlaceholders $servers (Get-InfobasePublishUrlBase $project)
    Assert-True ($servers.Count -eq 3) 'Remote service missing'
    Assert-True ($servers[0].url -eq 'https://mcp.example.invalid:8443/project/metadata/mcp') 'Quoted override lost path/port'
    Assert-True ($servers[1].url -eq 'http://127.0.0.1:18003/mcp') 'Explicit tunnel rejected'
    Assert-True ($servers[2].url -eq 'https://onec.example.invalid/base/hs/mcp') 'Publication normalization failed'
    Add-Content -LiteralPath $envPath -Value "`nMCP_URL_1C_DATA_MCP=https://mcp.example.invalid/data/mcp"
    $servers = @(Resolve-ProjectMcpServers (Catalogue) $project)
    Assert-True ($servers[2].url -eq 'https://mcp.example.invalid/data/mcp') 'Explicit data endpoint lost precedence'
    foreach ($url in @('file:///tmp/x', 'ftp://example.invalid/mcp', 'https://user:pass@example.invalid/mcp', 'https://example.invalid/mcp#fragment', 'not-a-url')) {
        Write-Fixture $envPath "MCP_URL_1C_DOCS_MCP=$url"
        $failed = $false
        try { $null = Resolve-ProjectMcpServers (Catalogue) $project } catch { $failed = $true }
        Assert-True $failed 'Invalid endpoint accepted'
    }
    Write-Fixture $envPath 'PLATFORM_MODE=remtoe'
    $failed = $false
    try { Get-PlatformMode $project } catch { $failed = $true }
    Assert-True $failed 'Invalid execution mode silently fell back to local'
    Write-Host 'OK  endpoints, tunnel, publication fallback, override precedence and invalid settings'

    # Real install/update/remove, including empty remote configuration. Tiny source
    # fixture keeps the test offline and avoids any global command directory.
    [void][IO.Directory]::CreateDirectory($source)
    Copy-Item -LiteralPath (Join-Path $repo 'adapters') -Destination $source -Recurse
    Copy-Item -LiteralPath $installer -Destination (Join-Path $source 'install.ps1')
    foreach ($file in @('AGENTS.md', 'USER-RULES.md', 'memory.md', 'LLM-RULES.md')) {
        Write-Fixture (Join-Path $source $file) "# $file"
    }
    Write-Fixture (Join-Path $source '.dev.env.example') "PLATFORM_MODE=local`nINFOBASE_PATH=`nUSE_EDT=false`n"
    foreach ($dir in @('rules', 'agents', 'commands', 'skills')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $source "content/$dir"))
    }
    Write-Fixture (Join-Path $source 'content/mcp-servers.json') '{"servers":[{"id":"1C-docs-mcp","transport":"http","url":"http://localhost:8003/mcp"}]}'
    Remove-Item -LiteralPath $envPath -Force
    $wrapper = Join-Path $repo 'plugins/1c-rules/scripts/invoke-install.ps1'
    $pluginLog = Join-Path $work 'plugin.log'
    & (Get-Process -Id $PID).Path -NoProfile -File $wrapper -Action init -Tool cursor `
        -PlatformMode remote -ProjectRoot $project -Source $source *> $pluginLog
    Assert-True ($LASTEXITCODE -eq 0) "Plugin init failed: $([IO.File]::ReadAllText($pluginLog))"
    Assert-True ((Read-DevEnvKeys $envPath)['PLATFORM_MODE'] -eq 'remote') 'Mode not persisted'
    $configPath = Join-Path $project '.cursor/mcp.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Assert-True (@($config.mcpServers.PSObject.Properties).Count -eq 0) 'Empty remote config leaked default services'
    Add-Content -LiteralPath $envPath -Value "`nMCP_URL_1C_DOCS_MCP=https://mcp.example.invalid/docs/mcp"
    $null = Run-Installer @('update')
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Assert-True ($config.mcpServers.'1C-docs-mcp'.url -eq 'https://mcp.example.invalid/docs/mcp') 'Endpoint not rendered'
    Assert-True ((Read-DevEnvKeys $envPath)['PLATFORM_MODE'] -eq 'remote') 'Update reset mode'
    $null = Run-Installer @('doctor')
    $null = Run-Installer @('remove')
    Assert-True (Test-Path $envPath) 'Remove deleted user settings'
    Write-Host 'OK  real init/update/doctor/remove with persisted remote mode and endpoint'
}
finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
