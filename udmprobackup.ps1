[cmdletbinding()]
param (
  [Parameter (Mandatory = $true)] [String]$ConfigFilePath
)

$startTime = Get-Date

if (-not(Test-Path -Path $ConfigFilePath -PathType Leaf)) {
  throw "json config file specified at $($ConfigFilePath) does not exist, aborting process"
}

$PowerShellObject=Get-Content -Path $ConfigFilePath | ConvertFrom-Json

if (-not(Test-Path -Path $PowerShellObject.Required.logsDirectory -PathType Container)) {
  throw "log root directory of $($PowerShellObject.Required.logsDirectory) does not exist, aborting process"
}

if (-not(Test-Path -Path $PowerShellObject.Required.udmPasswordFile -PathType Leaf)) {
  throw "secure udm file $($PowerShellObject.Required.udmPasswordFile) does not exist, aborting process"
}

if (-not(Test-Path -Path $PowerShellObject.Required.localBackupDirectory -PathType Container)) {
  throw "local backup path of $($PowerShellObject.Required.localBackupDirectory) does not exist, aborting process"
}


#set up variables
[string] $strExecDir = $PSScriptRoot
[string] $strServerName = $env:computername
[string] $strDetailLogFilePrefix = "udmpro-backup-detail-"
[string] $strLogExtension = ".log"

[uint16] $intDaysToKeepUDMBackups = 0
[uint16] $intDaysToKeepLogFiles = 0

[string] $strUDMUsername = "root"
[string] $strUDMIPHostname = "192.168.1.1"
[string] $strUDMRemoteBackupDirectory = "/data/unifi/data/backup/autobackup"

[bool] $blnSendSMTPErrorReport = $false
[bool] $blnSMTPAuthRequired = $false

if ($PowerShellObject.Optional.daysToKeepUDMBackups) {
  write-host "am I here"
  try {
    $intDaysToKeepUDMBackups = $PowerShellObject.Optional.daysToKeepUDMBackups
    write-host "using what is configured in config for udm backups to keep"
  } catch {
    write-host "defaulting to no backup purge"
  }
}

if ($PowerShellObject.Optional.daysToKeepLogFiles) {
  write-host "am I here"
  try {
    $intDaysToKeepLogFiles = $PowerShellObject.Optional.daysToKeepLogFiles
    write-host "using what is configured in config for log file retention"
  } catch {
    write-host "defaulting to no log file purge"
  }
}

if ($PowerShellObject.Optional.sendEmailError -and $PowerShellObject.Optional.sendEmailError.toLower().equals("true")) {
  if ($PowerShellObject.Optional.smtpServer -and $PowerShellObject.Optional.emailReportRecipient) {
    $blnSendSMTPErrorReport = $true
    write-host "we're sending smtp messages"
    if ($PowerShellObject.Optional.smtpauthrequired) {
      if ($PowerShellObject.Optional.smtpauthrequired.toLower().equals("true")) {
        $blnSMTPAuthRequired = $true
        if ($PowerShellObject.Optional.sendEmailError -AND $PowerShellObject.Optional.sendEmailError -AND (Test-Path -Path $PowerShellObject.Optional.smtpPasswordFile -PathType Leaf)) {
          write-host "smtp auth required and username and password file exist, so proceeding"
        } else {
          write-host "smtp auth required but no smtp username or password file, aborting smtp send"
        }
      }
    }
  } else {
    write-host "we're not sending smtp error messages"
  }
}

if ($PowerShellObject.Optional.udmUsername) {
  $strUDMUsername = $PowerShellObject.Optional.udmUsername
}

if ($PowerShellObject.Optional.udmIPHostname) {
  $strUDMIPHostname = $PowerShellObject.Optional.udmIPHostname
}

if ($PowerShellObject.Optional.udmRemoteBackupDirectory) {
  $strUDMRemoteBackupDirectory = $PowerShellObject.Optional.udmRemoteBackupDirectory
}

[string] $strTimeStamp = $(get-date -f yyyy-MM-dd-hh_mm_ss)

[int] $intErrorCount = 0
$arrStrErrors = @()

[string] $strDetailLogFilePath = $PowerShellObject.Required.logsDirectory + "\" + $strDetailLogFilePrefix + $strTimeStamp + $strLogExtension

