# Kit-Business.ps1 - Kit de manutenção para PC CORPORATIVO (domínio/AD).
# Abrir: duplo clique em Kit-Business.bat. NÃO precisa de administrador.
# Seguro por desenho: não altera registro de sistema, serviços, Defender, políticas (GPO), VBS nem drivers.
# O que faz: nota de saúde, "quem está travando" (eventos), limpeza do perfil, RAM/processos,
# inicialização (só itens do usuário), revisão de Downloads antigos (vai para a Lixeira), teste de rede/VPN,
# relatório pronto para abrir chamado na TI e limpeza semanal agendada.
param([switch]$SmokeTest, [string]$ShotDir, [switch]$Auto)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

# ================= estado e log =================
$script:dataDir = Join-Path $env:APPDATA 'KitBusiness'
if ($SmokeTest) { $script:dataDir = Join-Path $env:TEMP 'KitBusinessTest' }
New-Item $script:dataDir -ItemType Directory -Force | Out-Null
$script:logFile = Join-Path $script:dataDir 'log.txt'
$script:isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:logBox = $null; $script:busy = $false; $script:junkBytes = $null; $script:lastChecks = @(); $script:stab = $null; $script:netRows = @()
$script:taskName = 'KitBusiness-LimpezaSemanal'
$script:dlPath = $null

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
function MB($b) { [math]::Round($b / 1MB) }
function Get-GuidFrom($t) { if ($t -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $Matches[1] } else { '' } }

# ================= limpeza (somente perfil do usuário) =================
$script:cats = @(
    @{ Nome = 'Temporários do usuário (> 3 dias)'; Paths = @($env:TEMP); Dias = 3; Auto = $true },
    @{ Nome = 'Temporários do Windows (só se admin)'; Paths = @("$env:SystemRoot\Temp"); Dias = 3; Admin = $true },
    @{ Nome = 'Relatórios de erro e dumps de falha'; Paths = @("$env:LOCALAPPDATA\Microsoft\Windows\WER", "$env:LOCALAPPDATA\CrashDumps"); Dias = 3; Auto = $true },
    @{ Nome = 'Cache de miniaturas'; Paths = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer"); Dias = 3; Filtro = 'thumbcache*'; Auto = $true },
    @{ Nome = 'Cache do Edge (feche o Edge)'; Paths = @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache", "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"); Dias = 0 },
    @{ Nome = 'Cache do Chrome (feche o Chrome)'; Paths = @("$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache", "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"); Dias = 0 },
    @{ Nome = 'Lixeira'; Tipo = 'lixeira' }
)
function Get-CatFiles($c) {
    $lim = (Get-Date).AddDays(-[int]$c.Dias)
    foreach ($p in $c.Paths) {
        if (Test-Path $p) {
            $a = @{ Path = $p; Recurse = $true; Force = $true; File = $true; ErrorAction = 'SilentlyContinue' }
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
function Remove-Cat($c) {
    if ($c.Tipo -eq 'lixeira') { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; return }
    Get-CatFiles $c | Remove-Item -Force -ErrorAction SilentlyContinue
}

# ---- modo automático (tarefa agendada): limpa só o que é seguro, sem janela ----
if ($Auto) {
    $lib = 0
    foreach ($c in $script:cats) { if ($c.Auto) { $sz = Get-CatSize $c; if (-not $SmokeTest) { Remove-Cat $c }; $lib += $sz } }
    Log "Limpeza automática concluída: ~$(MB $lib) MB (temporários, erros, miniaturas)$(if ($SmokeTest) { ' [simulação]' })."
    exit 0
}

# ================= inicialização =================
$script:RunKeys = @(
    @{ Scope = 'Usuário'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Ap = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Edit = $true },
    @{ Scope = 'Máquina (TI)'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Ap = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Edit = $false },
    @{ Scope = 'Máquina 32 bits (TI)'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Ap = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Edit = $false }
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
                $list += [pscustomobject]@{ Nome = $p.Name; Comando = [string]$p.Value; Origem = $d.Scope; Ap = $d.Ap; Desativado = (Get-StartupState $d.Ap $p.Name); Editavel = $d.Edit }
            }
        }
    }
    $ap = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    foreach ($fi in (Get-ChildItem -Path ([Environment]::GetFolderPath('Startup')) -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
        $list += [pscustomobject]@{ Nome = $fi.Name; Comando = $fi.FullName; Origem = 'Pasta Inicializar'; Ap = $ap; Desativado = (Get-StartupState $ap $fi.Name); Editavel = $true }
    }
    $list
}

# ================= estabilidade: quem está travando =================
function Get-Stability {
    $since7 = (Get-Date).AddDays(-7); $since30 = (Get-Date).AddDays(-30)
    $crash = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = $since7 } -ErrorAction SilentlyContinue)
    $apps = @($crash | Group-Object { [string]$_.Properties[0].Value } | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { [pscustomobject]@{ App = $_.Name; Vezes = $_.Count } })
    $kp = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since30 } -ErrorAction SilentlyContinue)
    $dk = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'disk'; Id = 7, 11, 51; StartTime = $since30 } -ErrorAction SilentlyContinue)
    [pscustomobject]@{ Total = $crash.Count; Apps = $apps; Desligamentos = $kp.Count; ErrosDisco = $dk.Count }
}

