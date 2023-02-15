#!/bin/bash
# Copyright 2023 Netskope Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https:#www.apache.org/licenses/LICENSE-2.0
#
# Netskope Performance Troubleshooting Tool
# Author: Matthieu Bouthors

usage() { printf "Usage: $0 [-s <10|100>] [-i <interval>] [-l <loops>] [-c <comment>] [-u <download url>] [-r] [-q] [-n] [-f <folder>] [-p] [-h]
Options:
-c comment
-i inverval in seconds
-l loops
-s download size in MB (10 or 100)
-u custom download URL (otherwise Google Drive is used)
-r report mode, enable report mode on stdout, providing verbose output
-q quiet mode, disable output to the stdout
-n No Files mode, disable saving results in files
-f custom folder to save log files, by default Netskope Client log folder is used
-p perform inner capture at the same time
-h help\n" 1>&2; exit 1; }

#Defaults
Size=100
Interval=15
Loops=5
ReportMode=false
QuietMode=false
NoFiles=false
PcapMode=false
UrlArgs=false
PingDest=8.8.8.8
Mega=1048576
PID=$$
DefaultMaxStats=300

nsconfig="/Library/Application Support/Netskope/STAgent/nsconfig.json"
nsdiag="/Library/Application Support/Netskope/STAgent/nsdiag"
StatsCpu="top -l$DefaultMaxStats -n10 -i1"
OutputFolder=false
FilenameSpeedtest="nsspeedtest.log"
FilenameCpu="nsspeedtest_cpu.log"
FilenameLatency="nsspeedtest_latency.log"
Comment=false


CurlFormat="%{http_version}|%{http_code}|%{speed_download}|%{size_download}|%{time_total}|%{time_starttransfer}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_pretransfer}|%{time_redirect}"

declare -a gdrive
gdrive[10]="https://drive.google.com/uc?export=download&id=1UX-pO5OLPhv_hoUpk_ixu3IDmkHpqQoF"
gdrive[100]="https://drive.google.com/uc?export=download&id=1VYSsMYB0w18tntQipTZPkq3cg58nmEEo"


############## TEST PREPARATION ##############

Arguments="$@"

while getopts "c:f:hi:l:npqrs:u:" arg; do
    case "${arg}" in
        c)
            Comment=${OPTARG}
            ;;
        f)
            OutputFolder=${OPTARG}
            ;;
        h)
            usage
            ;;
        i)
            Interval=${OPTARG}
            ;;
        l)
            Loops=${OPTARG}
            ;;
        n)
            NoFiles=true
            ;;
        q)
            QuietMode=true
            ;;
        p)
            PcapMode=true
            ;;
        r)
            ReportMode=true
            ;;
        s)
            Size=${OPTARG}
            ((Size == 10 || Size == 100)) || usage
            ;;
        u)
            UrlArgs=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift "$((OPTIND-1))"

if [ "$Comment" == false ]; then
    printf "Please add a comment for this test, for example: \"Test Wifi 1\": "
    read Comment
fi

#Target Definition
if [ "$UrlArgs" == false ]; then
    Target=${gdrive[$Size]}
    TargetType="gdrive"
else
    Target="$UrlArgs"
    TargetType="custom"
fi

#OS detection
uname=$(uname -a)
if [[ "$uname" =~ Darwin ]]; then
    mode="mac"
    if [ "$OutputFolder" == false ]; then
        OutputFolder="/Library/Logs/Netskope"
    fi
else
    printf "ERROR: Unsupported system\n"
    exit
fi

#Output folder control
if [ "$NoFiles" == false ]; then
    if [ ! -d "$OutputFolder" ]; then
        while true; do
            read -p "Log folder not found, do you want to log in the local folder ([Y]es/No/Cancel)?" ync
            case $ync in
                [Yy]* ) OutputFolder="."; break;;
                "")     OutputFolder="."; break;;
                [Nn]* ) NoFiles=true; break;;
                [Cc]* ) exit;;
                * ) echo "Please answer Yes, No or Cancel";;
            esac
        done
    fi
