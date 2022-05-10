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

#set up variables
[string] $strServerName = $env:computername

[uint16] $intDaysToKeepUDMBackups = 0
[uint16] $intDaysToKeepLogFiles = 0

[string] $strUDMUsername = "root"
[string] $strUDMIPHostname = "192.168.1.1"
[string] $strUDMRemoteBackupDirectory = "/data/unifi/data/backup/autobackup"

[bool] $blnSendSMTPErrorReport = $false
[bool] $blnSMTPAuthRequired = $false
[bool] $blnBackupSuccessful = $false
[bool] $blnWriteToLog = $false
[uint16] $intSMTPPort = 587

[int] $intErrorCount = 0
$arrStrErrors = @()

#clear all errors before starting
$error.Clear()

#if path to log directory exists, set logging to true and setup log file
if (Test-Path -Path $PowerShellObject.Optional.logsDirectory -PathType Container) {
  $blnWriteToLog = $true
  [string] $strTimeStamp = $(get-date -f yyyy-MM-dd-hh_mm_ss)
  [string] $strDetailLogFilePath = $PowerShellObject.Optional.logsDirectory + "\udmpro-backup-detail-" + $strTimeStamp + ".log"
  $objDetailLogFile = [System.IO.StreamWriter] $strDetailLogFilePath
}

#function to write log file
Function LogWrite($objLogFile, [string]$strLogstring, [bool]$DisplayInConsole=$true)
{ 
  if ($DisplayInConsole -eq $true) {
    write-host $strLogstring
  }
  if ($blnWriteToLog -eq $true) {
    $objLogFile.writeline($strLogstring)
    $objLogFile.flush()
  }
}

#if days to keep udm backup files directive exists in config file, set configured days to keep local backups
if ($PowerShellObject.Optional.daysToKeepUDMBackups) {
  try {
    $intDaysToKeepUDMBackups = $PowerShellObject.Optional.daysToKeepUDMBackups
    LogWrite $objDetailLogFile "$(get-date) Info: Using $($PowerShellObject.Optional.daysToKeepUDMBackups) value specified in config file for backup retention"
  } catch {
    LogWrite $objDetailLogFile "$(get-date) Warning: $($PowerShellObject.Optional.daysToKeepUDMBackups) value specified in config file is not valid, defaulting to unlimited backup retention"
  }
}

#if days to keep log files directive exists in config file, set configured days to keep log files
if ($PowerShellObject.Optional.daysToKeepLogFiles) {
  try {
    $intDaysToKeepLogFiles = $PowerShellObject.Optional.daysToKeepLogFiles
    LogWrite $objDetailLogFile "$(get-date) Info: Using $($PowerShellObject.Optional.daysToKeepLogFiles) value specified in config file for log retention"
  } catch {
    LogWrite $objDetailLogFile "$(get-date) Warning: $($PowerShellObject.Optional.daysToKeepLogFiles) value specified in config file is not valid, defaulting to unlimited log retention"
  }
}

#if smtp port directive is configured, set port
if ($PowerShellObject.Optional.smtpport) {
  try {
    $intSMTPPort = $PowerShellObject.Optional.smtpport
    LogWrite $objDetailLogFile "$(get-date) Info: Using $($PowerShellObject.Optional.smtpport) value specified in config file for log for smtp port"
  } catch {
    LogWrite $objDetailLogFile "$(get-date) Warning: $($PowerShellObject.Optional.smtpport) value specified in config file is not valid, defaulting to $($intSMTPPort)"
  }
}

#if send smtp error directive exists along with smtp server, sender and recipient exist in config file, configure to send email on error
if ($PowerShellObject.Optional.sendEmailError -and $PowerShellObject.Optional.sendEmailError.toLower().equals("true")) {
  if ($PowerShellObject.Optional.smtpServer -and $PowerShellObject.Optional.emailReportRecipient) {
    $blnSendSMTPErrorReport = $true
    LogWrite $objDetailLogFile "$(get-date) Info: Sending email error report via $($PowerShellObject.Optional.smtpServer) to $($PowerShellObject.Optional.emailReportRecipient) as specified in config file"
    if ($PowerShellObject.Optional.smtpauthrequired) {
      if ($PowerShellObject.Optional.smtpauthrequired.toLower().equals("true")) {
        $blnSMTPAuthRequired = $true
        if ($PowerShellObject.Optional.smtpUsername -AND (Test-Path -Path $PowerShellObject.Optional.smtpPasswordFile -PathType Leaf)) {
          LogWrite $objDetailLogFile "$(get-date) Info: Using $($PowerShellObject.Optional.smtpUsername) as smtp username and $($PowerShellObject.Optional.smtpPasswordFile) smtp password file for smtp authentication as specified in config file"
        } else {
          LogWrite $objDetailLogFile "$(get-date) Warning: SMTP auth required but no smtp username or password file were specified, aborting smtp send"
        }
      }
    }
  }
}