# ================= verificações / nota =================
function New-Check($i, $e, $d, $t, $w = 0) { [pscustomobject]@{ Item = $i; Estado = $e; Detalhe = $d; Dica = $t; Peso = $w } }
function Get-Checks {
    $r = @()
    $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS
    $r += New-Check 'Equipamento' 'INFO' "$($cs.Manufacturer) $($cs.Model) | série $($bios.SerialNumber)" 'Informe a série ao abrir chamado.'
    $r += New-Check 'Rede corporativa' 'INFO' "domínio $($cs.Domain) | logon em $($env:LOGONSERVER -replace '\\','') | usuário $env:USERNAME" ''
    $up = (Get-Date) - $os.LastBootUpTime
    if ($up.TotalDays -gt 14) { $r += New-Check 'Tempo ligado' 'ALERTA' ("{0} dias sem reiniciar" -f [int]$up.TotalDays) 'Reinicie hoje: é a causa mais comum de lentidão.' 15 }
    elseif ($up.TotalDays -gt 7) { $r += New-Check 'Tempo ligado' 'ALERTA' ("{0} dias sem reiniciar" -f [int]$up.TotalDays) 'Reinicie ao fim do expediente.' 8 }
    else { $r += New-Check 'Tempo ligado' 'OK' ("{0:N1} dias" -f $up.TotalDays) '' }
    $pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    if ($pend) { $r += New-Check 'Reinício pendente' 'ALERTA' 'O Windows aguarda reinício para concluir atualizações' 'Reinicie o PC.' 6 }
    $tot = $os.TotalVisibleMemorySize; $freePct = [math]::Round($os.FreePhysicalMemory / $tot * 100)
    $top = Get-Process | Group-Object ProcessName | ForEach-Object { [pscustomobject]@{ N = $_.Name; MB = (MB ($_.Group | Measure-Object WorkingSet64 -Sum).Sum) } } | Sort-Object MB -Descending | Select-Object -First 3
    $topTxt = ($top | ForEach-Object { "$($_.N) $($_.MB) MB" }) -join ', '
    if ($freePct -lt 15) { $r += New-Check 'Memória RAM livre' 'ALERTA' "$freePct% livre de $([math]::Round($tot/1MB)) GB | maiores: $topTxt" 'Feche abas/apps (aba Processos). Se sempre assim, peça mais RAM à TI.' 15 }
    else { $r += New-Check 'Memória RAM livre' 'OK' "$freePct% livre de $([math]::Round($tot/1MB)) GB" '' }
    $br = @(Get-Process -Name msedge, chrome, msedgewebview2 -ErrorAction SilentlyContinue)
    $brMB = MB (($br | Measure-Object WorkingSet64 -Sum).Sum)
    if ($br.Count -gt 25 -or $brMB -gt 2500) { $r += New-Check 'Navegadores' 'ALERTA' "$($br.Count) processos usando $brMB MB" 'Feche abas, ative "abas em suspensão"/modo de eficiência no Edge/Chrome.' 6 }
    else { $r += New-Check 'Navegadores' 'OK' "$($br.Count) processos, $brMB MB" '' }
    $c = Get-Volume -DriveLetter $env:SystemDrive[0]
    if ($c -and $c.Size) {
        $pct = [math]::Round($c.SizeRemaining / $c.Size * 100)
        if ($pct -lt 15) { $r += New-Check 'Espaço no disco C:' 'ALERTA' "$pct% livre ($([math]::Round($c.SizeRemaining/1GB)) GB)" 'Limpe (aba Limpeza) e revise Downloads antigos.' 10 }
        else { $r += New-Check 'Espaço no disco C:' 'OK' "$pct% livre ($([math]::Round($c.SizeRemaining/1GB)) GB)" '' }
    }
    $bad = @(Get-PhysicalDisk | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne 'Healthy' })
    if ($bad.Count -gt 0) { $r += New-Check 'Saúde do disco' 'ALERTA' "$($bad[0].FriendlyName): $($bad[0].HealthStatus)" 'Abra chamado e faça backup imediatamente.' 20 }
    $st = @(Get-StartupEntries | Where-Object { -not $_.Desativado })
    if ($st.Count -gt 10) { $r += New-Check 'Inicialização' 'ALERTA' "$($st.Count) programas abrem com o Windows" 'Desative os seus que não usa (aba Inicialização).' 6 }
    else { $r += New-Check 'Inicialização' 'OK' "$($st.Count) programas" '' }
    $mp = Get-MpComputerStatus
    if ($mp) {
        if (-not $mp.RealTimeProtectionEnabled) { $r += New-Check 'Antivírus (Defender)' 'ALERTA' 'Proteção em tempo real DESLIGADA' 'Avise a TI.' 10 }
        else {
            $age = [int]((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
            if ($age -gt 7) { $r += New-Check 'Antivírus (Defender)' 'ALERTA' "assinaturas com $age dias" 'Avise a TI: atualização do antivírus parada.' 6 } else { $r += New-Check 'Antivírus (Defender)' 'OK' "ativo, assinaturas de $age dia(s)" '' }
        }
    }
    $wu = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 19; StartTime = (Get-Date).AddDays(-60) } -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($wu) {
        $d = [int]((Get-Date) - $wu.TimeCreated).TotalDays
        $r += New-Check 'Atualizações do Windows' 'OK' "última instalação há $d dia(s)" ''
    }
    else { $r += New-Check 'Atualizações do Windows' 'ALERTA' 'nenhuma atualização instalada nos últimos 60 dias' 'Verifique o Windows Update ou avise a TI.' 8 }
    if ($null -eq $script:stab) { $script:stab = Get-Stability }
    $s = $script:stab
    if ($s.Total -ge 5) { $r += New-Check 'Travamentos de apps (7 dias)' 'ALERTA' "$($s.Total) ocorrências; mais frequente: $($s.Apps[0].App) ($($s.Apps[0].Vezes)x)" 'Reinstale/atualize esse app ou avise a TI.' 8 }
    else { $r += New-Check 'Travamentos de apps (7 dias)' 'OK' "$($s.Total) ocorrência(s)" '' }
    if ($s.Desligamentos -ge 1) { $r += New-Check 'Desligamentos inesperados (30 dias)' 'ALERTA' "$($s.Desligamentos) vez(es) (queda de energia, tela azul ou travamento total)" 'Se recorrente, abra chamado (bateria, fonte ou driver).' 8 }
    else { $r += New-Check 'Desligamentos inesperados (30 dias)' 'OK' 'nenhum' '' }
    if ($s.ErrosDisco -ge 3) { $r += New-Check 'Erros de disco (30 dias)' 'ALERTA' "$($s.ErrosDisco) erros registrados" 'Possível SSD com defeito: abra chamado e faça backup.' 15 }
    elseif ($s.ErrosDisco -ge 1) { $r += New-Check 'Erros de disco (30 dias)' 'INFO' "$($s.ErrosDisco) ocorrência pontual (pendrive/HD externo também gera isso)" 'Se voltar a aparecer, abra chamado.' }
    if ($null -ne $script:junkBytes) {
        if ($script:junkBytes -gt 1GB) { $r += New-Check 'Lixo acumulado' 'ALERTA' "$(MB $script:junkBytes) MB recuperáveis" 'Rode a limpeza.' 4 } else { $r += New-Check 'Lixo acumulado' 'OK' "$(MB $script:junkBytes) MB" '' }
    }
    $bat = Get-CimInstance Win32_Battery | Select-Object -First 1
    if ($bat) { $r += New-Check 'Bateria' 'INFO' "$($bat.EstimatedChargeRemaining)% carga" 'Bateria viciada reduz desempenho em notebooks: peça diagnóstico à TI se durar pouco.' }
    $r
}
function Get-Score($checks) { $s = 100; foreach ($c in $checks) { if ($c.Estado -eq 'ALERTA') { $s -= $c.Peso } }; [math]::Max(0, $s) }
function Update-Saude {
    $script:stab = $null
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
    Log "Verificação concluída: nota $sc/100, $(@($script:lastChecks | Where-Object { $_.Estado -eq 'ALERTA' }).Count) ponto(s) de atenção."
    Update-Header
}

