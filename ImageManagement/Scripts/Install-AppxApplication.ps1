[CmdletBinding()]
param
(
    [parameter()]
    [string]$WorkingPath = "C:\AppDeployment",

    [parameter(ParameterSetName = 'Manifest', Position = 1)]
    [string]$AppInstallerLocation
)

Begin {
    $date = get-date -format [yyyy-MM-dd_mm:ss]-
    $date = $date.ToString()
    if (-not(Test-Path $WorkingPath)) {
        New-Item -ItemType Directory -Path $WorkingPath
    }   
   

    try {
        if ($AppInstallerLocation.Contains('raw.githubusercontent.com')) {
            Write-Verbose "Raw GitHub content provided"
            $repoPath = ($AppInstallerLocation -split $($AppInstallerLocation -split "/")[5])[-1] 
        }
        else {
            Write-Verbose "Human readable GitHub content provided"
            $repoPath = ($AppInstallerLocation -split $($AppInstallerLocation -split "/")[6])[-1]
        }
        $arguments = 'https://api.github.com/repos/{3}/{4}/contents' -f ($AppInstallerLocation -split "/") + [string]$repoPath
        $request = Invoke-WebRequest -Uri $($arguments) -UseBasicParsing:$true
        $content = $request.Content | ConvertFrom-Json
        $files = $content | Where-Object { $_.type -eq "file" } | Select-Object download_url, name
        try {
            $files.download_url -match '.appinstaller$'
            $appName = ($files | Where-Object { $_.name -match '.appinstaller$' }).Name.Split(".")[0] 
        }
        catch {
            throw "Location has no appinstaller file"
        }
        Write-Information "Downloading files"
    }
    catch {
        Write-Error "Location not found!!"
        break
    }

    if (-not(Test-Path (Join-Path -Path $WorkingPath -ChildPath $AppName))) {
        $AppWorkingPath = (New-Item -ItemType Directory -Path (Join-Path -Path $WorkingPath -ChildPath 'MSIX')).FullName
    }
    else {
        $AppWorkingPath = Join-Path -Path $WorkingPath -ChildPath 'MSIX'
    }
}
Process {
    $templateFilePath = (New-Item -ItemType Directory -Path (Join-Path -Path $AppWorkingPath -ChildPath $appName)).FullName
    $logFile = Join-Path -Path $AppWorkingPath -ChildPath 'install.log'
    $files | ForEach-Object {
        $requestParams = @{
            Uri             = $_.Download_url
            OutFile         = Join-Path -Path $templateFilePath -ChildPath $_.Name
            UseBasicParsing = $true
            Headers         = @{"Cache-Control" = "no-cache" }
        }
        Invoke-WebRequest @requestParams
        Write-Output "Downloaded file $($_.Name)" | Out-File $logFile -Append
    }
    $appInstallerFile = Get-ChildItem -Path $templateFilePath | Where { $_.Name.Endswith('.appinstaller') } | Sort-Object | Select-Object -Last 1

    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        if (-not (Get-Module -Name Appx -ListAvailable )) {
            Install-Module -Name AppX -Force
            Import-Module Appx -usewindowspowershell
            Write-Output "Installing application based on $appInstallerFile" | Out-File $logFile -Append
            $appInstallerFile | Add-AppPackage 
        }
    }
    catch {
        Throw "Install AppX module failed"
    }
 
}