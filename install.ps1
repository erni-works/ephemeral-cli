# Install the ephemeral CLI on Windows (Windows PowerShell 5.1 or PowerShell 7):
#
#   irm https://ephemer.al/install.ps1 | iex
#
# Environment:
#   EPHEMERAL_VERSION        release to install, e.g. v1.2.3 (default: latest)
#   EPHEMERAL_INSTALL_DIR    target directory (default: %LOCALAPPDATA%\Programs\ephemeral\bin)
#   EPHEMERAL_DOWNLOAD_BASE  release repository URL
#                            (default: https://github.com/erni-works/ephemeral-cli)
#
# The archive is verified against the release's checksums.txt before anything
# is installed. The install directory is added to the user PATH; no
# administrator rights are needed.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    function Fail([string]$Message) {
        throw "ephemeral installer: $Message"
    }

    function Get-File([string]$Uri, [string]$Path) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing
        } catch {
            Fail "could not download ${Uri}: $($_.Exception.Message)"
        }
    }

    # Read the tag from the /releases/latest redirect, which needs no GitHub
    # API token and is not rate limited.
    function Get-RedirectLocation([string]$Uri) {
        $params = @{ Uri = $Uri; MaximumRedirection = 0; UseBasicParsing = $true; ErrorAction = 'SilentlyContinue' }
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # Without this, PowerShell 7 throws on the unfollowed redirect.
            $params.SkipHttpErrorCheck = $true
        }
        # Both versions return the redirect response and also report the
        # exceeded redirection limit as a non-terminating error, hence
        # SilentlyContinue rather than Stop.
        try {
            $response = Invoke-WebRequest @params
        } catch {
            # PowerShell 6 throws instead and keeps the response on the exception.
            $response = $_.Exception.Response
        }
        if (-not $response) {
            return ''
        }
        if ($response.GetType().FullName -eq 'System.Net.Http.HttpResponseMessage') {
            return [string]$response.Headers.Location
        }
        return [string](@($response.Headers['Location'])[0])
    }

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        # Windows PowerShell may default to TLS 1.0, which GitHub rejects.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    $base = 'https://github.com/erni-works/ephemeral-cli'
    if ($env:EPHEMERAL_DOWNLOAD_BASE) {
        $base = $env:EPHEMERAL_DOWNLOAD_BASE
    }
    $base = $base.TrimEnd('/')
    if ($env:EPHEMERAL_INSTALL_DIR) {
        $installDir = $env:EPHEMERAL_INSTALL_DIR
    } elseif ($env:LOCALAPPDATA) {
        $installDir = Join-Path $env:LOCALAPPDATA 'Programs\ephemeral\bin'
    } else {
        Fail 'LOCALAPPDATA is not set; set EPHEMERAL_INSTALL_DIR'
    }

    # The operating system's architecture, not that of this possibly emulated
    # PowerShell process.
    try {
        $arch = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    } catch {
        $arch = '' # .NET Framework before 4.7.1
    }
    if (-not $arch) {
        $arch = $env:PROCESSOR_ARCHITECTURE
        if ($env:PROCESSOR_ARCHITEW6432) {
            $arch = $env:PROCESSOR_ARCHITEW6432
        }
    }
    switch ($arch) {
        { $_ -eq 'X64' -or $_ -eq 'AMD64' } { $arch = 'amd64'; break }
        'Arm64' { $arch = 'arm64'; break }
        default { Fail "unsupported architecture '$arch'" }
    }

    if ($env:EPHEMERAL_VERSION) {
        $tag = 'v' + $env:EPHEMERAL_VERSION.TrimStart('v')
    } else {
        $location = Get-RedirectLocation "$base/releases/latest"
        if ($location -notmatch '/releases/tag/([^/?#]+)') {
            Fail "could not determine the latest release from $base/releases/latest; set EPHEMERAL_VERSION"
        }
        $tag = $Matches[1]
    }
    if ($tag -notmatch '^v\d+\.\d+\.\d+([-+][0-9A-Za-z.+-]+)?$') {
        Fail "invalid version '$tag'; use a version like v1.2.3"
    }
    $version = $tag.Substring(1)
    $archive = "ephemeral_${version}_windows_$arch.zip"

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ephemeral-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Host "Downloading ephemeral $version for windows/$arch..."
        $sums = Join-Path $tmp 'checksums.txt'
        $zip = Join-Path $tmp $archive
        Get-File "$base/releases/download/$tag/checksums.txt" $sums
        $expected = ''
        foreach ($line in Get-Content -LiteralPath $sums) {
            $fields = -split $line
            if ($fields.Count -eq 2 -and $fields[1].TrimStart('*') -eq $archive) {
                $expected = $fields[0].ToLowerInvariant()
                break
            }
        }
        if (-not $expected) {
            Fail "release $tag has no build for windows/$arch"
        }
        Get-File "$base/releases/download/$tag/$archive" $zip
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
        if ($actual -ne $expected) {
            Fail "checksum mismatch for $archive (expected $expected, got $actual); nothing was installed"
        }

        $extract = Join-Path $tmp 'extract'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $binary = Join-Path $extract 'ephemeral.exe'
        if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
            Fail "$archive does not contain ephemeral.exe"
        }

        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
        $target = Join-Path $installDir 'ephemeral.exe'
        $old = "$target.old"
        # A running ephemeral.exe cannot be overwritten, but it can be renamed;
        # ephemeral deletes the .old file the next time it starts.
        Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $target) {
            Move-Item -LiteralPath $target -Destination $old -Force
        }
        try {
            Copy-Item -LiteralPath $binary -Destination $target -Force
        } catch {
            if (Test-Path -LiteralPath $old) {
                Move-Item -LiteralPath $old -Destination $target -Force
            }
            Fail "could not install $target`: $($_.Exception.Message)"
        }
        Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    $installed = & $target version
    if ($LASTEXITCODE -ne 0) {
        Fail "installed $target, but it does not run on this system"
    }
    Write-Host "Installed $installed to $target"

    # Add the directory to the user PATH. Read and write the raw registry value
    # so entries such as %USERPROFILE%\bin stay unexpanded.
    $environment = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $userPath = [string]$environment.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $entries = @($userPath -split ';' | Where-Object { $_ })
    $present = $entries | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $installDir.TrimEnd('\') }
    if (-not $present) {
        $environment.SetValue('Path', (($entries + $installDir) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
        # Changing a user variable through .NET broadcasts the settings change,
        # so terminals opened from now on see the new PATH.
        $notify = 'EPHEMERAL_INSTALL_' + [guid]::NewGuid().ToString('N')
        [Environment]::SetEnvironmentVariable($notify, '1', 'User')
        [Environment]::SetEnvironmentVariable($notify, [NullString]::Value, 'User')
        $env:Path = "$env:Path;$installDir"
        Write-Host "Added $installDir to your user PATH. Open a new terminal to use ephemeral there."
    }
    $environment.Close()
    Write-Host ''
    Write-Host 'Get started: ephemeral login'
}
