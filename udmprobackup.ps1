[cmdletbinding()]
param (
  [Parameter (Mandatory = $true)] [String]$ConfigFilePath
)

#if Posh-SSH module can't be loaded, abort process
try {
  import-module -name Posh-SSH
} catch {
  throw "Posh-SSH powershell module cannot be imported, aborting process"
}

#if json config file does not exist, abort process
if (-not(Test-Path -Path $ConfigFilePath -PathType Leaf)) {
  throw "json config file specified at $($ConfigFilePath) does not exist, aborting process"
}

#if config file configured is not json format, abort process.
try {
  $PowerShellObject=Get-Content -Path $ConfigFilePath | ConvertFrom-Json
} catch {
  throw "Config file of $($ConfigFilePath) is not a valid json file, aborting process"
}

#if udm secure password file does not exist, abort process
if (-not(Test-Path -Path $PowerShellObject.Required.udmPasswordFile -PathType Leaf)) {
  throw "secure udm file $($PowerShellObject.Required.udmPasswordFile) does not exist, aborting process"
}

#if backup directory specified for local udm backups does not exist, abort process
if (-not(Test-Path -Path $PowerShellObject.Required.localBackupDirectory -PathType Container)) {
  throw "local backup path of $($PowerShellObject.Required.localBackupDirectory) does not exist, aborting process"
}


#if errorMailSender optoin does not exist in json, abort process
if ($PowerShellObject.Required.errorMailSender) {
  $errorMailSender = $PowerShellObject.Required.errorMailSender
} else {
  throw "errorMailSender does not exist in json config file, aborting process"
}

#if errorMailRecipients option does not exist in json, abort process
if ($PowerShellObject.Required.errorMailRecipients) {
  $errorMailRecipients = $PowerShellObject.Required.errorMailRecipients
} else {
  throw "errorMailRecipients does not exist in json config file, aborting process"
}

#if errorMailTenantID option does not exist in json, abort process
if ($PowerShellObject.Required.errorMailTenantID) {
  $errorMailTenantID = $PowerShellObject.Required.errorMailTenantID
} else {
  throw "errorMailTenantID does not exist in json config file, aborting process"
}

#if errorMailAppID option does not exist in json, abort process
if ($PowerShellObject.Required.errorMailAppID) {
  $errorMailAppID = $PowerShellObject.Required.errorMailAppID
} else {
  throw "errorMailAppID does not exist in json config file, aborting process"
}

#if errorMailSubjectPrefix option does not exist in json, abort process
if ($PowerShellObject.Required.errorMailSubjectPrefix) {
  $errorMailSubjectPrefix = $PowerShellObject.Required.errorMailSubjectPrefix
} else {
  throw "errorMailSubjectPrefix does not exist in json config file, aborting process"
}

#if errorMailPasswordFile option does not exist in json, abort process
if ($PowerShellObject.Required.errorMailPasswordFile) {
  $errorMailPasswordFile = $PowerShellObject.Required.errorMailPasswordFile
} else {
  throw "errorMailPasswordFile does not exist in json config file, aborting process"
}

#set up variables
[string] $strServerName = $env:computername
[bool] $blnWriteToLog = $false
[int] $intErrorCount = 0
$arrStrErrors = @()

#clear all errors before starting
$error.Clear()

[string] $strServerName = $env:computername

[uint16] $intDaysToKeepUDMBackups = 0
[uint16] $intDaysToKeepLogFiles = 0

[string] $strUDMUsername = ""
[string] $strUDMIPHostname = ""
[string] $strUDMRemoteBackupDirectory = ""


#if path to log directory exists, set logging to true and setup log file
if (Test-Path -Path $PowerShellObject.Optional.logsDirectory -PathType Container) {
  $blnWriteToLog = $true
  [string] $strTimeStamp = $(get-date -f yyyy-MM-dd-hh_mm_ss)
  [string] $strDetailLogFilePath = $PowerShellObject.Optional.logsDirectory + "\udmpro-backup-detail-" + $strTimeStamp + ".log"
  $objDetailLogFile = [System.IO.StreamWriter] $strDetailLogFilePath
}