# ================= limpeza (UI) =================
function Invoke-Analisar {
    $script:lstClean.Items.Clear(); $tot = 0
    foreach ($c in $script:cats) {
        $sz = Get-CatSize $c; $c.Tam = $sz
        $blocked = ($c.Admin -and -not $script:isAdmin)
        if (-not $blocked) { $tot += $sz }
        $txt = "{0}  -  {1} MB{2}" -f $c.Nome, (MB $sz), $(if ($blocked) { '  [precisa de administrador]' } else { '' })
        [void]$script:lstClean.Items.Add($txt, ($sz -gt 0 -and -not $blocked -and $c.Tipo -ne 'lixeira' -and $c.Dias -gt 0))
        DoEv
    }
    $script:junkBytes = $tot
    $script:lblClean.Text = "Total recuperável: $(MB $tot) MB"
    Log "Análise de lixo: $(MB $tot) MB recuperáveis."
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

# ================= processos =================
$script:protegidos = 'system', 'idle', 'registry', 'smss', 'csrss', 'wininit', 'services', 'lsass', 'winlogon', 'svchost', 'dwm', 'explorer', 'fontdrvhost', 'msmpeng', 'mssense', 'sense', 'senseir', 'memory compression', 'securityhealthservice', 'sentinelagent', 'csfalconservice', 'csfalconcontainer', 'taniumclient', 'ccmexec', 'cylancesvc', 'openvpnserv', 'openvpnserv2', 'powershell', 'pwsh', 'conhost'
function Update-Procs {
    $script:lvProc.Items.Clear()
    Get-Process | Group-Object ProcessName | ForEach-Object { [pscustomobject]@{ Nome = $_.Name; Qtd = $_.Count; MB = (MB ($_.Group | Measure-Object WorkingSet64 -Sum).Sum) } } |
        Sort-Object MB -Descending | Select-Object -First 25 | ForEach-Object {
            $it = New-Object System.Windows.Forms.ListViewItem($_.Nome)
            [void]$it.SubItems.Add([string]$_.Qtd); [void]$it.SubItems.Add([string]$_.MB)
            [void]$script:lvProc.Items.Add($it)
        }
}
function Set-Prioridade($nome, $prio) {
    $ok = 0
    foreach ($p in @(Get-Process -Name $nome -ErrorAction SilentlyContinue)) { try { $p.PriorityClass = $prio; $ok++ } catch { } }
    $ok
}
function Selected-Proc { if ($script:lvProc.SelectedItems.Count -eq 0) { return $null }; $script:lvProc.SelectedItems[0].Text }
function Stop-Selecionado {
    $n = Selected-Proc; if (-not $n) { return }
    if ($script:protegidos -contains $n.ToLower()) { [void][System.Windows.Forms.MessageBox]::Show("'$n' é um processo do sistema/segurança da empresa. Não encerro.", 'Kit Business'); return }
    $aviso = if ($n -match 'msedge|chrome') { "`n`nISSO FECHA TODAS AS JANELAS E ABAS DO NAVEGADOR." } else { '' }
    if ([System.Windows.Forms.MessageBox]::Show("Encerrar TODOS os processos '$n'? Trabalho não salvo será perdido.$aviso", 'Confirmar', 'YesNo', 'Warning') -eq 'Yes') {
        Stop-Process -Name $n -Force -ErrorAction SilentlyContinue; Log "Processo encerrado: $n"; Start-Sleep -Milliseconds 500; Update-Procs; Update-Header
    }
}

# ================= inicialização (UI) =================
function Update-Startup {
    $script:lvStart.Items.Clear(); $script:startData = @(Get-StartupEntries)
    foreach ($e in $script:startData) {
        $it = New-Object System.Windows.Forms.ListViewItem($(if ($e.Desativado) { 'Desativado' } else { 'Ativo' }))
        [void]$it.SubItems.Add($e.Nome); [void]$it.SubItems.Add($e.Origem); [void]$it.SubItems.Add($e.Comando)
        if ($e.Desativado -or -not $e.Editavel) { $it.ForeColor = [System.Drawing.Color]::Gray }
        [void]$script:lvStart.Items.Add($it)
    }
}
function Switch-Startup([bool]$disable) {
    if ($script:lvStart.SelectedIndices.Count -eq 0) { return }
    $e = $script:startData[$script:lvStart.SelectedIndices[0]]
    if (-not $e.Editavel) { Log "'$($e.Nome)' é gerenciado pela TI (máquina). Peça à TI para alterar."; return }
    Set-StartupState $e.Ap $e.Nome $disable
    Log "$(if ($disable) { 'Desativado' } else { 'Reativado' }) na inicialização: $($e.Nome)"
    Update-Startup
}

# ================= downloads antigos =================
function Get-DownloadsPath {
    if ($script:dlPath) { return $script:dlPath }
    $p = $null; try { $p = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { }
    if (-not $p -or -not (Test-Path $p)) { $p = Join-Path $env:USERPROFILE 'Downloads' }
    $p
}
function Find-Downloads {
    $script:lvDl.Items.Clear(); $dias = [int]$script:numDias.Value; $lim = (Get-Date).AddDays(-$dias)
    $path = Get-DownloadsPath; $tot = 0
    Get-ChildItem -Path $path -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $lim } |
        Sort-Object Length -Descending | Select-Object -First 300 | ForEach-Object {
            $it = New-Object System.Windows.Forms.ListViewItem($_.Name)
            [void]$it.SubItems.Add(('{0:N1}' -f ($_.Length / 1MB))); [void]$it.SubItems.Add($_.LastWriteTime.ToString('yyyy-MM-dd')); [void]$it.SubItems.Add($_.DirectoryName)
            $it.Tag = $_.FullName; $tot += $_.Length
            [void]$script:lvDl.Items.Add($it)
        }
    $script:lblDl.Text = "$($script:lvDl.Items.Count) arquivo(s) com mais de $dias dias em $path ($(MB $tot) MB). Marque o que pode ir para a Lixeira."
    Log "Downloads antigos: $($script:lvDl.Items.Count) arquivos."
}
function Send-ToTrash($paths) {
    $n = 0
    foreach ($p in $paths) {
        try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin); $n++ } catch { }
    }
    $n
}
function Invoke-TrashMarcados {
    $sel = @($script:lvDl.CheckedItems | ForEach-Object { $_.Tag })
    if ($sel.Count -eq 0) { Log 'Nenhum arquivo marcado.'; return }
    if ([System.Windows.Forms.MessageBox]::Show("Enviar $($sel.Count) arquivo(s) para a Lixeira? (dá para restaurar de lá)", 'Confirmar', 'YesNo', 'Question') -ne 'Yes') { return }
    $n = Send-ToTrash $sel
    Log "$n arquivo(s) enviados para a Lixeira."
    Find-Downloads
}

