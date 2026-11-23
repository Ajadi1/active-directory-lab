<#
.SYNOPSIS
  Bulk-creates lab users in Active Directory from a CSV (AD & PowerShell Automation Lab, Step 7).

.DESCRIPTION
  - Builds OU structure:  _EMPLOYEES\<Department>  and  _GROUPS
  - Creates one security group per department (GRP-<Department>)
  - Creates each user with Department/Title/Company set, a random temporary
    password, and "must change password at next logon"
  - Usernames: first initial + last name (e.g. jsmith); duplicates get a number (jsmith2)
  - Safe to re-run: existing OUs, groups and users are skipped
  - Writes created usernames + temp passwords to a CSV for the lab (in production
    you would deliver these through a secure channel, never a plain file)

.EXAMPLE
  Set-ExecutionPolicy Bypass -Scope Process -Force
  C:\ADLab\Create-LabUsers.ps1
#>

param(
    [string]$CsvPath    = "C:\ADLab\users.csv",
    [string]$OutputPath = "C:\ADLab\temp-passwords.csv",
    [string]$Company    = "MyDomain Corp"
)

Import-Module ActiveDirectory -ErrorAction Stop

$domain   = Get-ADDomain
$domainDN = $domain.DistinguishedName
$upnSuffix = $domain.DNSRoot

function New-TempPassword {
    param([int]$Length = 14)
    $upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower  = 'abcdefghijkmnopqrstuvwxyz'
    $digits = '23456789'
    $symbol = '!@#$%*?'
    $all    = $upper + $lower + $digits + $symbol
    $rng    = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $pick = {
        param($set)
        $b = New-Object byte[] 4
        $rng.GetBytes($b)
        $set[[BitConverter]::ToUInt32($b, 0) % $set.Length]
    }
    # Guarantee one of each character class, then fill and shuffle
    $chars = @( (& $pick $upper), (& $pick $lower), (& $pick $digits), (& $pick $symbol) )
    for ($i = $chars.Count; $i -lt $Length; $i++) { $chars += (& $pick $all) }
    -join ($chars | Sort-Object { Get-Random })
}

function Ensure-OU {
    param([string]$Name, [string]$Path)
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false
        Write-Host "  + OU  $dn" -ForegroundColor Cyan
    }
    return $dn
}

# --- 1. Load CSV ---------------------------------------------------------------
if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
$users = Import-Csv $CsvPath
Write-Host "Loaded $($users.Count) users from $CsvPath" -ForegroundColor Green

# --- 2. OU structure + department groups --------------------------------------
Write-Host "`nBuilding OUs and groups..." -ForegroundColor Green
$employeesOU = Ensure-OU -Name "_EMPLOYEES" -Path $domainDN
$groupsOU    = Ensure-OU -Name "_GROUPS"    -Path $domainDN

$departments = $users.Department | Sort-Object -Unique
$deptOU = @{}
foreach ($dept in $departments) {
    $deptOU[$dept] = Ensure-OU -Name $dept -Path $employeesOU
    $groupName = "GRP-$dept"
    if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $groupName -SamAccountName $groupName -GroupScope Global `
            -GroupCategory Security -Path $groupsOU -Description "All $dept department staff"
        Write-Host "  + Group $groupName" -ForegroundColor Cyan
    }
}

# --- 3. Users ------------------------------------------------------------------
Write-Host "`nCreating users..." -ForegroundColor Green
$results = @()
$created = 0; $skipped = 0; $failed = 0

foreach ($u in $users) {
    $first = $u.FirstName.Trim()
    $last  = $u.LastName.Trim()
    $base  = ($first.Substring(0,1) + $last).ToLower() -replace '[^a-z0-9]', ''
    $display = "$first $last"

    # Skip if this exact person already exists (makes re-runs safe)
    $existing = Get-ADUser -Filter "GivenName -eq '$first' -and Surname -eq '$last' -and Department -eq '$($u.Department)'" -ErrorAction SilentlyContinue
    if ($existing) { $skipped++; continue }

    # Unique sAMAccountName: jsmith, jsmith2, jsmith3...
    $sam = $base; $n = 2
    while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) { $sam = "$base$n"; $n++ }

    $tempPw = New-TempPassword
    try {
        New-ADUser -Name $display -DisplayName $display `
            -GivenName $first -Surname $last `
            -SamAccountName $sam -UserPrincipalName "$sam@$upnSuffix" `
            -Department $u.Department -Title $u.Title -Company $Company `
            -Path $deptOU[$u.Department] `
            -AccountPassword (ConvertTo-SecureString $tempPw -AsPlainText -Force) `
            -ChangePasswordAtLogon $true -Enabled $true -ErrorAction Stop

        Add-ADGroupMember -Identity "GRP-$($u.Department)" -Members $sam

        $results += [pscustomobject]@{
            Username     = $sam
            Name         = $display
            Department   = $u.Department
            Title        = $u.Title
            TempPassword = $tempPw
        }
        $created++
        Write-Progress -Activity "Creating users" -Status "$sam ($created of $($users.Count))" `
            -PercentComplete (($created + $skipped) / $users.Count * 100)
    }
    catch {
        $failed++
        Write-Warning "Failed to create $display : $($_.Exception.Message)"
    }
}
Write-Progress -Activity "Creating users" -Completed

# --- 4. Output -----------------------------------------------------------------
if ($results.Count -gt 0) {
    $results | Export-Csv $OutputPath -NoTypeInformation
    Write-Host "`nTemp passwords saved to $OutputPath (lab only)" -ForegroundColor Yellow
}

Write-Host "`nDone. Created: $created  Skipped (already existed): $skipped  Failed: $failed" -ForegroundColor Green
Write-Host "`nUsers per department:" -ForegroundColor Green
foreach ($dept in $departments) {
    $count = (Get-ADGroupMember "GRP-$dept").Count
    Write-Host ("  {0,-12} {1}" -f $dept, $count)
}
