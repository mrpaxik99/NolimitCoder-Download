# NolimitCoder-Download auto-publish — po každém novém buildu vloží instalátor
# do tohoto repa a pushne ho na github.com/mrpaxik99/NolimitCoder-Download.
#
# Tohle je JEDINÝ zdroj pravdy pro verze:
#   - co tu leží (nejvýše jeden .exe), to se stahuje přes /api/download na webu
#   - a JEN TA verze taky funguje v aplikaci (kontrola přes /api/app-status)
# Když tu verze chybí, aplikace se po instalaci sama nabídne k aktualizaci.
#
# Bezi skryte na pozadi. Spoustec po prihlaseni:
#   Startup\NolimitCoder-Publish.bat
# Log: $env:TEMP\nolimit-publish.log
#
# Test rucne (nepushuje, jen zkontroluje stav):  powershell -File publish.ps1 -Status
# Ruční vypadek jednoho buntu hned:               powershell -File publish.ps1 -Now
param(
  [switch]$Now,     # publishnout hned, necekat na zmenu souboru
  [switch]$Status   # jen vypis stavu, nic nepublikuje
)
$ErrorActionPreference = 'Continue'
$Repo      = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppRoot   = 'D:\DEVELOPER\NolimitCoderV2\NolimitCoder'
$DistDir   = Join-Path $AppRoot 'dist'
$Log       = Join-Path $env:TEMP 'nolimit-publish.log'
$Marker    = Join-Path $env:TEMP 'nolimit-publish-last.txt'   # "|cas" posledniho pushnuteho stavu
$QuietSec  = 20     # push az 20 s po posledni zmene (pocka na dozneni ukladani)
$Branch    = 'main'
$Git       = 'C:\Users\PAXI\Tools\Git\cmd\git.exe'

function Log($m) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $m
  Add-Content -LiteralPath $Log -Value $line
  Write-Output $line
}

# Nejnovější instalátor v distu. Jméno nese verzi ("... Setup 1.1.0.exe"),
# takže podle data je bezpečné brát ten poslední sestavený.
function Find-Setup {
  Get-ChildItem -LiteralPath $DistDir -Filter '*Setup*.exe' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Ver-Of($name) {
  $m = [regex]::Matches([string]$name, '\d+(?:\.\d+)+')
  if ($m.Count -eq 0) { return '' }
  return $m[$m.Count - 1].Value
}

# Z repozitare se vždycky nechá jen JEDEN instalátor — ten nejnovější.
# Starší verze se maže (i z historie pri pushnuti nezbude, jen v aktualnim stavu).
function Keep-Only-Newest($keepName) {
  $exes = Get-ChildItem -LiteralPath $Repo -Filter '*.exe' -ErrorAction SilentlyContinue
  foreach ($e in $exes) {
    if ($e.Name -ne $keepName) {
      Remove-Item -LiteralPath $e.FullName -Force -ErrorAction SilentlyContinue
      Log ('uklid: smazan starsi instalator ' + $e.Name)
    }
  }
  Get-ChildItem -LiteralPath $Repo -Filter '*.blockmap' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

function Publish {
  $exe = Find-Setup
  if (!$exe) { Log 'SKIP: v distu zadne *Setup*.exe'; return }

  $ver   = Ver-Of $exe.Name
  $state = '{0}|{1}' -f $exe.Name, (Get-Date -Format o)
  if (!$ver) { Log ('SKIP: v nazvu "' + $exe.Name + '" neni cislo verze'); return }

  # Uz stejny stav? Nekommituj nasroc.
  if (Test-Path -LiteralPath $Marker) {
    $old = ((Get-Content -LiteralPath $Marker -Raw) + '').Trim()
    $parts = $old -split '\|'
    if ($parts[0] -eq $exe.Name -and (Test-Path -LiteralPath (Join-Path $Repo $exe.Name))) {
      return   # uz tam je, nic se nemenilo
    }
  }

  Log ('publishuji: ' + $exe.Name + ' (verze ' + $ver + ')')
  Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $Repo $exe.Name) -Force
  Keep-Only-Newest $exe.Name

  $msg = 'release: ' + $ver + ' — ' + $exe.Name
  & $Git -C $Repo add -A 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Log 'add FAIL'; return }
  # Chybu nech schválně vyplynout do logu — bez ni se pustina commitu jen mlčky zahodí.
  $cOut = (& $Git -C $Repo commit -m $msg 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) {
    Log ('commit FAIL: ' + (($cOut -replace '\s+', ' ').Trim()))
    return
  }
  $pOut = (& $Git -C $Repo push origin $Branch 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) {
    Log ('push FAIL: ' + (($pOut -replace '\s+', ' ').Trim()))
    return
  }

  Set-Content -LiteralPath $Marker -Value $state
  Log ('push OK: ' + $msg + '  ->  https://github.com/mrpaxik99/NolimitCoder-Download')
}

function Show-Status {
  $exe = Find-Setup
  Write-Output ('dist:      ' + $(if ($exe) { $exe.Name + '  (verze ' + (Ver-Of $exe.Name) + ')' } else { 'zadne *Setup*.exe' }))
  Write-Output ('v repu:    ' + ((Get-ChildItem -LiteralPath $Repo -Filter '*.exe' -ErrorAction SilentlyContinue).Name -join ', '))
  Write-Output ('remote:    ' + ((& $Git -C $Repo remote get-url origin 2>$null) -join ''))
  Write-Output ('log:       ' + $Log)
}

if ($Status) { Show-Status; return }

if ($Now) { Publish; return }   # jednorazove spusteni — po publishi skonci, nebezi done

Log ('watcher start, zdroj=' + $DistDir)

$w = New-Object System.IO.FileSystemWatcher
$w.Path = $DistDir
$w.Filter = '*.exe'
$w.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::Size
$w.EnableRaisingEvents = $true
$lastChange = $null

while ($true) {
  $r = $w.WaitForChanged([System.IO.WatcherChangeTypes]::All, 10000)
  if ($r.TimedOut) {
    if ($lastChange -and ((Get-Date) - $lastChange).TotalSeconds -ge $QuietSec) {
      $lastChange = $null
      Publish
    }
    continue
  }
  # .blockmap se taky generuje, ale nás zajímá jen .exe
  if ($r.Name -and $r.Name -notlike '*Setup*.exe') { continue }
  $lastChange = Get-Date
}