$script:OwnershipRouterSchemaVersion = 1
$script:OwnershipRouteKinds = @('setting', 'extension')
$script:OwnershipMatchTypes = @('exact', 'prefix', 'publisher')
$script:OwnershipDestinationTypes = @('component', 'platform', 'machine', 'profile', 'exclude', 'unresolved')
$script:OwnershipRouteSources = @('repository-policy', 'user-confirmed', 'custom-file', 'inferred', 'migration')
$script:OwnershipRouteStatuses = @('approved', 'provisional', 'disabled')
$script:OwnershipRoutingModes = @('Supplement', 'Override', 'Isolated')

function New-OwnershipRouterDocument {
    $document = New-OrderedMap
    $document['schemaVersion'] = $script:OwnershipRouterSchemaVersion
    $document['routes'] = [object[]]@()
    return $document
}

function Get-ManagedOwnershipRouterPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'config/ownership-router.jsonc'))
}

function ConvertFrom-OwnershipYamlScalar {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][int]$LineNumber
    )

    $value = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    if ($value.StartsWith('"')) {
        try { return ConvertFrom-JsonC -Content $value -Source "$Source`:$LineNumber" }
        catch { throw "Invalid quoted YAML scalar in '$Source' at line $LineNumber`: $($_.Exception.Message)" }
    }
    if ($value.StartsWith("'")) {
        if (-not $value.EndsWith("'") -or $value.Length -lt 2) {
            throw "Unterminated YAML scalar in '$Source' at line $LineNumber."
        }
        return $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    if ($value -match '^(?i:true|false)$') { return $value -ieq 'true' }
    if ($value -match '^(?i:null|~)$') { return $null }
    $integer = 0L
    if ([long]::TryParse($value, [ref]$integer)) { return $integer }
    return $value
}

function ConvertFrom-OwnershipRouterYaml {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Source
    )

    $document = New-OwnershipRouterDocument
    $routes = [System.Collections.Generic.List[object]]::new()
    $current = $null
    $section = $null
    $seenSchema = $false
    $seenRoutes = $false
    $lines = $Content -split "`r?`n"
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $raw = $lines[$index]
        if ($raw.Contains("`t")) { throw "Tabs are not supported in router YAML '$Source' at line $lineNumber." }
        $line = Remove-YamlComment -Line $raw
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Trim() -eq '---') { continue }

        if ($line -match '^schemaVersion:\s*(.+)$') {
            if ($seenSchema) { throw "Duplicate schemaVersion in '$Source'." }
            $document['schemaVersion'] = ConvertFrom-OwnershipYamlScalar $Matches[1] $Source $lineNumber
            $seenSchema = $true
            continue
        }
        if ($line -match '^routes:\s*$') {
            if ($seenRoutes) { throw "Duplicate routes block in '$Source'." }
            $seenRoutes = $true
            continue
        }
        if ($line -match '^  -\s+id:\s*(.+)$') {
            if (-not $seenRoutes) { throw "Route appears before routes block in '$Source' at line $lineNumber." }
            $current = New-OrderedMap
            $current['id'] = ConvertFrom-OwnershipYamlScalar $Matches[1] $Source $lineNumber
            $routes.Add($current)
            $section = $null
            continue
        }
        if ($null -eq $current) { throw "Unsupported router YAML in '$Source' at line $lineNumber." }
        if ($line -match '^    (match|destination):\s*$') {
            $section = $Matches[1]
            $current[$section] = New-OrderedMap
            continue
        }
        if ($line -match '^    ([A-Za-z][A-Za-z0-9]*):\s*(.*)$') {
            $current[$Matches[1]] = ConvertFrom-OwnershipYamlScalar $Matches[2] $Source $lineNumber
            $section = $null
            continue
        }
        if ($line -match '^      ([A-Za-z][A-Za-z0-9]*):\s*(.*)$' -and $section) {
            $current[$section][$Matches[1]] = ConvertFrom-OwnershipYamlScalar $Matches[2] $Source $lineNumber
            continue
        }
        throw "Unsupported router YAML in '$Source' at line $lineNumber."
    }
    if (-not $seenSchema -or -not $seenRoutes) {
        throw "Router YAML '$Source' requires schemaVersion and routes."
    }
    $document['routes'] = [object[]]$routes.ToArray()
    return $document
}

