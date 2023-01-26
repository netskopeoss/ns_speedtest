<#
.SYNOPSIS

Netskope Performance troubleshooting script.

.Description

This script helps to identify Throughput available on a device. Tests results are displayed on the command line and in log files.

.PARAMETER Size

Download size in MB
 
.PARAMETER Interval

Waiting time between downloads, in seconds
 
.PARAMETER Loops

Number of tests
 
.PARAMETER Help 

This help.

.PARAMETER Report

Turn on report mode, display all informations recorded. By default log files includes all informations, and the command line a condensed output.

.PARAMETER Quiet

Turn on quiet mode, no output will be displayed on the command line, use the log files to get test results

.PARAMETER NoFiles

Disable all file logging.

.PARAMETER Pcap

Perform packet capture at the same time.

.PARAMETER Comment

Test comment, please write context related to the test.

.PARAMETER Url

Destination url downloaded to evaluation the throughput. By default, the script use Google Drive.

.PARAMETER LogFolder

Define the location of the log files. By default logs are store in Netskope Client log folder (C:\Users\Public\netSkope)

.LINK

https://github.com/netskopeoss/ns_speedtest

#>



#! /usr/bin/pwsh

# Netskope Performance troubleshooting tool
# Author: Matthieu Bouthors
# Copyright Netskope


[CmdletBinding()]
Param (
   [ValidateSet(10,100)]
   [int]$Size=100,
   [int]$Interval=15,
   [int]$Loops=5,
   [switch]$Help=$false,
   [switch]$Report=$false,
   [switch]$Quiet=$false,
   [switch]$NoFiles=$false,
   [switch]$Pcap=$false,
   [string]$Comment=$(Read-Host -Prompt 'Please add a comment for this test, for example: "Test Wifi 1": '),
   [string]$Url,
   [string]$LogFolder


)

If($Help){
   Get-Help -Detailed $PSCommandPath
   Exit
}

$UrlArgs=$false
$PingDest="8.8.8.8"
$global:Mega=1048576
# $PID is automatic
$DefaultMaxStats=300
$CpuJobName="NsSpeedtestCpu"
$LatencyJobName="NsSpeedtestPing"

$nsconfig="C:\ProgramData\netskope\stagent\nsconfig.json"
$nsdiag="C:\Program Files (x86)\Netskope\STAgent\nsdiag.exe"
$StatsCpu="top -l$DefaultMaxStats -n10 -i1"
$OutputFolder="C:\Users\Public\netSkope"
$FilenameSpeedtest="nsspeedtest.log"
$FilenameCpu="nsspeedtest_cpu.log"
$FilenameLatency="nsspeedtest_latency.log"

$CurlFormat="%{http_version}|%{http_code}|%{speed_download}|%{size_download}|%{time_total}|%{time_starttransfer}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_pretransfer}|%{time_redirect}"

$gdrive=@{}
$gdrive[10]="https://drive.google.com/uc?export=download&id=1UX-pO5OLPhv_hoUpk_ixu3IDmkHpqQoF"
$gdrive[100]="https://drive.google.com/uc?export=download&id=1VYSsMYB0w18tntQipTZPkq3cg58nmEEo"

If($Url){
   $TargetType="custom"
   $Target=$Url
}else{
   $Target=$gdrive[$Size]
   $TargetType="gdrive"
}

If($LogFolder){
   $OutputFolder=$LogFolder
}

If(-Not $NoFiles){
   If(-Not (Test-Path -Path $OutputFolder)){
      $Continue=$false
      do{
         $ync=Read-Host -Prompt 'Log folder not found, do you want to log in the local folder ([Y]es/No/Cancel)? '
         If($ync -match "^(y(es)?)?$"){
            $OutputFolder="."
            $Continue=$true
         }elseif($ync -match "^n(o)?$") {
             $NoFiles=$true
             $Continue=$true
         }elseif($ync -match "^c(ancel)?$") {
            Exit
         }
      } until ($Continue)
   }
}

#convert to absolute path for jobs
$OutputFolder=Resolve-Path -Path $OutputFolder | select -ExpandProperty Path

function Timestamp {
   return (Get-Date -f s) + (Get-Date -f zzz)
}

If ($NoFiles -and $Quiet){
   Write-Host "ERROR: No output to files or screen, exiting"
   Exit
}