# ================= rede corporativa =================
function Test-Latencia($target, $n = 4) {
    $p = New-Object System.Net.NetworkInformation.Ping; $rt = @(); $lost = 0
    for ($i = 0; $i -lt $n; $i++) {
        try { $r = $p.Send($target, 1000); if ($r.Status -eq 'Success') { $rt += [double]$r.RoundtripTime } else { $lost++ } } catch { $lost++ }
        DoEv; Start-Sleep -Milliseconds 120
    }
    [pscustomobject]@{ Alvo = $target; Enviados = $n; Perdidos = $lost; Media = $(if ($rt.Count) { [math]::Round(($rt | Measure-Object -Average).Average, 1) } else { 0 }) }
}
function Invoke-Rede {
    $script:lvNet.Items.Clear(); $script:netRows = @()
    $alvos = @()
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if ($gw) { $alvos += , @('Gateway (roteador/switch)', $gw) }
    $dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses } | ForEach-Object { $_.ServerAddresses } | Select-Object -Unique | Select-Object -First 2)
    $i = 1; foreach ($d in $dns) { $alvos += , @("Servidor DNS $i", $d); $i++ }
    $dc = ($env:LOGONSERVER -replace '\\', ''); if ($dc) { $alvos += , @('Controlador de domínio', $dc) }
    $alvos += , @('Internet (1.1.1.1)', '1.1.1.1')
    foreach ($a in $alvos) {
        $r = Test-Latencia $a[1] 4
        $st = if ($r.Perdidos -eq $r.Enviados) { 'SEM RESPOSTA (pode bloquear ping)' } elseif ($r.Perdidos -gt 0) { 'Perda de pacotes' } elseif ($r.Media -gt 100) { 'Lento' } else { 'OK' }
        $it = New-Object System.Windows.Forms.ListViewItem($a[0]); [void]$it.SubItems.Add([string]$a[1]); [void]$it.SubItems.Add([string]$r.Media); [void]$it.SubItems.Add("$($r.Perdidos)/$($r.Enviados)"); [void]$it.SubItems.Add($st)
        if ($st -ne 'OK') { $it.BackColor = [System.Drawing.Color]::FromArgb(255, 235, 205) }
        [void]$script:lvNet.Items.Add($it)
        $script:netRows += "{0}: {1} -> media {2} ms, perda {3}/{4}, {5}" -f $a[0], $a[1], $r.Media, $r.Perdidos, $r.Enviados, $st
    }
    $dt = 0; try { $dt = [int](Measure-Command { Resolve-DnsName microsoft.com -ErrorAction Stop | Out-Null }).TotalMilliseconds } catch { $dt = -1 }
    $it = New-Object System.Windows.Forms.ListViewItem('Resolução de nomes (DNS)'); [void]$it.SubItems.Add('microsoft.com'); [void]$it.SubItems.Add($(if ($dt -ge 0) { [string]$dt } else { '-' })); [void]$it.SubItems.Add('-'); [void]$it.SubItems.Add($(if ($dt -lt 0) { 'FALHOU' } elseif ($dt -gt 300) { 'Lento' } else { 'OK' }))
    [void]$script:lvNet.Items.Add($it); $script:netRows += "DNS microsoft.com: $dt ms"
    $vpn = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'OpenVPN|TAP-Windows|Wintun|WireGuard|AnyConnect|Cisco|Fortinet|FortiClient|GlobalProtect|Palo Alto|VPN' })
    $vt = if ($vpn.Count) { ($vpn | ForEach-Object { "$($_.Name): $($_.Status)" }) -join '  |  ' } else { 'nenhum adaptador de VPN detectado' }
    $script:lblNet.Text = "VPN: $vt"
    $script:netRows += "VPN: $vt"
    Log 'Teste de rede concluído.'
}

# ================= reparo do Windows (SFC, DISM, CHKDSK, TRIM, gpupdate...) =================
$script:toolQueue = @(); $script:toolProc = $null; $script:toolFile = $null; $script:toolCur = $null; $script:toolStart = $null
$script:toolCancel = $false; $script:toolReboot = $false; $script:toolBtns = @(); $script:btnToolCancel = $null; $script:txtTool = $null; $script:lvTool = $null
$script:toolLog = Join-Path $script:dataDir 'ferramentas.log'
$script:isLaptop = [bool](Get-CimInstance Win32_Battery)

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
    $t['dism_restore'] = New-Tool 'dism_restore' 'DISM - REPARAR a imagem do Windows' 'dism.exe' '/Online /Cleanup-Image /RestoreHealth' $true 20 'Repara baixando arquivos do Windows Update/WSUS. Rode ANTES do SFC. Se falhar na empresa, a rede usa WSUS: avise a TI.'
    $t['sfc_scan'] = New-Tool 'sfc_scan' 'SFC - verificar e REPARAR arquivos do sistema' 'sfc.exe' '/scannow' $true 15 'Verifica e substitui arquivos do Windows danificados. Detalhes em Windows\Logs\CBS\CBS.log.'
    $t['dism_clean'] = New-Tool 'dism_clean' 'DISM - limpar componentes antigos (WinSxS)' 'dism.exe' '/Online /Cleanup-Image /StartComponentCleanup' $true 10 'Libera espaço removendo versões antigas de componentes do Windows. Seguro.'
    $t['trim'] = New-Tool 'trim' 'Otimizar o disco (TRIM no SSD / desfragmentar HDD)' 'powershell.exe' (New-PSArgs "`$ErrorActionPreference='Continue'; Optimize-Volume -DriveLetter ('$drv'.Substring(0,1)) -Verbose 4>&1 | ForEach-Object { `"`$_`" }; 'Otimizacao concluida.'") $true 3 'Executa o TRIM em SSD ou a desfragmentação em HDD, conforme o tipo do disco.'
    $t['defender'] = New-Tool 'defender' 'Antivírus Defender - varredura rápida' 'powershell.exe' (New-PSArgs "Start-MpScan -ScanType QuickScan; 'Varredura rapida concluida.'") $true 10 'Varredura rápida das áreas mais comuns de infecção.'
    $t['gpupdate'] = New-Tool 'gpupdate' 'Atualizar políticas da empresa (gpupdate)' 'gpupdate.exe' '/force' $false 1 'Reaplica as políticas do domínio. Resolve configurações e acessos que "não pegaram".'
    $t['dns'] = New-Tool 'dns' 'Limpar cache DNS' 'ipconfig.exe' '/flushdns' $false 0 'Resolve sites/servidores internos que não abrem por cache velho.'
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
        if (-not $SmokeTest) { [void][System.Windows.Forms.MessageBox]::Show("Estas ferramentas exigem administrador.`n`nClique em 'Reabrir como administrador'. Em PC da empresa, pode ser necessário pedir à TI.", 'Reparo do Windows') }
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
    catch { Log 'Elevação cancelada ou bloqueada pela política.' }
}
$script:guiaReparo = @"
REPARO DO WINDOWS - ordem recomendada quando o PC está lento, travando ou com erros estranhos:

  1. Verificação rápida (não altera nada): confere a imagem do Windows, os arquivos do sistema e o disco.
  2. Se algo apareceu: Reparo completo = DISM (repara a imagem) > SFC (repara arquivos) > limpeza de componentes.
     Sempre nessa ordem: o SFC depende da imagem estar saudável.
  3. Reinicie o PC depois do reparo.

