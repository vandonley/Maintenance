<#
.Synopsis
   Generate a list top CPU usage for failure report in RMM.
.DESCRIPTION
   WMI call for processor performance.
.EXAMPLE
   vitGet-CPUPerf.ps1
.OUTPUTS
  Total CPU usage, idle, and top 10 applications.
.EMAIL
   vdonley@visionms.net
.VERSION
   1.0
#>
# WMI call for formatted processor performance counters
$myPerf = Get-WmiObject Win32_PerfFormattedData_PerfProc_Process
# Sort by CPU percent, show 12 as first two will likely be Total and Idle, and output as a string.
$myPerf | Sort-Object PercentProcessorTime -Descending |Select-Object Name,IDProcess,PercentProcessorTime,PageFaultsPersec,WorkingSet,ThreadCount,PriorityBase -First 12 |`
    Format-List | Out-String