function Read-OwnershipRouterFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowMissing
    )

    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        if ($AllowMissing) { return New-OwnershipRouterDocument }
        throw "Ownership router '$resolved' does not exist."
    }
    $extension = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
    $content = [System.IO.File]::ReadAllText($resolved)
    if ($extension -in @('.yaml', '.yml')) {
        return ConvertFrom-OwnershipRouterYaml -Content $content -Source $resolved
    }
    if ($extension -notin @('.json', '.jsonc')) {
        throw "Ownership router '$resolved' must use .json, .jsonc, .yaml, or .yml."
    }
    return ConvertFrom-JsonC -Content $content -Source $resolved
}

function ConvertTo-OwnershipRouterYaml {
    param([Parameter(Mandatory)]$Document)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("schemaVersion: $($Document.schemaVersion)")
    $lines.Add('')
    $lines.Add('routes:')
    foreach ($route in @($Document.routes)) {
        $lines.Add("  - id: $([string]$route.id | ConvertTo-Json -Compress)")
        $lines.Add("    kind: $($route.kind)")
        $lines.Add('    match:')
        $lines.Add("      type: $($route.match.type)")
        $lines.Add("      value: $([string]$route.match.value | ConvertTo-Json -Compress)")
        $lines.Add('    destination:')
        $lines.Add("      type: $($route.destination.type)")
        if ($route.destination.Contains('name')) {
            $lines.Add("      name: $([string]$route.destination.name | ConvertTo-Json -Compress)")
        }
        $lines.Add("    source: $($route.source)")
        $lines.Add("    status: $($route.status)")
        $lines.Add("    reason: $([string]$route.reason | ConvertTo-Json -Compress)")
    }
    return ($lines -join "`n") + "`n"
}

function Write-OwnershipRouterFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Document
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $content = if ($extension -in @('.yaml', '.yml')) {
        ConvertTo-OwnershipRouterYaml $Document
    }
    else {
        ConvertTo-PrettyJson $Document
    }
    Write-Utf8File -Path $Path -Content $content
}

function New-OwnershipDestination {
    param(
        [Parameter(Mandatory)][ValidateSet('component', 'platform', 'machine', 'profile', 'exclude', 'unresolved')][string]$Type,
        [string]$Name
    )

    $destination = New-OrderedMap
    $destination['type'] = $Type.ToLowerInvariant()
    if ($Name) { $destination['name'] = $Name }
    return $destination
}

function New-OwnershipRoute {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('setting', 'extension')][string]$Kind,
        [Parameter(Mandatory)][ValidateSet('exact', 'prefix', 'publisher')][string]$MatchType,
        [Parameter(Mandatory)][string]$MatchValue,
        [Parameter(Mandatory)]$Destination,
        [ValidateSet('repository-policy', 'user-confirmed', 'custom-file', 'inferred', 'migration')][string]$Source = 'user-confirmed',
        [ValidateSet('approved', 'provisional', 'disabled')][string]$Status = 'approved',
        [Parameter(Mandatory)][string]$Reason
    )

    $route = New-OrderedMap
    $route['id'] = $Id
    $route['kind'] = $Kind
    $route['match'] = New-OrderedMap
    $route['match']['type'] = $MatchType
    $route['match']['value'] = $MatchValue
    $route['destination'] = $Destination
    $route['source'] = $Source
    $route['status'] = $Status
    $route['reason'] = $Reason
    return $route
}

function Get-OwnershipDestinationLabel {
    param([Parameter(Mandatory)]$Destination)
    if ($Destination.Contains('name')) { return "$($Destination.type)/$($Destination.name)" }
    return [string]$Destination.type
}

