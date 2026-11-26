# Kit-Personal.ps1 - Kit de desempenho para PC DE CASA / GAMER.
# Abrir: duplo clique em Kit-Personal.bat (botão direito > Executar como administrador libera tudo).
# O que faz: painel de saúde com nota, Modo Jogo automático, limpeza, inicialização, teste de lag,
# monitor ao vivo (CPU/GPU) e ajustes reversíveis com ponto de restauração.
# Nunca toca em: serviços críticos, Defender, VBS/HVCI, drivers, rede (TCP). Tudo que muda tem "Desfazer".
param([switch]$SmokeTest, [string]$ShotDir)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ================= estado, config, log =================
$script:dataDir = Join-Path $env:APPDATA 'KitPersonal'
if ($SmokeTest) { $script:dataDir = Join-Path $env:TEMP 'KitPersonalTest' }
New-Item $script:dataDir -ItemType Directory -Force | Out-Null
$script:bkFile = Join-Path $script:dataDir 'backup.json'
$script:cfgFile = Join-Path $script:dataDir 'config.json'
$script:logFile = Join-Path $script:dataDir 'log.txt'
$script:isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:isDomain = [bool](Get-CimInstance Win32_ComputerSystem).PartOfDomain
$script:isLaptop = [bool](Get-CimInstance Win32_Battery)
$script:logBox = $null
$script:busy = $false
$script:junkBytes = $null
$script:lastChecks = @()

$script:cfg = @{
    games = 'cs2,csgo,valorant-win64-shipping,fortniteclient-win64-shipping,r5apex,overwatch,rocketleague,dota2,gta5,eldenring,cod'
    bg    = 'chrome,msedge,onedrive,spotify,ms-teams,teams'
    high  = $true; demote = $true; plan = $true; watch = $true
}
if (Test-Path $script:cfgFile) {
    try { (Get-Content $script:cfgFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:cfg[$_.Name] = $_.Value } } catch { }
}
function Save-Cfg { try { $script:cfg | ConvertTo-Json | Set-Content -Path $script:cfgFile -Encoding utf8 } catch { } }

function Log($m) {
    $l = "{0:HH:mm:ss}  {1}" -f (Get-Date), $m
    try { Add-Content -Path $script:logFile -Value $l -Encoding utf8 } catch { }
    if ($script:logBox) { $script:logBox.AppendText($l + "`r`n") }
    if ($SmokeTest) { Write-Host $l }
}
function Run-Op([scriptblock]$sb) {
    if ($script:busy) { return }
    $script:busy = $true
    if ($script:tabs) { $script:tabs.Enabled = $false }
    if ($script:form) { $script:form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor }
    try { & $sb } catch { Log ("Erro: " + $_.Exception.Message) }
    finally {
        $script:busy = $false
        if ($script:tabs) { $script:tabs.Enabled = $true }
        if ($script:form) { $script:form.Cursor = [System.Windows.Forms.Cursors]::Default }
    }
}
function DoEv { [System.Windows.Forms.Application]::DoEvents() }
function Get-Names($csv) { @(([string]$csv) -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { ($_.Trim().ToLower()) -replace '\.exe$', '' }) }
function MB($b) { [math]::Round($b / 1MB) }

# ---- backup de registro (para Desfazer) ----
$script:bk = @{}
if (Test-Path $script:bkFile) {
    try { (Get-Content $script:bkFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:bk[$_.Name] = $_.Value } } catch { }
}
function Save-Bk { $script:bk | ConvertTo-Json -Depth 5 | Set-Content -Path $script:bkFile -Encoding utf8 }
function Set-Reg($path, $name, $value, $type = 'DWord') {
    $key = "$path|$name"
    if (-not $script:bk.ContainsKey($key)) {
        $old = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).$name
        $script:bk[$key] = @{ existed = ($null -ne $old); value = $old; type = $type }
    }
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -Force
}

# ================= energia =================
function Get-ActivePlan {
    $o = (powercfg /getactivescheme | Out-String); $g = ''; $n = ''
    if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $g = $Matches[1] }
    if ($o -match '\(([^)]+)\)') { $n = $Matches[1] }
    [pscustomobject]@{ Guid = $g; Nome = $n }
}
function Test-HighPlan($p) { ($p.Guid -match '^(8c5e7fda|e9a42b02)') -or ($p.Nome -match 'Ultimate|ximo|Alto desempenho|High performance|Superior') }
function Get-HighPlanGuid {
    $guid = ''
    foreach ($line in (powercfg /list)) {
        if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $g = $Matches[1]
            if ($g -match '^(8c5e7fda|e9a42b02)' -or $line -match 'Ultimate|ximo|Alto desempenho|High performance|Superior') { $guid = $g; break }
        }
    }
    if (-not $guid) {
        foreach ($src in 'e9a42b02-d5df-448d-aa00-03f14749eb61', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') {
            $o = (powercfg -duplicatescheme $src 2>$null | Out-String)
            if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $guid = $Matches[1]; break }
        }
    }
    $guid
}

# ================= inicialização (ativar/desativar sem apagar nada) =================
$script:RunKeys = @(
    @{ Scope = 'Usuário'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Ap = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Admin = $false },
    @{ Scope = 'Máquina'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Ap = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Admin = $true },
    @{ Scope = 'Máquina (32 bits)'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Ap = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Admin = $true }
)
function Get-StartupState($ap, $name) {
    $v = (Get-ItemProperty -Path $ap -ErrorAction SilentlyContinue).$name
    if ($v -is [byte[]] -and $v.Length -ge 1 -and $v[0] -eq 3) { return $true }
    $false
}
function Set-StartupState($ap, $name, [bool]$disabled) {
    if (-not (Test-Path $ap)) { New-Item -Path $ap -Force | Out-Null }
    if ($disabled) { $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTime())) }
    else { $bytes = [byte[]](@(2, 0, 0, 0) + (0..7 | ForEach-Object { 0 })) }
    Set-ItemProperty -Path $ap -Name $name -Value $bytes -Type Binary -Force
}
function Get-StartupEntries {
    $list = @()
    foreach ($d in $script:RunKeys) {
        $props = Get-ItemProperty -Path $d.Path -ErrorAction SilentlyContinue
        if ($props) {
            foreach ($p in $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' }) {
                $list += [pscustomobject]@{ Nome = $p.Name; Comando = [string]$p.Value; Origem = $d.Scope; Ap = $d.Ap; Desativado = (Get-StartupState $d.Ap $p.Name); Editavel = (-not $d.Admin -or $script:isAdmin) }
            }
        }
    }
    $ap = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    $folder = [Environment]::GetFolderPath('Startup')
    foreach ($fi in (Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
        $list += [pscustomobject]@{ Nome = $fi.Name; Comando = $fi.FullName; Origem = 'Pasta Inicializar'; Ap = $ap; Desativado = (Get-StartupState $ap $fi.Name); Editavel = $true }
    }
    $list
}

# ================= verificações / nota de saúde =================
function New-Check($i, $e, $d, $t, $w = 0) { [pscustomobject]@{ Item = $i; Estado = $e; Detalhe = $d; Dica = $t; Peso = $w } }
function Get-Checks {
    $r = @()
    $os = Get-CimInstance Win32_OperatingSystem
    $mods = @(Get-CimInstance Win32_PhysicalMemory)
    $gb = [math]::Round(($mods | Measure-Object Capacity -Sum).Sum / 1GB)
    if ($gb -lt 16) { $r += New-Check 'Memória RAM' 'ALERTA' "$gb GB instalados" 'Para jogos atuais o ideal é 16 GB ou mais.' 10 }
    else { $r += New-Check 'Memória RAM' 'OK' "$gb GB instalados" '' }
    if (-not $script:isLaptop) {
        if ($mods.Count -eq 1) { $r += New-Check 'Canais de memória' 'ALERTA' '1 pente = single channel' 'Use 2 pentes iguais (ex.: 2x8 GB) em dual channel. Maior ganho em 1% low.' 20 }
        elseif ($mods.Count -ge 2) { $r += New-Check 'Canais de memória' 'OK' "$($mods.Count) pentes (confira os slots A2/B2)" '' }
        $slow = @($mods | Where-Object { $_.ConfiguredClockSpeed -and $_.Speed -and $_.ConfiguredClockSpeed -lt $_.Speed })
        if ($slow.Count -gt 0) { $r += New-Check 'Velocidade da RAM' 'ALERTA' "rodando a $($slow[0].ConfiguredClockSpeed) MHz (nominal $($slow[0].Speed) MHz)" 'Ative XMP/DOCP na BIOS.' 15 }
        elseif ($mods.Count -gt 0) { $r += New-Check 'Velocidade da RAM' 'OK' "$($mods[0].ConfiguredClockSpeed) MHz" '' }
    }
    $p = Get-ActivePlan
    if (Test-HighPlan $p) { $r += New-Check 'Plano de energia' 'OK' $p.Nome '' } else { $r += New-Check 'Plano de energia' 'ALERTA' "$($p.Nome)" 'Use Alto/Máximo desempenho para jogar (aba Otimizar).' 8 }
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual' } | Select-Object -First 1
    if ($gpu) {
        $age = [int]((Get-Date) - $gpu.DriverDate).TotalDays
        $dv = $gpu.DriverVersion; $d = ($dv -replace '\.', '')
        if ($gpu.Name -match 'NVIDIA' -and $d.Length -ge 5) { $x = $d.Substring($d.Length - 5); $dv = "$($x.Substring(0,3)).$($x.Substring(3))" }
        if ($age -gt 200) { $r += New-Check 'Driver de vídeo' 'ALERTA' "$($gpu.Name) - driver $dv ($age dias)" 'Instale o driver mais novo com instalação limpa (aba Driver de vídeo).' 8 }
        else { $r += New-Check 'Driver de vídeo' 'OK' "$($gpu.Name) - driver $dv ($age dias)" '' }
    }
    $c = Get-Volume -DriveLetter $env:SystemDrive[0]
    if ($c -and $c.Size) {
        $pct = [math]::Round($c.SizeRemaining / $c.Size * 100)
        if ($pct -lt 15) { $r += New-Check 'Espaço no disco C:' 'ALERTA' "$pct% livre ($([math]::Round($c.SizeRemaining/1GB)) GB)" 'SSD cheio fica lento. Libere espaço (aba Limpeza).' 10 }
        else { $r += New-Check 'Espaço no disco C:' 'OK' "$pct% livre ($([math]::Round($c.SizeRemaining/1GB)) GB)" '' }
    }
    $hdd = @(Get-PhysicalDisk | Where-Object { $_.MediaType -eq 'HDD' })
    if ($hdd.Count -gt 0) { $r += New-Check 'Tipo de disco' 'INFO' "HDD detectado: $($hdd[0].FriendlyName)" 'Instale o jogo e o Windows em SSD.' }
    $bad = @(Get-PhysicalDisk | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne 'Healthy' })
    if ($bad.Count -gt 0) { $r += New-Check 'Saúde dos discos' 'ALERTA' "$($bad[0].FriendlyName): $($bad[0].HealthStatus)" 'Faça backup e troque o disco.' 20 }
    $up = (Get-Date) - $os.LastBootUpTime
    if ($up.TotalDays -gt 7) { $r += New-Check 'Tempo ligado' 'ALERTA' ("{0} dias sem reiniciar" -f [int]$up.TotalDays) 'Reinicie: libera memória e conclui atualizações.' 5 }
    else { $r += New-Check 'Tempo ligado' 'OK' ("{0:N1} dias" -f $up.TotalDays) '' }
    $st = @(Get-StartupEntries | Where-Object { -not $_.Desativado })
    if ($st.Count -gt 8) { $r += New-Check 'Inicialização' 'ALERTA' "$($st.Count) programas abrem com o Windows" 'Desative o que não usa (aba Inicialização).' 8 }
    else { $r += New-Check 'Inicialização' 'OK' "$($st.Count) programas" '' }
    $pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    if ($pend) { $r += New-Check 'Reinício pendente' 'ALERTA' 'Windows aguarda reinício' 'Reinicie o PC.' 4 }
    $dvr = (Get-ItemProperty 'HKCU:\System\GameConfigStore').GameDVR_Enabled
    if ($dvr -eq 0) { $r += New-Check 'Gravação em 2º plano (Game DVR)' 'OK' 'Desligada' '' } else { $r += New-Check 'Gravação em 2º plano (Game DVR)' 'ALERTA' 'Ligada' 'Consome GPU/CPU. Desligue na aba Otimizar.' 5 }
    $ms = (Get-ItemProperty 'HKCU:\Control Panel\Mouse').MouseSpeed
    if ("$ms" -eq '0') { $r += New-Check 'Aceleração do mouse' 'OK' 'Desligada' '' } else { $r += New-Check 'Aceleração do mouse' 'ALERTA' 'Ligada' 'Atrapalha a mira. Desligue na aba Otimizar.' 3 }
    if ($null -ne $script:junkBytes) {
        if ($script:junkBytes -gt 2GB) { $r += New-Check 'Lixo acumulado' 'ALERTA' "$(MB $script:junkBytes) MB recuperáveis" 'Rode a limpeza.' 4 }
        else { $r += New-Check 'Lixo acumulado' 'OK' "$(MB $script:junkBytes) MB" '' }
    }
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard
    if ($dg.VirtualizationBasedSecurityStatus -eq 2) { $r += New-Check 'VBS / Integridade de memória' 'INFO' 'Ligada' 'Protege contra malware, mas pode custar 3-10% de FPS. Decisão sua; não mexemos.' }
    $hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers').HwSchMode
    if ($hags) { $r += New-Check 'HAGS (agendamento de GPU)' 'INFO' $(if ($hags -eq 2) { 'Ligado' } else { 'Desligado' }) 'Teste os dois estados medindo o 1% low.' }
    $heavy = @(Get-Process -Name chrome, msedge -ErrorAction SilentlyContinue)
    if ($heavy.Count -gt 0) { $r += New-Check 'Navegador aberto' 'INFO' "$($heavy.Count) processos usando $(MB (($heavy | Measure-Object WorkingSet64 -Sum).Sum)) MB" 'Feche antes de jogar (ou use o Modo Jogo).' }
    $r
}
function Get-Score($checks) {
    $s = 100; foreach ($c in $checks) { if ($c.Estado -eq 'ALERTA') { $s -= $c.Peso } }
    [math]::Max(0, $s)
}
function Update-Painel {
    $script:lastChecks = @(Get-Checks)
    $script:lvCheck.Items.Clear()
    foreach ($c in $script:lastChecks) {
        $it = New-Object System.Windows.Forms.ListViewItem($c.Estado)
        [void]$it.SubItems.Add($c.Item); [void]$it.SubItems.Add($c.Detalhe); [void]$it.SubItems.Add($c.Dica)
        if ($c.Estado -eq 'ALERTA') { $it.BackColor = [System.Drawing.Color]::FromArgb(255, 235, 205) }
        elseif ($c.Estado -eq 'OK') { $it.BackColor = [System.Drawing.Color]::FromArgb(222, 245, 222) }
        else { $it.BackColor = [System.Drawing.Color]::FromArgb(230, 238, 250) }
        [void]$script:lvCheck.Items.Add($it)
    }
    $sc = Get-Score $script:lastChecks
    $script:lblScore.Text = "$sc"
    $script:lblScore.ForeColor = if ($sc -ge 80) { [System.Drawing.Color]::LightGreen } elseif ($sc -ge 60) { [System.Drawing.Color]::Orange } else { [System.Drawing.Color]::Tomato }
    $n = @($script:lastChecks | Where-Object { $_.Estado -eq 'ALERTA' }).Count
    Log "Verificação concluída: nota $sc/100, $n ponto(s) de atenção."
    Update-Header
}