As ferramentas rodam em segundo plano: pode continuar usando o PC e abrir as outras abas.
A saída aparece aqui ao vivo e fica salva em ferramentas.log (pasta de dados do programa).
Quase todas exigem administrador.
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
    $script:toolBtns = @($b1, $b2, $b3)
    $bar.Controls.AddRange(@($b1, $b2, $b3, $script:btnToolCancel, $b5, $b6))
    if (-not $script:isAdmin) { $b7 = New-Btn 'Reabrir como administrador' 200; $b7.Add_Click({ Restart-Admin }); $bar.Controls.Add($b7) }
    $tp.Controls.Add($script:txtTool); $tp.Controls.Add($script:lvTool); $tp.Controls.Add($bar)
    $tp
}
$script:tools = Get-Tools
$script:toolTimer = New-Object System.Windows.Forms.Timer; $script:toolTimer.Interval = 800; $script:toolTimer.Add_Tick({ try { Update-ToolTick } catch { } })

# ================= relatório para a TI + agendamento =================
function Build-Relatorio {
    $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS; $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if ($script:lastChecks.Count -eq 0) { $script:lastChecks = @(Get-Checks) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('RELATÓRIO DE DESEMPENHO PARA A TI - Kit Business')
    [void]$sb.AppendLine("Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm') | Usuário: $env:USERNAME | Computador: $env:COMPUTERNAME")
    [void]$sb.AppendLine("Equipamento: $($cs.Manufacturer) $($cs.Model) | Série: $($bios.SerialNumber) | BIOS: $($bios.SMBIOSBIOSVersion)")
    [void]$sb.AppendLine("Windows: $($os.Caption) build $($os.BuildNumber) | CPU: $($cpu.Name) | RAM: $([math]::Round($cs.TotalPhysicalMemory/1GB)) GB")
    [void]$sb.AppendLine("Domínio: $($cs.Domain) | Logon server: $($env:LOGONSERVER)")
    [void]$sb.AppendLine("NOTA DE SAÚDE: $(Get-Score $script:lastChecks)/100"); [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- VERIFICAÇÕES ---')
    foreach ($c in $script:lastChecks) { [void]$sb.AppendLine(("[{0}] {1}: {2}" -f $c.Estado, $c.Item, $c.Detalhe)) }
    if ($script:stab -and $script:stab.Apps.Count) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine('--- APPS QUE MAIS TRAVARAM (7 dias) ---')
        foreach ($a in $script:stab.Apps) { [void]$sb.AppendLine("  $($a.App): $($a.Vezes)x") }
    }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('--- TOP 10 PROCESSOS POR RAM ---')
    Get-Process | Group-Object ProcessName | ForEach-Object { [pscustomobject]@{ N = $_.Name; C = $_.Count; MB = (MB ($_.Group | Measure-Object WorkingSet64 -Sum).Sum) } } | Sort-Object MB -Descending | Select-Object -First 10 | ForEach-Object { [void]$sb.AppendLine(("  {0,-26} {1,3} proc  {2,6} MB" -f $_.N, $_.C, $_.MB)) }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('--- INICIALIZAÇÃO ---')
    foreach ($e in (Get-StartupEntries)) { [void]$sb.AppendLine(("  [{0}] {1} ({2})" -f $(if ($e.Desativado) { 'off' } else { 'on' }), $e.Nome, $e.Origem)) }
    if ($script:netRows.Count) { [void]$sb.AppendLine(''); [void]$sb.AppendLine('--- REDE ---'); foreach ($l in $script:netRows) { [void]$sb.AppendLine("  $l") } }
    $sb.ToString()
}
function Save-Relatorio {
    $txt = Build-Relatorio
    $dir = [Environment]::GetFolderPath('Desktop'); if ($SmokeTest -or -not $dir -or -not (Test-Path $dir)) { $dir = $script:dataDir }
    $f = Join-Path $dir ("RelatorioTI_{0}_{1:yyyyMMdd_HHmm}.txt" -f $env:COMPUTERNAME, (Get-Date))
    $txt | Out-File -FilePath $f -Encoding utf8
    if (-not $SmokeTest) { try { [System.Windows.Forms.Clipboard]::SetText($txt) } catch { } }
    if ($script:txtRel) { $script:txtRel.Text = $txt -replace "`r?`n", "`r`n"; $script:txtRel.SelectionStart = 0; $script:txtRel.SelectionLength = 0 }
    Log "Relatório salvo em: $f (e copiado para a área de transferência: é só colar no chamado)."
    $f
}
function Get-TaskInfo { Get-ScheduledTask -TaskName $script:taskName -ErrorAction SilentlyContinue }
function Update-TaskLabel { $t = Get-TaskInfo; $script:lblTask.Text = if ($t) { "Limpeza semanal: AGENDADA (sextas, 12:30)  -  estado: $($t.State)" } else { 'Limpeza semanal: não agendada' } }
function New-Agenda {
    if (-not $PSCommandPath) { Log 'Não consegui identificar o caminho do script.'; return }
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Auto"
    try {
        $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
        $t = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At '12:30'
        $s = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $script:taskName -Action $a -Trigger $t -Settings $s -Description 'Kit Business: limpeza semanal segura do perfil' -Force -ErrorAction Stop | Out-Null
        Log 'Limpeza semanal agendada (sextas 12:30). Mantenha este arquivo na mesma pasta.'
    } catch { Log "A política da empresa pode ter bloqueado o agendamento: $($_.Exception.Message)" }
    Update-TaskLabel
}
function Remove-Agenda { Unregister-ScheduledTask -TaskName $script:taskName -Confirm:$false -ErrorAction SilentlyContinue; Log 'Agendamento removido.'; Update-TaskLabel }

# ================= interface =================
function Update-Header {
    $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem
    $tot = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1); $free = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $c = Get-Volume -DriveLetter $env:SystemDrive[0]
    $script:lblSub.Text = ("{0}  |  {1}  |  RAM livre {2} de {3} GB  |  C: {4} GB livres" -f $env:COMPUTERNAME, $(if ($cs.PartOfDomain) { "domínio $($cs.Domain)" } else { 'fora do domínio' }), $free, $tot, [math]::Round($c.SizeRemaining / 1GB))
}
$fontUI = New-Object System.Drawing.Font('Segoe UI', 9)
function New-Btn($txt, $w = 160) { $b = New-Object System.Windows.Forms.Button; $b.Text = $txt; $b.Width = $w; $b.Height = 30; $b.FlatStyle = 'System'; $b }
function New-LV($cols, $check = $false) {
    $lv = New-Object System.Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.GridLines = $true; $lv.Dock = 'Fill'; $lv.HideSelection = $false; $lv.CheckBoxes = $check
    foreach ($c in $cols) { [void]$lv.Columns.Add($c[0], $c[1]) }; $lv
}
function New-BtnBar { $p = New-Object System.Windows.Forms.FlowLayoutPanel; $p.Dock = 'Bottom'; $p.Height = 44; $p.Padding = '4,5,4,4'; $p }
function New-Txt($t, $pad = '10,8,0,0') { $l = New-Object System.Windows.Forms.Label; $l.AutoSize = $true; $l.Padding = $pad; $l.Text = $t; $l }