function Test-OwnershipRouteMatch {
    param(
        [Parameter(Mandatory)]$Route,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Item
    )

    if ([string]$Route.kind -ine $Kind) { return $false }
    $type = [string]$Route.match.type
    $value = [string]$Route.match.value
    switch ($type.ToLowerInvariant()) {
        'exact' { return $Item -ieq $value }
        'prefix' { return $Item.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase) }
        'publisher' {
            if ($Kind -ne 'extension') { return $false }
            $publisher = ($Item -split '\.', 2)[0]
            return $publisher -ieq $value
        }
        default { return $false }
    }
}

function Test-OwnershipRouterDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document,
        [string]$RepositoryRoot,
        [string]$Source = '<router>',
        [switch]$Custom
    )

    $result = New-ValidationResult
    if (-not (Test-IsDictionary $Document)) {
        Add-ValidationItem $result errors 'router-root' 'Ownership router root must be an object.' $Source
        return $result
    }
    foreach ($key in $Document.Keys) {
        if ([string]$key -notin @('schemaVersion', 'routes')) {
            Add-ValidationItem $result errors 'router-unknown-field' "Unknown router field '$key'." $Source
        }
    }
    if (-not $Document.Contains('schemaVersion') -or [int]$Document.schemaVersion -ne $script:OwnershipRouterSchemaVersion) {
        Add-ValidationItem $result errors 'router-schema-version' "Router requires schemaVersion $($script:OwnershipRouterSchemaVersion)." $Source
    }
    if (-not $Document.Contains('routes') -or $Document.routes -isnot [System.Array]) {
        Add-ValidationItem $result errors 'router-routes' 'Router requires a routes array.' $Source
        return $result
    }

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $signatures = @{}
    $components = @()
    $profiles = @()
    $platforms = @()
    if ($RepositoryRoot) {
        $components = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'components') -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
        $profiles = @(Get-ProfileDefinitions $RepositoryRoot | ForEach-Object Id)
        $platforms = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'platform') -Filter '*.jsonc' -File -ErrorAction SilentlyContinue | ForEach-Object BaseName)
    }

    foreach ($routeValue in @($Document.routes)) {
        if (-not (Test-IsDictionary $routeValue)) {
            Add-ValidationItem $result errors 'router-route-root' 'Every route must be an object.' $Source
            continue
        }
        $route = $routeValue
        foreach ($field in @('id', 'kind', 'match', 'destination', 'source', 'status', 'reason')) {
            if (-not $route.Contains($field)) {
                Add-ValidationItem $result errors 'router-route-field' "Route is missing required field '$field'." $Source
            }
        }
        if (-not $route.Contains('id')) { continue }
        $id = [string]$route.id
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
            Add-ValidationItem $result errors 'router-route-id' "Route ID '$id' is invalid." $Source
        }
        elseif (-not $ids.Add($id)) {
            Add-ValidationItem $result errors 'router-duplicate-id' "Route ID '$id' is duplicated." $Source
        }
        if ([string]$route.kind -notin $script:OwnershipRouteKinds) {
            Add-ValidationItem $result errors 'router-kind' "Route '$id' has invalid kind '$($route.kind)'." $Source
        }
        if (-not (Test-IsDictionary $route.match) -or -not $route.match.Contains('type') -or -not $route.match.Contains('value')) {
            Add-ValidationItem $result errors 'router-match' "Route '$id' requires match.type and match.value." $Source
            continue
        }
        $matchType = [string]$route.match.type
        $matchValue = [string]$route.match.value
        if ($matchType -notin $script:OwnershipMatchTypes -or [string]::IsNullOrWhiteSpace($matchValue)) {
            Add-ValidationItem $result errors 'router-match' "Route '$id' has an invalid match." $Source
        }
        if ($matchType -eq 'publisher' -and [string]$route.kind -ne 'extension') {
            Add-ValidationItem $result errors 'router-match-kind' "Publisher route '$id' must target extensions." $Source
        }
        if ($matchType -eq 'publisher' -and $matchValue -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') {
            Add-ValidationItem $result errors 'router-publisher' "Route '$id' has invalid extension publisher '$matchValue'." $Source
        }
        if (-not (Test-IsDictionary $route.destination) -or -not $route.destination.Contains('type')) {
            Add-ValidationItem $result errors 'router-destination' "Route '$id' requires destination.type." $Source
            continue
        }
        $destinationType = [string]$route.destination.type
        $destinationName = if ($route.destination.Contains('name')) { [string]$route.destination.name } else { $null }
        if ($destinationType -notin $script:OwnershipDestinationTypes) {
            Add-ValidationItem $result errors 'router-destination-type' "Route '$id' has invalid destination type '$destinationType'." $Source
        }
        if ($destinationType -in @('component', 'platform', 'profile') -and [string]::IsNullOrWhiteSpace($destinationName)) {
            Add-ValidationItem $result errors 'router-destination-name' "Route '$id' destination '$destinationType' requires a name." $Source
        }
        if ($destinationType -in @('machine', 'exclude', 'unresolved') -and $destinationName) {
            Add-ValidationItem $result errors 'router-destination-name' "Route '$id' destination '$destinationType' cannot embed a machine or owner name." $Source
        }
        if ($RepositoryRoot) {
            if ($destinationType -eq 'component' -and $components -inotcontains $destinationName) {
                Add-ValidationItem $result errors 'router-missing-component' "Route '$id' references missing component '$destinationName'." $Source
            }
            if ($destinationType -eq 'profile' -and $profiles -inotcontains $destinationName) {
                Add-ValidationItem $result errors 'router-missing-profile' "Route '$id' references missing profile '$destinationName'." $Source
            }
            if ($destinationType -eq 'platform' -and $platforms -inotcontains $destinationName) {
                Add-ValidationItem $result errors 'router-missing-platform' "Route '$id' references missing platform '$destinationName'." $Source
            }
        }
        if ([string]$route.source -notin $script:OwnershipRouteSources) {
            Add-ValidationItem $result errors 'router-source' "Route '$id' has invalid provenance '$($route.source)'." $Source
        }
        if ([string]$route.status -notin $script:OwnershipRouteStatuses) {
            Add-ValidationItem $result errors 'router-status' "Route '$id' has invalid status '$($route.status)'." $Source
        }
        elseif ([string]$route.status -eq 'provisional') {
            Add-ValidationItem $result warnings 'router-provisional' "Route '$id' is provisional and will only be suggested." $Source
        }
        elseif ([string]$route.status -eq 'disabled') {
            Add-ValidationItem $result warnings 'router-disabled' "Route '$id' is disabled." $Source
        }
        if (-not $route.Contains('reason') -or [string]::IsNullOrWhiteSpace([string]$route.reason)) {
            Add-ValidationItem $result errors 'router-reason' "Route '$id' requires a human-readable reason." $Source
        }
        $signature = "$($route.kind)|$matchType|$($matchValue.ToLowerInvariant())"
        if ($signatures.ContainsKey($signature)) {
            $other = $signatures[$signature]
            $sameDestination = (Get-OwnershipDestinationLabel $other.destination) -ieq (Get-OwnershipDestinationLabel $route.destination)
            $level = if ($sameDestination) { 'warnings' } else { 'errors' }
            $validationCode = if ($sameDestination) { 'router-duplicate-route' } else { 'router-conflicting-route' }
            Add-ValidationItem $result $level $validationCode "Routes '$($other.id)' and '$id' use the same match$(if (-not $sameDestination) { ' with contradictory destinations' })." $Source
        }
        else { $signatures[$signature] = $route }
        if ($matchType -eq 'prefix' -and ($matchValue.Length -lt 3 -or -not $matchValue.Contains('.'))) {
            Add-ValidationItem $result warnings 'router-broad-pattern' "Route '$id' uses a broad prefix '$matchValue'." $Source
        }
    }

    $patterns = @($Document.routes | Where-Object { $_.match.type -in @('prefix', 'publisher') })
    for ($left = 0; $left -lt $patterns.Count; $left++) {
        for ($right = $left + 1; $right -lt $patterns.Count; $right++) {
            $a = $patterns[$left]
            $b = $patterns[$right]
            if ($a.kind -ine $b.kind -or $a.match.type -ine $b.match.type) { continue }
            $av = [string]$a.match.value
            $bv = [string]$b.match.value
            if ($av.StartsWith($bv, [System.StringComparison]::OrdinalIgnoreCase) -or
                $bv.StartsWith($av, [System.StringComparison]::OrdinalIgnoreCase)) {
                Add-ValidationItem $result warnings 'router-overlapping-pattern' "Routes '$($a.id)' and '$($b.id)' overlap; the most specific match wins." $Source
            }
        }
    }
    return $result
}