fi

# Setting up file names
if [ "$NoFiles" == false ]; then
    OutputFile="$OutputFolder/$FilenameSpeedtest"
    OutputFileLatency="$OutputFolder/$FilenameLatency"
    OutputFileCpu="$OutputFolder/$FilenameCpu"
fi

# Making sure there is an output and preparing end of command line to redirect outputs
CommandEnd=""
if [ "$QuietMode" == true ]; then
    if [ "$NoFiles" == true ]; then
        printf "ERROR: No output to files or screen, exiting\n"
        exit
    else
        CommandEnd=">> $OutputFile 2>&1"
    fi
else
    if [ "$NoFiles" == true ]; then
        CommandEnd=""
    else
        CommandEnd="|tee -a $OutputFile"
    fi
fi

# File rotation over 10MB
RotateFile(){
    local File=$1
    if [ ! -f "$File" ]; then
        return
    fi
    #get file size
    case "$mode" in
        mac)
            FileSize=$(stat -f%z "$File")
            ;;
        *)
            return
            ;;
    esac

    if [ $FileSize -gt 10000000 ]; then
        printf "Rotation needed for file %s, current size is %i\n" "$File" $FileSize 
        mv "$File" "$File.bak"
    fi
}

if [ "$NoFiles" == false ]; then
    RotateFile "$OutputFile"
    RotateFile "$OutputFileLatency"
    RotateFile "$OutputFileCpu"
fi


############## TEST START ##############

StartTime=$(date -Iseconds)


#### FUNCTION BEGIN
# Print output to stdout and file
# GLOBALS: 
#   QuietMode, ReportMode, NoFiles, PID, OutputFile
# ARGUMENTS: 
#   Print mode:
#    - "default", print screen and file
#    - "report", print screen (if report mode) and always to file
#   Print text: string to print
# OUTPUTS: 
#   Print text on the screen based on parameters
# RETURN: 
#   None
### FUNCTION END
#modes: 
# - "default": print screen and file, follow Quiet and NoFiles flags
# - "report": output files only but default, follows NoFiles and Report flags
# - "error": output always screen, follow NoFiles flag
# Global to disable file output
Cprintf(){
    local PrintMode=$1; shift
    local PrintText="$1"; shift
    if [ $PrintMode == error ]; then
        printf "$PrintText" "$@"
        if [ $NoFiles == false ]; then
            printf "[$PID] $PrintText" "$@" >> $OutputFile
        fi  
    fi

    if [ $PrintMode == default ]; then
        if [ $QuietMode == false ]; then
            printf "$PrintText" "$@"
        fi
        if [ $NoFiles == false ]; then
            printf "[$PID] $PrintText" "$@" >> $OutputFile
        fi  
    fi
    if [ $PrintMode == report ]; then
        if [ $ReportMode == true ]; then
            if [ $QuietMode == false ]; then
                printf "$PrintText" "$@"
            fi
        fi
        if [ $NoFiles == false ]; then
            printf "[$PID] $PrintText" "$@" >> $OutputFile
        fi  
    fi
}





Cprintf "report" "***** START ***** %s\n" "$Comment"
Cprintf "default" "%s Starting $0 %s\n" "$StartTime" "$Arguments"

Cprintf "report" "***** Options ***** %s\n" "$Comment"
Cprintf "report" "PID = %s\n" "${PID}"
Cprintf "report" "Report Mode = %s\n" "${ReportMode}"
Cprintf "report" "Quiet Mode = %s\n" "${QuietMode}"
Cprintf "report" "Pcap Mode = %s\n" "${PcapMode}"
Cprintf "report" "NoFiles Mode = %s\n" "${NoFiles}"
Cprintf "report" "Log folder = %s\n" "${OutputFolder}"
Cprintf "report" "Speedtest file = %s\n" "${OutputFile}"
Cprintf "report" "Latency file = %s\n" "${OutputFileLatency}"
Cprintf "report" "Cpu stats file = %s\n" "${OutputFileCpu}"

