# ns_speedtest - Netskope Performance troubleshooting script.

# Introduction

This script helps to identify Throughput available on a device. Tests results are displayed on the command line and in log files.

# Main features

* Windows and Mac supported, Linux will come next
* Leverage download to Google Drive to calculate end to end performances
* Calculate average on multiple iterations
* CPU and latency recording
* Latency and routing logging

# Windows
## Usage
```
NAME
    V:\ns_speedtest\ns_speedtest.ps1

SYNOPSIS
    Netskope Performance troubleshooting script.


SYNTAX
    V:\ns_speedtest\ns_speedtest.ps1 [[-Size] <Int32>] [[-Interval] <Int32>] [[-Loops] <Int32>] [-Help] [-Report] [-Quiet]
    [-NoFiles] [-Pcap] [[-Comment] <String>] [[-Url] <String>] [[-LogFolder] <String>] [<CommonParameters>]


DESCRIPTION
    This script helps to identify Throughput available on a device. Tests results are displayed on the command line and in
    log files.


PARAMETERS
    -Size <Int32>
        Download size in MB

    -Interval <Int32>
        Waiting time between downloads, in seconds

    -Loops <Int32>
        Number of tests

    -Help [<SwitchParameter>]
        This help.

    -Report [<SwitchParameter>]
        Turn on report mode, display all informations recorded. By default log files includes all informations, and the
        command line a condensed output.

    -Quiet [<SwitchParameter>]
        Turn on quiet mode, no output will be displayed on the command line, use the log files to get test results

    -NoFiles [<SwitchParameter>]
        Disable all file logging.

    -Pcap [<SwitchParameter>]
        Perform packet capture at the same time.

    -Comment <String>
        Test comment, please write context related to the test.

    -Url <String>
        Destination url downloaded to evaluation the throughput. By default, the script use Google Drive.

    -LogFolder <String>
        Define the location of the log files. By default logs are store in Netskope Client log folder
        (C:\Users\Public\netSkope)

    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer, PipelineVariable, and OutVariable. For more information, see
        about_CommonParameters (https:/go.microsoft.com/fwlink/?LinkID=113216).

REMARKS
    To see the examples, type: "get-help V:\ns_speedtest\ns_speedtest.ps1 -examples".
    For more information, type: "get-help V:\ns_speedtest\ns_speedtest.ps1 -detailed".
    For technical information, type: "get-help V:\ns_speedtest\ns_speedtest.ps1 -full".
    For online help, type: "get-help V:\ns_speedtest\ns_speedtest.ps1 -online"
```

## Examples

# Mac
## Usage
```
Usage: ./ns_speedtest.sh [-i <nterval>] [-l <loops>] [-s <10|100>] [-u <download url>] -r -q -n -h -f folder
Options:
-c comment
-p perform inner capture at the same time
-i inverval in seconds
-l loops
-u URL
-s size 10 or 100MB for gdrive download
-r report mode, enable report mode on stdout, providing verbose output
-q quiet mode, disable output to the stdout
-n No Files mode, disable saving results in files
-h help
```

## Examples