# ================= limpeza =================
$script:cats = @(
    @{ Nome = 'Temporários do usuário (> 3 dias)'; Paths = @($env:TEMP); Dias = 3 },
    @{ Nome = 'Temporários do Windows (admin)'; Paths = @("$env:SystemRoot\Temp"); Dias = 3; Admin = $true },
    @{ Nome = 'Relatórios de erro e dumps de falha'; Paths = @("$env:LOCALAPPDATA\Microsoft\Windows\WER", "$env:LOCALAPPDATA\CrashDumps"); Dias = 3 },
    @{ Nome = 'Cache de miniaturas'; Paths = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer"); Dias = 3; Filtro = 'thumbcache*' },
    @{ Nome = 'Cache do Edge (feche o Edge)'; Paths = @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache", "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"); Dias = 0 },
    @{ Nome = 'Cache do Chrome (feche o Chrome)'; Paths = @("$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache", "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"); Dias = 0 },
    @{ Nome = 'Cache do Discord'; Paths = @("$env:APPDATA\discord\Cache", "$env:APPDATA\discord\Code Cache", "$env:APPDATA\discord\GPUCache"); Dias = 0 },
    @{ Nome = 'Cache web da Steam'; Paths = @("$env:LOCALAPPDATA\Steam\htmlcache"); Dias = 0 },
    @{ Nome = 'Cache do Epic Games Launcher'; Paths = @("$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache*"); Dias = 0 },
    @{ Nome = 'Cache do Firefox (feche o Firefox)'; Paths = @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2"); Dias = 0 },
    @{ Nome = 'Dumps de memória do Windows - Minidump (admin)'; Paths = @("$env:SystemRoot\Minidump"); Dias = 0; Admin = $true },
    @{ Nome = 'Dump de memória completo MEMORY.DMP (admin)'; Paths = @("$env:SystemRoot"); Filtro = 'MEMORY.DMP'; NoRecurse = $true; Dias = 0; Admin = $true },
    @{ Nome = 'Instaladores antigos da NVIDIA (admin)'; Paths = @("$env:SystemDrive\NVIDIA"); Dias = 0; Admin = $true },
    @{ Nome = 'Cache do Windows Update (admin)'; Paths = @("$env:SystemRoot\SoftwareDistribution\Download"); Dias = 0; Admin = $true; Servico = 'wuauserv' },
    @{ Nome = 'Otimização de entrega (admin)'; Paths = @("$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"); Dias = 0; Admin = $true; Servico = 'dosvc' },
    @{ Nome = 'Lixeira'; Tipo = 'lixeira' }
)
function Get-CatFiles($c) {
    $lim = (Get-Date).AddDays(-[int]$c.Dias)
    foreach ($p in $c.Paths) {
        if (Test-Path $p) {
            $a = @{ Path = $p; Force = $true; File = $true; ErrorAction = 'SilentlyContinue' }
            if (-not $c.NoRecurse) { $a.Recurse = $true }
            if ($c.Filtro) { $a.Filter = $c.Filtro }
            Get-ChildItem @a | Where-Object { $_.LastWriteTime -lt $lim }
        }
    }
}
function Get-CatSize($c) {
    if ($c.Tipo -eq 'lixeira') { $s = 0; try { (New-Object -ComObject Shell.Application).NameSpace(0xA).Items() | ForEach-Object { $s += $_.Size } } catch { }; return $s }
    $s = (Get-CatFiles $c | Measure-Object Length -Sum).Sum
    if ($s) { return [long]$s } else { return 0 }
}
function Invoke-Analisar {
    $script:lstClean.Items.Clear(); $tot = 0
    foreach ($c in $script:cats) {
        $sz = Get-CatSize $c; $c.Tam = $sz
        $blocked = ($c.Admin -and -not $script:isAdmin)
        if (-not $blocked) { $tot += $sz }
        $txt = "{0}  -  {1} MB{2}" -f $c.Nome, (MB $sz), $(if ($blocked) { '  [precisa de administrador]' } else { '' })
        [void]$script:lstClean.Items.Add($txt, ($sz -gt 0 -and -not $blocked))
        DoEv
    }
    $script:junkBytes = $tot
    $script:lblClean.Text = "Total recuperável: $(MB $tot) MB"
    Log "Análise de lixo: $(MB $tot) MB recuperáveis."
}
function Remove-Cat($c) {
    if ($c.Tipo -eq 'lixeira') { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; return }
    if ($c.Servico) { Stop-Service -Name $c.Servico -Force -ErrorAction SilentlyContinue }
    Get-CatFiles $c | Remove-Item -Force -ErrorAction SilentlyContinue
    if ($c.Servico) { Start-Service -Name $c.Servico -ErrorAction SilentlyContinue }
}
function Invoke-Limpar {
    $lib = 0
    foreach ($idx in @($script:lstClean.CheckedIndices)) {
        $c = $script:cats[$idx]
        if ($c.Admin -and -not $script:isAdmin) { continue }
        Remove-Cat $c; $lib += $c.Tam; Log "Limpo: $($c.Nome)"; DoEv
    }
    Log "Limpeza concluída (~$(MB $lib) MB). Arquivos em uso são ignorados."
    Invoke-Analisar
}

# ================= inicialização (UI) =================
function Update-Startup {
    $script:lvStart.Items.Clear(); $script:startData = @(Get-StartupEntries)
    foreach ($e in $script:startData) {
        $it = New-Object System.Windows.Forms.ListViewItem($(if ($e.Desativado) { 'Desativado' } else { 'Ativo' }))
        [void]$it.SubItems.Add($e.Nome); [void]$it.SubItems.Add($e.Origem); [void]$it.SubItems.Add($e.Comando)
        if ($e.Desativado) { $it.ForeColor = [System.Drawing.Color]::Gray }
        [void]$script:lvStart.Items.Add($it)
    }
}
function Switch-Startup([bool]$disable) {
    if ($script:lvStart.SelectedIndices.Count -eq 0) { return }
    $e = $script:startData[$script:lvStart.SelectedIndices[0]]
    if (-not $e.Editavel) { Log "'$($e.Nome)' é da máquina: abra o programa como administrador."; return }
    Set-StartupState $e.Ap $e.Nome $disable
    Log "$(if ($disable) { 'Desativado' } else { 'Reativado' }) na inicialização: $($e.Nome)"
    Update-Startup
}

# ================= modo jogo =================
$script:boost = @{}; $script:gameOn = $false; $script:gameName = ''; $script:prevPlan = $null
function Get-RunningGames { $n = Get-Names $script:cfg.games; @(Get-Process | Where-Object { $n -contains $_.ProcessName.ToLower() }) }
function Apply-Demote($gameIds) {
    $c = 0
    foreach ($n in (Get-Names $script:cfg.bg)) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            if (($gameIds -notcontains $p.Id) -and (-not $script:boost.ContainsKey("$($p.Id)"))) {
                try { $old = [string]$p.PriorityClass; $p.PriorityClass = 'BelowNormal'; $script:boost["$($p.Id)"] = $old; $c++ } catch { }
            }
        }
    }
    $c
}
function Start-Boost($games) {
    $script:gameOn = $true; $script:gameName = $games[0].ProcessName
    if ($script:cfg.high) { foreach ($g in $games) { try { $script:boost["$($g.Id)"] = [string]$g.PriorityClass; $g.PriorityClass = 'High' } catch { } } }
    $dem = 0; if ($script:cfg.demote) { $dem = Apply-Demote @($games | ForEach-Object { $_.Id }) }
    if ($script:cfg.plan) {
        $cur = Get-ActivePlan
        if (-not (Test-HighPlan $cur)) { $hp = Get-HighPlanGuid; if ($hp) { $script:prevPlan = $cur.Guid; powercfg /setactive $hp | Out-Null } }
    }
    Log "MODO JOGO ligado: $($script:gameName) em prioridade alta; $dem app(s) de fundo rebaixados."
    if ($script:lblGame) { $script:lblGame.Text = "JOGO ATIVO: $($script:gameName)"; $script:lblGame.ForeColor = [System.Drawing.Color]::Green }
}
function Stop-Boost {
    foreach ($k in @($script:boost.Keys)) {
        try { $p = Get-Process -Id ([int]$k) -ErrorAction Stop; $p.PriorityClass = $script:boost[$k] } catch { }
    }
    $script:boost = @{}
    if ($script:prevPlan) { powercfg /setactive $script:prevPlan | Out-Null; $script:prevPlan = $null }
    if ($script:gameOn) { Log 'MODO JOGO desligado: prioridades e plano de energia restaurados.' }
    $script:gameOn = $false; $script:gameName = ''
    if ($script:lblGame) { $script:lblGame.Text = 'Aguardando um jogo abrir...'; $script:lblGame.ForeColor = [System.Drawing.Color]::DimGray }
}
function Update-Game {
    $g = Get-RunningGames
    if ($g.Count -gt 0 -and -not $script:gameOn) { Start-Boost $g }
    elseif ($g.Count -eq 0 -and $script:gameOn) { Stop-Boost }
    elseif ($g.Count -gt 0 -and $script:gameOn -and $script:cfg.demote) { [void](Apply-Demote @($g | ForEach-Object { $_.Id })) }
}

# ================= rede / lag =================
function Test-Latencia($target, $n = 20) {
    $p = New-Object System.Net.NetworkInformation.Ping; $rt = @(); $lost = 0
    for ($i = 0; $i -lt $n; $i++) {
        try { $r = $p.Send($target, 1000); if ($r.Status -eq 'Success') { $rt += [double]$r.RoundtripTime } else { $lost++ } } catch { $lost++ }
        DoEv; Start-Sleep -Milliseconds 150
    }
    $jit = 0
    if ($rt.Count -gt 1) { $d = @(); for ($i = 1; $i -lt $rt.Count; $i++) { $d += [math]::Abs($rt[$i] - $rt[$i - 1]) }; $jit = ($d | Measure-Object -Average).Average }
    [pscustomobject]@{ Alvo = $target; Enviados = $n; Perdidos = $lost; Min = $(if ($rt.Count) { ($rt | Measure-Object -Minimum).Minimum } else { 0 }); Media = $(if ($rt.Count) { [math]::Round(($rt | Measure-Object -Average).Average, 1) } else { 0 }); Max = $(if ($rt.Count) { ($rt | Measure-Object -Maximum).Maximum } else { 0 }); Jitter = [math]::Round($jit, 1) }
}
function Invoke-Rede {
    $t = $script:txtHost.Text.Trim(); if (-not $t) { $t = '1.1.1.1' }
    $n = [int]$script:numPing.Value
    $script:txtNet.Text = "Testando $t ($n pacotes)...`r`n"
    $ad = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    $tipo = ''
    foreach ($a in $ad) { $tipo += "  - $($a.Name) ($($a.InterfaceDescription)) $($a.LinkSpeed)`r`n" }
    $r = Test-Latencia $t $n
    $v = 'Conexão boa para jogar.'
    if ($r.Enviados -eq $r.Perdidos) { $v = 'Sem resposta. O alvo pode bloquear ping ou você está sem internet.' }
    elseif ($r.Perdidos -gt 0 -or $r.Jitter -gt 10) { $v = 'Conexão INSTÁVEL (perda ou jitter alto): prefira cabo, feche downloads/streaming e teste o roteador.' }
    elseif ($r.Media -gt 60) { $v = 'Latência alta. Troque de servidor/região ou verifique a operadora.' }
    $wifi = [bool]($ad | Where-Object { $_.PhysicalMediaType -match '802.11|Native 802.11' -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless' })
    $extra = ''; if ($wifi) { $extra = "`r`nDica: você está em Wi-Fi. Cabo de rede reduz jitter e travadas no jogo online." }
    $script:txtNet.Text = "Alvo: $($r.Alvo)`r`nEnviados: $($r.Enviados)   Perdidos: $($r.Perdidos)`r`nMín: $($r.Min) ms   Média: $($r.Media) ms   Máx: $($r.Max) ms   Jitter: $($r.Jitter) ms`r`n`r`nAdaptadores ativos:`r`n$tipo`r`nVeredito: $v$extra"
    Log "Teste de rede $t : média $($r.Media) ms, jitter $($r.Jitter) ms, perda $($r.Perdidos)/$($r.Enviados)."
}

# ================= monitor ao vivo =================
$script:peak = @{}
$script:nvsmi = $null
foreach ($c in @("$env:SystemRoot\System32\nvidia-smi.exe", "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe")) { if (Test-Path $c) { $script:nvsmi = $c; break } }
function Set-Mon($row, $now, $peakVal, [bool]$max = $true) {
    $it = $script:lvMon.Items[$row]; $it.SubItems[1].Text = [string]$now
    if ($null -ne $peakVal) {
        $k = "$row"
        if (-not $script:peak.ContainsKey($k)) { $script:peak[$k] = $peakVal }
        elseif ($max -and $peakVal -gt $script:peak[$k]) { $script:peak[$k] = $peakVal }
        elseif ((-not $max) -and $peakVal -lt $script:peak[$k]) { $script:peak[$k] = $peakVal }
        $it.SubItems[2].Text = [string]$script:peak[$k]
    }
}
function Update-Monitor {
    $os = Get-CimInstance Win32_OperatingSystem
    $ramPct = [math]::Round(100 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100)
    $pi = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"
    $util = $null; $perf = $null
    if ($pi) { $util = [int]$pi.PercentProcessorUtility; $perf = [int]$pi.PercentProcessorPerformance }
    else { $pr = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"; if ($pr) { $util = [int]$pr.PercentProcessorTime } }
    $dk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
    if ($null -ne $util) { Set-Mon 0 "$util %" $util } else { Set-Mon 0 'n/d' $null }
    if ($null -ne $perf) { Set-Mon 1 "$perf %" $perf $false } else { Set-Mon 1 'n/d' $null }
    Set-Mon 2 "$ramPct %" $ramPct
    if ($dk) { Set-Mon 3 "$([int]$dk.PercentDiskTime) %" ([int]$dk.PercentDiskTime) }
    $verd = 'CPU e clock normais.'
    if ($script:nvsmi) {
        $o = (& $script:nvsmi --query-gpu=utilization.gpu,temperature.gpu,clocks.gr,power.draw,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
        if ($o) {
            $v = @($o -split ',' | ForEach-Object { $_.Trim() })
            if ($v.Count -ge 6) {
                Set-Mon 4 "$($v[0]) %" ([int]$v[0]); Set-Mon 5 "$($v[1]) °C" ([int]$v[1]); Set-Mon 6 "$($v[2]) MHz" ([int]$v[2])
                Set-Mon 7 "$($v[3]) W" ([double]$v[3]); Set-Mon 8 "$($v[4]) / $($v[5]) MB" ([int]$v[4])
                if ([int]$v[1] -ge 83) { $verd = 'GPU muito quente (>= 83 °C): limpe poeira e melhore o fluxo de ar.' }
            }
        }
    } else { foreach ($i in 4..8) { Set-Mon $i 'sem nvidia-smi' $null } }
    if ($null -ne $util -and $null -ne $perf -and $util -ge 70 -and $perf -lt 60) { $verd = 'ATENÇÃO: CPU carregada mas com clock baixo = possível limite térmico/de energia (cooler, pasta, PL1/PL2).' }
    $script:lblMon.Text = "Diagnóstico ao vivo: $verd"
}

# ================= otimizações reversíveis =================
function Invoke-Otimizar([bool]$power, [bool]$game, [bool]$mouse, [bool]$tips, [bool]$transp) {
    if ($script:isDomain) { Log 'Este PC está no domínio (empresa): ajustes bloqueados. Use o Kit Business.'; return }
    if ($script:isAdmin) {
        try { Enable-ComputerRestore -Drive "$env:SystemDrive\"; Checkpoint-Computer -Description 'Kit Personal' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Log 'Ponto de restauração criado.' }
        catch { Log 'Aviso: ponto de restauração não criado (já existe um nas últimas 24h ou está desativado).' }
    }
    if ($power) {
        if (-not $script:bk.ContainsKey('powerplan')) { $cur = Get-ActivePlan; if ($cur.Guid) { $script:bk['powerplan'] = $cur.Guid } }
        $hp = Get-HighPlanGuid
        if ($hp) { powercfg /setactive $hp | Out-Null; Log 'Plano de energia: alto desempenho.' } else { Log 'Não consegui obter um plano de alto desempenho.' }
    }
    if ($game) {
        Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
        Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
        Log 'Game Mode ligado; gravação em segundo plano desligada.'
    }
    if ($mouse) {
        Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
        Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
        Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
        Log 'Aceleração do mouse desligada (vale após novo logon).'
    }
    if ($tips) {
        $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        foreach ($n in 'SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-310093Enabled', 'SoftLandingEnabled') { Set-Reg $k $n 0 }
        Log 'Sugestões, dicas e anúncios do Windows desligados.'
    }
    if ($transp) { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0; Log 'Efeitos de transparência desligados.' }
    Save-Bk
    Log 'Ajustes aplicados. Reinicie ou refaça o logon para valerem 100%.'
}
function Invoke-Desfazer {
    foreach ($k in @($script:bk.Keys)) {
        if ($k -eq 'powerplan') { powercfg /setactive $script:bk[$k] | Out-Null; Log 'Plano de energia restaurado.'; continue }
        $path, $name = $k -split '\|', 2; $e = $script:bk[$k]
        if ($e.existed) { Set-ItemProperty -Path $path -Name $name -Value $e.value -Type $e.type -Force } else { Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue }
    }
    $n = $script:bk.Count
    $script:bk = @{}; if (Test-Path $script:bkFile) { Remove-Item $script:bkFile -Force }
    Log "Desfeito: $n ajuste(s) revertidos ao estado original."
}
function Invoke-Tudo {
    $msg = "Vai executar:`n - ponto de restauração (se admin)`n - ajustes de jogo/mouse/dicas (reversíveis)`n - limpeza dos itens marcados na aba Limpeza`n`nContinuar?"
    if ($script:isDomain) { $msg = "PC no domínio: só a limpeza será executada (ajustes bloqueados).`n`nContinuar?" }
    if ([System.Windows.Forms.MessageBox]::Show($msg, 'Otimizar tudo', 'YesNo', 'Question') -ne 'Yes') { return }
    Invoke-Otimizar $true $true $true $true $false
    Invoke-Analisar; Invoke-Limpar
    Update-Painel
    Log 'OTIMIZAÇÃO COMPLETA concluída.'
}

# ================= driver de vídeo (instalação limpa / DDU) =================
$script:vendors = @{
    NVIDIA = @{ Url = 'https://www.nvidia.com/Download/index.aspx'; Signer = 'NVIDIA' }
    AMD    = @{ Url = 'https://www.amd.com/en/support/download/drivers.html'; Signer = 'Advanced Micro Devices' }
    Intel  = @{ Url = 'https://www.intel.com/content/www/us/en/download-center/home.html'; Signer = 'Intel' }
}
function Get-VendorKey($fab, $nome) {
    $t = "$fab $nome"
    if ($t -match 'NVIDIA') { return 'NVIDIA' }
    if ($t -match 'Advanced Micro|AMD|Radeon') { return 'AMD' }
    if ($t -match 'Intel') { return 'Intel' }
    ''
}
function Get-DisplayDrivers {
    @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceName -notmatch 'Basic|Remote|Virtual' } | ForEach-Object {
            $dv = [string]$_.DriverVersion; $d = ($dv -replace '\.', ''); $ver = $dv
            if ($_.Manufacturer -match 'NVIDIA' -and $d.Length -ge 5) { $x = $d.Substring($d.Length - 5); $ver = "$($x.Substring(0,3)).$($x.Substring(3))" }
            $age = -1; if ($_.DriverDate) { $age = [int]((Get-Date) - $_.DriverDate).TotalDays }
            [pscustomobject]@{ Nome = [string]$_.DeviceName; Fabricante = [string]$_.Manufacturer; Versao = $ver; Data = $_.DriverDate; Idade = $age; Inf = [string]$_.InfName; Vendor = (Get-VendorKey $_.Manufacturer $_.DeviceName) }
        })
}
function Test-DriverInstaller($path, $vendorKey) {
    $sig = Get-AuthenticodeSignature -FilePath $path
    $subj = ''; if ($sig.SignerCertificate) { $subj = [string]$sig.SignerCertificate.Subject }
    $regexes = @(); if ($vendorKey -and $script:vendors.ContainsKey($vendorKey)) { $regexes = @($script:vendors[$vendorKey].Signer) } else { $regexes = @($script:vendors.Values | ForEach-Object { $_.Signer }) }
    $match = $false; foreach ($rx in $regexes) { if ($subj -match [regex]::Escape($rx)) { $match = $true } }
    [pscustomobject]@{ Valido = ($sig.Status -eq 'Valid'); Status = [string]$sig.Status; Assinante = $subj; Fabricante = $match; OK = (($sig.Status -eq 'Valid') -and $match) }
}
function Update-Driver {
    $script:lvDrv.Items.Clear(); $script:drivers = @(Get-DisplayDrivers)
    foreach ($d in $script:drivers) {
        $it = New-Object System.Windows.Forms.ListViewItem($d.Nome)
        [void]$it.SubItems.Add($d.Fabricante); [void]$it.SubItems.Add($d.Versao)
        [void]$it.SubItems.Add($(if ($d.Data) { $d.Data.ToString('yyyy-MM-dd') } else { '-' })); [void]$it.SubItems.Add($(if ($d.Idade -ge 0) { "$($d.Idade) dias" } else { '-' })); [void]$it.SubItems.Add($d.Inf)
        if ($d.Idade -gt 200) { $it.BackColor = [System.Drawing.Color]::FromArgb(255, 235, 205) }
        [void]$script:lvDrv.Items.Add($it)
    }
    if ($script:lvDrv.Items.Count -gt 0) { $script:lvDrv.Items[0].Selected = $true }
}
function Get-SelDriver { if ($script:drivers.Count -eq 0) { return $null }; if ($script:lvDrv.SelectedIndices.Count -gt 0) { return $script:drivers[$script:lvDrv.SelectedIndices[0]] }; $script:drivers[0] }
function Open-Fabricante {
    $d = Get-SelDriver; $k = ''; if ($d) { $k = $d.Vendor }
    if (-not $k) { $k = 'NVIDIA' }
    Start-Process $script:vendors[$k].Url; Log "Aberta a página oficial de drivers ($k). Baixe somente de lá."
}
function Backup-Driver {
    if (-not $script:isAdmin) { Log 'Backup do driver precisa de administrador (use "Reabrir como administrador").'; return $null }
    $docs = [Environment]::GetFolderPath('MyDocuments'); if (-not $docs) { $docs = $script:dataDir }
    $dest = Join-Path $docs ('KitPersonal\BackupDriver\' + (Get-Date -Format 'yyyyMMdd_HHmm'))
    New-Item $dest -ItemType Directory -Force | Out-Null
    foreach ($d in $script:drivers) { if ($d.Inf) { $o = (pnputil.exe /export-driver $d.Inf $dest | Out-String); if ($o -match 'rro|rror|ail') { Log "pnputil: $($o.Trim())" } } }
    $n = @(Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue).Count
    if ($n -gt 0) { Log "Backup do driver atual salvo em: $dest ($n arquivos). Para voltar: Gerenciador de Dispositivos > Atualizar driver > Procurar nesta pasta." } else { Log 'Backup não gerou arquivos (driver pode ser genérico do Windows).' }
    $dest
}
$script:guiaDriver = @"
INSTALAÇÃO LIMPA DO DRIVER - passo a passo

NÍVEL 1 (suficiente para a maioria dos casos - recomendado):
  1. Botão "Site do fabricante": baixe o driver mais novo da sua placa (somente do site oficial).
  2. Botão "Backup do driver atual" (admin): guarda o driver que funciona, para poder voltar.
  3. Botão "Instalar driver baixado": o programa confere a assinatura digital e abre o instalador.
  4. No instalador NVIDIA: "Instalação personalizada" > marque "Executar uma instalação limpa" > instalar.
  5. Reinicie. Depois reabra a aba Painel e confira a nota.

NÍVEL 2 (DDU - só se o driver estiver com problema: travadas, tela preta, erros de instalação):
  1. Baixe o instalador do driver novo E o DDU (botão "Site oficial do DDU"). Guarde em uma pasta fácil.
  2. Desconecte o cabo de rede / Wi-Fi (senão o Windows Update instala um driver genérico por cima).
  3. Faça o backup do driver (acima).
  4. Botão "Reiniciar em Modo Seguro": no menu azul escolha Solução de problemas > Opções avançadas >
     Configurações de inicialização > Reiniciar > tecla 4 (Modo Seguro).
  5. No Modo Seguro abra o DDU, escolha o tipo GPU e o fabricante e clique "Limpar e reiniciar".
  6. De volta ao Windows (ainda sem internet), instale o driver baixado com instalação limpa.
  7. Reconecte a internet e reinicie.

DEPOIS DE INSTALAR (CS2): no Painel de Controle NVIDIA > Gerenciar configurações 3D > "Modo de gerenciamento
de energia: Preferir desempenho máximo"; no jogo, ative o NVIDIA Reflex. Não apague o cache de shaders.

Se algo der errado: Gerenciador de Dispositivos > Adaptadores de vídeo > Atualizar driver > Procurar > pasta do backup.
"@
function Invoke-InstalarDriver {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog; $dlg.Title = 'Escolha o instalador de driver que você baixou'; $dlg.Filter = 'Instalador (*.exe)|*.exe'
    $dir = Join-Path $env:USERPROFILE 'Downloads'; if (Test-Path $dir) { $dlg.InitialDirectory = $dir }
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $d = Get-SelDriver; $k = ''; if ($d) { $k = $d.Vendor }
    $r = Test-DriverInstaller $dlg.FileName $k
    if (-not $r.OK) {
        $why = if (-not $r.Valido) { "assinatura digital INVÁLIDA ou ausente ($($r.Status))" } else { "assinado por outra empresa: $($r.Assinante)" }
        Log "Instalador recusado: $why"
        [void][System.Windows.Forms.MessageBox]::Show("Não vou abrir este arquivo:`n$why`n`nBaixe o driver apenas do site oficial do fabricante.", 'Instalador não confiável', 'OK', 'Warning'); return
    }
    $msg = "Assinatura digital VÁLIDA.`nAssinante: $($r.Assinante)`n`nNo instalador escolha 'Instalação personalizada' e marque 'Executar uma instalação limpa'.`nA tela pode piscar durante a instalação.`n`nAbrir o instalador agora?"
    if ([System.Windows.Forms.MessageBox]::Show($msg, 'Instalar driver', 'YesNo', 'Question') -ne 'Yes') { return }
    if ($script:isAdmin) { try { Enable-ComputerRestore -Drive "$env:SystemDrive\"; Checkpoint-Computer -Description 'Kit Personal - driver' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Log 'Ponto de restauração criado.' } catch { Log 'Ponto de restauração não criado (já existe um nas últimas 24h ou está desativado).' } }
    Start-Process -FilePath $dlg.FileName; Log "Instalador aberto: $($dlg.FileName)"
}
function Invoke-AbrirDDU {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog; $dlg.Title = 'Escolha o "Display Driver Uninstaller.exe" que você baixou'; $dlg.Filter = 'DDU (*.exe)|*.exe'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    if ((Split-Path $dlg.FileName -Leaf) -notmatch 'Display Driver Uninstaller|DDU') { [void][System.Windows.Forms.MessageBox]::Show('O arquivo não parece ser o DDU. Baixe somente do site oficial (wagnardsoft.com).', 'Kit Personal'); return }
    $sig = Get-AuthenticodeSignature -FilePath $dlg.FileName
    $info = "Assinatura: $($sig.Status)`nAssinante: $(if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(nenhum)' })"
    $safe = [bool](Get-CimInstance Win32_ComputerSystem).BootupState -and ((Get-CimInstance Win32_ComputerSystem).BootupState -ne 'Normal boot')
    $aviso = if ($safe) { 'Você está em Modo Seguro: ótimo.' } else { 'ATENÇÃO: você NÃO está em Modo Seguro. O DDU deve rodar em Modo Seguro e SEM internet.' }
    if ([System.Windows.Forms.MessageBox]::Show("$aviso`n`n$info`n`nSeu PC ficará sem driver de vídeo até você instalar o novo. Já tem o instalador salvo e fez o backup?`n`nAbrir o DDU?", 'Abrir DDU', 'YesNo', 'Warning') -ne 'Yes') { return }
    Start-Process -FilePath $dlg.FileName; Log 'DDU aberto pelo usuário.'
}
function Invoke-ModoSeguro {
    $m = "O PC vai reiniciar AGORA para o menu de recuperação do Windows.`nSalve seu trabalho.`n`nLá escolha: Solução de problemas > Opções avançadas > Configurações de inicialização > Reiniciar > tecla 4.`n`nReiniciar?"
    if ([System.Windows.Forms.MessageBox]::Show($m, 'Reiniciar em Modo Seguro', 'YesNo', 'Warning') -eq 'Yes') { Log 'Reiniciando para o menu de recuperação (Modo Seguro).'; shutdown.exe /r /o /t 5 }
}

# ================= reparo do Windows (SFC, DISM, CHKDSK, TRIM, rede, Windows Update...) =================
$script:toolQueue = @(); $script:toolProc = $null; $script:toolFile = $null; $script:toolCur = $null; $script:toolStart = $null
$script:toolCancel = $false; $script:toolReboot = $false; $script:toolBtns = @(); $script:btnToolCancel = $null; $script:txtTool = $null; $script:lvTool = $null
$script:toolLog = Join-Path $script:dataDir 'ferramentas.log'

function New-Tool($id, $nome, $exe, $argLine, $admin, $min, $dica, $confirm = '', $reboot = $false, $abrir = '') {
    [pscustomobject]@{ Id = $id; Nome = $nome; Exe = $exe; Args = $argLine; Admin = $admin; Min = $min; Dica = $dica; Confirm = $confirm; Reboot = $reboot; Abrir = $abrir }
}
function New-PSArgs($code) { '-NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code)) }
function Get-Tools {
    $t = [ordered]@{}
    $drv = $env:SystemDrive
    $t['dism_check'] = New-Tool 'dism_check' 'DISM - verificação rápida da imagem' 'dism.exe' '/Online /Cleanup-Image /CheckHealth' $true 1 'Só consulta se o Windows já foi marcado como corrompido. Não altera nada.'
    $t['dism_scan'] = New-Tool 'dism_scan' 'DISM - varredura completa da imagem' 'dism.exe' '/Online /Cleanup-Image /ScanHealth' $true 6 'Procura corrupção no repositório de componentes. Não altera nada.'
    $t['sfc_verify'] = New-Tool 'sfc_verify' 'SFC - verificar arquivos do sistema (sem reparar)' 'sfc.exe' '/verifyonly' $true 10 'Confere os arquivos protegidos do Windows sem corrigir nada.'
    $t['chkdsk'] = New-Tool 'chkdsk' 'CHKDSK - verificar o disco (sem reparar)' 'chkdsk.exe' "$drv /scan" $true 8 'Varredura online do sistema de arquivos. Não exige reinício e não corrige.'
    $t['dism_restore'] = New-Tool 'dism_restore' 'DISM - REPARAR a imagem do Windows' 'dism.exe' '/Online /Cleanup-Image /RestoreHealth' $true 20 'Repara baixando arquivos do Windows Update. Rode ANTES do SFC. Precisa de internet.'
    $t['sfc_scan'] = New-Tool 'sfc_scan' 'SFC - verificar e REPARAR arquivos do sistema' 'sfc.exe' '/scannow' $true 15 'Verifica e substitui arquivos do Windows danificados. Detalhes em Windows\Logs\CBS\CBS.log.'
    $t['dism_clean'] = New-Tool 'dism_clean' 'DISM - limpar componentes antigos (WinSxS)' 'dism.exe' '/Online /Cleanup-Image /StartComponentCleanup' $true 10 'Libera espaço removendo versões antigas de componentes do Windows. Seguro.'
    $t['trim'] = New-Tool 'trim' 'Otimizar o disco (TRIM no SSD / desfragmentar HDD)' 'powershell.exe' (New-PSArgs "`$ErrorActionPreference='Continue'; Optimize-Volume -DriveLetter ('$drv'.Substring(0,1)) -Verbose 4>&1 | ForEach-Object { `"`$_`" }; 'Otimizacao concluida.'") $true 3 'Executa o TRIM em SSD ou a desfragmentação em HDD, conforme o tipo do disco.'
    $t['defender'] = New-Tool 'defender' 'Antivírus Defender - varredura rápida' 'powershell.exe' (New-PSArgs "Start-MpScan -ScanType QuickScan; 'Varredura rapida concluida.'") $true 10 'Varredura rápida das áreas mais comuns de infecção.'
    $t['dns'] = New-Tool 'dns' 'Limpar cache DNS' 'ipconfig.exe' '/flushdns' $false 0 'Resolve sites/servidores que não abrem por cache velho.'
    $t['winsock'] = New-Tool 'winsock' 'Rede - redefinir Winsock' 'netsh.exe' 'winsock reset' $true 1 'Conserta lag/queda e "sem internet" causados por driver/VPN/vírus antigo.' 'Pode derrubar conexões e VPN até reiniciar.' $true
    $t['iprst'] = New-Tool 'iprst' 'Rede - redefinir pilha TCP/IP' 'netsh.exe' 'int ip reset' $true 1 'Restaura a pilha TCP/IP ao padrão. Use com o Winsock quando a rede está instável.' 'Volta o IP/DNS manual para automático. Exige reiniciar.' $true
    $t['wu_reset'] = New-Tool 'wu_reset' 'Windows Update - redefinir componentes' 'powershell.exe' (New-PSArgs @'
$svc = 'wuauserv','bits','cryptsvc','msiserver'
foreach ($s in $svc) { Stop-Service $s -Force -ErrorAction SilentlyContinue; "parado: $s" }
$stamp = Get-Date -Format yyyyMMddHHmm
foreach ($p in "$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\System32\catroot2") { if (Test-Path $p) { Rename-Item $p ($p + '.bak' + $stamp) -ErrorAction SilentlyContinue; "renomeado: $p" } }
foreach ($s in $svc) { Start-Service $s -ErrorAction SilentlyContinue; "iniciado: $s" }
'Componentes do Windows Update redefinidos. As pastas antigas ficaram como .bak e podem ser apagadas depois.'
'@) $true 2 'Conserta atualizações que falham ou travam. As pastas antigas ficam como .bak.' 'Reinicia os serviços do Windows Update e renomeia seus caches.'
    $t['icon'] = New-Tool 'icon' 'Reconstruir cache de ícones e miniaturas' 'powershell.exe' (New-PSArgs @'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter 'iconcache*' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
'Cache de icones reconstruido.'
'@) $false 1 'Corrige ícones em branco/errados. A barra de tarefas pisca por alguns segundos.' 'A barra de tarefas e as janelas do Explorer vão fechar e reabrir.'
    $t['hib_off'] = New-Tool 'hib_off' 'Desativar hibernação (libera GBs do arquivo hiberfil)' 'powercfg.exe' '-h off' $true 0 'Libera de 6 a 12 GB no disco. Desliga também a inicialização rápida.' 'Perde a hibernação e a inicialização rápida (reversível na próxima opção).'
    $t['hib_on'] = New-Tool 'hib_on' 'Reativar hibernação' 'powercfg.exe' '-h on' $true 0 'Desfaz a opção anterior.'
    if ($script:isLaptop) { $bf = Join-Path $script:dataDir 'bateria.html'; $t['battery'] = New-Tool 'battery' 'Relatório de saúde da bateria' 'powercfg.exe' "/batteryreport /output `"$bf`"" $false 1 'Gera e abre o relatório com capacidade original x atual da bateria.' '' $false $bf }
    $t
}
function Get-Enc { $cp = 850; try { $cp = [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage } catch { }; try { [Text.Encoding]::GetEncoding($cp) } catch { [Text.Encoding]::Default } }
function Read-ToolOutput($file) {
    if (-not $file -or -not (Test-Path $file)) { return '' }
    try { $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite'); $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); $fs.Close(); $b = $ms.ToArray() } catch { return '' }
    if ($b.Length -eq 0) { return '' }
    $zeros = 0; $n = [math]::Min($b.Length, 400); for ($i = 0; $i -lt $n; $i++) { if ($b[$i] -eq 0) { $zeros++ } }
    if ($zeros -gt ($n / 4)) { $t = [Text.Encoding]::Unicode.GetString($b) } else { $t = (Get-Enc).GetString($b) }
    $t.Replace([string][char]0xFEFF, '')
}
function Format-ToolOutput($t) {
    $lines = @(($t -split "[\r\n]+") | Where-Object { $_.Trim() })
    $rx = '^\s*\[[=\s]*[\d\.,]+%[=\s]*\]\s*$'
    $out = @()
    foreach ($l in $lines) { if ($l -match $rx -and $out.Count -gt 0 -and $out[$out.Count - 1] -match $rx) { $out[$out.Count - 1] = $l } else { $out += $l } }
    (($out | Select-Object -Last 40) -join "`r`n")
}
function Set-ToolUi([bool]$running) {
    foreach ($b in $script:toolBtns) { $b.Enabled = (-not $running) }
    if ($script:btnToolCancel) { $script:btnToolCancel.Enabled = $running }
}
function Start-NextTool {
    if ($script:toolQueue.Count -eq 0) {
        $script:toolProc = $null; $script:toolCur = $null
        if ($script:toolTimer) { $script:toolTimer.Stop() }
        Set-ToolUi $false
        if ($script:toolReboot) { Log 'REINICIE o PC para concluir as alterações.' }
        return
    }
    $t = $script:toolQueue[0]; $script:toolQueue = @($script:toolQueue | Select-Object -Skip 1)
    $script:toolCur = $t
    $script:toolFile = Join-Path $script:dataDir ('tool_{0:HHmmssfff}.txt' -f (Get-Date))
    $cmd = '/s /c ""' + $t.Exe + '" ' + $t.Args + ' > "' + $script:toolFile + '" 2>&1"'
    $psi = New-Object System.Diagnostics.ProcessStartInfo('cmd.exe', $cmd)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $script:toolStart = Get-Date; $script:toolCancel = $false
    try { $script:toolProc = [System.Diagnostics.Process]::Start($psi) }
    catch { Log "Não consegui iniciar $($t.Nome): $($_.Exception.Message)"; $script:toolProc = $null; Start-NextTool; return }
    Set-ToolUi $true
    if ($script:toolTimer) { $script:toolTimer.Start() }
    Log "Iniciando: $($t.Nome)"
}
function Update-ToolTick {
    if (-not $script:toolProc) { return }
    $exited = $script:toolProc.HasExited
    $txt = Format-ToolOutput (Read-ToolOutput $script:toolFile)
    $el = (Get-Date) - $script:toolStart
    if ($script:txtTool) {
        $new = ("[{0}]  tempo: {1} min {2} s" -f $script:toolCur.Nome, [int][math]::Floor($el.TotalMinutes), $el.Seconds) + "`r`n`r`n" + $txt
        if ($script:txtTool.Text -ne $new) { $script:txtTool.Text = $new; $script:txtTool.SelectionStart = $script:txtTool.Text.Length; $script:txtTool.ScrollToCaret() }
    }
    if ($exited) {
        $code = $script:toolProc.ExitCode
        try { Add-Content -Path $script:toolLog -Value ("==== {0:yyyy-MM-dd HH:mm} {1} (código {2})`r`n{3}`r`n" -f (Get-Date), $script:toolCur.Nome, $code, $txt) -Encoding utf8 } catch { }
        Remove-Item $script:toolFile -Force -ErrorAction SilentlyContinue
        if ($script:toolCancel) { Log "Cancelado: $($script:toolCur.Nome)" }
        else {
            Log ("Concluído: {0} (código {1})" -f $script:toolCur.Nome, $code)
            if ($script:toolCur.Reboot) { $script:toolReboot = $true }
            if ($script:toolCur.Abrir -and (Test-Path $script:toolCur.Abrir)) { Start-Process $script:toolCur.Abrir }
        }
        Start-NextTool
    }
}
function Start-ToolQueue($list) { $script:toolQueue = @($list); $script:toolReboot = $false; Start-NextTool }
function Stop-Tools {
    $script:toolQueue = @()
    if ($script:toolProc -and -not $script:toolProc.HasExited) { $script:toolCancel = $true; & taskkill.exe /PID $script:toolProc.Id /T /F | Out-Null }
}
function Invoke-Ferramentas($ids) {
    if ($script:toolProc) { [void][System.Windows.Forms.MessageBox]::Show('Já existe uma ferramenta em execução. Aguarde ou clique em Cancelar.', 'Reparo do Windows'); return }
    $sel = @(); foreach ($id in $ids) { if ($script:tools.Contains($id)) { $sel += $script:tools[$id] } }
    if ($sel.Count -eq 0) { Log 'Nenhuma ferramenta marcada.'; return }
    if ((@($sel | Where-Object { $_.Admin }).Count -gt 0) -and -not $script:isAdmin) {
        Log 'Estas ferramentas exigem administrador. Use "Reabrir como administrador".'
        if (-not $SmokeTest) { [void][System.Windows.Forms.MessageBox]::Show("Estas ferramentas exigem administrador.`n`nClique em 'Reabrir como administrador'.", 'Reparo do Windows') }
        return
    }
    $min = ($sel | Measure-Object Min -Sum).Sum
    $lista = ($sel | ForEach-Object { " - $($_.Nome)" }) -join "`n"
    $extra = (@($sel | Where-Object { $_.Confirm } | ForEach-Object { "`n! $($_.Confirm)" })) -join ''
    $msg = "Vai executar:`n$lista`n`nTempo estimado: cerca de $min min. Você pode continuar usando o PC, mas não o desligue.$extra`n`nContinuar?"
    if ([System.Windows.Forms.MessageBox]::Show($msg, 'Reparo do Windows', 'YesNo', 'Question') -ne 'Yes') { return }
    Start-ToolQueue $sel
}
function Restart-Admin {
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`""); $script:form.Close() }
    catch { Log 'Elevação cancelada.' }
}
$script:guiaReparo = @"
REPARO DO WINDOWS - ordem recomendada quando o PC está lento, travando ou com erros estranhos:

  1. Verificação rápida (não altera nada): confere a imagem do Windows, os arquivos do sistema e o disco.
  2. Se algo apareceu: Reparo completo = DISM (repara a imagem) > SFC (repara arquivos) > limpeza de componentes.
     Sempre nessa ordem: o SFC depende da imagem estar saudável.
  3. Reinicie o PC depois do reparo.

Para lag de internet no jogo: marque "Rede - redefinir Winsock" + "Rede - redefinir TCP/IP" + "Limpar cache DNS" e reinicie.
Para espaço em disco: "DISM - limpar componentes antigos" e, se não usa hibernação, "Desativar hibernação".

As ferramentas rodam em segundo plano: pode continuar usando o PC e abrir as outras abas.
A saída aparece aqui ao vivo e fica salva em ferramentas.log (pasta de dados do programa).
Quase todas exigem administrador (botão "Reabrir como administrador").
"@
function New-ReparoTab {
    $tp = New-Object System.Windows.Forms.TabPage 'Reparo do Windows'
    $script:txtTool = New-Object System.Windows.Forms.TextBox; $script:txtTool.Multiline = $true; $script:txtTool.ReadOnly = $true; $script:txtTool.ScrollBars = 'Vertical'; $script:txtTool.Dock = 'Fill'; $script:txtTool.Font = New-Object System.Drawing.Font('Consolas', 9.5)
    $script:txtTool.Text = ($script:guiaReparo -replace "`r?`n", "`r`n"); $script:txtTool.SelectionStart = 0; $script:txtTool.SelectionLength = 0
    $script:lvTool = New-LV @(@('Ferramenta', 330), @('Admin', 55), @('Tempo', 70), @('O que faz', 560)) $true; $script:lvTool.Dock = 'Top'; $script:lvTool.Height = 250
    foreach ($t in $script:tools.Values) {
        $it = New-Object System.Windows.Forms.ListViewItem($t.Nome)
        [void]$it.SubItems.Add($(if ($t.Admin) { 'sim' } else { 'não' })); [void]$it.SubItems.Add($(if ($t.Min -gt 0) { "~$($t.Min) min" } else { '<1 min' })); [void]$it.SubItems.Add($t.Dica)
        $it.Tag = $t.Id; [void]$script:lvTool.Items.Add($it)
    }
    $bar = New-BtnBar; $bar.Height = 86
    $b1 = New-Btn 'Executar marcados' 150; $b1.Add_Click({ Invoke-Ferramentas @($script:lvTool.CheckedItems | ForEach-Object { $_.Tag }) })
    $b2 = New-Btn 'Verificação rápida (não altera)' 210; $b2.Add_Click({ Invoke-Ferramentas @('dism_check', 'sfc_verify', 'chkdsk') })
    $b3 = New-Btn 'Reparo completo (DISM + SFC)' 210; $b3.Add_Click({ Invoke-Ferramentas @('dism_restore', 'sfc_scan', 'dism_clean') })
    $script:btnToolCancel = New-Btn 'Cancelar' 100; $script:btnToolCancel.Enabled = $false; $script:btnToolCancel.Add_Click({ Stop-Tools })
    $b5 = New-Btn 'Limpeza de Disco do Windows' 200; $b5.Add_Click({ Start-Process cleanmgr.exe -ArgumentList ('/d ' + $env:SystemDrive.Substring(0, 1)); Log 'Aberta a Limpeza de Disco do Windows.' })
    $b6 = New-Btn 'Diagnóstico de memória' 170; $b6.Add_Click({ if ([System.Windows.Forms.MessageBox]::Show("O teste de memória exige REINICIAR o PC e leva de 15 a 30 minutos.`nSalve seu trabalho. Abrir agora?", 'Diagnóstico de memória', 'YesNo', 'Warning') -eq 'Yes') { Start-Process mdsched.exe; Log 'Aberto o Diagnóstico de Memória do Windows.' } })
    $b8x = New-Btn 'Reparo de rede (lag)' 170; $b8x.Add_Click({ Invoke-Ferramentas @('winsock', 'iprst', 'dns') })
    $script:toolBtns = @($b1, $b2, $b3, $b8x)
    $bar.Controls.AddRange(@($b1, $b2, $b3, $b8x, $script:btnToolCancel, $b5, $b6))
    if (-not $script:isAdmin) { $b7 = New-Btn 'Reabrir como administrador' 200; $b7.Add_Click({ Restart-Admin }); $bar.Controls.Add($b7) }
    $tp.Controls.Add($script:txtTool); $tp.Controls.Add($script:lvTool); $tp.Controls.Add($bar)
    $tp
}
$script:tools = Get-Tools
$script:toolTimer = New-Object System.Windows.Forms.Timer; $script:toolTimer.Interval = 800; $script:toolTimer.Add_Tick({ try { Update-ToolTick } catch { } })

# ================= relatório =================
function Save-Relatorio {
    $os = Get-CimInstance Win32_OperatingSystem; $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpu = (Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join ' | '
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("KIT PERSONAL - Relatório de $env:COMPUTERNAME em $(Get-Date -Format 'dd/MM/yyyy HH:mm')")
    [void]$sb.AppendLine("Windows: $($os.Caption) build $($os.BuildNumber) | CPU: $($cpu.Name) | GPU: $gpu")
    [void]$sb.AppendLine("Nota de saúde: $(Get-Score $script:lastChecks)/100"); [void]$sb.AppendLine('')
    foreach ($c in $script:lastChecks) { [void]$sb.AppendLine(("[{0}] {1}: {2}{3}" -f $c.Estado, $c.Item, $c.Detalhe, $(if ($c.Dica) { "  -> $($c.Dica)" } else { '' }))) }
    $dir = [Environment]::GetFolderPath('Desktop'); if ($SmokeTest -or -not $dir) { $dir = $script:dataDir }
    $f = Join-Path $dir ("KitPersonal_{0}_{1:yyyyMMdd_HHmm}.txt" -f $env:COMPUTERNAME, (Get-Date))
    $sb.ToString() | Out-File -FilePath $f -Encoding utf8
    Log "Relatório salvo em: $f"; $f
}

# ================= interface =================
function Update-Header {
    $os = Get-CimInstance Win32_OperatingSystem
    $tot = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1); $free = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $c = Get-Volume -DriveLetter $env:SystemDrive[0]
    $mode = if ($script:isAdmin) { 'administrador' } else { 'usuário comum' }
    $script:lblSub.Text = ("{0}  |  RAM livre {1} de {2} GB  |  C: {3} GB livres  |  rodando como {4}" -f $env:COMPUTERNAME, $free, $tot, [math]::Round($c.SizeRemaining / 1GB), $mode)
}
$fontUI = New-Object System.Drawing.Font('Segoe UI', 9)
function New-Btn($txt, $w = 160) { $b = New-Object System.Windows.Forms.Button; $b.Text = $txt; $b.Width = $w; $b.Height = 30; $b.FlatStyle = 'System'; $b }
function New-LV($cols, $check = $false) {
    $lv = New-Object System.Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.GridLines = $true; $lv.Dock = 'Fill'; $lv.HideSelection = $false
    $lv.CheckBoxes = $check
    foreach ($c in $cols) { [void]$lv.Columns.Add($c[0], $c[1]) }; $lv
}
function New-BtnBar { $p = New-Object System.Windows.Forms.FlowLayoutPanel; $p.Dock = 'Bottom'; $p.Height = 44; $p.Padding = '4,5,4,4'; $p }
function New-Txt($t, $pad = '10,8,0,0') { $l = New-Object System.Windows.Forms.Label; $l.AutoSize = $true; $l.Padding = $pad; $l.Text = $t; $l }

$script:form = New-Object System.Windows.Forms.Form
$f = $script:form; $f.Text = 'Kit Personal - PC Gamer'; $f.Size = New-Object System.Drawing.Size(1040, 760); $f.MinimumSize = New-Object System.Drawing.Size(900, 640); $f.StartPosition = 'CenterScreen'; $f.Font = $fontUI

$header = New-Object System.Windows.Forms.Panel; $header.Dock = 'Top'; $header.Height = 78; $header.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 38)
$lblTitle = New-Object System.Windows.Forms.Label; $lblTitle.Text = 'KIT PERSONAL'; $lblTitle.ForeColor = [System.Drawing.Color]::White; $lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold); $lblTitle.AutoSize = $true; $lblTitle.Location = New-Object System.Drawing.Point(16, 6)
$script:lblSub = New-Object System.Windows.Forms.Label; $script:lblSub.ForeColor = [System.Drawing.Color]::Silver; $script:lblSub.AutoSize = $true; $script:lblSub.Location = New-Object System.Drawing.Point(18, 46)
$cap = New-Object System.Windows.Forms.Label; $cap.Text = 'SAÚDE'; $cap.ForeColor = [System.Drawing.Color]::Silver; $cap.AutoSize = $true; $cap.Anchor = 'Top,Right'; $cap.Location = New-Object System.Drawing.Point(($f.ClientSize.Width - 130), 6)
$script:lblScore = New-Object System.Windows.Forms.Label; $script:lblScore.Text = '--'; $script:lblScore.ForeColor = [System.Drawing.Color]::White; $script:lblScore.Font = New-Object System.Drawing.Font('Segoe UI', 28, [System.Drawing.FontStyle]::Bold); $script:lblScore.AutoSize = $true; $script:lblScore.Anchor = 'Top,Right'; $script:lblScore.Location = New-Object System.Drawing.Point(($f.ClientSize.Width - 135), 20)
$btnAdm = New-Btn 'Reabrir como administrador' 190; $btnAdm.Anchor = 'Top,Right'; $btnAdm.Location = New-Object System.Drawing.Point(($f.ClientSize.Width - 350), 24); $btnAdm.Visible = (-not $script:isAdmin)
$btnAdm.Add_Click({
        Restart-Admin
    })
$cap.Anchor = 'None'; $script:lblScore.Anchor = 'None'; $btnAdm.Anchor = 'None'
$header.Controls.AddRange(@($lblTitle, $script:lblSub, $cap, $script:lblScore, $btnAdm))
function Place-Header {
    $w = $script:header.ClientSize.Width
    $script:lblScore.Location = New-Object System.Drawing.Point(($w - $script:lblScore.Width - 24), 18)
    $script:cap.Location = New-Object System.Drawing.Point(($w - $script:cap.Width - 28), 4)
    $script:btnAdm.Location = New-Object System.Drawing.Point(($w - $script:lblScore.Width - $script:btnAdm.Width - 50), 24)
}
$script:header = $header; $script:cap = $cap; $script:btnAdm = $btnAdm
$header.Add_Resize({ Place-Header })
$script:lblScore.Add_TextChanged({ Place-Header })

$script:tabs = New-Object System.Windows.Forms.TabControl; $script:tabs.Dock = 'Fill'
$script:logBox = New-Object System.Windows.Forms.TextBox; $script:logBox.Multiline = $true; $script:logBox.ReadOnly = $true; $script:logBox.ScrollBars = 'Vertical'; $script:logBox.Dock = 'Bottom'; $script:logBox.Height = 105; $script:logBox.BackColor = [System.Drawing.Color]::White

# --- Painel
$t1 = New-Object System.Windows.Forms.TabPage 'Painel'
$script:lvCheck = New-LV @(@('Estado', 70), @('Item', 230), @('Detalhe', 330), @('O que fazer', 360))
$b1 = New-BtnBar
$x = New-Btn 'Otimizar tudo (1 clique)' 200; $x.Add_Click({ Run-Op { Invoke-Tudo } }); $b1.Controls.Add($x)
$x = New-Btn 'Verificar de novo' 150; $x.Add_Click({ Run-Op { Update-Painel } }); $b1.Controls.Add($x)
$x = New-Btn 'Salvar relatório' 140; $x.Add_Click({ Run-Op { [void](Save-Relatorio) } }); $b1.Controls.Add($x)
$b1.Controls.Add((New-Txt 'Nota = 100 menos os pontos de cada alerta. Itens azuis são só informação.'))
$t1.Controls.Add($script:lvCheck); $t1.Controls.Add($b1)

# --- Modo Jogo
$t2 = New-Object System.Windows.Forms.TabPage 'Modo Jogo'
$pg = New-Object System.Windows.Forms.Panel; $pg.Dock = 'Fill'; $pg.Padding = '12,12,12,12'
$script:lblGame = New-Object System.Windows.Forms.Label; $script:lblGame.Text = 'Aguardando um jogo abrir...'; $script:lblGame.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold); $script:lblGame.ForeColor = [System.Drawing.Color]::DimGray; $script:lblGame.AutoSize = $true; $script:lblGame.Location = New-Object System.Drawing.Point(14, 10)
$script:chkWatch = New-Object System.Windows.Forms.CheckBox; $script:chkWatch.Text = 'Vigiar jogos automaticamente enquanto este programa estiver aberto'; $script:chkWatch.AutoSize = $true; $script:chkWatch.Checked = [bool]$script:cfg.watch; $script:chkWatch.Location = New-Object System.Drawing.Point(16, 48)
$script:chkHigh = New-Object System.Windows.Forms.CheckBox; $script:chkHigh.Text = 'Prioridade ALTA para o jogo'; $script:chkHigh.AutoSize = $true; $script:chkHigh.Checked = [bool]$script:cfg.high; $script:chkHigh.Location = New-Object System.Drawing.Point(16, 76)
$script:chkDem = New-Object System.Windows.Forms.CheckBox; $script:chkDem.Text = 'Rebaixar prioridade dos apps de fundo da lista abaixo (sem fechar nada)'; $script:chkDem.AutoSize = $true; $script:chkDem.Checked = [bool]$script:cfg.demote; $script:chkDem.Location = New-Object System.Drawing.Point(16, 104)
$script:chkPlan = New-Object System.Windows.Forms.CheckBox; $script:chkPlan.Text = 'Trocar para plano de energia de alto desempenho durante o jogo (volta ao normal depois)'; $script:chkPlan.AutoSize = $true; $script:chkPlan.Checked = [bool]$script:cfg.plan; $script:chkPlan.Location = New-Object System.Drawing.Point(16, 132)
$l1 = New-Txt 'Jogos monitorados (nomes dos processos, separados por vírgula):' '0,0,0,0'; $l1.Location = New-Object System.Drawing.Point(16, 168)
$script:txtGames = New-Object System.Windows.Forms.TextBox; $script:txtGames.Text = [string]$script:cfg.games; $script:txtGames.Location = New-Object System.Drawing.Point(16, 190); $script:txtGames.Width = 900; $script:txtGames.Anchor = 'Top,Left,Right'
$l2 = New-Txt 'Apps de fundo para rebaixar durante o jogo:' '0,0,0,0'; $l2.Location = New-Object System.Drawing.Point(16, 224)
$script:txtBg = New-Object System.Windows.Forms.TextBox; $script:txtBg.Text = [string]$script:cfg.bg; $script:txtBg.Location = New-Object System.Drawing.Point(16, 246); $script:txtBg.Width = 900; $script:txtBg.Anchor = 'Top,Left,Right'
$btnSaveG = New-Btn 'Salvar configuração' 170; $btnSaveG.Location = New-Object System.Drawing.Point(16, 282)
$btnSaveG.Add_Click({
        $script:cfg.games = $script:txtGames.Text; $script:cfg.bg = $script:txtBg.Text
        $script:cfg.high = $script:chkHigh.Checked; $script:cfg.demote = $script:chkDem.Checked; $script:cfg.plan = $script:chkPlan.Checked; $script:cfg.watch = $script:chkWatch.Checked
        $script:gameTimer.Enabled = $script:chkWatch.Checked
        Save-Cfg; Log 'Configuração do Modo Jogo salva.'
    })
$tip = New-Txt 'Como funciona: ao detectar o jogo, ele ganha prioridade de CPU e os apps de fundo (navegador, OneDrive...) ficam com prioridade baixa.  Nada é fechado nem apagado.  Ao fechar o jogo tudo volta ao normal.  Minimizar este programa o envia para a bandeja.' '0,10,0,0'
$tip.MaximumSize = New-Object System.Drawing.Size(900, 0); $tip.Location = New-Object System.Drawing.Point(16, 326)
$pg.Controls.AddRange(@($script:lblGame, $script:chkWatch, $script:chkHigh, $script:chkDem, $script:chkPlan, $l1, $script:txtGames, $l2, $script:txtBg, $btnSaveG, $tip))
$t2.Controls.Add($pg)

# --- Limpeza
$t3 = New-Object System.Windows.Forms.TabPage 'Limpeza'
$script:lstClean = New-Object System.Windows.Forms.CheckedListBox; $script:lstClean.Dock = 'Fill'; $script:lstClean.CheckOnClick = $true
$b3 = New-BtnBar
$x = New-Btn 'Analisar' 120; $x.Add_Click({ Run-Op { Invoke-Analisar } }); $b3.Controls.Add($x)
$x = New-Btn 'Limpar selecionados' 170; $x.Add_Click({ Run-Op { Invoke-Limpar } }); $b3.Controls.Add($x)
$script:lblClean = New-Txt ''; $b3.Controls.Add($script:lblClean)
$b3.Controls.Add((New-Txt 'O cache de shaders dos jogos NÃO é apagado (recriá-lo causa travadas).'))
$t3.Controls.Add($script:lstClean); $t3.Controls.Add($b3)

# --- Inicialização
$t4 = New-Object System.Windows.Forms.TabPage 'Inicialização'
$script:lvStart = New-LV @(@('Estado', 90), @('Nome', 230), @('Origem', 140), @('Comando', 520))
$b4 = New-BtnBar
$x = New-Btn 'Desativar selecionado' 170; $x.Add_Click({ Run-Op { Switch-Startup $true } }); $b4.Controls.Add($x)
$x = New-Btn 'Reativar selecionado' 160; $x.Add_Click({ Run-Op { Switch-Startup $false } }); $b4.Controls.Add($x)
$x = New-Btn 'Atualizar' 100; $x.Add_Click({ Run-Op { Update-Startup } }); $b4.Controls.Add($x)
$x = New-Btn 'Gerenciador de Tarefas' 170; $x.Add_Click({ Start-Process taskmgr.exe '/0 /startup' }); $b4.Controls.Add($x)
$b4.Controls.Add((New-Txt 'Desativar não apaga nada: dá para reativar quando quiser.'))
$t4.Controls.Add($script:lvStart); $t4.Controls.Add($b4)

# --- Rede
$t5 = New-Object System.Windows.Forms.TabPage 'Rede (lag)'
$pn = New-Object System.Windows.Forms.Panel; $pn.Dock = 'Fill'; $pn.Padding = '10,10,10,10'
$ln = New-Txt 'Alvo (IP ou site):' '0,0,0,0'; $ln.Location = New-Object System.Drawing.Point(14, 16)
$script:txtHost = New-Object System.Windows.Forms.TextBox; $script:txtHost.Text = '1.1.1.1'; $script:txtHost.Width = 200; $script:txtHost.Location = New-Object System.Drawing.Point(120, 12)
$lp = New-Txt 'Pacotes:' '0,0,0,0'; $lp.Location = New-Object System.Drawing.Point(340, 16)
$script:numPing = New-Object System.Windows.Forms.NumericUpDown; $script:numPing.Minimum = 3; $script:numPing.Maximum = 100; $script:numPing.Value = 20; $script:numPing.Width = 60; $script:numPing.Location = New-Object System.Drawing.Point(400, 12)
$bt = New-Btn 'Testar' 100; $bt.Location = New-Object System.Drawing.Point(480, 9); $bt.Add_Click({ Run-Op { Invoke-Rede } })
$bd = New-Btn 'Limpar cache DNS' 150; $bd.Location = New-Object System.Drawing.Point(590, 9); $bd.Add_Click({ Run-Op { ipconfig /flushdns | Out-Null; Log 'Cache DNS limpo.' } })
$script:txtNet = New-Object System.Windows.Forms.TextBox; $script:txtNet.Multiline = $true; $script:txtNet.ReadOnly = $true; $script:txtNet.Font = New-Object System.Drawing.Font('Consolas', 10); $script:txtNet.Location = New-Object System.Drawing.Point(14, 52); $script:txtNet.Size = New-Object System.Drawing.Size(900, 330); $script:txtNet.Anchor = 'Top,Left,Right,Bottom'
$script:txtNet.Text = "Dica: use o IP do servidor do jogo, ou 1.1.1.1 para testar sua internet.`r`nJitter acima de 10 ms ou qualquer perda de pacote causa 'lag' mesmo com ping baixo."
$pn.Controls.AddRange(@($ln, $script:txtHost, $lp, $script:numPing, $bt, $bd, $script:txtNet)); $t5.Controls.Add($pn)

# --- Monitor
$t6 = New-Object System.Windows.Forms.TabPage 'Monitor ao vivo'
$script:lvMon = New-LV @(@('Métrica', 260), @('Agora', 200), @('Pico/Mínimo da sessão', 220))
foreach ($n in 'CPU - uso', 'CPU - clock (% do base; mínimo da sessão)', 'RAM - uso', 'Disco - atividade', 'GPU - uso', 'GPU - temperatura', 'GPU - clock', 'GPU - consumo', 'GPU - VRAM') {
    $it = New-Object System.Windows.Forms.ListViewItem($n); [void]$it.SubItems.Add('-'); [void]$it.SubItems.Add('-'); [void]$script:lvMon.Items.Add($it)
}
$script:lblMon = New-Txt 'Diagnóstico ao vivo: clique em Iniciar e jogue/abra o app que trava.' '10,8,0,0'
$b6 = New-BtnBar
$script:btnMon = New-Btn 'Iniciar' 110; $script:btnMon.Add_Click({
        if ($script:monTimer.Enabled) { $script:monTimer.Stop(); $script:btnMon.Text = 'Iniciar' } else { $script:peak = @{}; $script:monTimer.Start(); $script:btnMon.Text = 'Parar'; Update-Monitor }
    })
$b6.Controls.Add($script:btnMon); $b6.Controls.Add($script:lblMon)
$t6.Controls.Add($script:lvMon); $t6.Controls.Add($b6)

# --- Otimizar
$t7 = New-Object System.Windows.Forms.TabPage 'Otimizar'
$po = New-Object System.Windows.Forms.FlowLayoutPanel; $po.Dock = 'Fill'; $po.FlowDirection = 'TopDown'; $po.WrapContents = $false; $po.Padding = '14,14,14,14'
function New-Chk($t) { $c = New-Object System.Windows.Forms.CheckBox; $c.Text = $t; $c.AutoSize = $true; $c.Checked = $true; $c.Margin = '0,0,0,8'; $c }
$script:cPower = New-Chk 'Plano de energia: alto desempenho'
$script:cGame = New-Chk 'Game Mode ligado + gravação em segundo plano (Game DVR) desligada'
$script:cMouse = New-Chk 'Mouse sem aceleração (precisão do ponteiro desligada)'
$script:cTips = New-Chk 'Desligar sugestões, dicas e anúncios do Windows'
$script:cTransp = New-Chk 'Desligar efeitos de transparência (ganho pequeno em PC fraco)'; $script:cTransp.Checked = $false
$nota = New-Txt "Todos os ajustes são reversíveis (botão Desfazer) e o valor original fica guardado em:`r`n$($script:bkFile)`r`n`r`nNão mexemos em: serviços, Defender, VBS/HVCI, TCP/rede, drivers. O maior ganho em jogos está na BIOS (XMP + dual channel), driver limpo e temperatura." '0,14,0,0'
$nota.MaximumSize = New-Object System.Drawing.Size(900, 0)
$po.Controls.AddRange(@($script:cPower, $script:cGame, $script:cMouse, $script:cTips, $script:cTransp, $nota))
$b7 = New-BtnBar
$x = New-Btn 'Aplicar' 120; $x.Add_Click({ Run-Op { Invoke-Otimizar $script:cPower.Checked $script:cGame.Checked $script:cMouse.Checked $script:cTips.Checked $script:cTransp.Checked; Update-Painel } }); $b7.Controls.Add($x)
$x = New-Btn 'Desfazer tudo' 140; $x.Add_Click({ Run-Op { Invoke-Desfazer; Update-Painel } }); $b7.Controls.Add($x)
if ($script:isDomain) { $po.Enabled = $false; $b7.Enabled = $false; $nota.Text = 'BLOQUEADO: este PC está no domínio (empresa). Ajustes de desempenho ficam com a TI. Use o Kit Business.'; $nota.ForeColor = [System.Drawing.Color]::Firebrick }
$t7.Controls.Add($po); $t7.Controls.Add($b7)

# --- Driver de vídeo
$t8 = New-Object System.Windows.Forms.TabPage 'Driver de vídeo'
$script:txtGuia = New-Object System.Windows.Forms.TextBox; $script:txtGuia.Multiline = $true; $script:txtGuia.ReadOnly = $true; $script:txtGuia.ScrollBars = 'Vertical'; $script:txtGuia.Dock = 'Fill'; $script:txtGuia.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$script:txtGuia.Text = ($script:guiaDriver -replace "`r?`n", "`r`n"); $script:txtGuia.SelectionStart = 0; $script:txtGuia.SelectionLength = 0
$script:lvDrv = New-LV @(@('Placa de vídeo', 280), @('Fabricante', 150), @('Versão', 90), @('Data do driver', 110), @('Idade', 80), @('INF', 90)); $script:lvDrv.Dock = 'Top'; $script:lvDrv.Height = 96
$b8 = New-BtnBar; $b8.Height = 86
$x = New-Btn 'Site do fabricante' 150; $x.Add_Click({ Run-Op { Open-Fabricante } }); $b8.Controls.Add($x)
$x = New-Btn 'Backup do driver atual' 170; $x.Add_Click({ Run-Op { [void](Backup-Driver) } }); $b8.Controls.Add($x)
$x = New-Btn 'Instalar driver baixado' 180; $x.Add_Click({ Run-Op { Invoke-InstalarDriver } }); $b8.Controls.Add($x)
$x = New-Btn 'Reiniciar em Modo Seguro' 190; $x.Add_Click({ Run-Op { Invoke-ModoSeguro } }); $b8.Controls.Add($x)
$x = New-Btn 'Abrir DDU baixado' 150; $x.Add_Click({ Run-Op { Invoke-AbrirDDU } }); $b8.Controls.Add($x)
$x = New-Btn 'Site oficial do DDU' 160; $x.Add_Click({ Start-Process 'https://www.wagnardsoft.com/'; Log 'Aberto o site oficial do DDU.' }); $b8.Controls.Add($x)
$x = New-Btn 'Atualizar lista' 120; $x.Add_Click({ Run-Op { Update-Driver } }); $b8.Controls.Add($x)
$t8.Controls.Add($script:txtGuia); $t8.Controls.Add($script:lvDrv); $t8.Controls.Add($b8)

$t9 = New-ReparoTab
$script:form.Add_FormClosing({ try { Stop-Tools; $script:toolTimer.Stop() } catch { } })
$script:tabs.TabPages.AddRange(@($t1, $t2, $t3, $t4, $t5, $t6, $t8, $t9, $t7))
$f.Controls.Add($script:tabs); $f.Controls.Add($script:logBox); $f.Controls.Add($header)

# --- timers e bandeja
$script:gameTimer = New-Object System.Windows.Forms.Timer; $script:gameTimer.Interval = 3000; $script:gameTimer.Add_Tick({ try { Update-Game } catch { } }); $script:gameTimer.Enabled = [bool]$script:cfg.watch
$script:monTimer = New-Object System.Windows.Forms.Timer; $script:monTimer.Interval = 2000; $script:monTimer.Add_Tick({ try { Update-Monitor } catch { } })
$script:tray = New-Object System.Windows.Forms.NotifyIcon; $script:tray.Icon = [System.Drawing.SystemIcons]::Application; $script:tray.Text = 'Kit Personal'; $script:tray.Visible = $false
$script:tray.Add_DoubleClick({ $script:form.Show(); $script:form.WindowState = 'Normal'; $script:tray.Visible = $false })
$f.Add_Resize({ if ($script:form.WindowState -eq 'Minimized' -and $script:cfg.watch) { $script:form.Hide(); $script:tray.Visible = $true; $script:tray.ShowBalloonTip(2000, 'Kit Personal', 'Continua vigiando seus jogos em segundo plano.', 'Info') } })
$f.Add_FormClosing({ try { Stop-Boost; $script:gameTimer.Stop(); $script:monTimer.Stop(); $script:tray.Visible = $false; $script:tray.Dispose() } catch { } })

# ================= inicialização do app =================
Update-Header; Update-Startup
Log "Kit Personal iniciado. Admin: $($script:isAdmin). Domínio: $($script:isDomain). Notebook: $($script:isLaptop)."
if ($script:isDomain) { Log 'AVISO: PC no domínio. Ajustes de desempenho ficam bloqueados (use o Kit Business).' }

# ================= teste automático =================
if ($SmokeTest) {
    $fail = 0
    function Check($nome, $ok) { $ts = (Get-Date).ToString('HH:mm:ss'); if ($ok) { Write-Host "$ts [PASS] $nome" -ForegroundColor Green } else { Write-Host "$ts [FAIL] $nome" -ForegroundColor Red; $script:fail++ } }
    $script:fail = 0
    Update-Painel; Check 'Painel gera verificações e nota' ($script:lastChecks.Count -ge 5 -and $script:lblScore.Text -match '^\d+$')
    Invoke-Analisar; Check 'Análise de limpeza' ($script:lstClean.Items.Count -eq $script:cats.Count)
    Update-Startup; Check 'Lista de inicialização' ($script:lvStart.Items.Count -ge 0)
    Update-Monitor; Check 'Monitor ao vivo (CPU/RAM)' ($script:lvMon.Items[2].SubItems[1].Text -match '\d')
    $r = Test-Latencia '127.0.0.1' 3; Check 'Teste de latência (loopback)' ($r.Perdidos -eq 0)
    # inicialização: ativa/desativa uma entrada falsa
    $rk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Set-ItemProperty -Path $rk -Name 'KitTestEntry' -Value 'C:\Windows\notepad.exe' -Type String
    $e = Get-StartupEntries | Where-Object { $_.Nome -eq 'KitTestEntry' }; Check 'Startup: entrada encontrada e ativa' ($e -and -not $e.Desativado)
    Set-StartupState $e.Ap $e.Nome $true; Check 'Startup: desativar' ((Get-StartupEntries | Where-Object { $_.Nome -eq 'KitTestEntry' }).Desativado)
    Set-StartupState $e.Ap $e.Nome $false; Check 'Startup: reativar' (-not (Get-StartupEntries | Where-Object { $_.Nome -eq 'KitTestEntry' }).Desativado)
    Remove-ItemProperty -Path $rk -Name 'KitTestEntry'; Remove-ItemProperty -Path $e.Ap -Name 'KitTestEntry'
    # backup/desfazer com chave falsa
    Set-Reg 'HKCU:\Software\KitPersonalTest' 'X' 5; Save-Bk
    Check 'Set-Reg grava valor' ((Get-ItemProperty 'HKCU:\Software\KitPersonalTest').X -eq 5)
    Invoke-Desfazer; Check 'Desfazer remove valor criado' ($null -eq (Get-ItemProperty 'HKCU:\Software\KitPersonalTest' -ErrorAction SilentlyContinue).X)
    Remove-Item 'HKCU:\Software\KitPersonalTest' -Recurse -ErrorAction SilentlyContinue
    # modo jogo com processos falsos (copias do ping.exe)
    $tdir = Join-Path $env:TEMP 'KitPersonalTest'; Copy-Item "$env:SystemRoot\System32\PING.EXE" (Join-Path $tdir 'cs2.exe') -Force; Copy-Item "$env:SystemRoot\System32\PING.EXE" (Join-Path $tdir 'fakebg.exe') -Force
    $script:cfg.bg = 'fakebg'; $script:cfg.plan = $false
    $pg1 = Start-Process (Join-Path $tdir 'cs2.exe') -ArgumentList '-t 127.0.0.1' -WindowStyle Hidden -PassThru
    $pb1 = Start-Process (Join-Path $tdir 'fakebg.exe') -ArgumentList '-t 127.0.0.1' -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 800
    Update-Game
    $pg1.Refresh(); $pb1.Refresh()
    Check 'Modo Jogo: detecta jogo e põe prioridade ALTA' ($script:gameOn -and $pg1.PriorityClass -eq 'High')
    Check 'Modo Jogo: rebaixa app de fundo' ($pb1.PriorityClass -eq 'BelowNormal')
    Stop-Process -Id $pg1.Id -Force; Start-Sleep -Milliseconds 500
    Update-Game; $pb1.Refresh()
    Check 'Modo Jogo: restaura ao fechar o jogo' ((-not $script:gameOn) -and $pb1.PriorityClass -eq 'Normal')
    Stop-Process -Id $pb1.Id -Force
    # driver de vídeo
    Update-Driver
    Check 'Driver: lista placas de vídeo' ($script:drivers.Count -ge 1 -and $script:lvDrv.Items.Count -eq $script:drivers.Count)
    Check 'Driver: reconhece fabricantes' ((Get-VendorKey 'NVIDIA Corporation' 'GeForce RTX 5060') -eq 'NVIDIA' -and (Get-VendorKey 'Advanced Micro Devices, Inc.' 'Radeon RX') -eq 'AMD' -and (Get-VendorKey 'Intel Corporation' 'UHD Graphics') -eq 'Intel')
    $ms = Test-DriverInstaller "$env:SystemRoot\System32\cmd.exe" 'NVIDIA'
    Check 'Driver: assinatura válida mas de outro fabricante é RECUSADA' ($ms.Valido -and -not $ms.Fabricante -and -not $ms.OK)
    $fk = Join-Path $tdir 'falso.exe'; Copy-Item "$env:SystemRoot\System32\cmd.exe" $fk -Force; [IO.File]::AppendAllText($fk, 'adulterado')
    $fr = Test-DriverInstaller $fk 'NVIDIA'; Check 'Driver: arquivo adulterado/sem assinatura é RECUSADO' (-not $fr.Valido -and -not $fr.OK)
    $vv = Test-DriverInstaller "$env:SystemRoot\System32\cmd.exe" ''; Check 'Driver: fabricante desconhecido não aceita assinante Microsoft' (-not $vv.OK)
    $bd = Backup-Driver; Check 'Driver: backup sem admin falha com mensagem (não quebra)' ((-not $script:isAdmin -and $null -eq $bd) -or ($script:isAdmin -and $bd))
    Check 'Driver: guia de instalação limpa presente' ($script:txtGuia.Text -match 'DDU' -and $script:txtGuia.Text -match 'instalação limpa')
    # reparo do Windows: executor de ferramentas (sem admin aqui: usa comandos inofensivos e o SFC/DISM só para testar a leitura)
    function Wait-Tools($sec) { $t0 = Get-Date; while ($script:toolProc -and ((Get-Date) - $t0).TotalSeconds -lt $sec) { DoEv; Update-ToolTick; Start-Sleep -Milliseconds 250 } }
    Check 'Reparo: tabela de ferramentas completa' (($script:tools.Count -ge 15) -and (@($script:tools.Values | Where-Object { -not $_.Nome -or -not $_.Exe }).Count -eq 0) -and $script:tools.Contains('sfc_scan') -and $script:tools.Contains('dism_restore') -and $script:tools.Contains('winsock') -and $script:tools.Contains('wu_reset'))
    Check 'Reparo: aba criada com todas as ferramentas' ($script:lvTool.Items.Count -eq $script:tools.Count)
    Check 'Reparo: comandos codificados (reset WU / ícones) são texto base64 válido' ((($script:tools['wu_reset'].Args -split ' ')[-1]).Length -gt 100 -and (($script:tools['icon'].Args -split ' ')[-1]).Length -gt 100)
    Check 'Limpeza: novas categorias (Epic, Firefox, dumps) presentes' ((@($script:cats | Where-Object { $_.Nome -match 'Epic|Firefox|Minidump|MEMORY' })).Count -eq 4)
    if (-not $script:isAdmin) {
        Invoke-Ferramentas @('sfc_verify') 2>$null
        Check 'Reparo: sem admin não inicia ferramenta que exige admin' ($null -eq $script:toolProc)
    }
    $f1 = New-Tool 't1' 'Teste fila 1' 'cmd.exe' '/c echo ola-fila-um' $false 0 ''; $f2 = New-Tool 't2' 'Teste fila 2' 'cmd.exe' '/c echo ola-fila-dois' $false 0 '' '' $true
    Start-ToolQueue @($f1, $f2); Wait-Tools 20
    Check 'Reparo: fila executa duas ferramentas em sequência e termina' (($null -eq $script:toolProc) -and ((Get-Content $script:toolLog -Raw) -match 'ola-fila-um') -and ((Get-Content $script:toolLog -Raw) -match 'ola-fila-dois'))
    Check 'Reparo: ferramenta com reinício sinaliza reboot' ($script:toolReboot)
    $pe = New-Tool 't3' 'Teste PowerShell codificado' 'powershell.exe' (New-PSArgs "'ola-powershell-codificado'") $false 0 ''
    Start-ToolQueue @($pe); Wait-Tools 40
    Check 'Reparo: comando PowerShell codificado funciona' ((Get-Content $script:toolLog -Raw) -match 'ola-powershell-codificado')
    $sf = New-Tool 't4' 'Teste SFC (UTF-16)' 'sfc.exe' '/verifyonly' $false 0 ''
    Start-ToolQueue @($sf); Wait-Tools 60
    $bloco = ((Get-Content $script:toolLog -Raw) -split '====')[-1]
    Check 'Reparo: saída UTF-16 do SFC é decodificada (sem caracteres nulos)' (($bloco -match 'sfc|SFC') -and ($bloco -notmatch "`0"))
    $dm = New-Tool 't5' 'Teste DISM (OEM)' 'dism.exe' '/Online /Cleanup-Image /CheckHealth' $false 0 ''
    Start-ToolQueue @($dm); Wait-Tools 60
    $bloco = ((Get-Content $script:toolLog -Raw) -split '====')[-1]
    Check 'Reparo: saída do DISM é capturada' ($bloco -match 'DISM|Deployment|Implantação|740|Erro|Error')
    $lg2 = New-Tool 't6' 'Teste cancelar' 'ping.exe' '-n 40 127.0.0.1' $false 0 ''
    Start-ToolQueue @($lg2, $f1); Start-Sleep -Milliseconds 800; $pidc = $script:toolProc.Id; Stop-Tools; Wait-Tools 10
    Start-Sleep -Milliseconds 500
    Check 'Reparo: cancelar encerra o processo e esvazia a fila' (($null -eq $script:toolProc) -and ($null -eq (Get-Process -Id $pidc -ErrorAction SilentlyContinue)))
    $rp = Save-Relatorio; Check 'Relatório salvo' (Test-Path $rp)
    # capturas de tela
    if ($ShotDir) {
        New-Item $ShotDir -ItemType Directory -Force | Out-Null
        $f.Show(); DoEv; Start-Sleep -Milliseconds 500
        $script:monTimer.Start(); Update-Monitor
        $i = 0
        foreach ($tp in $script:tabs.TabPages) {
            $script:tabs.SelectedTab = $tp; DoEv; Start-Sleep -Milliseconds 350; DoEv
            $bmp = New-Object System.Drawing.Bitmap $f.Width, $f.Height
            $f.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $f.Width, $f.Height)))
            $bmp.Save((Join-Path $ShotDir ("personal_{0}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $i++
        }
        $f.Close()
    }
    Write-Host "RESULTADO: $($script:fail) falha(s)"
    Remove-Item $tdir -Recurse -Force -ErrorAction SilentlyContinue
    exit $script:fail
}

$f.Add_Shown({ Run-Op { Update-Painel; Invoke-Analisar; Update-Painel; Update-Driver } })
[void]$f.ShowDialog()
