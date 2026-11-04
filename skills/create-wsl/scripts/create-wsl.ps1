#Requires -Version 5.1
<#
.SYNOPSIS
    创建并注册新的 WSL Debian 发行版，并验证默认用户。

.DESCRIPTION
    按顺序把用户名、密码、密码三行写入一次性临时目录，
    由 cmd 以文件重定向方式作为 `wsl.exe --install --name <Name> -d Debian` 的标准输入；
    安装结束后删除临时目录并校验删除结果，再验证发行版是否注册、是否为 WSL 2、默认用户是否与 -User 一致。

    初始账号通过 cmd 文件重定向传入，不依赖交互式输入，并返回明确的退出码。

    脚本内置固定看门狗（不作为参数）：
      - 在线列表检查 120 秒；
      - 安装过程 900 秒。
    超时即终止对应进程，并按失败返回结构化信息。

    退出码：
      0  安装并验证成功
      2  校验失败：参数非法、名称冲突、WSL 不可用、在线列表获取失败（kind= 区分）
      3  安装失败：network / permission / timeout / other（kind= 区分）
      4  安装后验证或收尾失败（kind=verify reason= 区分）

.PARAMETER Name
    发行版名称，默认当天 yyyyMMdd。必须唯一，只允许字母、数字、点、下划线、短横线。

.PARAMETER User
    Linux 用户名，默认 u<当天日期>。必须符合 Linux 用户名规则，且不能是 root。

.PARAMETER Pass
    初始密码，默认当天日期。密码只写入临时目录，不输出到标准输出。

.EXAMPLE
    & .\create-wsl.ps1 -Name 20261105 -User u20261105 -Pass 20261105

.EXAMPLE
    & .\create-wsl.ps1 -Name dev-box -User dev -Pass 'change-me-later'
#>
[CmdletBinding()]
param(
    [string]$Name,
    [string]$User,
    [string]$Pass
)

$ErrorActionPreference = 'Stop'

$script:Today = Get-Date -Format 'yyyyMMdd'
$Distro = 'Debian'
$script:OnlineCheckTimeoutSec = 120
$script:InstallTimeoutSec = 900
$script:LeakedDirs = @()

function Write-Line {
    param([string]$Text)
    [Console]::Out.WriteLine($Text)
}

function Fail {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("[ERROR] $Message")
    if ($script:LeakedDirs.Count -gt 0) {
        [Console]::Error.WriteLine("[ERROR] credentialsDir=deleteFailed dirs=" + ($script:LeakedDirs -join ','))
    }
    exit $Code
}

function Exit-WithCleanup {
    param([int]$Code)
    # 所有非 0 退出前统一报告临时目录清理状态，避免删除失败被静默吞掉。
    if ($script:LeakedDirs.Count -gt 0) {
        Write-Line ("[ERROR] credentialsDir=deleteFailed dirs=" + ($script:LeakedDirs -join ','))
    }
    exit $Code
}

function Read-CapturedText {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) {
        return ''
    }
    # wsl.exe 不同子命令的输出编码不一致：--version/-l/-l -o 为 UTF-16LE，管道输出为 UTF-8。
    $oddNulls = 0
    for ($i = 1; $i -lt $bytes.Length; $i += 2) {
        if ($bytes[$i] -eq 0) { $oddNulls++ }
    }
    if ($oddNulls -gt [Math]::Floor($bytes.Length / 4)) {
        $text = [System.Text.Encoding]::Unicode.GetString($bytes)
    }
    else {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    return (($text -replace "`0", '') -replace "`r`n", "`n").Trim()
}