function Get-ApprovedOwnershipMatches {
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)][ValidateSet('exact', 'pattern')][string]$Category
    )

    return @($Document.routes | Where-Object {
        $type = [string]$_.match.type
        $categoryMatch = if ($Category -eq 'exact') { $type -eq 'exact' } else { $type -ne 'exact' }
        $categoryMatch -and $_.status -eq 'approved' -and (Test-OwnershipRouteMatch $_ $Kind $Item)
    } | Sort-Object @{ Expression = { ([string]$_.match.value).Length }; Descending = $true }, @{ Expression = { [string]$_.id }; Ascending = $true })
}

function Resolve-OwnershipItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Item,
        [AllowNull()]$Value,
        [object[]]$ExistingOwners = @(),
        [Parameter(Mandatory)]$ManagedRouter,
        $CustomRouter,
        [ValidateSet('Supplement', 'Override', 'Isolated')][string]$RoutingMode = 'Supplement',
        $ExplicitDestination
    )

    $candidates = [System.Collections.Generic.List[object]]::new()
    $ownerList = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in @($ExistingOwners)) {
        if ($candidate -is [System.Array]) {
            foreach ($nested in $candidate) { if ($null -ne $nested) { $ownerList.Add($nested) } }
        }
        elseif ($null -ne $candidate) { $ownerList.Add($candidate) }
    }
    $owners = [object[]]$ownerList.ToArray()
    $classification = if ($Kind -eq 'setting') { Get-SettingValueClassification -SettingKey $Item -Value $Value } else { $null }
    if ($ExplicitDestination) {
        $candidates.Add([pscustomobject]@{ precedence = 1; source = 'per-run'; id = 'explicit-assignment'; status = 'matched'; destination = $ExplicitDestination; reason = 'Explicit assignment for this synchronization.' })
    }

    $customExact = if ($CustomRouter) { @(Get-ApprovedOwnershipMatches $CustomRouter $Kind $Item exact) } else { @() }
    foreach ($route in $customExact) {
        $candidates.Add([pscustomobject]@{ precedence = 2; source = 'custom'; id = $route.id; status = 'matched'; destination = $route.destination; reason = $route.reason })
    }
    if ($owners.Count -gt 1) {
        $paths = @($owners | ForEach-Object path) -join ', '
        throw "Ownership conflict for $Kind '$Item': $paths. Remove duplicate ownership before synchronizing."
    }
    if ($owners.Count -eq 1) {
        $owner = $owners[0]
        $candidates.Add([pscustomobject]@{ precedence = 3; source = 'existing'; id = 'existing-repository-owner'; status = 'matched'; destination = $owner.destination; reason = "Existing exact repository ownership at $($owner.path)."; owner = $owner })
    }
    if ($RoutingMode -ne 'Isolated') {
        foreach ($route in @(Get-ApprovedOwnershipMatches $ManagedRouter $Kind $Item exact)) {
            $status = if ($RoutingMode -eq 'Override' -and $customExact.Count -gt 0) { 'suppressed-by-custom' } else { 'matched' }
            $candidates.Add([pscustomobject]@{ precedence = 4; source = 'managed'; id = $route.id; status = $status; destination = $route.destination; reason = $route.reason })
        }
    }
    $customPattern = if ($CustomRouter) { @(Get-ApprovedOwnershipMatches $CustomRouter $Kind $Item pattern) } else { @() }
    foreach ($route in $customPattern) {
        $candidates.Add([pscustomobject]@{ precedence = 5; source = 'custom'; id = $route.id; status = 'matched'; destination = $route.destination; reason = $route.reason; specificity = ([string]$route.match.value).Length })
    }
    if ($RoutingMode -ne 'Isolated') {
        foreach ($route in @(Get-ApprovedOwnershipMatches $ManagedRouter $Kind $Item pattern)) {
            $status = if ($RoutingMode -eq 'Override' -and $customPattern.Count -gt 0) { 'suppressed-by-custom' } else { 'matched' }
            $candidates.Add([pscustomobject]@{ precedence = 6; source = 'managed'; id = $route.id; status = $status; destination = $route.destination; reason = $route.reason; specificity = ([string]$route.match.value).Length })
        }
    }
    foreach ($route in @($ManagedRouter.routes + $(if ($CustomRouter) { @($CustomRouter.routes) } else { @() }) | Where-Object {
        $_.status -eq 'provisional' -and (Test-OwnershipRouteMatch $_ $Kind $Item)
    })) {
        $candidates.Add([pscustomobject]@{ precedence = 7; source = 'suggestion'; id = $route.id; status = 'provisional'; destination = $route.destination; reason = $route.reason })
    }

    $eligible = @($candidates | Where-Object status -eq 'matched' | Sort-Object precedence, @{ Expression = { if ($_.PSObject.Properties.Name -contains 'specificity') { -[int]$_.specificity } else { 0 } } })
    $winner = $null
    if ($eligible.Count -gt 0) {
        $bestPrecedence = $eligible[0].precedence
        $sameLevel = @($eligible | Where-Object precedence -eq $bestPrecedence)
        if ($bestPrecedence -in @(5, 6) -and $sameLevel.Count -gt 1) {
            $specificity = ($sameLevel | Measure-Object specificity -Maximum).Maximum
            $sameLevel = @($sameLevel | Where-Object specificity -eq $specificity)
        }
        $destinations = @($sameLevel | ForEach-Object { Get-OwnershipDestinationLabel $_.destination } | Select-Object -Unique)
        if ($destinations.Count -gt 1) {
            $routeIds = @($sameLevel | ForEach-Object id) -join ', '
            throw "Routing conflict for $Kind '$Item' at precedence $bestPrecedence`: $routeIds."
        }
        $winner = $sameLevel[0]
    }

    $override = $null
    if ($Kind -eq 'setting' -and $classification.classification -eq 'secret-or-private') {
        $override = [pscustomobject]@{
            destination = New-OwnershipDestination exclude
            id = 'security-classification'
            reason = 'Sensitive or private state is always excluded.'
        }
    }
    elseif ($Kind -eq 'setting' -and $classification.classification -eq 'machine-local-path') {
        $override = [pscustomobject]@{
            destination = New-OwnershipDestination machine
            id = 'machine-path-classification'
            reason = 'Machine-local path classification overrides portable routing.'
        }
    }
    if ($override) {
        $candidates.Add([pscustomobject]@{ precedence = 0; source = 'classification'; id = $override.id; status = 'override'; destination = $override.destination; reason = $override.reason })
        $winner = [pscustomobject]@{ precedence = 0; source = 'classification'; id = $override.id; status = 'matched'; destination = $override.destination; reason = $override.reason }
    }

    return [pscustomobject][ordered]@{
        kind = $Kind
        item = $Item
        classification = $classification
        candidates = [object[]]$candidates.ToArray()
        winner = $winner
        resolved = $null -ne $winner -and [string]$winner.destination.type -notin @('unresolved')
        destination = if ($winner) { $winner.destination } else { New-OwnershipDestination unresolved }
    }
}

function ConvertTo-UnresolvedRouterDocument {
    param([Parameter(Mandatory)][object[]]$Items)

    $document = New-OwnershipRouterDocument
    $routes = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Items | Sort-Object kind, item) {
        $safe = ([string]$item.item).ToLowerInvariant() -replace '[^a-z0-9._-]', '-'
        $routes.Add((New-OwnershipRoute -Id "unresolved-$($item.kind)-$safe" -Kind $item.kind -MatchType exact -MatchValue $item.item `
            -Destination (New-OwnershipDestination unresolved) -Source inferred -Status provisional `
            -Reason 'Review and replace the unresolved destination before reuse.'))
    }
    $document['routes'] = [object[]]$routes.ToArray()
    return $document
}
