#Requires -RunAsAdministrator
# ===========================================================
# Otimizador Corporativo Windows 10/11  v2.2
# Compativel: Windows 10 (1903+) e Windows 11
# Execucao  : powershell.exe -ExecutionPolicy Bypass -File .\Optimize-WindowsCorporate.ps1
# ===========================================================

# SECAO 0 - POLITICA DE EXECUCAO
# Libera apenas o processo atual, sem alterar politica global da maquina.
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
} catch { }

# SECAO 1 - INICIALIZACAO
$StartTime    = Get-Date
$ComputerName = $env:COMPUTERNAME
$UserName     = $env:USERNAME
$LogPath      = "$env:SystemDrive\Logs\Optimization"
$LogFile      = "$LogPath\Optimize-$ComputerName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$ErrorCount   = 0
$SuccessCount = 0

if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

try {
    Start-Transcript -Path $LogFile -Append -Force
    Write-Host "Transcricao iniciada em: $LogFile" -ForegroundColor Cyan
} catch {
    Write-Warning "Nao foi possivel iniciar transcricao: $_"
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error','Section')]
        [string]$Level = 'Info'
    )
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Colors = @{ Info='White'; Success='Green'; Warning='Yellow'; Error='Red'; Section='Cyan' }
    $Prefix  = @{ Info='[INFO]   '; Success='[OK]     '; Warning='[AVISO]  '; Error='[ERRO]   '; Section='[SECAO]  ' }
    Write-Host "$Timestamp $($Prefix[$Level]) $Message" -ForegroundColor $Colors[$Level]
    if ($Level -eq 'Error')   { $script:ErrorCount++ }
    if ($Level -eq 'Success') { $script:SuccessCount++ }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "║      OTIMIZADOR CORPORATIVO WINDOWS 10/11  v2.2          ║" -ForegroundColor Cyan
Write-Host "║      Maquina : $($ComputerName.PadRight(43))║" -ForegroundColor White
Write-Host "║      Usuario : $($UserName.PadRight(43))║" -ForegroundColor White
Write-Host "║      Data    : $($(Get-Date -Format 'dd/MM/yyyy HH:mm').PadRight(43))║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""

$OSInfo    = Get-CimInstance Win32_OperatingSystem
$OSVersion = [System.Environment]::OSVersion.Version
Write-Log "Sistema detectado: $($OSInfo.Caption) - Build $($OSVersion.Build)" -Level Info

if ($OSVersion.Build -lt 18362) {
    Write-Log 'Requer Windows 10 versao 1903 (build 18362) ou superior.' -Level Error
    Stop-Transcript
    exit 1
}

# SECAO 2 - PONTO DE RESTAURACAO
Write-Section "PONTO DE RESTAURACAO"

