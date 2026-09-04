<#
.SYNOPSIS
    Instalação automatizada (silenciosa) do Spiceworks Agent (Resolve Agent)
    com site key vinculada, para monitoramento de ambiente.

.DESCRIPTION
    - Baixa o instalador .msi mais recente diretamente do repositório oficial da Spiceworks/Resolve.
    - Executa instalação silenciosa (/qn) passando a SITE_KEY do ambiente.
    - Gera log detalhado do msiexec para auditoria/troubleshooting.
    - Valida se o serviço do agente ficou em execução após a instalação.
    - Pode ser distribuído via GPO (Startup Script), Intune (Win32 App / script), SCCM,
      RMM de terceiros, ou executado manualmente com privilégios administrativos.

.NOTES
    Requer execução como Administrador (privilégios locais elevados).
    Testado com o pacote "SpiceworksAgentShell.msi" (linha atual "Resolve Agent").

.PARAMETER SiteKey
    Site key da organização no Spiceworks/Resolve. Já preenchida com o valor informado.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Deploy-SpiceworksAgent.ps1
#>

[CmdletBinding()]
param(
    [string]$SiteKey = "_5SNr5iw9EoKOlpKddtS",

    # URL oficial de download do instalador (linha "Resolve Agent" / Spiceworks Agent Shell)
    [string]$InstallerUrl = "https://download.spiceworks.com/ResolveAgent/current/SpiceworksAgentShell.msi",

    # Diretório de trabalho para download temporário e logs
    [string]$WorkDir = "$env:ProgramData\SpiceworksAgentDeploy",

    # Nome do serviço instalado pelo agente
    [string]$ServiceName = "AgentShellService"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

# 1. Preparar diretório de trabalho e log
if (-not (Test-Path $WorkDir)) {
    New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
}
$LogFile   = Join-Path $WorkDir "deploy-spiceworks-agent.log"
$MsiPath   = Join-Path $WorkDir "SpiceworksAgentShell.msi"
$MsiLog    = Join-Path $WorkDir "msiexec-install.log"

Write-Log "===== Iniciando deploy do Spiceworks Agent ====="

# 2. Checar se já está instalado (evita reinstalar/duplicar site key)
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Log "Agente já instalado (serviço '$ServiceName' encontrado). Verificando estado..."
    if ($existing.Status -ne "Running") {
        Write-Log "Serviço parado. Iniciando..."
        Start-Service -Name $ServiceName
    }
    Write-Log "Nada a fazer. Encerrando com sucesso."
    exit 0
}

# 3. Baixar o instalador MSI
try {
    Write-Log "Baixando instalador de: $InstallerUrl"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $MsiPath -UseBasicParsing
    Write-Log "Download concluído: $MsiPath"
}
catch {
    Write-Log "ERRO ao baixar o instalador: $($_.Exception.Message)"
    exit 1
}

# 4. Instalação silenciosa com a site key
$arguments = @(
    "/i", "`"$MsiPath`"",
    "SITE_KEY=`"$SiteKey`"",
    "/qn",
    "/norestart",
    "/l*v", "`"$MsiLog`""
) -join " "

Write-Log "Executando instalação silenciosa via msiexec..."
Write-Log "Comando: msiexec.exe $arguments"

$proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
$exitCode = $proc.ExitCode

$validExitCodes = @(0, 3010, 1641)
if ($validExitCodes -notcontains $exitCode) {
    Write-Log "ERRO: msiexec retornou código de saída $exitCode. Verifique o log: $MsiLog"
    exit $exitCode
}

Write-Log "Instalação concluída com código de saída $exitCode."

# 5. Validar serviço
Start-Sleep -Seconds 5
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Log "AVISO: Serviço '$ServiceName' não encontrado após instalação. Verifique o log MSI."
    exit 1
}
if ($service.Status -ne "Running") {
    Write-Log "Serviço encontrado mas não está em execução. Tentando iniciar..."
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    $service.Refresh()
}

if ($service.Status -eq "Running") {
    Write-Log "SUCESSO: Serviço '$ServiceName' em execução. Agente registrado no ambiente com a site key configurada."
    exit 0
} else {
    Write-Log "ERRO: Serviço não iniciou. Status atual: $($service.Status)."
    exit 1
}