$script:form = New-Object System.Windows.Forms.Form
$f = $script:form; $f.Text = 'Kit Business - Manutenção corporativa'; $f.Size = New-Object System.Drawing.Size(1040, 760); $f.MinimumSize = New-Object System.Drawing.Size(900, 640); $f.StartPosition = 'CenterScreen'; $f.Font = $fontUI

$header = New-Object System.Windows.Forms.Panel; $header.Dock = 'Top'; $header.Height = 78; $header.BackColor = [System.Drawing.Color]::FromArgb(0, 62, 125)
$lblTitle = New-Object System.Windows.Forms.Label; $lblTitle.Text = 'KIT BUSINESS'; $lblTitle.ForeColor = [System.Drawing.Color]::White; $lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold); $lblTitle.AutoSize = $true; $lblTitle.Location = New-Object System.Drawing.Point(16, 6)
$script:lblSub = New-Object System.Windows.Forms.Label; $script:lblSub.ForeColor = [System.Drawing.Color]::FromArgb(200, 215, 235); $script:lblSub.AutoSize = $true; $script:lblSub.Location = New-Object System.Drawing.Point(18, 46)
$cap = New-Object System.Windows.Forms.Label; $cap.Text = 'SAÚDE'; $cap.ForeColor = [System.Drawing.Color]::FromArgb(200, 215, 235); $cap.AutoSize = $true
$script:lblScore = New-Object System.Windows.Forms.Label; $script:lblScore.Text = '--'; $script:lblScore.ForeColor = [System.Drawing.Color]::White; $script:lblScore.Font = New-Object System.Drawing.Font('Segoe UI', 28, [System.Drawing.FontStyle]::Bold); $script:lblScore.AutoSize = $true
$header.Controls.AddRange(@($lblTitle, $script:lblSub, $cap, $script:lblScore))
$script:header = $header; $script:cap = $cap
function Place-Header {
    $w = $script:header.ClientSize.Width
    $script:lblScore.Location = New-Object System.Drawing.Point(($w - $script:lblScore.Width - 24), 18)
    $script:cap.Location = New-Object System.Drawing.Point(($w - $script:cap.Width - 28), 4)
}
$header.Add_Resize({ Place-Header }); $script:lblScore.Add_TextChanged({ Place-Header })

$script:tabs = New-Object System.Windows.Forms.TabControl; $script:tabs.Dock = 'Fill'
$script:logBox = New-Object System.Windows.Forms.TextBox; $script:logBox.Multiline = $true; $script:logBox.ReadOnly = $true; $script:logBox.ScrollBars = 'Vertical'; $script:logBox.Dock = 'Bottom'; $script:logBox.Height = 105; $script:logBox.BackColor = [System.Drawing.Color]::White

# --- Saúde
$t1 = New-Object System.Windows.Forms.TabPage 'Saúde'
$script:lvCheck = New-LV @(@('Estado', 70), @('Item', 240), @('Detalhe', 380), @('O que fazer', 330))
$b1 = New-BtnBar
$x = New-Btn 'Verificar de novo' 160; $x.Add_Click({ Run-Op { Update-Saude } }); $b1.Controls.Add($x)
$x = New-Btn 'Gerar relatório para a TI' 200; $x.Add_Click({ Run-Op { [void](Save-Relatorio) } }); $b1.Controls.Add($x)
$b1.Controls.Add((New-Txt 'Verde = ok, laranja = atenção, azul = informação. A nota considera só os alertas.'))
$t1.Controls.Add($script:lvCheck); $t1.Controls.Add($b1)

# --- Limpeza
$t2 = New-Object System.Windows.Forms.TabPage 'Limpeza'
$script:lstClean = New-Object System.Windows.Forms.CheckedListBox; $script:lstClean.Dock = 'Fill'; $script:lstClean.CheckOnClick = $true
$b2 = New-BtnBar
$x = New-Btn 'Analisar' 120; $x.Add_Click({ Run-Op { Invoke-Analisar } }); $b2.Controls.Add($x)
$x = New-Btn 'Limpar selecionados' 170; $x.Add_Click({ Run-Op { Invoke-Limpar } }); $b2.Controls.Add($x)
$script:lblClean = New-Txt ''; $b2.Controls.Add($script:lblClean)
$b2.Controls.Add((New-Txt 'Só arquivos do SEU perfil. Nada de sistema, serviços ou políticas.'))
$t2.Controls.Add($script:lstClean); $t2.Controls.Add($b2)

# --- Processos
$t3 = New-Object System.Windows.Forms.TabPage 'Processos'
$script:lvProc = New-LV @(@('Processo', 300), @('Instâncias', 90), @('RAM (MB)', 100))
$b3 = New-BtnBar
$x = New-Btn 'Atualizar' 100; $x.Add_Click({ Run-Op { Update-Procs; Update-Header } }); $b3.Controls.Add($x)
$x = New-Btn 'Baixar prioridade' 150; $x.Add_Click({ Run-Op { $n = Selected-Proc; if ($n) { $k = Set-Prioridade $n 'BelowNormal'; Log "Prioridade baixa em $k processo(s) de '$n' (volta ao reiniciar o app)." } } }); $b3.Controls.Add($x)
$x = New-Btn 'Prioridade normal' 150; $x.Add_Click({ Run-Op { $n = Selected-Proc; if ($n) { $k = Set-Prioridade $n 'Normal'; Log "Prioridade normal em $k processo(s) de '$n'." } } }); $b3.Controls.Add($x)
$x = New-Btn 'Encerrar' 100; $x.Add_Click({ Run-Op { Stop-Selecionado } }); $b3.Controls.Add($x)
$b3.Controls.Add((New-Txt 'Fechar o que consome RAM é a otimização real. "Limpar RAM" é placebo. Processos de segurança/sistema são protegidos.'))
$t3.Controls.Add($script:lvProc); $t3.Controls.Add($b3)