If(-Not $NoFiles){
   $global:OutputFile="$OutputFolder\$FilenameSpeedtest"
   $OutputFileLatency="$OutputFolder\$FilenameLatency"
   $OutputFileCpu="$OutputFolder\$FilenameCpu"
}

function RotateFile(){
   [CmdletBinding()]
   param(
      [Parameter(Mandatory)]
      [string]$File
   )

   If(Test-Path $File -PathType leaf){
      $FileSize=(Get-Item -Path $File).Length
      If($FileSize -gt 10000000){
         Write-Host ("Rotation needed for file {0}, current size is {1:n} Bytes" -f $File, $FileSize)
         $BackupFile="$File.bak"
         if (Test-Path $BackupFile) 
         {
            Remove-Item $BackupFile
            Write-Host ("Previous backup deleted: {0}" -f $BackupFile)
         }  
         mv "$File" "$File.bak"
         Write-Host ("Rotation done" -f $File, $FileSize)
      }
   }
}

If(-Not $NoFiles){
   RotateFile -File $global:OutputFile
   RotateFile -File $OutputFileLatency
   RotateFile -File $OutputFileCpu
}


function Top {
    While(1) {  
      Timestamp >> $OutputFileCpu
      $p = get-counter '\Process(*)\% Processor Time'
      $p.CounterSamples | sort -des CookedValue | select -f 15 >> $OutputFileCpu
      sleep 2
   }
}
Stop-Job -Name NsSpeedtest*
Remove-job -Name NsSpeedtest*

If(-Not $NoFiles){
   Start-Job -Name NsSpeedtestCpu -ScriptBlock { for ($i=1; $i -le $args[0]; $i=$i+1) {  (Get-Date -f s) + (Get-Date -f zzz) >> $args[1] ; $p = get-counter '\Process(*)\% Processor Time'; $p.CounterSamples | sort -des CookedValue | select -f 15 >> $args[1] }} -ArgumentList $DefaultMaxStats, $OutputFileCpu | Out-Null
}

$StartTime=Timestamp

# Cprintf manages output of the script to screen and files
#Modes:
# - default: output screen and file, follow Quiet and NoFiles flags
# - report: output files only but default, follows NoFiles and Report flags
# - error: output always screen, follow NoFiles flag
function Cprintf {
   [CmdletBinding()]
   param(
      [Parameter(Mandatory)]
      [ValidateSet("default","report","error")]
      [string]$Mode,
      [Parameter(Mandatory)]
      [string]$Text
   )

   If($Mode -eq "error"){
      Write-Host $Text
   }

   If(-Not $Quiet){
      If(($Mode -eq "default") -Or $Report){
         Write-Host $Text
      }

   }
   If(-Not $NoFiles){
      "[$PID] $Text" >> $global:OutputFile
   }
}

Cprintf -Mode "default" -Text "***** Netskope Speedtest Script *****"


Cprintf -Mode "report" -Text "***** START ***** $Comment"
Cprintf -Mode "report" -Text "$StartTime Starting $0"
Cprintf -Mode "report" -Text "***** Options ***** $Comment"
Cprintf -Mode "report" -Text "PID = ${PID}"
Cprintf -Mode "report" -Text "Report Mode = ${Report}"
Cprintf -Mode "report" -Text "Quiet Mode = ${Quiet}"
Cprintf -Mode "report" -Text "Pcap Mode = ${Pcap}"
Cprintf -Mode "report" -Text "NoFiles Mode = ${NoFiles}"
Cprintf -Mode "report" -Text "Log folder = ${OutputFolder}"
Cprintf -Mode "report" -Text "Speedtest file = ${OutputFile}"
Cprintf -Mode "report" -Text "Latency file = ${OutputFileLatency}"
Cprintf -Mode "report" -Text "Cpu stats file = ${OutputFileCpu}"

Cprintf -Mode "report" -Text "Size = ${Size}"
Cprintf -Mode "report" -Text "Interval = ${Interval}"
Cprintf -Mode "report" -Text "Loops = ${Loops}"
Cprintf -Mode "report" -Text "Target type = $TargetType"
Cprintf -Mode "report" -Text "Target = $Target"
Cprintf -Mode "report" -Text "Curl Format = ${CurlFormat}"