#if days to keep udm backup files directive exists in config file, set configured days to keep local backups
if ($PowerShellObject.Optional.daysToKeepUDMBackups) {
  try {
    $intDaysToKeepUDMBackups = $PowerShellObject.Optional.daysToKeepUDMBackups
    Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $true -LogString "Using $($PowerShellObject.Optional.daysToKeepUDMBackups) value specified in config file for backup retention" -LogType "Info"
  } catch {
    Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $true -LogString "$($PowerShellObject.Optional.daysToKeepUDMBackups) value specified in config file is not valid, defaulting to unlimited backup retention" -LogType "Warning"
  }
}

#if days to keep log files directive exists in config file, set configured days to keep log files
if ($PowerShellObject.Optional.daysToKeepLogFiles) {
  try {
    $intDaysToKeepLogFiles = $PowerShellObject.Optional.daysToKeepLogFiles
    Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $true -LogString "Using $($PowerShellObject.Optional.daysToKeepLogFiles) value specified in config file for log retention" -LogType "Info"
  } catch {
    Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $true -LogString "$($PowerShellObject.Optional.daysToKeepLogFiles) value specified in config file is not valid, defaulting to unlimited log retention" -LogType "Warning"
  }
}

#check for presense of udm username in config file
if ($PowerShellObject.Optional.udmUsername) {
  $strUDMUsername = $PowerShellObject.Optional.udmUsername
} else {
  $strUDMUsername = "root"
}

#check for presense of udm IP/Hostname in config file
if ($PowerShellObject.Optional.udmIPHostname) {
  $strUDMIPHostname = $PowerShellObject.Optional.udmIPHostname
} else {
  $strUDMIPHostname = "192.168.1.1"
}

#chek for presense of udm remote backup directory in config file
if ($PowerShellObject.Optional.udmRemoteBackupDirectory) {
  $strUDMRemoteBackupDirectory = $PowerShellObject.Optional.udmRemoteBackupDirectory
} else {
  $strUDMRemoteBackupDirectory = "/data/unifi/data/backup/autobackup"
}

Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $true -LogString "Beginning process to backup UDM Pro via scp at $($strUDMIPHostname) with $($strUDMUsername), copying $($strUDMRemoteBackupDirectory) to $($PowerShellObject.Required.localBackupDirectory)" -LogType "Info"

#perform actual backup of udm device
try {
  Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $true -LogString "Building credential" -LogType "Info"
  $objPassword = Get-Content $PowerShellObject.Required.udmPasswordFile | ConvertTo-SecureString
	$objCredential = New-Object System.Management.Automation.PSCredential ($strUDMUsername, $objPassword)
  Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $true -LogString "Backing up UDM Pro..." -LogType "Info"
	Get-SCPItem -AcceptKey -ComputerName $strUDMIPHostname -Credential $objCredential -Path $strUDMRemoteBackupDirectory -PathType Directory -Destination $PowerShellObject.Required.localBackupDirectory -ErrorAction Stop
  Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $true -LogString "Successfully backed up UDM Pro" -LogType "Info"
  $blnBackupSuccessful = $true
} catch {
	$ErrorMessage = $_.Exception.Message
	$line = $_.InvocationInfo.ScriptLineNumber
	$arrStrErrors += "Failed to connect to UDM Pro at $($strUDMIPHostname) with $($strUDMUsername), copying $($strUDMRemoteBackupDirectory) to $($PowerShellObject.Required.localBackupDirectory) at $($line) with the following error: $ErrorMessage"
  Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $true -LogString "Failed to connect to UDM Pro at $($strUDMIPHostname) with $($strUDMUsername), copying $($strUDMRemoteBackupDirectory) to $($PowerShellObject.Required.localBackupDirectory) at $($line) with the following error: $ErrorMessage" -LogType "Error"
}