function Get-TailLines {
    param([string]$Text, [int]$Count = 30)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $lines = @($Text -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    if ($lines.Count -le $Count) { return ($lines -join "`n") }
    return (($lines | Select-Object -Last $Count) -join "`n")
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$StandardInputContent,
        [int]$TimeoutSeconds = 0
    )

    # 所有中间文件都放在一个随机临时目录里，结束后整体删除并校验，
    # 避免密码文件、批处理文件和输出文件残留；删除失败会记录到 $script:LeakedDirs。
    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-create-wsl-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    $batchFile = Join-Path $workDir 'run.cmd'
    $stdoutFile = Join-Path $workDir 'stdout.txt'
    $stderrFile = Join-Path $workDir 'stderr.txt'
    $process = $null

    try {
        # 只给路径加引号；wsl.exe 会把带引号的参数当作要在 Linux 内执行的命令行。
        # 其余参数均已做字符集校验，不包含空格或 cmd 特殊字符。
        $quotedExe = '"' + ($FilePath -replace '"', '""') + '"'
        $commandLine = (@($quotedExe) + $Arguments) -join ' '

        if (-not [string]::IsNullOrEmpty($StandardInputContent)) {
            $stdinFile = Join-Path $workDir 'stdin.txt'
            [System.IO.File]::WriteAllText($stdinFile, $StandardInputContent, [System.Text.UTF8Encoding]::new($false))
            $commandLine += ' < "' + $stdinFile + '"'
        }
        $commandLine += ' > "' + $stdoutFile + '" 2> "' + $stderrFile + '"'

        $batchContent = "@echo off`r`n$commandLine`r`nexit /b %errorlevel%`r`n"
        [System.IO.File]::WriteAllText($batchFile, $batchContent, [System.Text.Encoding]::ASCII)

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = "$env:ComSpec"
        $startInfo.Arguments = '/d /c ""' + $batchFile + '""'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()

        if ($TimeoutSeconds -gt 0) {
            $finished = $process.WaitForExit($TimeoutSeconds * 1000)
        }
        else {
            $process.WaitForExit()
            $finished = $true
        }

        if (-not $finished) {
            try {
                & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>&1 | Out-Null
            }
            catch {
                try { $process.Kill() } catch { }
            }
            try { [void]$process.WaitForExit(5000) } catch { }
            return [pscustomobject]@{
                ExitCode = -1
                TimedOut = $true
                StdOut   = Read-CapturedText $stdoutFile
                StdErr   = Read-CapturedText $stderrFile
            }
        }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            TimedOut = $false
            StdOut   = Read-CapturedText $stdoutFile
            StdErr   = Read-CapturedText $stderrFile
        }
    }
    finally {
        if ($process) {
            try { $process.Dispose() } catch { }
        }
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $workDir) {
            Start-Sleep -Milliseconds 200
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $workDir) {
            $script:LeakedDirs += $workDir
        }
    }
}

function Get-DistroNames {
    param([Parameter(Mandatory = $true)][string]$WslPath)
    $result = Invoke-CapturedProcess -FilePath $WslPath -Arguments @('-l', '-q') -TimeoutSeconds 30
    if ($result.TimedOut -or $result.ExitCode -ne 0) {
        Fail 2 ("kind=list-unreadable exitCode={0} detail={1}" -f $result.ExitCode, (Get-TailLines ($result.StdOut + "`n" + $result.StdErr) 10))
    }
    return @(
        $result.StdOut -split "`r?`n" |
            ForEach-Object { $_.Trim().TrimStart([char]0xFEFF) } |
            Where-Object { $_ -ne '' }
    )
}

function Get-DistroFacts {
    param(
        [Parameter(Mandatory = $true)][string]$WslPath,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $facts = [pscustomobject]@{
        Registered = 'unknown'
        State      = 'unknown'
        WslVersion = 'unknown'
    }
    $verbose = Invoke-CapturedProcess -FilePath $WslPath -Arguments @('-l', '-v') -TimeoutSeconds 30
    if ($verbose.TimedOut -or $verbose.ExitCode -ne 0) {
        return $facts
    }
    $matched = $false
    foreach ($line in ($verbose.StdOut -split "`r?`n")) {
        if ($line -match ('^\s*\*?\s*' + [regex]::Escape($Name) + '\s')) {
            $matched = $true
            $tokens = @($line.Trim() -split '\s+' | Where-Object { $_ -ne '' })
            if ($tokens.Count -ge 2) { $facts.State = $tokens[$tokens.Count - 2] }
            if ($tokens.Count -ge 1) { $facts.WslVersion = $tokens[$tokens.Count - 1] }
            break
        }
    }
    $facts.Registered = if ($matched) { 'yes' } else { 'no' }
    return $facts
}

function Get-InstallFailureKind {
    param([string]$Text)
    if ($Text -match '(?i)(0x80072e|WU_E|connection|connect|network|timed?\s*out|timeout|连接|网络|下载)') {
        return 'network'
    }
    if ($Text -match '(?i)(0x80070005|access is denied|permission denied|拒绝访问|administrator|管理员|elevat|权限)') {
        return 'permission'
    }
    return 'other'
}

function Test-OnlineDebian {
    param([Parameter(Mandatory = $true)][string]$WslPath)
    $result = Invoke-CapturedProcess -FilePath $WslPath -Arguments @('-l', '-o') -TimeoutSeconds $script:OnlineCheckTimeoutSec
    if ($result.TimedOut) {
        Fail 2 ("kind=network online-list=timeout timeoutSec={0}" -f $script:OnlineCheckTimeoutSec)
    }
    if ($result.ExitCode -ne 0) {
        Fail 2 ("kind=network online-list=failed exitCode={0} detail={1}" -f $result.ExitCode, (Get-TailLines ($result.StdOut + "`n" + $result.StdErr) 5))
    }
    $text = $result.StdOut + "`n" + $result.StdErr
    $available = @()
    foreach ($line in ($text -split "`r?`n")) {
        $trim = $line.Trim()
        if ($trim -eq '') { continue }
        if ($trim -match '^NAME\b') { continue }
        if ($trim -notmatch '^[A-Za-z0-9]') { continue }
        $available += ($trim -split '\s+')[0]
    }
    $hasDebian = @($available | Where-Object { $_ -ieq 'Debian' }).Count -gt 0
    if (-not $hasDebian) {
        if ($available.Count -eq 0) {
            Fail 2 'kind=network online-list=unparsed detail=在线列表输出无法解析'
        }
        Fail 2 ("kind=distro-missing available={0}" -f ($available -join ','))
    }
    Write-Line '[INFO] onlineCheck=ok distro=Debian'
}

# ---- 默认值与参数校验 ----------------------------------------------------

$passwordWasProvided = -not [string]::IsNullOrWhiteSpace($Pass)

if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $script:Today }
if ([string]::IsNullOrWhiteSpace($User)) { $User = "u$($script:Today)" }
if ([string]::IsNullOrWhiteSpace($Pass)) { $Pass = $script:Today }