Cprintf -Mode "default" -Text "***** DEVICE CONTEXT ***** $Comment"
Cprintf -Mode "default" -Text "*** Computer details"
$WindowsDetails=(systeminfo) -join [Environment]::NewLine

Cprintf -Mode "default" -Text "$WindowsDetails"

Cprintf -Mode "default" -Text "*** Netskope Client Configuration"
If(Test-Path $nsdiag -PathType leaf){
   $ClientConfiguration=(cmd /c "$nsdiag" -f) -join [Environment]::NewLine
   Cprintf -Mode "default" -Text "${ClientConfiguration}"
}else{
   Cprintf -Mode "error" -Text "WARNING: Netskope Client nsdiag not found"
   $ClientConfiguration=""
}

Cprintf -Mode "default" -Text "*** Netskope context"
If(Test-Path $nsconfig -PathType leaf){
   $DpGatewayLdns=$Management=Select-String -Path "C:\ProgramData\netskope\stagent\nsconfig.json" -Pattern '"host": "(gateway-[^"]*)"' | % { $_.Matches.groups[1].value }
   Cprintf -Mode "default" -Text "DP Gateway LDNS    = ${DpGatewayLdns}"
   $DpGatewayLdnsIp=Resolve-DnsName -Type A -Name $DpGatewayLdns | % { $_.IPAddress -join ',' }
   Cprintf -Mode "default" -Text "DP Gateway LDNS IP = ${DpGatewayLdnsIp}"
   $Management=Select-String -Path "C:\ProgramData\netskope\stagent\nsconfig.json" -Pattern '"host": "gateway-([^"]*)"' | % { $_.Matches.groups[1].value }
   Cprintf -Mode "default" -Text "Management         = ${Management}"
   $Achecker="achecker-$Management"
   Cprintf -Mode "default" -Text "Achecker           = ${Achecker}"
   $AcheckerUrl="https://$Achecker/downloadsize=${Size}m"
   Cprintf -Mode "default" -Text "Achecker Download  = ${AcheckerUrl}"
}else{
   Cprintf -Mode "error" -Text "WARNING: Netskope Client Configuration file not found"
}


If($ClientConfiguration -match "NSTUNNEL_CONNECTED")
{
   $Connected=$true
   Cprintf -Mode "default" -Text "Tunnel Connected"

   If($ClientConfiguration -like "Tunnel Protocol:: DTLS")
   {
      Cprintf -Mode"default" -Text "DTLS detected\n"
   }

   if ($ClientConfiguration -match "Gateway IP:: ([0-9.]*)\.")
   {
      $DpGatewayIp=$Matches[1]
      Cprintf -Mode "default" -Text "DP Gateway IP      = ${DpGatewayIp}"
      $PingDest=$DpGatewayIp -replace  "\.\d{1,3}$", ".1"
   }else{
      Cprintf -Mode "default" -Text "Gateway IP not found" 
   }

}else{
   $Connected=$false
   Cprintf -Mode "default" -Text "Tunnel NOT Connected"
   $PingDest="drive.google.com"
   If ($Pcap){
     Cprintf -Mode "default" -Text "Disabling Pcap because tunnel is not connected"
     $Pcap=$false
   }
}

If(-Not $NoFiles){
   Start-Job -Name NsSpeedtestPing -ScriptBlock { ping.exe -n $args[0] -w 1000 $args[1]|Foreach{("{0} - {1}" -f ((Get-Date -f s) + (Get-Date -f zzz)),$_)} |Out-File -Append -Filepath $args[2]} -ArgumentList $DefaultMaxStats, $PingDest, $OutputFileLatency | Out-Null
}

If($Pcap){
    $PcapOutput=(cmd /c "$nsdiag" -c start -s 60) -join [Environment]::NewLine
    Cprintf -Mode "default" -Text $PcapOutput
}

#search for real public IP, ifconfig.me need to be steered by Netskope
Cprintf -Mode "default" -Text "*** Public IP Check with ifconfig.me"
$PublicIP=(curl.exe -s "ifconfig.me/ip") -join [Environment]::NewLine
Cprintf -Mode "default" -Text "Public IP: ${PublicIP}"
$PublicXFF=(curl.exe -s "ifconfig.me/forwarded") -join [Environment]::NewLine
Cprintf -Mode "default" -Text "Public X-Forwarded-For: ${PublicXFF}"