Cprintf "report" "Size = %s\n" "${Size}"
Cprintf "report" "Interval = %i\n" "${Interval}"
Cprintf "report" "Loops = %i\n" "${Loops}"
Cprintf "report" "Target type = %s\n" "${TargetType}"
Cprintf "report" "Target = %s\n" "${Target}"
Cprintf "report" "Curl Format = %s\n" "${CurlFormat}"
Cprintf "report" "%s\n" "$uname"


Cprintf "default" "***** DEVICE CONTEXT ***** %s\n" "$Comment"

case "$mode" in
    mac)
        Cprintf "default" "*** Mac detected\n"
        MacDetails=$(system_profiler SPSoftwareDataType SPHardwareDataType)
        Cprintf "default" "%s\n" "$MacDetails"
        ;;
    *)
        Cprintf "error" "ERROR: Unsupported system\n"
        exit
        ;;
esac

Cprintf "default" "*** Netskope Client Configuration\n"
if [ -f "$nsdiag" ]; then
    ClientConfiguration=$("$nsdiag" -f)
    Cprintf "default" "%s\n" "${ClientConfiguration}"
else
    ClientConfiguration=""
    Cprintf "error" "WARNING: Netskope Client nsdiag not found\n"
fi

Cprintf "default" "*** Netskope context\n"
if [ -f "${nsconfig}" ]; then
    DpGatewayLdns=$(grep '"host": "gateway-' "${nsconfig}"|cut -d'"' -f4)
    Cprintf "default" "DP Gateway LDNS    = %s\n" "${DpGatewayLdns}"
    DpGatewayLdnsIp=$(dig +short "$DpGatewayLdns")
    Cprintf "default" "DP Gateway LDNS IP = %s\n" "${DpGatewayLdnsIp}"
    if [[ $DpGatewayLdns =~ gateway-(.*) ]]; then
        Management=${BASH_REMATCH[1]}
        Cprintf "default" "Management         = %s\n" "${Management}"
        Achecker="achecker-$Management"
        Cprintf "default" "Achercker          = %s\n" "${Achecker}"
        AcheckerUrl="https://$Achecker/downloadsize=${Size}m"
        Cprintf "default" "Achecker Download   = %s\n" "${AcheckerUrl}"
    else
        Cprintf "error" "Management domain not found\n"
        Connected=false
    fi
else
    Cprintf  "error" "WARNING: Netskope Client Configuration file not found\n"
fi

if [[ "${ClientConfiguration}" =~ NSTUNNEL_CONNECTED ]]
then
    Connected=true
    Cprintf "default" "Tunnel Connected\n"

    if [[ "${ClientConfiguration}" =~ Tunnel\ Protocol::\ DTLS ]]; then
        Cprintf "default" "DTLS detected\n"
    fi

    if [[ "${ClientConfiguration}" =~ Gateway\ IP::\ ([0-9.]*)\. ]]; then 
        DpGatewayIp="${BASH_REMATCH[1]}"
        Cprintf "default" "DP Gateway IP      = %s\n" "${DpGatewayIp}"
        PingDest="${DpGatewayIp}"
    else 
        Cprintf "default" "Gateway IP not found\n"; 
    fi
else
    Connected=false
    Cprintf "default" "Tunnel NOT Connected\n"
    PingDest="drive.google.com"
    if [ "$PcapMode" == true ]; then
        Cprintf "error" "ERROR: Disabling Pcap because tunnel is not connected\n"
        PcapMode=false
    fi
	
fi

#search for real public IP, ifconfig.me need to be steered by Netskope
PublicIP=$(curl -s "ifconfig.me/ip")
Cprintf "default" "Public IP: %s\n" "${PublicIP}"
PublicXFF=$(curl -s "ifconfig.me/forwarded")
Cprintf "default" "Public X-Forwarded-For: %s\n" "${PublicXFF}"

Cprintf "report" "*** Device Route table\n"
NetstatOutput=$(netstat -rn)
Cprintf "report" "%s\n" "$NetstatOutput"

Cprintf "report" "Starting traceroute to $PingDest\n"
eval "traceroute -q1 -w2 -m20 $PingDest $CommandEnd"


