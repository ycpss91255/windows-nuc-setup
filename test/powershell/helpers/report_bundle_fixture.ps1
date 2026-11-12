#Requires -Version 5.1
# Contract placeholder for the red test; no fixture is produced.
function New-TestReportBundleFixture {
 param([string]$RepositoryRoot,[string]$Destination)
 [pscustomobject]@{Root=$Destination}
}