Cprintf -Mode "report" -Text "*** Device Route table"
$NetstatOutput=(netstat.exe -rn) -join [Environment]::NewLine
Cprintf -Mode "report" -Text $NetstatOutput

Cprintf -Mode "default" -Text "***** SPEEDTEST ***** $Comment"

#TestResult class is used to store Speedtest results, analysis and output
Class TestResult {
   [string]$Time
   [string]$Destination
   [string]$DestinationType


   [string]$HttpVersion
   [int]$HttpCode
   [int]$SpeedDownload
   [int]$SizeDownload
   [float]$TimeTotal
   [float]$TimeStarttransfer
   [float]$TimeNamelookup
   [float]$TimeConnect
   [float]$TimeAppconnect
   [float]$TimePretransfer
   [float]$TimeRedirect

   [float]$TimeDownload
   [float]$Throughput
   [float]$NiceThroughput
   [float]$NiceSpeedDownload
   [float]$NiceSizeDownload
   [int]$DurationNamelookup
   [int]$DurationConnect
   [int]$DurationAppconnect
   [int]$DurationPretransfer
   [int]$DurationRedirect
   [int]$DurationStarttransfer


   [void] CalculateValues(){
      $this.TimeDownload=$this.TimeTotal - $this.TimeStarttransfer
      $this.Throughput=$this.SizeDownload * 8 / $this.TimeDownload
      $this.NiceThroughput=$this.Throughput / $global:Mega
      $this.NiceSpeedDownload=$this.SpeedDownload * 8 / $global:Mega
      $this.NiceSizeDownload=$this.SizeDownload / $global:Mega
      $this.DurationNamelookup=$this.TimeNamelookup * 1000
      $this.DurationConnect=($this.TimeConnect - $this.TimeNamelookup) * 1000
      $this.DurationAppconnect=($this.TimeAppconnect - $this.TimeConnect) * 1000
      $this.DurationPretransfer=($this.TimePretransfer - $this.TimeAppconnect) * 1000
      If($this.TimeRedirect -eq 0){
         $this.DurationRedirect=0
         $this.DurationStarttransfer=($this.TimeStarttransfer - $this.TimePretransfer) * 1000
      }else{
         $this.DurationRedirect=($this.TimeRedirect - $this.TimePretransfer) * 1000
         $this.DurationStarttransfer=($this.TimeStarttransfer - $this.TimeRedirect) * 1000
      }
   }


   [void] ImportCurlResult([string]$TestTime, [string]$Url, [string]$UrlType, [string]$TestResult){
      $this.Time=$TestTime
      $this.Destination=$Url
      $this.DestinationType=$UrlType

      $ResultArray=$TestResult.Split("|")
      If(($ResultArray[0] -notmatch "^[\d\.]+$") -or ($ResultArray.count -ne 11)){
         Cprintf -Mode "error" -Text ("ERROR with curl result: {0}" -f $TestResult)
         Exit
      }

      $this.HttpVersion=$ResultArray[0]
      $this.HttpCode=$ResultArray[1]
      $this.SpeedDownload=$ResultArray[2]
      $this.SizeDownload=$ResultArray[3]
      $this.TimeTotal=$ResultArray[4]
      $this.TimeStarttransfer=$ResultArray[5]
      $this.TimeNamelookup=$ResultArray[6]
      $this.TimeConnect=$ResultArray[7]
      $this.TimeAppconnect=$ResultArray[8]
      $this.TimePretransfer=$ResultArray[9]
      $this.TimeRedirect=$ResultArray[10]

      $this.CalculateValues()
   }

   [void] CprintfTest(){
      Cprintf -Mode "default" -Text ("http version:       {0}" -f $this.HttpVersion)
      Cprintf -Mode "default" -Text ("http code:          {0}" -f $this.HttpCode)
      Cprintf -Mode "default" -Text ("Size:               {0:n2} MB" -f $this.NiceSizeDownload)
      Cprintf -Mode "default" -Text ("Throughput          {0:n2} Mbps" -f $this.NiceThroughput)
      Cprintf -Mode "default" -Text ("End to End Speed:   {0:n2} Mpbs" -f $this.NiceSpeedDownload)
      Cprintf -Mode "default" -Text ("Total time:         {0:n3} s" -f $this.TimeTotal)
      Cprintf -Mode "default" -Text ("StartTransfer Time: {0:n3} s (DNS:{1}ms,Connect:{2}ms,App:{3}ms,Pretransfer:{4}ms,Redirect:{5}ms,Startransfer:{6}ms)" -f $this.TimeStarttransfer, $this.DurationNamelookup, $this.DurationConnect, $this.DurationAppconnect, $this.DurationPretransfer, $this.DurationRedirect, $this.DurationStarttransfer)
      Cprintf -Mode "default" -Text ("Download Time:      {0:n3} s" -f $this.TimeDownload)

      Cprintf -Mode "report" -Text ("Details:")
      Cprintf -Mode "report" -Text ("NameLookupTime:     {0:n3} s" -f $this.TimeNamelookup)
      Cprintf -Mode "report" -Text ("ConnectTime:        {0:n3} s" -f $this.TimeConnect)
      Cprintf -Mode "report" -Text ("AppConnectTime:     {0:n3} s" -f $this.TimeAppconnect)
      Cprintf -Mode "report" -Text ("PretransferTime:    {0:n3} s" -f $this.TimePretransfer)
      Cprintf -Mode "report" -Text ("RedirectTime:       {0:n3} s" -f $this.TimeRedirect)
      Cprintf -Mode "report" -Text ("StarttransferTime:  {0:n3} s" -f $this.TimeStarttransfer)
      Cprintf -Mode "report" -Text ("TotalTime:          {0:n3} s" -f $this.TimeTotal)
   }

   [string] Export(){
      [string]$text=("{0} {1} {2:n2} {3:n2} {4:n3} {5:n3} {6:n3} {7:n3} {8} {9} {10} {11} {12} {13} {14} {15} {16}" -f $this.Time, $this.DestinationType, $this.NiceSizeDownload, $this.NiceThroughput, $this.NiceSpeedDownload, $this.TimeStarttransfer, $this.TimeDownload, $this.TimeTotal, $this.HttpCode, $this.HttpVersion, $this.DurationNamelookup, $this.DurationConnect, $this.DurationAppconnect, $this.DurationPretransfer, $this.DurationRedirect, $this.DurationStarttransfer, $this.Destination)
      return $text
   }
}
   