############## BACKGROUND MONITORING ##############

if [ "$PcapMode" == true ]; then
    Pcap=$("$nsdiag" -c start -s 60)
    Cprintf "default" "$Pcap\n"
fi

PingPid=false
TopPid=false
if [ "$NoFiles" == false ]; then
    eval "ping --apple-time -c${DefaultMaxStats} ${PingDest} >> $OutputFileLatency&"
    PingPid=$!
    Cprintf "default" "*** Latency recording started (%s)\n" "$PingPid"

    eval "$StatsCpu >> $OutputFileCpu&"
    CpuPid=$!
    Cprintf "default" "*** Cpu recording started (%s)\n" "$CpuPid"
fi


############## TEST FUNCTIONS ##############

declare -a Destination DestinationType HttpVersion HttpCode SpeedDownload SizeDownload TimeTotal TimeStarttransfer TimeNamelookup TimeConnect TimeAppconnect TimePretransfer TimeRedirect TimeDownload Throughput NiceThroughput NiceSpeedDownload NiceSizeDownload DurationNamelookup DurationConnect DurationAppconnect DurationPretransfer DurationRedirect DurationStarttransfer

#### FUNCTION BEGIN
# Perform speedtest
# GLOBALS: 
# 	CurlFormat Mega Destination HttpVersion HttpCode SpeedDownload SizeDownload TimeTotal TimeStarttransfer TimeNamelookup TimeConnect TimeAppconnect TimePretransfer TimeRedirect TimeDownload Throughput NiceThroughput NiceSpeedDownload NiceSizeDownload DurationNamelookup DurationConnect DurationAppconnect DurationPretransfer DurationRedirect DurationStarttransfer
# ARGUMENTS: 
#   Array Index
# 	Url
#   Url type
# OUTPUTS: 
# 	Speedtest results based on the configuration
# RETURN: 
# 	None
### FUNCTION END
SpeedTest() {
    local i="$1"
    local url="$2"
    local UrlType="$3"
    DateStr[$i]=`date -Iseconds`
    Cprintf "default" "*** %s Test %i %s...\n" "${DateStr[$i]}" "$i" "${url}"
    res=$(curl -s -L -k -o /dev/null --write-out "${CurlFormat}" "${url}")
    Cprintf "report" "Curl output: %s\n" "$res"
    
    Destination[$i]="${url}"
    DestinationType[$i]="${UrlType}"
    HttpVersion[$i]="$(echo "${res}" | cut -d'|' -f1)"
    HttpCode[$i]="$(echo "${res}" | cut -d'|' -f2)"
    SpeedDownload[$i]="$(echo "${res}" | cut -d'|' -f3)"
    SizeDownload[$i]="$(echo "${res}" | cut -d'|' -f4)"
    TimeTotal[$i]="$(echo "${res}" | cut -d'|' -f5)"
    TimeStarttransfer[$i]="$(echo "${res}" | cut -d'|' -f6)"
    TimeNamelookup[$i]="$(echo "${res}" | cut -d'|' -f7)"
    TimeConnect[$i]="$(echo "${res}" | cut -d'|' -f8)"
    TimeAppconnect[$i]="$(echo "${res}" | cut -d'|' -f9)"
    TimePretransfer[$i]="$(echo "${res}" | cut -d'|' -f10)"
    TimeRedirect[$i]="$(echo "${res}" | cut -d'|' -f11)"

    TimeDownload[$i]="$(echo "${TimeTotal[$i]} - ${TimeStarttransfer[$i]}" | bc)"
    Throughput[$i]="$(echo "${SizeDownload[$i]} * 8 / ${TimeDownload[$i]}" | bc)"

    NiceThroughput[$i]="$(echo "scale=2; ${Throughput[$i]} / ${Mega}" | bc -l)"
    NiceSpeedDownload[$i]="$(echo "scale=2; ${SpeedDownload[$i]} * 8 / ${Mega}" | bc -l)"
    NiceSizeDownload[$i]="$(echo "scale=2; ${SizeDownload[$i]} / ${Mega}" | bc -l)"
    DurationNamelookup[$i]="$(echo "${TimeNamelookup[$i]} * 1000 / 1" | bc)"
    DurationConnect[$i]="$(echo "(${TimeConnect[$i]} - ${TimeNamelookup[$i]}) * 1000 / 1" | bc)"
    DurationAppconnect[$i]="$(echo "(${TimeAppconnect[$i]} - ${TimeConnect[$i]}) * 1000 / 1" | bc)"
    DurationPretransfer[$i]="$(echo "(${TimePretransfer[$i]} - ${TimeAppconnect[$i]}) * 1000 / 1" | bc)"
    if [ ${TimeRedirect[$i]} == 0.000000 ]
    then
        DurationRedirect[$i]=0
        DurationStarttransfer[$i]="$(echo "(${TimeStarttransfer[$i]} - ${TimePretransfer[$i]}) * 1000 / 1" | bc)"
    else
        DurationRedirect[$i]="$(echo "(${TimeRedirect[$i]} - ${TimePretransfer[$i]}) * 1000 / 1" | bc)"
        DurationStarttransfer[$i]="$(echo "(${TimeStarttransfer[$i]} - ${TimeRedirect[$i]}) * 1000 / 1" | bc)"
    fi

    Cprintf "default" "http version:       %s\n"        "${HttpVersion[$i]}"
    Cprintf "default" "http code:          %s\n"        "${HttpCode[$i]}"
    Cprintf "default" "Size:               %s MB\n"  "${NiceSizeDownload[$i]}"
    Cprintf "default" "Throughput          %s Mbps\n" "${NiceThroughput[$i]}"
    Cprintf "default" "End to End Speed:   %s Mbps\n" "${NiceSpeedDownload[$i]}"
    Cprintf "default" "Total time:         %.3f s\n"      "${TimeTotal[$i]}"
    Cprintf "default" "StartTransfer Time: %.3f s (DNS:%sms,Connect:%sms,App:%sms,Pretransfer:%sms,Redirect:%sms,Startransfer:%sms)\n"      "${TimeStarttransfer[$i]}" "${DurationNamelookup[$i]}" "${DurationConnect[$i]}" "${DurationAppconnect[$i]}" "${DurationPretransfer[$i]}" "${DurationRedirect[$i]}" "${DurationStarttransfer[$i]}"

    Cprintf "default" "Download Time:      %.3f s\n"      "${TimeDownload[$i]}"
    
    Cprintf "report" "Details:\n"
    Cprintf "report" "NameLookupTime:     %.3f s\n"      "${TimeNamelookup[$i]}"
    Cprintf "report" "ConnectTime:        %.3f s\n"      "${TimeConnect[$i]}"
    Cprintf "report" "AppConnectTime:     %.3f s\n"      "${TimeAppconnect[$i]}"
    Cprintf "report" "PretransferTime:    %.3f s\n"      "${TimePretransfer[$i]}"
    Cprintf "report" "RedirectTime:       %.3f s\n"      "${TimeRedirect[$i]}"
    Cprintf "report" "StarttransferTime:  %.3f s\n"      "${TimeStarttransfer[$i]}"
    Cprintf "report" "TotalTime:          %.3f s\n"      "${TimeTotal[$i]}"
    return
}