#check for presense of udm username in config file
if ($PowerShellObject.Optional.udmUsername) {
  $strUDMUsername = $PowerShellObject.Optional.udmUsername
}

#check for presense of udm IP/Hostname in config file
if ($PowerShellObject.Optional.udmIPHostname) {
  $strUDMIPHostname = $PowerShellObject.Optional.udmIPHostname
}

#chek for presense of udm remote backup directory in config file
if ($PowerShellObject.Optional.udmRemoteBackupDirectory) {
  $strUDMRemoteBackupDirectory = $PowerShellObject.Optional.udmRemoteBackupDirectory
}

LogWrite $objDetailLogFile "$(get-date) Info: Beginning process to backup UDM Pro via scp at $($strUDMIPHostname) with $($strUDMUsername), copying $($strUDMRemoteBackupDirectory) to $($PowerShellObject.Required.localBackupDirectory)"

#perform actual backup of udm device
try {
	LogWrite $objDetailLogFile "$(get-date) Info: Building credential"
  $objPassword = Get-Content $PowerShellObject.Required.udmPasswordFile | ConvertTo-SecureString
	$objCredential = New-Object System.Management.Automation.PSCredential ($strUDMUsername, $objPassword)
	LogWrite $objDetailLogFile "$(get-date) Info: Backing up UDM Pro..."
	Get-SCPItem -AcceptKey -ComputerName $strUDMIPHostname -Credential $objCredential -Path $strUDMRemoteBackupDirectory -PathType Directory -Destination $PowerShellObject.Required.localBackupDirectory -ErrorAction Stop
	LogWrite $objDetailLogFile "$(get-date) Info: Successfully backed up UDM Pro"
  $blnBackupSuccessful = $true
} catch {
	$ErrorMessage = $_.Exception.Message
	$line = $_.InvocationInfo.ScriptLineNumber
	$arrStrErrors += "Failed to connect to UDM Pro at $($strUDMIPHostname) with $($strUDMUsername), copying $($strUDMRemoteBackupDirectory) to $($PowerShellObject.Required.localBackupDirectory) at $($line) with the following error: $ErrorMessage"
	LogWrite $objDetailLogFile "$(get-date) Error: Failed to connect to UDM Pro at $($strUDMIPHostname) with $($strUDMUsername), copying $($strUDMRemoteBackupDirectory) to $($PowerShellObject.Required.localBackupDirectory) at $($line) with the following error: $ErrorMessage"
}


#backup retention
if ($blnBackupSuccessful -eq $true -and $intDaysToKeepUDMBackups -gt 0) {
  try {
    LogWrite $objDetailLogFile "$(get-date) Info: Purging backups older than $($intDaysToKeepUDMBackups) days from $($PowerShellObject.Required.localBackupDirectory)\autobackup"
    $CurrentDate = Get-Date
    $DatetoDelete = $CurrentDate.AddDays("-$($intDaysToKeepUDMBackups)")
    Get-ChildItem "$($PowerShellObject.Required.localBackupDirectory)\autobackup" | Where-Object { $_.LastWriteTime -lt $DatetoDelete } | Remove-Item
  } catch {
    $ErrorMessage = $_.Exception.Message
	  $line = $_.InvocationInfo.ScriptLineNumber
	  $arrStrErrors += "Failed to purge backup files older than $($intDaysToKeepUDMBackups) days from $($PowerShellObject.Required.localBackupDirectory)\autobackup with the following error: $ErrorMessage"
	  LogWrite $objDetailLogFile "$(get-date) Error: Failed to purge backup files older than $($intDaysToKeepUDMBackups) days from $($PowerShellObject.Required.localBackupDirectory)\autobackup with the following error: $ErrorMessage"
  }
}

#log retention
if ($blnBackupSuccessful -eq $true -and $intDaysToKeepLogFiles -gt 0) {
  try {
    LogWrite $objDetailLogFile "$(get-date) Info: Purging log files older than $($intDaysToKeepLogFiles) days from $($PowerShellObject.Required.logsDirectory)"
    $CurrentDate = Get-Date
    $DatetoDelete = $CurrentDate.AddDays("-$($intDaysToKeepLogFiles)")
    Get-ChildItem "$($PowerShellObject.Required.logsDirectory)" | Where-Object { $_.LastWriteTime -lt $DatetoDelete } | Remove-Item
  } catch {
    $ErrorMessage = $_.Exception.Message
	  $line = $_.InvocationInfo.ScriptLineNumber
	  $arrStrErrors += "Failed to purge log files older than $($intDaysToKeepLogFiles) days from $($PowerShellObject.Required.logsDirectory) with the following error: $ErrorMessage"
	  LogWrite $objDetailLogFile "$(get-date) Error: Failed to purge log files older than $($intDaysToKeepLogFiles) days from $($PowerShellObject.Required.logsDirectory) with the following error: $ErrorMessage"
  }
}

