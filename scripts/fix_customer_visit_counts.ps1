$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$mainPath = Join-Path $repoRoot 'lib\main.dart'
$mainContent = Get-Content -Path $mainPath -Raw

$urlMatch = [regex]::Match($mainContent, "const _supabaseUrl = '([^']+)';")
$keyMatch = [regex]::Match($mainContent, "_supabaseAnonKey\s*=\s*'([^']+)';")

if (-not $urlMatch.Success -or -not $keyMatch.Success) {
  throw 'Failed to read Supabase config from lib/main.dart.'
}

$supabaseUrl = $urlMatch.Groups[1].Value
$supabaseKey = $keyMatch.Groups[1].Value

$headers = @{
  apikey        = $supabaseKey
  Authorization = "Bearer $supabaseKey"
  Prefer        = 'return=representation'
}

function Get-IntOrZero($value) {
  if ($null -eq $value -or $value -eq '') {
    return 0
  }
  return [int]$value
}

function Get-MinimumVisitCountForGrade([string]$grade) {
  switch ($grade) {
    'New' { return 1 }
    'N' { return 2 }
    'S' { return 5 }
    'G' { return 10 }
    'V' { return 20 }
    'VV' { return 50 }
    default { return 1 }
  }
}

function Get-GradeForVisitCount([int]$visitCount) {
  if ($visitCount -le 1) { return 'New' }
  if ($visitCount -le 4) { return 'N' }
  if ($visitCount -le 9) { return 'S' }
  if ($visitCount -le 19) { return 'G' }
  if ($visitCount -le 49) { return 'V' }
  return 'VV'
}

function Build-ContactLabel(
  [string]$prefix,
  [string]$phone,
  [string]$source,
  [int]$visitCount,
  [int]$dayVisitCount,
  [int]$nightVisitCount
) {
  $digits = ($phone -replace '\D', '')
  $suffix = if ($digits.Length -ge 4) { $digits.Substring($digits.Length - 4) } else { $digits }
  $grade = Get-GradeForVisitCount $visitCount
  return "$prefix$grade$source($dayVisitCount)($nightVisitCount)$suffix"
}

function Parse-Counts([string]$name) {
  $matches = [regex]::Matches($name, '\((\d+)\)')
  if ($matches.Count -lt 2) {
    return $null
  }

  return @{
    day = [int]$matches[0].Groups[1].Value
    night = [int]$matches[1].Groups[1].Value
  }
}

function Parse-Grade([string]$name) {
  $match = [regex]::Match($name, '(?:-)?(New|N|S|G|V|VV)(?:-)?')
  if ($match.Success) {
    return $match.Groups[1].Value
  }
  return $null
}

$customersUrl = "$supabaseUrl/rest/v1/customers?select=id,name,phone,customer_source,visit_count,day_visit_count,night_visit_count"
$customers = Invoke-RestMethod -Method Get -Uri $customersUrl -Headers $headers
$updated = @()

foreach ($customer in $customers) {
  $name = [string]$customer.name
  $grade = Parse-Grade $name
  if ([string]::IsNullOrWhiteSpace($grade)) {
    continue
  }

  $counts = Parse-Counts $name
  $minimumVisitCount = Get-MinimumVisitCountForGrade $grade

  if ($null -ne $counts) {
    $dayVisitCount = $counts.day
    $nightVisitCount = $counts.night
    $visitCount = [Math]::Max($minimumVisitCount, $dayVisitCount + $nightVisitCount)
  } else {
    $dayVisitCount = $minimumVisitCount
    $nightVisitCount = 0
    $visitCount = $minimumVisitCount
  }

  $currentVisitCount = Get-IntOrZero $customer.visit_count
  $currentDayVisitCount = Get-IntOrZero $customer.day_visit_count
  $currentNightVisitCount = Get-IntOrZero $customer.night_visit_count

  $payloadMap = @{
    visit_count = $visitCount
    day_visit_count = $dayVisitCount
    night_visit_count = $nightVisitCount
  }

  $source = [string]$customer.customer_source
  if (-not [string]::IsNullOrWhiteSpace($source) -and $name.Length -ge 2) {
    $prefix = $name.Substring(0, 2)
    $payloadMap['name'] = Build-ContactLabel `
      -prefix $prefix `
      -phone ([string]$customer.phone) `
      -source $source `
      -visitCount $visitCount `
      -dayVisitCount $dayVisitCount `
      -nightVisitCount $nightVisitCount
  }

  $nextName = if ($payloadMap.ContainsKey('name')) { [string]$payloadMap['name'] } else { $name }

  if (
    $currentVisitCount -eq $visitCount -and
    $currentDayVisitCount -eq $dayVisitCount -and
    $currentNightVisitCount -eq $nightVisitCount -and
    $name -eq $nextName
  ) {
    continue
  }

  $encodedId = [System.Uri]::EscapeDataString([string]$customer.id)
  $updateUrl = "$supabaseUrl/rest/v1/customers?id=eq.$encodedId"
  $payload = $payloadMap | ConvertTo-Json

  Invoke-RestMethod -Method Patch -Uri $updateUrl -Headers $headers -Body $payload -ContentType "application/json" | Out-Null

  $updated += [pscustomobject]@{
    id = $customer.id
    phone = $customer.phone
    old_name = $name
    new_name = $nextName
    visit_count = $visitCount
    day_visit_count = $dayVisitCount
    night_visit_count = $nightVisitCount
  }
}

$updated | ConvertTo-Json -Depth 5