#SpeedTest is performing download via curl
function SpeedTest {
   [CmdletBinding()]
   param(
      [Parameter(Mandatory)]
      [string]$Url,
      [string]$UrlType
   )
   $Start=Timestamp
   Cprintf -Mode "report" -Text "$Start curl $Url"
   $Results=curl.exe -s -S -L -k -m60 -o NUL --write-out "$CurlFormat" "$Url" 2>&1
   Cprintf -Mode "report" -Text "Curl output: $Results"
   $Test=[TestResult]::new()
   $Test.ImportCurlResult($Start,$Url,$UrlType,$Results)
   return $Test
}

#Array for results
$SpeedTestResults=@{}
#Array for dedicated tunnel speedtest
$TunnelSpeedTestResults=@{}

for ($i=1; $i -le $loops; $i=$i+1)
{
   If ($Connected){
      Cprintf -Mode "default" -Text ("*** {0} Test {1}/{2}..." -f "Tunnel", $i, $loops)
      $TunnelSpeedTestResults[$i]=SpeedTest -Url "$AcheckerUrl" -UrlType "achecker"
      $TunnelSpeedTestResults[$i].CprintfTest()
      If($TunnelSpeedTestResults[$i].HttpCode -ne 200 ){
         Cprintf -Mode "error" -Text ("ERROR Wrong status code {0}" -f $TunnelSpeedTestResults[$i].StatusCode)
         Exit
      }
   }

   Cprintf -Mode "default" -Text ("*** {0} Test {1}/{2}..." -f $TargetType, $i, $loops)
   $SpeedTestResults[$i]=SpeedTest -Url "$Target" -UrlType "$TargetType"
   $SpeedTestResults[$i].CprintfTest()
   If($SpeedTestResults[$i].HttpCode -ne 200 ){
      Cprintf -Mode "error" -Text ("ERROR Wrong status code {0}" -f $SpeedTestResults[$i].StatusCode)
      Exit
   }

   Cprintf -Mode "default" -Text "*** Sleeping for $Interval seconds...."
   ping.exe -n $Interval -w 1000 $PingDest|Foreach{Cprintf -Mode "default" -Text ("{0} - {1}" -f (Timestamp),$_)}
}