############## TEST LOOPS ##############

Cprintf "default" "***** SPEEDTEST ***** %s\n" "$Comment"

i=1
Index=0
for (( i=1; i<=$Loops; i++ ))
do

#If connected, testing Dataplane first
    if [ "$Connected" == true ]; then
    	((Index++))
        SpeedTest "$Index" "${AcheckerUrl}" "achecker"
        StatusCode="${HttpCode[$Index]}"
        
        if [ $StatusCode -ne 200 ]
        then
            Cprintf "error" "ERROR: Wrong status code %s\n" "${HttpCode[$Index]}"
            exit
        fi
    fi

#Target test
    ((Index++))
    SpeedTest "$Index" "${Target}" "${TargetType}"
    StatusCode="${HttpCode[$Index]}"

    if [ "$StatusCode" -ne 200 ]
    then
        Cprintf "error" "ERROR: Wrong status code %s\n" "${StatusCode}"
	exit
    fi

    Cprintf "default" "*** Sleeping %i seconds....\n" "${Interval}"
    eval "ping --apple-time -c${Interval} ${PingDest} ${CommandEnd}"
done


############## EXPORT ##############

Cprintf "default" "***** EXPORT ***** %s\n" "$Comment"
Cprintf "default" "Date Size(MB) Throughput(Mbps) \"End to End speed(Mbps)\" \"StartTransfert time(s)\" \"Download time(s)\" \"Total time(s)\" \"HTTP code\" \"HTTP Version\" \"DNS(ms)\" \"Connect(ms)\" \"App(ms)\" \"Pretransfer(ms)\" \"Redirect(ms)\" \"Starttransfer(ms)\" Destination\n"
i=1
for (( i=1; i<=$Index; i++ ))
do
    Cprintf "default" "%s %s %s %s %.3f %.3f %.3f %.3f %s %s %s %s %s %s %s %s %s %s\n" "${DateStr[$i]}" "${DestinationType[$i]}" ${NiceSizeDownload[$i]} ${NiceThroughput[$i]} ${NiceSpeedDownload[$i]} ${TimeStarttransfer[$i]} ${TimeDownload[$i]} ${TimeTotal[$i]} ${HttpCode[$i]} ${HttpVersion[$i]} "${DurationNamelookup[$i]}" "${DurationConnect[$i]}" "${DurationAppconnect[$i]}" "${DurationPretransfer[$i]}" "${DurationRedirect[$i]}" "${DurationStarttransfer[$i]}" "${Destination[$i]}"
