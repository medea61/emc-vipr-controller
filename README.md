PowerShell Wrapper for EMC ViPR Controller
==========================================

Usage
-----
1. You need PowerShell 2.0 or better

2. Enable execution of PowerShell scripts by starting an administratively privileged command prompt and issuing:

        powershell set-executionpolicy unrestricted
    
3. Download vipr.psm1

4. Create a new script or type interactively on PowerShell command prompt:

        Import-Module .\vipr.psm1
        Vipr-Login -viprApiUri https://myViprInstance:4443 -user myUserID -password myPassword
        Vipr-GetHosts
        Vipr-GetTenant
        Vipr-AddHost -hostname myHostname -type Windows
        Vipr-AddInitiator -hostId myHostId -portWwn 10:00:00:00:11:22:33:44