Cprintf -Mode "default" -Text "***** EXPORT ***** $Comment"
Cprintf -Mode "default" -Text "Date Size(MB) Throughput(Mbps) ""End to End speed(Mbps)"" ""StartTransfert time(s)"" ""Download time(s)"" ""Total time(s)"" ""HTTP code"" ""HTTP Version"" ""DNS(ms)"" ""Connect(ms)"" ""App(ms)"" ""Pretransfer(ms)"" ""Redirect(ms)"" ""Starttransfer(ms)"" Destination"
for ($i=1; $i -le [int]$loops; $i=$i+1)
{
   Cprintf -Mode "default" -Text $SpeedTestResults[$i].Export()
}


Cprintf -Mode "default" -Text "***** STATISTICS ***** $Comment"

#Analyze perform Average,Min,Max compute for a property of the results
function Analyze{
   [CmdletBinding()]
   param(
      [Parameter(Mandatory)]
      [array]$Table,
      [Parameter(Mandatory)]
      [string]$PropertyTitle
   )

   return $Table.Values | Measure-Object -Property $PropertyTitle -Minimum -Maximum -Average
}

Cprintf -Mode "default" -Text ("{0,-30}|{1,7}|{2,7}|{3,7}|{4,7}" -f "Value", "Average", "Maximum", "Minimum", "Unit")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "NiceThroughput"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n2}|{2,7:n2}|{3,7:n2}|{4,7}" -f "Throughput Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "Mbps")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "NiceThroughput"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n2}|{2,7:n2}|{3,7:n2}|{4,7}" -f "Throughput $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "Mbps")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "NiceSpeedDownload"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n2}|{2,7:n2}|{3,7:n2}|{4,7}" -f "End to End Speed Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "Mbps")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "NiceSpeedDownload"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n2}|{2,7:n2}|{3,7:n2}|{4,7}" -f "End to End Speed $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "Mbps")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "TimeStarttransfer"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n3}|{2,7:n3}|{3,7:n3}|{4,7}" -f "Time to first byte Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "s")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "TimeStarttransfer"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n3}|{2,7:n3}|{3,7:n3}|{4,7}" -f "Time to first byte $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "s")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "TimeDownload"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n3}|{2,7:n3}|{3,7:n3}|{4,7}" -f "Download time Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "s")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "TimeDownload"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n3}|{2,7:n3}|{3,7:n3}|{4,7}" -f "Download time $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "s")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "TimeTotal"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n3}|{2,7:n3}|{3,7:n3}|{4,7}" -f "Total time Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "s")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "TimeTotal"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n3}|{2,7:n3}|{3,7:n3}|{4,7}" -f "Total time $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "s")

Cprintf -Mode "default" -Text "*** Duration details:"

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "DurationNamelookup"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "DNS lookup Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "DurationNamelookup"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "DNS lookup $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "DurationConnect"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "Connect Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "DurationConnect"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "Connect $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "DurationAppconnect"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "App Connect Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "DurationAppconnect"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "App Connect $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "DurationPretransfer"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "Pre Transfer Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "DurationPretransfer"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "Pre Transfer $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "DurationRedirect"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "Redirect Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "DurationRedirect"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "Redirect $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")

If($Connected){
   $Analyze = Analyze -Table $TunnelSpeedTestResults -PropertyTitle "DurationStarttransfer"
   Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "Start Transfer Tunnel", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")
}
$Analyze = Analyze -Table $SpeedTestResults -PropertyTitle "DurationStarttransfer"
Cprintf -Mode "default" -Text ("{0,-30}|{1,7:n0}|{2,7:n0}|{3,7:n0}|{4,7}" -f "Start Transfer $TargetType", $Analyze.Average, $Analyze.Maximum, $Analyze.Minimum, "ms")

$EndTime=Timestamp
Cprintf -Mode "report" -Text "$EndTime Ending"

If($Pcap){
    $PcapOutput=(cmd /c "$nsdiag" -c stop) -join [Environment]::NewLine
    Cprintf -Mode "default" -Text $PcapOutput
}

Stop-Job -Name NsSpeedtest*
Remove-job -Name NsSpeedtest*

Cprintf -Mode "report" -Text "***** END *****"