try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    Checkpoint-Computer `
        -Description "Otimizacao Corporativa - $(Get-Date -Format 'dd/MM/yyyy HH:mm')" `
        -RestorePointType "MODIFY_SETTINGS" `
        -ErrorAction Stop
    Write-Log "Ponto de restauracao criado com sucesso." -Level Success
} catch {
    Write-Log "Ponto de restauracao nao criado: $_ (continuando...)" -Level Warning
}

# SECAO 3 - OTIMIZACAO DE SERVICOS
Write-Section "OTIMIZACAO DE SERVICOS"

$ServicesToDisable = @(
    @{ Name='TapiSrv';        Display='Telephony';                         Reason='Desnecessario sem modem/PSTN' },
    @{ Name='XblAuthManager'; Display='Xbox Live Auth Manager';            Reason='Nao necessario em ambiente corporativo' },
    @{ Name='XblGameSave';    Display='Xbox Live Game Save';               Reason='Nao necessario em ambiente corporativo' },
    @{ Name='XboxNetApiSvc';  Display='Xbox Live Networking Service';      Reason='Nao necessario em ambiente corporativo' },
    @{ Name='XboxGipSvc';     Display='Xbox Accessory Management Service'; Reason='Nao necessario em ambiente corporativo' },
    @{ Name='WbioSrvc';       Display='Windows Biometric Service';         Reason='Desativar se leitores biometricos nao forem usados' },
    @{ Name='SCardSvr';       Display='Smart Card';                        Reason='Desativar se cartoes inteligentes nao forem usados' },
    @{ Name='SCPolicySvc';    Display='Smart Card Removal Policy';         Reason='Complementar ao Smart Card' },
    @{ Name='Fax';            Display='Fax';                               Reason='Obsoleto na maioria dos ambientes' },
    @{ Name='RemoteRegistry'; Display='Remote Registry';                   Reason='Reduz superficie de ataque remoto' },
    @{ Name='WerSvc';         Display='Windows Error Reporting Service';   Reason='Reduz overhead; erros ainda sao logados localmente' },
    @{ Name='SysMain';        Display='SysMain (Superfetch)';              Reason='Desativado em HDD para reduzir I/O' }
)

# Detecta tipo de disco do sistema (SSD/NVMe vs HDD)
$IsSSD = $false
try {
    $SysDiskNum    = (Get-Partition | Where-Object { $_.IsSystem -or $_.IsBoot } | Select-Object -First 1).DiskNumber
    $DiskMediaType = (Get-PhysicalDisk | Where-Object DeviceId -eq $SysDiskNum).MediaType
    if ($DiskMediaType -in @('SSD', 'NVMe')) {
        $IsSSD = $true
        Write-Log "Disco do sistema: SSD/NVMe - SysMain sera mantido ativo." -Level Info
    } else {
        Write-Log "Disco do sistema: HDD - SysMain sera desativado." -Level Info
    }
} catch {
    Write-Log "Tipo de disco nao detectado. SysMain sera desativado por padrao." -Level Warning
}

foreach ($Svc in $ServicesToDisable) {
    if ($Svc.Name -eq 'SysMain' -and $IsSSD) {
        Write-Log "SysMain mantido (SSD detectado)." -Level Info
        continue
    }
    try {
        $Service = Get-Service -Name $Svc.Name -ErrorAction SilentlyContinue
        if ($null -eq $Service) {
            Write-Log "$($Svc.Display): nao encontrado nesta versao do Windows." -Level Warning
            continue
        }
        if ($Service.Status -eq 'Running') {
            Stop-Service -Name $Svc.Name -Force -ErrorAction Stop
            Write-Log "$($Svc.Display): parado." -Level Info
        }
        Set-Service -Name $Svc.Name -StartupType Disabled -ErrorAction Stop
        Write-Log "$($Svc.Display): desativado. ($($Svc.Reason))" -Level Success
    } catch {
        Write-Log "$($Svc.Display): falha ao desativar - $_" -Level Error
    }
}

# Windows Search (opcional - descomente se necessario)
<#
try {
    $WSearch = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
    if ($WSearch) {
        Stop-Service -Name 'WSearch' -Force -ErrorAction Stop
        Set-Service  -Name 'WSearch' -StartupType Disabled -ErrorAction Stop
        Write-Log "Windows Search: desativado (opcional)." -Level Success
    }
} catch {
    Write-Log "Windows Search: falha ao desativar - $_" -Level Error
}
#>

# SECAO 4 - AJUSTES DE DESEMPENHO
Write-Section "AJUSTES DE DESEMPENHO"

# 4.1 Prioridade de processos Win32
# Valor 38 (0x26): boost alto para foreground, quantum curto.
try {
    $RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
    if (Test-Path $RegPath) {
        Set-ItemProperty -Path $RegPath -Name 'Win32PrioritySeparation' -Value 38 -Type DWord -ErrorAction Stop
        Write-Log "Win32PrioritySeparation: ajustado para 38 (melhor responsividade)." -Level Success
    }
} catch {
    Write-Log "Win32PrioritySeparation: falha - $_" -Level Error
}

# 4.2 Desativar apps em segundo plano
try {
    $BgAppsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
    if (-not (Test-Path $BgAppsPath)) { New-Item -Path $BgAppsPath -Force | Out-Null }
    Set-ItemProperty -Path $BgAppsPath -Name 'GlobalUserDisabled' -Value 1 -Type DWord -ErrorAction Stop
    Write-Log "Apps em segundo plano: desativados globalmente." -Level Success
} catch {
    Write-Log "Background Apps: falha - $_" -Level Error
}

# 4.3 Efeitos visuais - melhor desempenho
# VisualFXSetting = 2: Adjust for best performance
try {
    $VisualPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    if (-not (Test-Path $VisualPath)) { New-Item -Path $VisualPath -Force | Out-Null }
    Set-ItemProperty -Path $VisualPath -Name 'VisualFXSetting' -Value 2 -Type DWord -ErrorAction Stop
    Write-Log "Efeitos visuais: ajustados para melhor desempenho." -Level Success
} catch {
    Write-Log "Efeitos visuais: falha - $_" -Level Error
}

# 4.4 Desativar animacoes de janela
try {
    $DesktopPath = 'HKCU:\Control Panel\Desktop'
    $PerfMask    = [byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)
    Set-ItemProperty -Path $DesktopPath -Name 'UserPreferencesMask' -Value $PerfMask -Type Binary -ErrorAction Stop
    Set-ItemProperty -Path $DesktopPath -Name 'MinAnimate' -Value '0' -Type String -ErrorAction Stop
    Write-Log "Animacoes de janela: desativadas." -Level Success
} catch {
    Write-Log "Animacoes: falha - $_" -Level Error
}

# 4.5 Desativar transparencia da interface
try {
    $PersonalizePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    if (-not (Test-Path $PersonalizePath)) { New-Item -Path $PersonalizePath -Force | Out-Null }
    Set-ItemProperty -Path $PersonalizePath -Name 'EnableTransparency' -Value 0 -Type DWord -ErrorAction Stop
    Write-Log "Transparencia da interface: desativada." -Level Success
} catch {
    Write-Log "Transparencia: falha - $_" -Level Error
}

# SECAO 5 - GERENCIAMENTO DE ENERGIA
Write-Section "GERENCIAMENTO DE ENERGIA"

# Detecta laptop por dois metodos:
# 1) Presenca de bateria (Win32_Battery)
# 2) ChassisType via Win32_SystemEnclosure (mais confiavel em notebooks corporativos)
$HasBattery = $false
$IsLaptop   = $false

try {
    $Battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if ($null -ne $Battery -and @($Battery).Count -gt 0) { $HasBattery = $true }
} catch { }

try {
    $Chassis = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue
    if ($null -ne $Chassis) {
        $LaptopTypes = @(9, 10, 14)
        foreach ($Type in $Chassis.ChassisTypes) {
            if ($Type -in $LaptopTypes) { $IsLaptop = $true; break }
        }
    }
} catch { }

if ($HasBattery -or $IsLaptop) {
    Write-Log "Laptop detectado - mantendo plano de energia Equilibrado." -Level Info
    try {
        powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null
        Write-Log "Plano de energia: Equilibrado ativado (laptop)." -Level Success
    } catch {
        Write-Log "Plano de energia (laptop): falha - $_" -Level Error
    }
} else {
    Write-Log "Desktop detectado - ativando plano Alto Desempenho." -Level Info
    try {
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
        Write-Log "Plano de energia: Alto Desempenho ativado (desktop)." -Level Success
    } catch {
        Write-Log "Plano de energia (desktop): falha - $_" -Level Error
    }
    try {
        powercfg /hibernate off 2>$null
        Write-Log "Hibernacao: desativada (desktop - libera espaco igual a RAM instalada)." -Level Success
    } catch {
        Write-Log "Hibernacao: falha ao desativar - $_" -Level Error
    }
}

# SECAO 6 - LIMPEZA DO SISTEMA
Write-Section "LIMPEZA DO SISTEMA"

# 6.1 Temp do Windows
try {
    $WinTemp = "$env:SystemRoot\Temp"
    if (Test-Path $WinTemp) {
        Get-ChildItem -Path $WinTemp -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Temp do Windows ($WinTemp): limpo." -Level Success
    }
} catch {
    Write-Log "Temp Windows: falha - $_" -Level Error
}

# 6.2 Temp do usuario atual
try {
    $UserTemp = $env:TEMP
    if (Test-Path $UserTemp) {
        Get-ChildItem -Path $UserTemp -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Temp do usuario ($UserTemp): limpo." -Level Success
    }
} catch {
    Write-Log "Temp usuario: falha - $_" -Level Error
}

# 6.3 Cache do Windows Update (apenas subpasta Download)
# Nao afeta historico de atualizacoes nem logs do Windows Update.
try {
    $WUCache = "$env:SystemRoot\SoftwareDistribution\Download"
    if (Test-Path $WUCache) {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Get-ChildItem -Path $WUCache -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Write-Log "Cache do Windows Update: limpo." -Level Success
    }
} catch {
    Write-Log "Cache Windows Update: falha - $_" -Level Error
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
}

# 6.4 Limpeza de disco via CleanMgr (silenciosa)
try {
    $CleanRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $Categories   = @(
        'Temporary Files',
        'Recycle Bin',
        'Temporary Internet Files',
        'Thumbnails',
        'Windows Error Reporting Files',
        'Delivery Optimization Files'
    )
    foreach ($Cat in $Categories) {
        $CatPath = "$CleanRegPath\$Cat"
        if (Test-Path $CatPath) {
            Set-ItemProperty -Path $CatPath -Name 'StateFlags0100' -Value 2 -Type DWord -ErrorAction SilentlyContinue
        }
    }
    Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:100' -Wait -WindowStyle Hidden -ErrorAction Stop
    Write-Log "Limpeza de disco (CleanMgr): concluida." -Level Success
} catch {
    Write-Log "CleanMgr: falha - $_" -Level Error
}

# SECAO 7 - OTIMIZACAO DE INICIALIZACAO
Write-Section "OTIMIZACAO DE INICIALIZACAO"

# Remove APENAS entradas listadas explicitamente.
# Preserva OneDrive corporativo, antivirus, agentes MDM, Teams, etc.
$StartupToRemove = @(
    'OneDriveSetup',
    'MicrosoftEdgeAutoLaunch_*',
    'GameBarPresenceWriter',
    'XboxGameOverlay'
)

$RunPaths = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)

foreach ($RunPath in $RunPaths) {
    if (-not (Test-Path $RunPath)) { continue }
    foreach ($Entry in $StartupToRemove) {
        try {
            $Props = Get-ItemProperty -Path $RunPath -ErrorAction SilentlyContinue
            if ($null -eq $Props) { continue }
            $MatchingNames = $Props.PSObject.Properties.Name | Where-Object { $_ -like $Entry }
            foreach ($Name in $MatchingNames) {
                Remove-ItemProperty -Path $RunPath -Name $Name -ErrorAction Stop
                Write-Log "Startup removido: '$Name' de '$RunPath'." -Level Success
            }
        } catch {
            Write-Log "Startup '$Entry': falha - $_" -Level Error
        }
    }
}

# SECAO 8 - INTERFACE, UX E NOTIFICACOES
Write-Section "INTERFACE E UX"

# 8.1 Desativar sugestoes do Windows (ContentDeliveryManager)
try {
    $CDMPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    if (-not (Test-Path $CDMPath)) { New-Item -Path $CDMPath -Force | Out-Null }
    $CDMSettings = @{
        'ContentDeliveryAllowed'          = 0
        'OemPreInstalledAppsEnabled'      = 0
        'PreInstalledAppsEnabled'         = 0
        'PreInstalledAppsEverEnabled'     = 0
        'SilentInstalledAppsEnabled'      = 0
        'SubscribedContent-310093Enabled' = 0
        'SubscribedContent-338387Enabled' = 0
        'SubscribedContent-338388Enabled' = 0
        'SubscribedContent-338389Enabled' = 0
        'SubscribedContent-338393Enabled' = 0
        'SubscribedContent-353694Enabled' = 0
        'SubscribedContent-353696Enabled' = 0
        'SystemPaneSuggestionsEnabled'    = 0
        'FeatureManagementEnabled'        = 0
    }
    foreach ($Setting in $CDMSettings.GetEnumerator()) {
        Set-ItemProperty -Path $CDMPath -Name $Setting.Key -Value $Setting.Value -Type DWord -ErrorAction Stop
    }
    Write-Log "ContentDeliveryManager: sugestoes e conteudo publicitario desativados." -Level Success
} catch {
    Write-Log "ContentDeliveryManager: falha - $_" -Level Error
}

# 8.2 Notificacoes na tela de bloqueio
try {
    $NotifPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    if (-not (Test-Path $NotifPath)) { New-Item -Path $NotifPath -Force | Out-Null }
    Set-ItemProperty -Path $NotifPath -Name 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Write-Log "Notificacoes na tela de bloqueio: desativadas." -Level Success
} catch {
    Write-Log "Notificacoes: falha - $_" -Level Error
}

# 8.3 Xbox Game Bar e Game DVR
try {
    $GameBarPath = 'HKCU:\Software\Microsoft\GameBar'
    if (-not (Test-Path $GameBarPath)) { New-Item -Path $GameBarPath -Force | Out-Null }
    Set-ItemProperty -Path $GameBarPath -Name 'UseNexusForGameBarEnabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    $GameDVRPath = 'HKCU:\System\GameConfigStore'
    if (-not (Test-Path $GameDVRPath)) { New-Item -Path $GameDVRPath -Force | Out-Null }
    Set-ItemProperty -Path $GameDVRPath -Name 'GameDVR_Enabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Write-Log "Xbox Game Bar e Game DVR: desativados." -Level Success
} catch {
    Write-Log "Xbox Game Bar: falha - $_" -Level Error
}

# SECAO 9 - DEBLOAT SEGURO
Write-Section "DEBLOAT SEGURO"

# NAO remove: Calculator, Store, Photos, Notepad, Snipping Tool, componentes do sistema.
$AppsToRemove = @(
    'Microsoft.XboxApp',
    'Microsoft.XboxGameOverlay',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.Xbox.TCUI',
    'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo',
    'Microsoft.GetHelp',
    'Microsoft.Getstarted',
    'Microsoft.People',
    'Microsoft.MixedReality.Portal',
    'Microsoft.3DBuilder',
    'Microsoft.Print3D',
    'Microsoft.BingNews',
    'Microsoft.BingWeather',
    'Microsoft.BingFinance',
    'Microsoft.BingSports',
    'Microsoft.Microsoft3DViewer',
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.GamingApp'
)

foreach ($App in $AppsToRemove) {
    try {
        $Package = Get-AppxPackage -Name $App -ErrorAction SilentlyContinue
        if ($null -ne $Package) {
            $Package | Remove-AppxPackage -ErrorAction Stop
            Write-Log "App removido: $App" -Level Success
        } else {
            Write-Log "App nao instalado (pulado): $App" -Level Info
        }
    } catch {
        Write-Log "App '$App': falha ao remover - $_" -Level Error
    }
}

# SECAO 10 - OTIMIZACAO DE REDE
Write-Section "OTIMIZACAO DE REDE"

# 10.1 TCP Auto-Tuning
# Leitura direta do registro para evitar problemas com saida localizada do netsh.
try {
    $TcpRegPath   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    $CurrentLevel = (Get-ItemProperty -Path $TcpRegPath -Name 'TcpAutoTuningLevel' -ErrorAction SilentlyContinue).TcpAutoTuningLevel
    if ($null -eq $CurrentLevel -or $CurrentLevel -ne 'normal') {
        netsh int tcp set global autotuninglevel=normal | Out-Null
        Write-Log "TCP Auto-Tuning: definido como normal." -Level Success
    } else {
        Write-Log "TCP Auto-Tuning: ja esta em normal." -Level Info
    }
} catch {
    Write-Log "TCP Auto-Tuning: falha - $_" -Level Error
}

# 10.2 RSS (Receive Side Scaling)
# Distribui processamento de pacotes entre nucleos; melhora throughput em multicore.
try {
    netsh int tcp set global rss=enabled | Out-Null
    Write-Log "RSS (Receive Side Scaling): habilitado." -Level Success
} catch {
    Write-Log "RSS: falha - $_" -Level Error
}

# 10.3 ECN (Explicit Congestion Notification)
# Desativado por compatibilidade com switches legados.
try {
    netsh int tcp set global ecncapability=disabled | Out-Null
    Write-Log "ECN Capability: desativado." -Level Info
} catch {
    Write-Log "ECN: falha - $_" -Level Error
}

# SECAO 11 - GERENCIAMENTO DE MEMORIA
Write-Section "GERENCIAMENTO DE MEMORIA"

# 11.1 Garante paginacao automatica
try {
    $CS = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if (-not $CS.AutomaticManagedPagefile) {
        $CS | Set-CimInstance -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
        Write-Log "Pagefile: restaurado para gerenciamento automatico." -Level Success
    } else {
        Write-Log "Pagefile: ja esta em modo automatico." -Level Info
    }
} catch {
    Write-Log "Pagefile: falha ao verificar - $_" -Level Error
}

# 11.2 Limpeza do pagefile no desligamento (opcional - politica de seguranca)
# Descomente se for requisito de seguranca da organizacao.
# Atencao: aumenta ligeiramente o tempo de desligamento.
<#
try {
    $MemMgmtPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Set-ItemProperty -Path $MemMgmtPath -Name 'ClearPageFileAtShutdown' -Value 1 -Type DWord -ErrorAction Stop
    Write-Log "Pagefile: configurado para ser limpo no desligamento." -Level Success
} catch {
    Write-Log "ClearPageFile: falha - $_" -Level Error
}
#>

# SECAO 12 - RELATORIO FINAL
Write-Section "RELATORIO FINAL"

$EndTime  = Get-Date
$Duration = $EndTime - $StartTime

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "║                  RESUMO DE EXECUCAO                      ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor DarkCyan
$EndTime  = Get-Date
$Duration = $EndTime - $StartTime
Write-Host "║  Maquina       : $($ComputerName.PadRight(40))║" -ForegroundColor White
Write-Host "║  Inicio        : $($(Get-Date $StartTime -Format 'dd/MM/yyyy HH:mm:ss').PadRight(40))║" -ForegroundColor White
Write-Host "║  Fim           : $($(Get-Date $EndTime   -Format 'dd/MM/yyyy HH:mm:ss').PadRight(40))║" -ForegroundColor White
Write-Host "║  Duracao       : $("$([int]$Duration.TotalMinutes)m $($Duration.Seconds)s".PadRight(40))║" -ForegroundColor White
Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor DarkCyan
Write-Host "║  [OK]  Sucessos: $($SuccessCount.ToString().PadRight(40))║" -ForegroundColor Green
Write-Host "║  [!]   Avisos  : verificar log                           ║" -ForegroundColor Yellow
Write-Host "║  [X]   Erros   : $($ErrorCount.ToString().PadRight(40))║" -ForegroundColor Red
Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor DarkCyan
Write-Host "║  Log salvo em:                                           ║" -ForegroundColor Cyan
Write-Host "║  $($LogFile.Substring(0, [Math]::Min($LogFile.Length, 56)).PadRight(56))║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""

if ($ErrorCount -gt 0) {
    Write-Host "  ! $ErrorCount erro(s) ocorreu. Revise o log para detalhes." -ForegroundColor Yellow
} else {
    Write-Host "  OK - Otimizacao concluida sem erros." -ForegroundColor Green
}

Write-Host ""
Write-Host "  Recomendacao: reinicie a maquina para aplicar todas as alteracoes." -ForegroundColor Cyan
Write-Host ""

try { Stop-Transcript } catch { }

# FIM DO SCRIPT