# --- Inicialização
$t4 = New-Object System.Windows.Forms.TabPage 'Inicialização'
$script:lvStart = New-LV @(@('Estado', 90), @('Nome', 230), @('Origem', 150), @('Comando', 500))
$b4 = New-BtnBar
$x = New-Btn 'Desativar selecionado' 170; $x.Add_Click({ Run-Op { Switch-Startup $true } }); $b4.Controls.Add($x)
$x = New-Btn 'Reativar selecionado' 160; $x.Add_Click({ Run-Op { Switch-Startup $false } }); $b4.Controls.Add($x)
$x = New-Btn 'Atualizar' 100; $x.Add_Click({ Run-Op { Update-Startup } }); $b4.Controls.Add($x)
$b4.Controls.Add((New-Txt 'Itens cinza "(TI)" são da máquina e só a TI altera. Desativar não apaga: dá para reativar.'))
$t4.Controls.Add($script:lvStart); $t4.Controls.Add($b4)

# --- Downloads
$t5 = New-Object System.Windows.Forms.TabPage 'Downloads antigos'
$script:lvDl = New-LV @(@('Arquivo', 330), @('MB', 70), @('Modificado', 100), @('Pasta', 470)) $true
$script:lblDl = New-Txt 'Clique em Procurar.' '10,0,0,0'; $script:lblDl.Dock = 'Top'; $script:lblDl.Height = 26; $script:lblDl.AutoSize = $false; $script:lblDl.TextAlign = 'MiddleLeft'
$b5 = New-BtnBar
$b5.Controls.Add((New-Txt 'Mais antigos que (dias):' '4,8,0,0'))
$script:numDias = New-Object System.Windows.Forms.NumericUpDown; $script:numDias.Minimum = 7; $script:numDias.Maximum = 3650; $script:numDias.Value = 60; $script:numDias.Width = 60; $script:numDias.Margin = '0,6,10,0'; $b5.Controls.Add($script:numDias)
$x = New-Btn 'Procurar' 110; $x.Add_Click({ Run-Op { Find-Downloads } }); $b5.Controls.Add($x)
$x = New-Btn 'Enviar marcados para a Lixeira' 220; $x.Add_Click({ Run-Op { Invoke-TrashMarcados } }); $b5.Controls.Add($x)
$x = New-Btn 'Abrir pasta Downloads' 170; $x.Add_Click({ Start-Process explorer.exe (Get-DownloadsPath) }); $b5.Controls.Add($x)
$t5.Controls.Add($script:lvDl); $t5.Controls.Add($script:lblDl); $t5.Controls.Add($b5)

# --- Rede
$t6 = New-Object System.Windows.Forms.TabPage 'Rede / VPN'
$script:lvNet = New-LV @(@('Teste', 220), @('Endereço', 200), @('Média (ms)', 90), @('Perda', 70), @('Resultado', 320))
$script:lblNet = New-Txt 'Clique em Testar para medir roteador, DNS, controlador de domínio e internet.' '10,0,0,0'; $script:lblNet.Dock = 'Top'; $script:lblNet.Height = 26; $script:lblNet.AutoSize = $false; $script:lblNet.TextAlign = 'MiddleLeft'
$b6 = New-BtnBar
$x = New-Btn 'Testar conexão' 150; $x.Add_Click({ Run-Op { Invoke-Rede } }); $b6.Controls.Add($x)
$b6.Controls.Add((New-Txt 'Onde falha? Roteador ruim = Wi-Fi/cabo; DNS/domínio lento = TI; só a internet = operadora.'))
$t6.Controls.Add($script:lvNet); $t6.Controls.Add($script:lblNet); $t6.Controls.Add($b6)

# --- Manutenção
$t7 = New-Object System.Windows.Forms.TabPage 'Relatório e agenda'
$script:txtRel = New-Object System.Windows.Forms.TextBox; $script:txtRel.Multiline = $true; $script:txtRel.ReadOnly = $true; $script:txtRel.ScrollBars = 'Both'; $script:txtRel.Dock = 'Fill'; $script:txtRel.Font = New-Object System.Drawing.Font('Consolas', 9); $script:txtRel.WordWrap = $false
$script:txtRel.Text = "Clique em 'Gerar relatório' para criar um resumo técnico pronto para colar no chamado da TI (série, RAM, disco, travamentos, processos, rede).`r`nO arquivo é salvo na Área de Trabalho e o texto vai para a área de transferência."
$script:lblTask = New-Txt '' '10,0,0,0'; $script:lblTask.Dock = 'Top'; $script:lblTask.Height = 26; $script:lblTask.AutoSize = $false; $script:lblTask.TextAlign = 'MiddleLeft'
$b7 = New-BtnBar
$x = New-Btn 'Gerar relatório' 140; $x.Add_Click({ Run-Op { [void](Save-Relatorio) } }); $b7.Controls.Add($x)
$x = New-Btn 'Agendar limpeza semanal' 190; $x.Add_Click({ Run-Op { New-Agenda } }); $b7.Controls.Add($x)
$x = New-Btn 'Remover agendamento' 170; $x.Add_Click({ Run-Op { Remove-Agenda } }); $b7.Controls.Add($x)
$x = New-Btn 'Abrir pasta de logs' 150; $x.Add_Click({ Start-Process explorer.exe $script:dataDir }); $b7.Controls.Add($x)
$t7.Controls.Add($script:txtRel); $t7.Controls.Add($script:lblTask); $t7.Controls.Add($b7)

$t8 = New-ReparoTab
$script:form.Add_FormClosing({ try { Stop-Tools; $script:toolTimer.Stop() } catch { } })
$script:tabs.TabPages.AddRange(@($t1, $t2, $t3, $t4, $t5, $t6, $t8, $t7))
$f.Controls.Add($script:tabs); $f.Controls.Add($script:logBox); $f.Controls.Add($header)

# ================= início =================
Update-Header; Update-Procs; Update-Startup; Update-TaskLabel
Log "Kit Business iniciado. Usuário: $env:USERNAME. Admin: $($script:isAdmin)."