if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    Fail 2 ("kind=param check=name value='{0}'；只允许字母、数字、点、下划线、短横线，且以字母或数字开头。" -f $Name)
}
if ($User -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
    Fail 2 ("kind=param check=user value='{0}'；需以小写字母或下划线开头，只含小写字母、数字、下划线、短横线，最长 32 字符。" -f $User)
}
if ($User -eq 'root') {
    Fail 2 'kind=param check=user value=root；Linux 用户名不能是 root。'
}
if ($Pass.Length -eq 0 -or $Pass -match "[\r\n`0]") {
    Fail 2 'kind=param check=pass；密码不能为空，且不能包含换行或 NUL 字符。'
}

# ---- 环境校验 ------------------------------------------------------------

$wslCommand = Get-Command -Name 'wsl.exe' -ErrorAction SilentlyContinue
if (-not $wslCommand) {
    Fail 2 'kind=wsl-missing；未找到 wsl.exe，请先安装 WSL 2。'
}
$wslPath = $wslCommand.Source
if ([string]::IsNullOrEmpty($wslPath)) { $wslPath = $wslCommand.Path }

$versionResult = Invoke-CapturedProcess -FilePath $wslPath -Arguments @('--version') -TimeoutSeconds 30
if ($versionResult.TimedOut -or $versionResult.ExitCode -ne 0) {
    Fail 2 ("kind=wsl-version exitCode={0}；无法获取 WSL 版本，请确认已安装 WSL 2。" -f $versionResult.ExitCode)
}
$versionText = $versionResult.StdOut
if ($versionText -notmatch 'WSL') {
    Fail 2 ("kind=wsl-version detail=无法识别版本输出：{0}" -f (Get-TailLines $versionText 5))
}
$versionNumber = 'unknown'
if ($versionText -match '(\d+\.\d+(?:\.\d+){0,2})') {
    $versionNumber = $Matches[1]
}
if ($versionText -match 'WSL\D*(\d+)\.') {
    if ([int]$Matches[1] -lt 2) {
        Fail 2 ("kind=wsl-version actual={0} required=2；请运行 wsl --update 后重试。" -f $versionNumber)
    }
}

$helpResult = Invoke-CapturedProcess -FilePath $wslPath -Arguments @('--help') -TimeoutSeconds 30
# wsl --help 的退出码不稳定（本机返回 -1），只按输出是否包含 --name 判断支持性。
if ($helpResult.TimedOut -or $helpResult.StdOut -notmatch '--name') {
    Fail 2 'kind=wsl-unsupported；当前 WSL 不支持 `wsl --install --name`，请运行 wsl --update 更新后重试。'
}

$existingNames = Get-DistroNames -WslPath $wslPath
$conflict = $existingNames | Where-Object { $_ -ieq $Name } | Select-Object -First 1
if ($conflict) {
    Fail 2 ("kind=name-conflict name={0} existing={1}" -f $Name, ($existingNames -join ','))
}

# 在线列表检查：固定 120 秒看门狗，确认可获取且包含 Debian。
Test-OnlineDebian -WslPath $wslPath

$passwordIsWeak = $Pass -eq $script:Today

$installArguments = @('--install', '--name', $Name, '-d', $Distro)

# ---- 执行安装（固定 900 秒看门狗） ---------------------------------------

Write-Line ("[INFO] install=start name={0} distro={1}" -f $Name, $Distro)

