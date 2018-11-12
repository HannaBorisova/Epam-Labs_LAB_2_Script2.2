#Script for execution on computers that are in the same domen
[CmdletBinding()]
Param(
    [parameter(Mandatory=$true, HelpMessage="Enter Password")]
    [string]$passw,

    [parameter(Mandatory=$true, Helpmessage="Enter path for the log file")]
    [string]$path
)

$DomSwitch = Read-Host "Are your computers on the same domen? [y/n]"
switch ( $DomSwitch )  {
    y { Write-Host "OK"  }
    n { 
        Enable-PSRemoting -SkipNetworkProfileCheck -Force
        $curr=(get-item WSMan:\localhost\Client\TrustedHosts).value
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value ($Curr,10.0.0.1) 
    }
}

#Creating new DB
$CreateDB = @'
CREATE DATABASE [PCDRIVE]
 ON  PRIMARY 
( NAME = N'PCDRIVE', 
  FILENAME = N'F:\DATA\PCDRIVE.mdf' , 
  SIZE = 51200KB , 
  FILEGROWTH = 5120KB )
 LOG ON 
(NAME = N'PCDRIVE_log', 
FILENAME = N'F:\LOGS\PCDRIVE_log.ldf' , 
SIZE = 5120KB , 
FILEGROWTH = 1024KB )
'@

#Creating new table in the DB
$CreateTable = @'
USE [PCDRIVE]
CREATE TABLE PhysicalDisk
(
  DiskID smallint IDENTITY not null, 
  FriendlyName varchar(100) not null,
  BusType varchar(20) not null,
  HealthStatus varchar(20) not null,
)
'@

#Counting the amount of pages in use
$GetPages=@'
USE PCDRIVE;  
GO  
SELECT SUM(allocated_extent_page_count) AS [pages in work],   
(SUM(allocated_extent_page_count)*1.0/128) AS [allocated space in MB]  
FROM sys.dm_db_file_space_usage;
'@

#Filling in the table from CSV file
$FillTable= @'
BULK
INSERT PCDRIVE.dbo.PhysicalDisk
FROM 'E:\PhysicalDisk.csv'
WITH
(
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n'
)
GO
--Check the content of the table.
SELECT REPLACE(FriendlyName,'"','') FriendlyName,
REPLACE([BusType],'"','') [BusType],
REPLACE([HealthStatus],'"','') [HealthStatus]
 
FROM PCDRIVE.dbo.PhysicalDisk
GO
'@
#Creating log file
$Logfile=New-Item -ItemType File -Path $($path+"Logging.txt")

Function Write-Log
{
   Param ([string]$log)
    $date=Get-Date
    Add-content $Logfile -value $log,$date
    Write-Host $log -BackgroundColor DarkCyan
}

#Opening SQL connection
Write-Log -log "Opening SQL Connection"
$SqlServer = "10.0.0.1";
$SqlLogin = "Sa";
$SqlPassw = $passw
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = "Server=$SQLServer; ; User ID=$SqlLogin; Password=$SqlPassw;"
$SqlConnection.Open()
Write-Log -log "SQL Connection Opened"


#Creation of DB and table
Write-Log -log "Start Creating DB"
$SqlCmd = $SqlConnection.CreateCommand()
$SqlCmd.CommandText = $CreateDB
$objReader = $SqlCmd.ExecuteReader()
$objReader.close()
Write-Log -log "DB created"

$SqlCmd = $SqlConnection.CreateCommand()
$SqlCmd.CommandText = $CreateTable
$objReader = $SqlCmd.ExecuteReader()
$objReader.close()

$SqlConnection.Close()

$length1 = Invoke-Command -ComputerName "vm1.adatum.com" -ScriptBlock {Get-Item F:\DATA\PCDRIVE.mdf | Measure-Object -Property length -sum }
$Pages1 = Invoke-Sqlcmd -ServerInstance "10.0.0.1" -Query $GetPages

Invoke-Command -ComputerName "vm1.adatum.com" -ScriptBlock { Get-PhysicalDisk | Select-Object -Property FriendlyName,Description,BusType,@{Label="AllocatedSize";Expression={$_.Size / 1mb -as [int] }} |`
     ConvertTo-Csv -NoTypeInformation | Set-Content -Path E:\PhysicalDisk.csv } 

Invoke-Sqlcmd -ServerInstance "10.0.0.1" -Query $FillTable

$length2 = Invoke-Command -ComputerName "vm1.adatum.com" -ScriptBlock {Get-Item F:\DATA\PCDRIVE.mdf | Measure-Object -Property length -sum }
$Pages2 = Invoke-Sqlcmd -ServerInstance "10.0.0.1" -Query $GetPages

Write-Host "Data Files length before filling the table - " $length1.sum
Write-Host "Data Files length after filing the table - " $length2.sum

Write-Host "Allocated pages before filling the table" $Pages1
Write-Host "Allocated pages after filling the table" $Pages2
