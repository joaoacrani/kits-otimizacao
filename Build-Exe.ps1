# Build-Exe.ps1 - gera dist\Kit-Personal.exe e dist\Kit-Business.exe
# Nao baixa nada: usa o compilador C# (csc.exe) que ja vem com o Windows (.NET Framework 4).
# Cada .exe embute o .ps1 correspondente, extrai para %LOCALAPPDATA%\<Kit>\app e abre sem janela de console.
# Depois de editar um .ps1, rode este script de novo:  powershell -ExecutionPolicy Bypass -File .\Build-Exe.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item $dist -ItemType Directory -Force | Out-Null

$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe (.NET Framework 4) nao encontrado neste PC.' }

$template = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

static class Launcher
{
    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "__FOLDER__", "app");
            Directory.CreateDirectory(dir);
            string ps1 = Path.Combine(dir, "__SCRIPT__");
            byte[] data;
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("KitScript"))
            using (MemoryStream ms = new MemoryStream())
            {
                s.CopyTo(ms);
                data = ms.ToArray();
            }
            bool write = true;
            if (File.Exists(ps1))
            {
                byte[] cur = File.ReadAllBytes(ps1);
                if (cur.Length == data.Length)
                {
                    write = false;
                    for (int i = 0; i < cur.Length; i++) { if (cur[i] != data[i]) { write = true; break; } }
                }
            }
            if (write) File.WriteAllBytes(ps1, data);

            StringBuilder sb = new StringBuilder("-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + ps1 + "\"");
            foreach (string a in args)
            {
                if (a.IndexOf(' ') >= 0) sb.Append(" \"" + a.Replace("\"", "\\\"") + "\"");
                else sb.Append(" " + a);
            }
            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", sb.ToString());
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            // evita herdar PSModulePath de outro PowerShell (ex.: PowerShell 7), que quebra modulos do Windows PowerShell 5.1
            psi.EnvironmentVariables.Remove("PSModulePath");
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Nao foi possivel iniciar o __TITLE__:\n\n" + ex.Message, "__TITLE__", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
'@

function New-Ico($path, $hex, $letter) {
    $bmp = New-Object System.Drawing.Bitmap 64, 64
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)
    $br = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($hex))
    $g.FillEllipse($br, 1, 1, 61, 61)
    $font = New-Object System.Drawing.Font('Segoe UI', 32, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString($letter, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 2, 64, 64)), $sf)
    $g.Dispose()
    $ico = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $fs = [System.IO.File]::Create($path); $ico.Save($fs); $fs.Close(); $bmp.Dispose()
}

$tmp = Join-Path $env:TEMP ('kitbuild_' + [guid]::NewGuid().ToString('N'))
New-Item $tmp -ItemType Directory | Out-Null
try {
    $apps = @(
        @{ Name = 'Kit-Personal'; Title = 'Kit Personal'; Folder = 'KitPersonal'; Color = '#C8283C'; Letter = 'P' },
        @{ Name = 'Kit-Business'; Title = 'Kit Business'; Folder = 'KitBusiness'; Color = '#003E7D'; Letter = 'B' }
    )
    foreach ($a in $apps) {
        $script = Join-Path $root ($a.Name + '.ps1')
        if (-not (Test-Path $script)) { throw "Nao encontrei $script" }
        $cs = Join-Path $tmp ($a.Name + '.cs')
        $src = $template.Replace('__FOLDER__', $a.Folder).Replace('__SCRIPT__', ($a.Name + '.ps1')).Replace('__TITLE__', $a.Title)
        [System.IO.File]::WriteAllText($cs, $src, (New-Object System.Text.UTF8Encoding($false)))
        $ico = Join-Path $tmp ($a.Name + '.ico'); New-Ico $ico $a.Color $a.Letter
        $exe = Join-Path $dist ($a.Name + '.exe')
        if (Test-Path $exe) { Remove-Item $exe -Force }
        $out = & $csc /nologo /target:winexe /optimize+ "/out:$exe" "/win32icon:$ico" /reference:System.Windows.Forms.dll "/resource:$script,KitScript" $cs 2>&1
        if (-not (Test-Path $exe)) { throw "Falha ao compilar $($a.Name):`n$($out | Out-String)" }
        Write-Host ("OK  {0}  ({1:N0} KB)" -f $exe, ((Get-Item $exe).Length / 1KB))
    }
}
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