#backup retention
if ($blnBackupSuccessful -eq $true -and $intDaysToKeepUDMBackups -gt 0) {
  try {
    Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $blnWriteToLog -LogString "Purging backups older than $($intDaysToKeepUDMBackups) days from $($PowerShellObject.Required.localBackupDirectory)\autobackup" -LogType "Info"
    $CurrentDate = Get-Date
    $DatetoDelete = $CurrentDate.AddDays("-$($intDaysToKeepUDMBackups)")
    Get-ChildItem "$($PowerShellObject.Required.localBackupDirectory)\autobackup" | Where-Object { $_.LastWriteTime -lt $DatetoDelete } | Remove-Item -force
  } catch {
    $ErrorMessage = $_.Exception.Message
	  $line = $_.InvocationInfo.ScriptLineNumber
	  $arrStrErrors += "Failed to purge backup files older than $($intDaysToKeepUDMBackups) days from $($PowerShellObject.Required.localBackupDirectory)\autobackup with the following error: $ErrorMessage"
    Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $blnWriteToLog -LogString "Failed to purge backup files older than $($intDaysToKeepUDMBackups) days from $($PowerShellObject.Required.localBackupDirectory)\autobackup with the following error: $ErrorMessage" -LogType "Error"
  }
}
#log retention
if ($intDaysToKeepLogFiles -gt 0) {
  try {
      Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $blnWriteToLog -LogString "Purging log files older than $($intDaysToKeepLogFiles) days from $($PowerShellObject.Optional.logsDirectory)" -LogType "Info"
      $CurrentDate = Get-Date
      $DatetoDelete = $CurrentDate.AddDays("-$($intDaysToKeepLogFiles)")
      Get-ChildItem "$($PowerShellObject.Optional.logsDirectory)" | Where-Object { $_.LastWriteTime -lt $DatetoDelete } | Remove-Item -Force
  } catch {
      $ErrorMessage = $_.Exception.Message
      $line = $_.InvocationInfo.ScriptLineNumber
      $arrStrErrors += "Failed to purge log files older than $($intDaysToKeepLogFiles) days from $($PowerShellObject.Optional.logsDirectory) with the following error: $ErrorMessage"
      Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $blnWriteToLog -LogString "Failed to purge log files older than $($intDaysToKeepLogFiles) days from $($PowerShellObject.Optional.logsDirectory) with the following error: $ErrorMessage" -LogType "Error"
  }
}

[int] $intErrorCount = $arrStrErrors.Count

if ($intErrorCount -gt 0) {
  Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $blnWriteToLog -LogString "Encountered $intErrorCount errors, sending error report email" -LogType "Error"
  #loop through all errors and add them to email body
  foreach ($strErrorElement in $arrStrErrors) {
      $intErrorCounter = $intErrorCounter + 1
      $strEmailBody = $strEmailBody + $intErrorCounter.toString() + ") " + $strErrorElement + "<br>"
  }
  $strEmailBody = $strEmailBody + "<br>Please see $strDetailLogFilePath on $strServerName for more details"

  Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $blnWriteToLog -LogString "Sending email error report via $($errorMailAppID) app on $($errorMailTenantID) tenant from $($errorMailSender) to $($errorMailRecipients) as specified in config file" -LogType "Info"
  $errorEmailPasswordSecure = Get-Content $errorMailPasswordFile | ConvertTo-SecureString
  $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($errorEmailPasswordSecure)
  $errorEmailPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

  Send-GVMailMessage -sender $errorMailSender -TenantID $errorMailTenantID -AppID $errorMailAppID -subject "$($errorMailSubjectPrefix): Encountered $($intErrorCount) errors during process" -body $strEmailBody -ContentType "HTML" -Recipient $errorMailRecipients -ClientSecret $errorEmailPassword
}

Out-GVLogFile -LogFileObject $objDetailLogFile -WriteToLog $blnWriteToLog -LogString "Process Complete" -LogType "Info"

$objDetailLogFile.close()
