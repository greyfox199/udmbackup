# udmbackup
this utility is used to backup a udm device to a location off the device itself. 

Requirements:  
-Assumes root level access to the udm device  
-Assumes auto backups have been configured on the udn device itself  
-Assumes remote host path can run powershell scripts (has only been tested on windows)  
-Assumes posh-ssh module is installed (https://github.com/darkoperator/Posh-SSH)  
-Assumes powershell execution mode set to unrestricted (required for posh-ssh)  
-Assumes setup as scheduled task via task scheduler  

# install
To install this script, either utilize the git-clone feature or manaually download from this repo.  It should be placed in a suitable location of your choosing for scheduled tasks.  This script requires a json config file to be passed in as a parameter.  The config file should be placed in an appropriate location; it does not have to reside in the same location as the script but it can.  It also expects the password for the root-level account to connect to the udm device to be in a "secure" file.  This can be done as follows:

Read-Host "Enter Password" -AsSecureString |  ConvertFrom-SecureString | Out-File "X:\path\to\udmpw" 

Where the path can be adjusted as appropriate.  Note that the user that runs this must be the same user that is configured to run this via the task scheduler.  This can be kept in the root of the user profile that will be running the script via the task scheduler.

Once the powershell script, secure password file and json config file have been created and configured, the script can be run manually as follows:  

.\udmprobackup.ps1 -ConfigFilePath "X:\path\to\udmbackup.json"

A basic scheduled task can be created with an approrpriate schedule.  Just note that the user configured in the task must match the user that created the secure file to connect to the udm and for smtp authentication if required.  

The "Program/script:" section must be configured as "powershell.exe" with the "Add arguments (optional):" list configured as the full path to the script along with the full path to the json config file:

X:\path\to\udmproscriptdirectory\udmprobackup.ps1 -ConfigFilePath "X:\path\to\udmbackup.json"

The "Start in (optional):" section can be populated with the full path to the directory that contains the powershell script:

X:\path\to\udmproscriptdirectory

# config file
The config file is a json-formatted config file.  There are 2 required fields and several optional fields to control things like logging, sending error reports via email, and local backup/log retention.

The simplest file will be this:
```json
{
    "required": {
        "udmPasswordFile": "X:\\path\\to\\udnpw",
        "localBackupDirectory": "X:\\path\\to\\udmbackup"
    }
}
```
**udmPasswordFile**: This is the path to the secure password file for the root-level account to the udm device  
**localBackupDirectory**: This is the path where the backups will be retained.  Note that without a retention configured as an optional parameter, the number of backup files will continue to grow unrestricted.

The complete list of optional parameters is as follows:  

```json
{
    "required": {
        "udmPasswordFile": "X:\\path\\to\\udnpw",
        "localBackupDirectory": "X:\\path\\to\\udmbackup"
    },
    "optional": {
        "logsDirectory": "X:\\path\\to\\logs\\udmbackup",
        "daysToKeepUDMBackups": "0",
        "daysToKeepLogFiles": "0",
        "sendEmailError": "true",
        "smtpServer": "mail.server.address",
        "emailReportRecipient": "errorreport@recipient.com",
        "smtpUsername": "errorreport@sender.com",
        "smtpauthrequired": "true",
        "smtpPasswordFile": "X:\\path\\to\\smtppw",
        "smtpsslrequired": "true",
        "smtpport": "587",
        "udmUsername": "root",
        "udmIPHostname": "192.168.1.1",
        "udmRemoteBackupDirectory": "/data/unifi/data/backup/autobackup"
    }
}
```

**logsDirectory**: This is the path to an optional directory to log the output of the job.  Without the additional optional daysToKeepLogFiles directive set, the log files will continue to be added each time the job is run without restrictions.  
**daysToKeepUDMBackups**: This setting controls the number of days to keep the udm backups locally.  It is expecting an unsigned int from range 0 to 65535, with 0 indicating that no local backups will be purged.  If this value is left blank, not numerical or outside the range of an unsigned int16, it defaults to 0.  
**daysToKeepLogFiles**: This setting controls the number of days to keep logs locally, assuming the logsDirectory directive was set.  It is expecting an unsigned int from range 0 to 65535, with 0 indicating that no local log files will be purged.  If this value is left blank, not numerical or outside the range of an unsigned int16, it defaults to 0.  
**sendEmailError**: This setting controls whether an email report will be sent if any errors occur.  This accepts two values, "true" or "false".  If this is empty or not one of those 2 values, it defaults to "false".  
**smtpServer**: This is the smtp mail server to use to send error reports if any errors occur.  This value is ignored if sendEmailError is not set to true.  
**emailReportRecipient**: This is the recipent that will receive the error report if any errors occur.  This value is ignored if sendEmailError is not set to true.  
**smtpUsername**: This is the sender that will be used to send the error report if any errors occur.  It is also the value for the username that is used if smtp auth is required.  This value is ignored if sendEmailError is not set to true.  
**smtpauthrequired**: This setting controls whether smtp authentication is required to connect to the configured mail server.  This accepts two values, "true" or "false".  If this is empty or not one of those 2 values, it defaults to "false".  This setting is ignored if sendEmailError is not set to true.  
**smtpPasswordFile**: This setting controls the path to the secure password file for the root-level account to the udm device.  See instructions on creating a secure password file for the udm device to create one for smtp authentication.  This setting is ignored if sendEmailError is not set to true.  
**smtpsslrequired**:  This setting controls whether a secure channel is required to connect to the specified smtp server.  This accepts two values, "true" or "false".  If this is empty or not one of those 2 values, it defaults to "false".  This setting is ignored if sendEmailError is not set to true.  
**smtpport**:  This setting controls the port number used to connect to the specified smtp server.  It is expecting an unsigned int from range 0 to 65535.  If this value is left blank, not numerical or outside the range of an unsigned int16, it defaults to 587.  This setting is ignored if sendEmailError is not set to true.  
**udmUsername**:  This setting controls the username used to connect to the udm device.  If left blank, it defaults to "root".  
**udmIPHostname**:  This setting controls the IP/hostname used to connect to the udm device.  It will accept a valid IP address or dns hostname.  If left blank, it defaults to "192.168.1.1".  
**udmRemoteBackupDirectory**:  This setting controls the location on the remote udm device that holds the configured backups.  If left blank, it defaults to "/data/unifi/data/backup/autobackup".  