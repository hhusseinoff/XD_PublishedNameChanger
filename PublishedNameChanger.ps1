function debug($message)
{
    write-host "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" -BackgroundColor Black -ForegroundColor Green
    Add-Content -Path "$PSScriptRoot\VerboseLogs\SAC_DesktopNameChanger.log" -Value "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" 
}

function debug_FailSkip([string]$Type,[string]$Reason,[string]$DCName,[string]$PublishedName,[string]$XDGroupName,[string]$XDController)
{
    $FileExists = Test-Path -Path "$PSScriptRoot\FailSkipLogs\SAC_DesktopNameChangerFails.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$PSScriptRoot\FailSkipLogs\SAC_DesktopNameChangerFails.txt" -Value "--Timestamp(UTC)--`tType`tReason`tMachine Name`tPublished Name`tXD Group name`tXD Controller" 
    }

    Add-Content -Path "$PSScriptRoot\FailSkipLogs\SAC_DesktopNameChangerFails.txt" -Value "$($(Get-Date).ToUniversalTime())`t$Type`t$Reason`t$DCName`t$PublishedName`t$XDGroupName`t$XDController" 
}

function debug_Success([string]$DCName,[string]$NewPublishedName,[string]$XDGroupName,[string]$XDController)
{
    $FileExists = Test-Path -Path "$PSScriptRoot\SuccessLogs\SAC_DesktopNameChangerSuccess.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$PSScriptRoot\SuccessLogs\SAC_DesktopNameChangerSuccess.txt" -Value "--Timestamp(UTC)--`tMachine Name`tNew Published Name`tXD Group name`tXD Controller" 
    }

    Add-Content -Path "$PSScriptRoot\SuccessLogs\SAC_DesktopNameChangerSuccess.txt" -Value "$($(Get-Date).ToUniversalTime())`t$DCName`t$NewPublishedName`t$XDGroupName`t$XDController" 
}

##Create Log folders at the script root if they dont exist
##---------------------------------------------------------------------------------------------------------------------------------
$VerboseLogsFolderExists = Test-path -Path "$PSScriptRoot\VerboseLogs" -PathType Container

if($false -eq $VerboseLogsFolderExists)
{
    New-Item -Path "$PSScriptRoot" -Name "VerboseLogs" -ItemType Directory -Force -Confirm:$false -ErrorAction Stop | Out-Null
}

$SuccessLogsFolderExists = Test-path -Path "$PSScriptRoot\SuccessLogs" -PathType Container

if($false -eq $SuccessLogsFolderExists)
{
    New-Item -Path "$PSScriptRoot" -Name "SuccessLogs" -ItemType Directory -Force -Confirm:$false -ErrorAction Stop | Out-Null
}

$FailSkiLogsFolderExists = Test-path -Path "$PSScriptRoot\FailSkipLogs" -PathType Container

if($false -eq $FailSkiLogsFolderExists)
{
    New-Item -Path "$PSScriptRoot" -Name "FailSkipLogs" -ItemType Directory -Force -Confirm:$false -ErrorAction Stop | Out-Null
}

##Check if input file exists. If Not, script will not run
##---------------------------------------------------------------------------------------------------------------------------------

$InputExists = Test-Path -Path "$PSScriptRoot\XD_Name_MappingEU_E2.txt" -PathType Leaf

if($false -eq $InputExists)
{
    debug "Script will not run. Input file not found!"

    Exit 1
}

debug "------SAC Assignment script by Señor José Garcia initiated------"

debug "Loading input file..."

$InputData = (Get-Content -Path "$PSScriptRoot\XD_Name_MappingEU_E2.txt")

if($null -eq $InputData)
{
    debug "Script will not run. Input file failed to load!"
}

##Delete Non-Verbose Logs from Last run (will interfere, causing double, triple assignment)
##---------------------------------------------------------------------------------------------------------------------------------

$Phase1FailLogExists = Test-Path -Path "$PSScriptRoot\FailSkipLogs\SAC_DesktopNameChangerFails.txt" -PathType Leaf

if($true -eq $Phase1FailLogExists)
{
    Remove-Item -Path "$PSScriptRoot\FailSkipLogs\SAC_DesktopNameChangerFails.txt" -Force -Confirm:$false
}

$Phase1SuccessogExists = Test-Path -Path "$PSScriptRoot\SuccessLogs\SAC_DesktopNameChangerSuccess.txt" -PathType Leaf

if($true -eq $Phase1FailLogExists)
{
    Remove-Item -Path "$PSScriptRoot\SuccessLogs\SAC_DesktopNameChangerSuccess.txt" -Force -Confirm:$false
}

##---------------------------------------------------------------------------------------------------------------------------------

debug "Input File loaded"


:MainLoop foreach($Entry in $InputData)
{
    if($Entry -like "*Abbreviation*")
    {
        continue MainLoop
    }

    debug "Working on $Entry"

    $FragmentedArray = $Entry.Split("`t")

    $ExtractedRegion = $FragmentedArray[0]
    $ExtractedAbbreviation = $FragmentedArray[1]
    $ExtractedXD_DG = $FragmentedArray[2]
    $ExtractedXD_Controller = $FragmentedArray[3]

    debug "Extracted Region: $ExtractedRegion"
    debug "Extracted OE Abbreviation: $ExtractedAbbreviation"
    debug "Extracted XenDesktop Delivery Group name: $ExtractedXD_DG"
    debug "Extracted XenDesktop Controller for the DG: $ExtractedXD_Controller"

    debug "Getting all machines in $ExtractedXD_DG.."

    $DesktopsArray = Get-BrokerMachine -DesktopGroupName $ExtractedXD_DG -AdminAddress $ExtractedXD_Controller -ErrorAction SilentlyContinue

    if($null -eq $DesktopsArray)
    {
        debug "Failed to retrieve all Desktops in $ExtractedXD_DG"
    }

    debug "Machines Retrieved."

    $StringPart = "22H2 UAT" + " " + $ExtractedAbbreviation

    debug "Constructed last part of the new published name: $StringPart"

    :ChangePublishedNames foreach($DesktopObject in $DesktopsArray)
    {
        $OldPublishedName = $DesktopObject.PublishedName

        $HostedName = $DesktopObject.HostedMachineName

        $FullMachineName = $DesktopObject.MachineName

        debug "Working on $HostedName with a published name of: $OldPublishedName"

        $NewPublishedName = "DC" + " " + $HostedName + " " + $StringPart + " "

        debug "Constructed new published Name: $NewPublishedName"

        debug "Proceeding to set it..."

        Set-BrokerPrivateDesktop -MachineName $FullMachineName -PublishedName $NewPublishedName -ErrorAction SilentlyContinue

        $NewDesktopData = Get-BrokerMachine -HostedMachineName $HostedName -AdminAddress $ExtractedXD_Controller

        $PublishedNameCheck = $NewDesktopData.PublishedName

        if($PublishedNameCheck -eq $NewPublishedName)
        {
            debug "Successfully set $NewPublishedName for $HostedName. Appending success..."

            debug_Success -DCName $HostedName -NewPublishedName $NewPublishedName -XDGroupName $ExtractedXD_DG -XDController $ExtractedXD_Controller

            continue ChangePublishedNames
        }
        else
        {
            debug "Failed to set $NewPublishedName for $HostedName. Appending Fail..."

            debug_FailSkip -Type "Fail" -Reason "Failed to set new Published Name" -DCName $HostedName -PublishedName $NewPublishedName -XDGroupName $ExtractedXD_DG -XDController $ExtractedXD_Controller

            continue ChangePublishedNames
        }
    }


}