done

############## STATISTICS ##############

Cprintf "default" "***** STATISTICS ***** %s\n" "$Comment"

declare Max Min Total Avg

#Analyze perform Average,Min,Max compute for a property of the results
function Analyze() {
    [ "$#" -gt 1 ] || return

    Filter=$1
    shift

    Max=false
    Min=false
    Total=false
    Avg=false
    Index=0
    Count=0

    for Value in "$@"; do
    
        ((Index++))

        if [[ ${DestinationType[$Index]} =~ $Filter ]]
        then
            if [ "$Max" == false ]
            then
                Max=$Value
                Min=$Value
                Total=$Value
                ((Count++))
            else
                if (( $(echo "$Value > $Max" |bc -l) )) ; then
                  Max=$Value
                fi
                if (( $(echo "$Value < $Min" |bc -l) )) ; then
                  Min=$Value
                fi
                Total=$(echo "$Total + $Value"|bc -l)
                ((Count++))
            fi
        fi

    done
    if [ "$Count" -ge 1 ]; then
        Avg=$(echo "$Total / $Count"|bc -l)
    else
        Avg=0
    fi
}

Cprintf "default" "%-30s|%7s|%7s|%7s|%7s\n" "Value" "Average" "Maximum" "Minimum" "Unit"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${NiceThroughput[@]}"
    Cprintf "default" "%-30s|%7.2f|%7.2f|%7.2f|%7s\n" "Throughput tunnel" "$Avg" "$Max" "$Min" "Mbps"
fi
Analyze "$TargetType" "${NiceThroughput[@]}"
Cprintf "default" "%-30s|%7.2f|%7.2f|%7.2f|%7s\n" "Throughput $TargetType" "$Avg" "$Max" "$Min" "Mbps"


if [ "$Connected" == true ]; then
    Analyze "achecker" "${NiceSpeedDownload[@]}"
    Cprintf "default" "%-30s|%7.2f|%7.2f|%7.2f|%7s\n" "End to End Speed tunnel" "$Avg" "$Max" "$Min" "Mbps"