$installResult = Invoke-CapturedProcess `
    -FilePath $wslPath `
    -Arguments $installArguments `
    -StandardInputContent ("{0}`n{1}`n{1}`n" -f $User, $Pass) `
    -TimeoutSeconds $script:InstallTimeoutSec

if ($installResult.TimedOut) {
    $facts = Get-DistroFacts -WslPath $wslPath -Name $Name
    Write-Line ("[ERROR] kind=timeout timeoutSec={0}" -f $script:InstallTimeoutSec)
    Write-Line ("[ERROR] facts registered={0} state={1} wslVersion={2}" -f $facts.Registered, $facts.State, $facts.WslVersion)
    Exit-WithCleanup 3
}

if ($installResult.ExitCode -ne 0) {
    $combined = $installResult.StdOut + "`n" + $installResult.StdErr
    $kind = Get-InstallFailureKind $combined
    $facts = Get-DistroFacts -WslPath $wslPath -Name $Name
    Write-Line ("[ERROR] kind={0} installExitCode={1}" -f $kind, $installResult.ExitCode)
    Write-Line ("[ERROR] facts registered={0} state={1} wslVersion={2}" -f $facts.Registered, $facts.State, $facts.WslVersion)
    $detail = Get-TailLines $combined 30
    if ($detail) { Write-Line $detail }
    Exit-WithCleanup 3
}

# ---- 验证 ----------------------------------------------------------------

$facts = Get-DistroFacts -WslPath $wslPath -Name $Name

if ($facts.Registered -ne 'yes') {
    Write-Line '[ERROR] kind=verify reason=name-not-registered'
    Write-Line ("[ERROR] facts registered={0} state={1} wslVersion={2}" -f $facts.Registered, $facts.State, $facts.WslVersion)
    Exit-WithCleanup 4
}

if ($facts.State -eq 'unknown' -or $facts.WslVersion -eq 'unknown') {
    Write-Line '[ERROR] kind=verify reason=state-unparsed'
    Write-Line ("[ERROR] facts registered={0} state={1} wslVersion={2}" -f $facts.Registered, $facts.State, $facts.WslVersion)
    Exit-WithCleanup 4
}

if ($facts.WslVersion -ne '2') {
    Write-Line ("[ERROR] kind=verify reason=wsl-version expected=2 actual={0}" -f $facts.WslVersion)
    Write-Line ("[ERROR] facts registered={0} state={1} wslVersion={2}" -f $facts.Registered, $facts.State, $facts.WslVersion)
    Exit-WithCleanup 4
}

$idResult = Invoke-CapturedProcess -FilePath $wslPath -Arguments @('-d', $Name, '--', 'id', '-un') -TimeoutSeconds 120
$actualUser = ''
foreach ($line in ($idResult.StdOut -split "`r?`n")) {
    if ($line.Trim() -ne '') { $actualUser = $line.Trim() }
}
if ($idResult.TimedOut -or $idResult.ExitCode -ne 0 -or $actualUser -ne $User) {
    Write-Line ("[ERROR] kind=verify reason=default-user expected={0} actual={1} idExitCode={2}" -f $User, $actualUser, $idResult.ExitCode)
    Write-Line ("[ERROR] facts registered={0} state={1} wslVersion={2}" -f $facts.Registered, $facts.State, $facts.WslVersion)
    $detail = Get-TailLines ($idResult.StdOut + "`n" + $idResult.StdErr) 10
    if ($detail) { Write-Line $detail }
    Exit-WithCleanup 4
}

if ($script:LeakedDirs.Count -gt 0) {
    Write-Line ("[ERROR] kind=verify reason=cleanup-failed dirs={0}" -f ($script:LeakedDirs -join ','))
    Write-Line ("[ERROR] facts registered={0} state={1} wslVersion={2}" -f $facts.Registered, $facts.State, $facts.WslVersion)
    exit 4
}

# ---- 成功输出 ------------------------------------------------------------

Write-Line "[OK] name=$Name"
Write-Line "[OK] distro=$Distro"
Write-Line ("[OK] wslVersion={0} state={1}" -f $facts.WslVersion, $facts.State)
Write-Line "[OK] defaultUser=$actualUser"
Write-Line "[OK] verify=wsl.exe -d $Name -- id -un"
Write-Line "[OK] enter=wsl.exe -d $Name"
if ($passwordWasProvided) {
    Write-Line '[INFO] passwordSource=provided'
}
else {
    Write-Line '[INFO] passwordSource=default-date'
}
if ($passwordIsWeak) {
    Write-Line "[WARN] 密码等于当天日期（弱密码）；修改：wsl.exe -d $Name -u root passwd $User"
}
Write-Line '[OK] credentialsFile=deleted'
exit 0