[int] $intErrorCount = $arrStrErrors.Count

#sending email report if any errors occured
if ($PowerShellObject.Optional.sendEmailError -and $PowerShellObject.Optional.sendEmailError.toLower().equals("true") -and $intErrorCount -gt 0) {
  #if smtp server, sender and email recipient are populated
  if ($PowerShellObject.Optional.smtpServer -and $PowerShellObject.Optional.smtpUsername -and $PowerShellObject.Optional.emailReportRecipient) {
    $blnSendSMTPErrorReport = $true
    LogWrite $objDetailLogFile "$(get-date) Info: Encountered $intErrorCount errors, sending error report email"
    #loop through all errors and add them to email body
    foreach ($strErrorElement in $arrStrErrors) {
      $intErrorCounter = $intErrorCounter + 1
      $strEmailBody = $strEmailBody + $intErrorCounter.toString() + ") " + $strErrorElement + "`n"
    }
    $strEmailBody = $strEmailBody + "`n`nPlease see $strDetailLogFilePath on $strServerName for more details"

    LogWrite $objDetailLogFile "$(get-date) Info: Sending email error report via $($PowerShellObject.Optional.smtpServer) from $($PowerShellObject.Optional.smtpUsername) to $($PowerShellObject.Optional.emailReportRecipient) as specified in config file"
    #if smtp auth is required, handle credentials
    if ($PowerShellObject.Optional.smtpauthrequired -and $PowerShellObject.Optional.smtpauthrequired.toLower().equals("true")) {
      $blnSMTPAuthRequired = $true
      $objPassword = Get-Content $PowerShellObject.Optional.smtpPasswordFile | ConvertTo-SecureString
      $objSMTPCredential = New-Object System.Management.Automation.PSCredential ($PowerShellObject.Optional.smtpUsername, $objPassword)
      if ($PowerShellObject.Optional.sendEmailError -AND $PowerShellObject.Optional.sendEmailError -AND (Test-Path -Path $PowerShellObject.Optional.smtpPasswordFile -PathType Leaf)) {
        #if smtp ssl is required, send mail with ssl flag
        if ($PowerShellObject.Optional.smtpsslrequired.toLower().equals("true")) {
          send-MailMessage -From $PowerShellObject.Optional.smtpUsername -To $PowerShellObject.Optional.emailReportRecipient -SmtpServer $PowerShellObject.Optional.smtpServer -Subject "<<UDM Pro Backup>> Errors during process" -Body $strEmailBody  -UseSsl -Port $intSMTPPort -Credential $objSMTPCredential
        #else smtp ssl is NOT required, so so not use ssl flag when sending mail
        } else {
          send-MailMessage -From $PowerShellObject.Optional.smtpUsername -To $PowerShellObject.Optional.emailReportRecipient -SmtpServer $PowerShellObject.Optional.smtpServer -Subject "<<UDM Pro Backup>> Errors during process" -Body $strEmailBody  -Port $intSMTPPort -Credential $objSMTPCredential
        }
      } else {
        LogWrite $objDetailLogFile "$(get-date) Warning: SMTP Auth set to required in config file but username or password file aren't set, aborting smtp send"
      }
    #else smtp auth is NOT required, so continue without credentials
    } else {
      LogWrite $objDetailLogFile "$(get-date) Info: Sending email report via unauthenticated session"
      if ($PowerShellObject.Optional.smtpsslrequired.toLower().equals("true")) {
        send-MailMessage -From $PowerShellObject.Optional.smtpUsername -To $PowerShellObject.Optional.emailReportRecipient -SmtpServer $PowerShellObject.Optional.smtpServer -Subject "<<UDM Pro Backup>> Errors during process" -Body $strEmailBody  -UseSsl -Port $intSMTPPort
      #else smtp ssl is NOT required, so so not use ssl flag when sending mail
      } else {
        send-MailMessage -From $PowerShellObject.Optional.smtpUsername -To $PowerShellObject.Optional.emailReportRecipient -SmtpServer $PowerShellObject.Optional.smtpServer -Subject "<<UDM Pro Backup>> Errors during process" -Body $strEmailBody  -Port $intSMTPPort
      }
    }
  #smtp server, sender and/or recipient are NOT populated
  } else {
    LogWrite $objDetailLogFile "$(get-date) Warning: Send email error report set to true in config, but smtp server, sender and/or recipient left blank in config file, aborting sending of email error report"
  }
}

LogWrite $objDetailLogFile "$(get-date) Info: Process Complete"

$objDetailLogFile.close()