#clear all errors before starting
$error.Clear()

$objDetailLogFile = [System.IO.StreamWriter] $strDetailLogFilePath

#********************************************************************************
#functions
#********************************************************************************
#function to write log file
Function LogWrite($objLogFile, [string]$strLogstring)
{  
  write-host $strLogstring
  $objLogFile.writeline($strLogstring)
  $objLogFile.flush()
}



LogWrite $objDetailLogFile "$(get-date) Info: Beginning process to backup UDM Pro via scp at $($strUDMIPHostname) with $($strUDMUsername), copying $($strUDMRemoteBackupDirectory) to $($PowerShellObject.Required.localBackupDirectory)"

try {
	LogWrite $objDetailLogFile "$(get-date) Info: Building credential"
	#$objPassword = ConvertTo-SecureString $strUDMProPassword -AsPlainText -Force
  $objPassword = Get-Content $PowerShellObject.Required.udmPasswordFile | ConvertTo-SecureString
	$objCredential = New-Object System.Management.Automation.PSCredential ($strUDMUsername, $objPassword)
	LogWrite $objDetailLogFile "$(get-date) Info: Backing up UDM Pro..."
	Get-SCPItem -AcceptKey -ComputerName $strUDMIPHostname -Credential $objCredential -Path $strUDMRemoteBackupDirectory -PathType Directory -Destination $PowerShellObject.Required.localBackupDirectory
	LogWrite $objDetailLogFile "$(get-date) Info: Successfully backed up UDM Pro"
} catch {
	$ErrorMessage = $_.Exception.Message
	$line = $_.InvocationInfo.ScriptLineNumber
	$arrStrErrors += "Failed to connect to UDM Pro at $($strUDMIPHostname) with $($strUDMUsername), copying $($strUDMRemoteBackupDirectory) to $($PowerShellObject.Required.localBackupDirectory) at $($line) with the following error: $ErrorMessage"
	LogWrite $objDetailLogFile "$(get-date) Error: Failed to connect to UDM Pro at $($strUDMIPHostname) with $($strUDMUsername), copying $($strUDMRemoteBackupDirectory) to $($PowerShellObject.Required.localBackupDirectory) at $($line) with the following error: $ErrorMessage"
}

if ($blnSendSMTPErrorReport -eq $true) {
  [int] $intErrorCount = $arrStrErrors.Count
  if ($intErrorCount -gt 0) {
    LogWrite $objDetailLogFile "$(get-date) Info: Encountered $intErrorCount errors, sending error report email"
  
    #loop through all errors and add them to email body
    foreach ($strErrorElement in $arrStrErrors) {
    $intErrorCounter = $intErrorCounter + 1
    $strEmailBody = $strEmailBody + $intErrorCounter.toString() + ") " + $strErrorElement + "`n"
    }
    $strEmailBody = $strEmailBody + "`n`nPlease see $strDetailLogFilePath on $strServerName for more details"
    if ($blnSMTPAuthRequired -eq $true) {
      #$objSMTPPassword = ConvertTo-SecureString $strSMTPPassword -AsPlainText -Force
      $objPassword = Get-Content $PowerShellObject.Optional.smtpPasswordFile | ConvertTo-SecureString
      $objSMTPCredential = New-Object System.Management.Automation.PSCredential ($PowerShellObject.Optional.smtpUsername, $objPassword)
      send-MailMessage -From $PowerShellObject.Optional.smtpUsername -To $PowerShellObject.Optional.emailReportRecipient -SmtpServer $PowerShellObject.Optional.smtpServer -Subject "<<UDM Pro Backup>> Errors during process" -Body $strEmailBody  -UseSsl -Port 587 -Credential $objSMTPCredential
    } else {
      send-MailMessage -From $PowerShellObject.Optional.smtpUsername -To $PowerShellObject.Optional.emailReportRecipient -SmtpServer $PowerShellObject.Optional.smtpServer -Subject "<<UDM Pro Backup>> Errors during process" -Body $strEmailBody  -UseSsl -Port 587
    }
  }
}
LogWrite $objDetailLogFile "$(get-date) Info: Process Complete"

$objDetailLogFile.close()