fi
Analyze "$TargetType" "${NiceSpeedDownload[@]}"
Cprintf "default" "%-30s|%7.2f|%7.2f|%7.2f|%7s\n" "End to End Speed $TargetType" "$Avg" "$Max" "$Min" "Mbps"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${TimeStarttransfer[@]}"
    Cprintf "default" "%-30s|%7.3f|%7.3f|%7.3f|%7s\n" "Time to first byte tunnel" "$Avg" "$Max" "$Min" "s"
fi
Analyze "$TargetType" "${TimeStarttransfer[@]}"
Cprintf "default" "%-30s|%7.3f|%7.3f|%7.3f|%7s\n" "Time to first byte $TargetType" "$Avg" "$Max" "$Min" "s"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${TimeDownload[@]}"
    Cprintf "default" "%-30s|%7.3f|%7.3f|%7.3f|%7s\n" "Download time tunnel" "$Avg" "$Max" "$Min" "s"
fi
Analyze "$TargetType" "${TimeDownload[@]}"
Cprintf "default" "%-30s|%7.3f|%7.3f|%7.3f|%7s\n" "Download time $TargetType" "$Avg" "$Max" "$Min" "s"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${TimeTotal[@]}"
    Cprintf "default" "%-30s|%7.3f|%7.3f|%7.3f|%7s\n" "Total time tunnel" "$Avg" "$Max" "$Min" "s"
fi
Analyze "$TargetType" "${TimeTotal[@]}"
Cprintf "default" "%-30s|%7.3f|%7.3f|%7.3f|%7s\n" "Total time $TargetType" "$Avg" "$Max" "$Min" "s"

Cprintf "default" "*** Duration details:\n"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${DurationNamelookup[@]}"
    Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "DNS lookup tunnel" "$Avg" "$Max" "$Min" "ms"
fi
Analyze "$TargetType" "${DurationNamelookup[@]}"
Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "DNS lookup $TargetType" "$Avg" "$Max" "$Min" "ms"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${DurationConnect[@]}"
    Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "Connect tunnel" "$Avg" "$Max" "$Min" "ms"
fi
Analyze "$TargetType" "${DurationConnect[@]}"
Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "Connect $TargetType" "$Avg" "$Max" "$Min" "ms"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${DurationAppconnect[@]}"
    Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "App Connect tunnel" "$Avg" "$Max" "$Min" "ms"
fi
Analyze "$TargetType" "${DurationAppconnect[@]}"
Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "App Connect $TargetType" "$Avg" "$Max" "$Min" "ms"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${DurationPretransfer[@]}"
    Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "Pre Transfer tunnel" "$Avg" "$Max" "$Min" "ms"
fi
Analyze "$TargetType" "${DurationPretransfer[@]}"
Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "Pre Transfer $TargetType" "$Avg" "$Max" "$Min" "ms"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${DurationRedirect[@]}"
    Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "Redirect tunnel" "$Avg" "$Max" "$Min" "ms"
fi
Analyze "$TargetType" "${DurationRedirect[@]}"
Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "Redirect $TargetType" "$Avg" "$Max" "$Min" "ms"

if [ "$Connected" == true ]; then
    Analyze "achecker" "${DurationStarttransfer[@]}"
    Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "Start Transfer tunnel $TargetType" "$Avg" "$Max" "$Min" "ms"
fi
Analyze "$TargetType" "${DurationStarttransfer[@]}"
Cprintf "default" "%-30s|%7.0f|%7.0f|%7.0f|%7s\n" "Start Transfer $TargetType" "$Avg" "$Max" "$Min" "ms"

EndTime=$(date -Iseconds)
Cprintf "default" "%s Ending $0 %s\n" "$EndTime" "$Arguments"

if [ "$PingPid" != false ]; then
    kill -SIGQUIT "$PingPid"
    Cprintf "default" "*** Latency recording stopped (%s)\n" "$PingPid"
fi

if [ "$CpuPid" != false ]; then
    kill -SIGINT "$CpuPid"
    Cprintf "default" "*** Cpu recording stopped (%s)\n" "$CpuPid"

fi
if [ "$PcapMode" == true ]; then
    Pcap=$("$nsdiag" -d stop)
    Cprintf "default" "$Pcap\n"
fi

Cprintf "default" "***** END *****\n"