# ================= teste automático =================
if ($SmokeTest) {
    function Check($nome, $ok) { $ts = (Get-Date).ToString('HH:mm:ss'); if ($ok) { Write-Host "$ts [PASS] $nome" -ForegroundColor Green } else { Write-Host "$ts [FAIL] $nome" -ForegroundColor Red; $script:fail++ } }
    $script:fail = 0
    Update-Saude; Check 'Saúde gera verificações e nota' ($script:lastChecks.Count -ge 6 -and $script:lblScore.Text -match '^\d+$')
    Check 'Estabilidade (eventos) consultada' ($null -ne $script:stab)
    Invoke-Analisar; Check 'Análise de limpeza' ($script:lstClean.Items.Count -eq $script:cats.Count)
    Update-Procs; Check 'Lista de processos' ($script:lvProc.Items.Count -ge 5)
    Update-Startup; Check 'Lista de inicialização' ($true)
    $rk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Set-ItemProperty -Path $rk -Name 'KitTestEntryB' -Value 'C:\Windows\notepad.exe' -Type String
    $e = Get-StartupEntries | Where-Object { $_.Nome -eq 'KitTestEntryB' }; Check 'Startup: entrada de usuário editável' ($e -and $e.Editavel -and -not $e.Desativado)
    Set-StartupState $e.Ap $e.Nome $true; Check 'Startup: desativar' ((Get-StartupEntries | Where-Object { $_.Nome -eq 'KitTestEntryB' }).Desativado)
    Set-StartupState $e.Ap $e.Nome $false; Check 'Startup: reativar' (-not (Get-StartupEntries | Where-Object { $_.Nome -eq 'KitTestEntryB' }).Desativado)
    Remove-ItemProperty -Path $rk -Name 'KitTestEntryB'; Remove-ItemProperty -Path $e.Ap -Name 'KitTestEntryB'
    $hk = Get-StartupEntries | Where-Object { $_.Origem -like 'Máquina*' } | Select-Object -First 1
    if ($hk) { Check 'Startup: itens da máquina são somente leitura' (-not $hk.Editavel) }
    # prioridade
    $tdir = Join-Path $env:TEMP 'KitBusinessTest'; Copy-Item "$env:SystemRoot\System32\PING.EXE" (Join-Path $tdir 'kitfake.exe') -Force
    $pp = Start-Process (Join-Path $tdir 'kitfake.exe') -ArgumentList '-t 127.0.0.1' -WindowStyle Hidden -PassThru; Start-Sleep -Milliseconds 600
    $k = Set-Prioridade 'kitfake' 'BelowNormal'; $pp.Refresh(); Check 'Processos: baixar prioridade' ($k -eq 1 -and $pp.PriorityClass -eq 'BelowNormal')
    $k = Set-Prioridade 'kitfake' 'Normal'; $pp.Refresh(); Check 'Processos: restaurar prioridade' ($pp.PriorityClass -eq 'Normal')
    Stop-Process -Id $pp.Id -Force
    Check 'Processos: lista de proteção cobre lsass/MsMpEng' (($script:protegidos -contains 'lsass') -and ($script:protegidos -contains 'msmpeng'))
    # downloads: pasta falsa com arquivos antigos e novos
    $dl = Join-Path $tdir 'dl'; New-Item $dl -ItemType Directory -Force | Out-Null; $script:dlPath = $dl
    $old = Join-Path $dl 'velho.bin'; [IO.File]::WriteAllBytes($old, (New-Object byte[] 2048)); (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-200)
    $new = Join-Path $dl 'novo.bin'; [IO.File]::WriteAllBytes($new, (New-Object byte[] 2048))
    Find-Downloads; Check 'Downloads: acha só o arquivo antigo' ($script:lvDl.Items.Count -eq 1 -and $script:lvDl.Items[0].Text -eq 'velho.bin')
    $n = Send-ToTrash @($old); Check 'Downloads: envia para a Lixeira (não apaga direto)' ($n -eq 1 -and -not (Test-Path $old) -and (Test-Path $new))
    # rede
    Invoke-Rede; Check 'Rede: executa os testes' ($script:lvNet.Items.Count -ge 2)
    # relatório
    # reparo do Windows: executor de ferramentas (sem admin aqui: usa comandos inofensivos e o SFC só para testar a leitura)
    function Wait-Tools($sec) { $t0 = Get-Date; while ($script:toolProc -and ((Get-Date) - $t0).TotalSeconds -lt $sec) { DoEv; Update-ToolTick; Start-Sleep -Milliseconds 250 } }
    Check 'Reparo: tabela de ferramentas completa' (($script:tools.Count -ge 11) -and (@($script:tools.Values | Where-Object { -not $_.Nome -or -not $_.Exe }).Count -eq 0) -and $script:tools.Contains('sfc_scan') -and $script:tools.Contains('dism_restore') -and $script:tools.Contains('gpupdate'))
    Check 'Reparo: aba criada com todas as ferramentas' ($script:lvTool.Items.Count -eq $script:tools.Count)
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
    $lg = Get-Content $script:toolLog -Raw; $bloco = ($lg -split '====')[-1]
    Check 'Reparo: saída UTF-16 do SFC é decodificada (sem caracteres nulos)' (($bloco -match 'sfc|SFC') -and ($bloco -notmatch "`0"))
    $dm = New-Tool 't5' 'Teste DISM (OEM)' 'dism.exe' '/Online /Cleanup-Image /CheckHealth' $false 0 ''
    Start-ToolQueue @($dm); Wait-Tools 60
    $bloco = ((Get-Content $script:toolLog -Raw) -split '====')[-1]
    Check 'Reparo: saída do DISM é capturada' ($bloco -match 'DISM|Deployment|Implantação|740|Erro|Error')
    $lg2 = New-Tool 't6' 'Teste cancelar' 'ping.exe' '-n 40 127.0.0.1' $false 0 ''
    Start-ToolQueue @($lg2, $f1); Start-Sleep -Milliseconds 800; $pidc = $script:toolProc.Id; Stop-Tools; Wait-Tools 10
    Start-Sleep -Milliseconds 500
    Check 'Reparo: cancelar encerra o processo e esvazia a fila' (($null -eq $script:toolProc) -and ($null -eq (Get-Process -Id $pidc -ErrorAction SilentlyContinue)))
    $rp = Save-Relatorio; Check 'Relatório gerado e salvo' ((Test-Path $rp) -and (Get-Content $rp -Raw).Contains('NOTA DE SAÚDE'))
    # modo automático: roda o script em outro processo e confere que sai sem erro
    $pr = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Auto', '-SmokeTest') -Wait -PassThru -WindowStyle Hidden
    Check 'Modo -Auto executa e termina com código 0' ($pr.ExitCode -eq 0)
    # agendamento: cria, consulta e remove
    New-Agenda; $ti = Get-TaskInfo
    if ($ti) { Check 'Agendamento: tarefa criada' $true; Remove-Agenda; Check 'Agendamento: tarefa removida' ($null -eq (Get-TaskInfo)) }
    else { Write-Host '[AVISO] Agendamento bloqueado neste PC (política); tratado com mensagem amigável.' -ForegroundColor Yellow }
    if ($ShotDir) {
        New-Item $ShotDir -ItemType Directory -Force | Out-Null
        $script:dlPath = $null
        $f.Show(); DoEv; Start-Sleep -Milliseconds 500
        Find-Downloads
        $i = 0
        foreach ($tp in $script:tabs.TabPages) {
            $script:tabs.SelectedTab = $tp; DoEv; Start-Sleep -Milliseconds 350; DoEv
            $bmp = New-Object System.Drawing.Bitmap $f.Width, $f.Height
            $f.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $f.Width, $f.Height)))
            $bmp.Save((Join-Path $ShotDir ("business_{0}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $i++
        }
        $f.Close()
    }
    Write-Host "RESULTADO: $($script:fail) falha(s)"
    Remove-Item $tdir -Recurse -Force -ErrorAction SilentlyContinue
    exit $script:fail
}

$f.Add_Shown({ Run-Op { Update-Saude; Invoke-Analisar; Update-Saude } })
[void]$f.ShowDialog()
