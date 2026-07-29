Set-StrictMode -Version Latest

$script:MachineSchemaVersion = 1
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:SensitivePattern = '(?i)(password|(?<!semantic)token|secret|credential|connectionstring|api[_-]?key|private[_-]?key)'
$script:PrivateResourcePattern = '(?i)(saved.?connections?|connection.?profiles?|(^|[._/-])connections?($|[._/-])|user(name)?|account.?id|private.?host|remote.?endpoint|remote\.ssh\.(remoteplatform|serverinstallpath)|certificate|identity.?file|ssh.?key|authentication.?state)'
$script:CredentialValuePattern = '(?i)(ghp_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{12,}|(?:password|token|secret|api[_-]?key)\s*[:=]\s*\S+|(?:postgres(?:ql)?|mongodb(?:\+srv)?|mysql|mssql|redis|amqp|ssh)://[^\s/@:]+:[^@\s]+@|(?:Server|Data Source|Host)\s*=[^;]+;|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
$script:CodeProfileSchema = 'vscode-user-data-profile-template'
$script:CodeProfileSchemaVersion = 'unversioned'
$script:CodeProfileVerifiedVersion = '1.129.1'
$script:CodeProfileVerifiedCommit = '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8'

. (Join-Path $PSScriptRoot 'OwnershipRouter.ps1')

function New-OrderedMap {
    return [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
}

function ConvertFrom-JsonElement {
    param([Parameter(Mandatory)][System.Text.Json.JsonElement]$Element)

    switch ($Element.ValueKind) {
        Object {
            $result = New-OrderedMap
            foreach ($property in $Element.EnumerateObject()) {
                $result[$property.Name] = ConvertFrom-JsonElement -Element $property.Value
            }
            return ,$result
        }
        Array {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Element.EnumerateArray()) {
                $items.Add((ConvertFrom-JsonElement -Element $item))
            }
            return ,$items.ToArray()
        }
        String { return $Element.GetString() }
        Number {
            $integer = 0L
            if ($Element.TryGetInt64([ref]$integer)) { return $integer }
            $decimal = 0D
            if ($Element.TryGetDecimal([ref]$decimal)) { return $decimal }
            return $Element.GetDouble()
        }
        True { return $true }
        False { return $false }
        Null { return $null }
        default { throw "Unsupported JSON value kind '$($Element.ValueKind)'." }
    }
}

function ConvertFrom-JsonC {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][string]$Content,
        [string]$Source = '<text>'
    )

    process {
        try {
            $options = [System.Text.Json.JsonDocumentOptions]@{
                AllowTrailingCommas = $true
                CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
            }
            $document = [System.Text.Json.JsonDocument]::Parse($Content, $options)
            try {
                return ConvertFrom-JsonElement -Element $document.RootElement
            }
            finally {
                $document.Dispose()
            }
        }
        catch {
            throw "Invalid JSONC in '$Source': $($_.Exception.Message)"
        }
    }
}

function Read-JsonCFile {
    param([Parameter(Mandatory)][string]$Path)
    return ConvertFrom-JsonC -Content ([System.IO.File]::ReadAllText($Path)) -Source $Path
}

function Remove-YamlComment {
    param([Parameter(Mandatory)][string]$Line)

    $singleQuoted = $false
    $doubleQuoted = $false
    for ($index = 0; $index -lt $Line.Length; $index++) {
        $character = $Line[$index]
        if ($character -eq "'" -and -not $doubleQuoted) {
            if ($singleQuoted -and $index + 1 -lt $Line.Length -and $Line[$index + 1] -eq "'") {
                $index++
                continue
            }
            $singleQuoted = -not $singleQuoted
        }
        elseif ($character -eq '"' -and -not $singleQuoted) {
            $escaped = $index -gt 0 -and $Line[$index - 1] -eq '\'
            if (-not $escaped) { $doubleQuoted = -not $doubleQuoted }
        }
        elseif ($character -eq '#' -and -not $singleQuoted -and -not $doubleQuoted) {
            return $Line.Substring(0, $index).TrimEnd()
        }
    }
    return $Line.TrimEnd()
}

function ConvertFrom-YamlScalar {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][int]$LineNumber
    )

    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "Invalid YAML in '$Source' at line $LineNumber`: a scalar value is required."
    }
    if ($trimmed.StartsWith('"')) {
        try { return $trimmed | ConvertFrom-Json -ErrorAction Stop }
        catch { throw "Invalid YAML in '$Source' at line $LineNumber`: invalid double-quoted value." }
    }
    if ($trimmed.StartsWith("'")) {
        if (-not $trimmed.EndsWith("'") -or $trimmed.Length -lt 2) {
            throw "Invalid YAML in '$Source' at line $LineNumber`: unterminated single-quoted value."
        }
        return $trimmed.Substring(1, $trimmed.Length - 2).Replace("''", "'")
    }
    if ($trimmed -match '[:\[\]\{\},&*!|>@`]') {
        throw "Invalid or unsupported YAML scalar in '$Source' at line $LineNumber`."
    }
    return $trimmed
}

function Read-ProfileRecipe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $lines = [System.IO.File]::ReadAllLines($Path)
    $name = $null
    $components = [System.Collections.Generic.List[string]]::new()
    $section = $null
    $seenName = $false
    $seenComponents = $false

    for ($index = 0; $index -lt $lines.Length; $index++) {
        $lineNumber = $index + 1
        $rawLine = $lines[$index]
        if ($rawLine.Contains("`t")) {
            throw "Invalid YAML in '$Path' at line $lineNumber`: tabs are not supported."
        }
        $line = Remove-YamlComment -Line $rawLine
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Trim() -eq '---') { continue }

        if ($line -match '^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2]
            switch ($key) {
                'name' {
                    if ($seenName) { throw "Invalid YAML in '$Path' at line $lineNumber`: duplicate 'name'." }
                    $name = ConvertFrom-YamlScalar -Value $value -Source $Path -LineNumber $lineNumber
                    $seenName = $true
                    $section = $null
                }
                'components' {
                    if ($seenComponents) { throw "Invalid YAML in '$Path' at line $lineNumber`: duplicate 'components'." }
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        throw "Invalid YAML in '$Path' at line $lineNumber`: components must be a block list."
                    }
                    $seenComponents = $true
                    $section = 'components'
                }
                default { throw "Invalid YAML in '$Path' at line $lineNumber`: unsupported key '$key'." }
            }
            continue
        }

        if ($line -match '^\s{2}-\s+(.+)$' -and $section -eq 'components') {
            $component = ConvertFrom-YamlScalar -Value $Matches[1] -Source $Path -LineNumber $lineNumber
            if ($component -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
                throw "Invalid YAML in '$Path' at line $lineNumber`: invalid component ID '$component'."
            }
            $components.Add($component)
            continue
        }

        throw "Invalid or unsupported YAML in '$Path' at line $lineNumber`."
    }

    if (-not $seenName -or [string]::IsNullOrWhiteSpace([string]$name)) {
        throw "Invalid YAML in '$Path': required 'name' is missing."
    }
    if (-not $seenComponents -or $components.Count -eq 0) {
        throw "Invalid YAML in '$Path': required 'components' list is missing or empty."
    }

    return [pscustomobject]@{
        Name = [string]$name
        Components = [string[]]$components.ToArray()
    }
}

function New-ValidationResult {
    return [pscustomobject]@{
        errors = [System.Collections.Generic.List[object]]::new()
        warnings = [System.Collections.Generic.List[object]]::new()
        information = [System.Collections.Generic.List[object]]::new()
    }
}

function Add-ValidationItem {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][ValidateSet('errors', 'warnings', 'information')][string]$Level,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [string]$Source,
        [string]$Path
    )
    $item = [ordered]@{ code = $Code; message = $Message }
    if ($Source) { $item.source = $Source }
    if ($Path) { $item.path = $Path }
    $Result.$Level.Add([pscustomobject]$item)
}

function Get-RelativeDisplayPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string]$Path)
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $relative = [System.IO.Path]::GetRelativePath($root, $fullPath)
    if (-not $relative.StartsWith('..') -and -not [System.IO.Path]::IsPathRooted($relative)) {
        return $relative.Replace('\', '/')
    }
    return "[external]/$([System.IO.Path]::GetFileName($fullPath))"
}

function Test-IsDictionary {
    param($Value)
    return $Value -is [System.Collections.IDictionary]
}

function Get-ValueLeaves {
    param($Value, [string]$Path = '')
    if (Test-IsDictionary $Value) {
        foreach ($key in $Value.Keys) {
            $childPath = if ($Path) { "$Path/$key" } else { "/$key" }
            Get-ValueLeaves -Value $Value[$key] -Path $childPath
        }
        return
    }
    if ($Value -is [System.Array]) {
        for ($index = 0; $index -lt $Value.Count; $index++) {
            Get-ValueLeaves -Value $Value[$index] -Path "$Path/$index"
        }
        return
    }
    [pscustomobject]@{ Path = $Path; Value = $Value }
}

function Get-PathValueKind {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $trimmed = $Value.Trim().Trim('"', "'")
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }
    if ($trimmed -match '^/(?:[^/\\]|\\.)+/[dgimsuvy]*$') { return $null }
    if ($trimmed -match '(?i)^file:(//)?/?[A-Z]:[\\/]' -or
        $trimmed -match '(?i)^[A-Z]:[\\/]' -or
        $trimmed -match '^(\\\\|//)[^\\/]+[\\/][^\\/]+' -or
        $trimmed -match '^/(?!/)[^\s]*' -or
        $trimmed -match '^~[\\/]' -or
        $trimmed -match '(?i)^(%((USERPROFILE)|(HOME)|(LOCALAPPDATA)|(APPDATA))%[\\/]|(\$\{?env:)(USERPROFILE|HOME|LOCALAPPDATA|APPDATA)\}?[\\/]|(\$\{?)(USERPROFILE|HOME|LOCALAPPDATA|APPDATA)\}?[\\/])') {
        return 'machine-path'
    }
    return $null
}

function Get-SafeSettingValueDisplay {
    param(
        [Parameter(Mandatory)][string]$Classification,
        [AllowNull()]$Value
    )

    if ($Classification -in @('secret-or-private', 'machine-local-path')) {
        return "[REDACTED: $Classification]"
    }
    $text = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
    if ($text.Length -gt 120) { return $text.Substring(0, 117) + '...' }
    return $text
}

function Get-SettingValueClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SettingKey,
        [AllowNull()]$Value
    )

    $sensitivePaths = [System.Collections.Generic.List[string]]::new()
    $machinePaths = [System.Collections.Generic.List[string]]::new()
    if ($SettingKey -match $script:SensitivePattern -or $SettingKey -match $script:PrivateResourcePattern) {
        $sensitivePaths.Add("/$(ConvertTo-JsonPointerSegment $SettingKey)")
    }
    foreach ($leaf in (Get-ValueLeaves -Value $Value)) {
        $leafPath = "/$(ConvertTo-JsonPointerSegment $SettingKey)$($leaf.Path)"
        $text = if ($null -eq $leaf.Value) { '' } else { [string]$leaf.Value }
        if ($leaf.Path -match $script:SensitivePattern -or
            $leaf.Path -match $script:PrivateResourcePattern -or
            $text -match $script:CredentialValuePattern) {
            $sensitivePaths.Add($leafPath)
            continue
        }
        if ($leaf.Value -is [string] -and (Get-PathValueKind -Value $text)) {
            $machinePaths.Add($leafPath)
        }
    }

    if ($sensitivePaths.Count -gt 0) {
        return [pscustomobject][ordered]@{
            classification = 'secret-or-private'
            destination = 'excluded-private'
            ruleId = 'sync-sensitive-setting'
            paths = [string[]]$sensitivePaths.ToArray()
            safeValue = Get-SafeSettingValueDisplay 'secret-or-private' $Value
        }
    }
    if ($machinePaths.Count -gt 0) {
        return [pscustomobject][ordered]@{
            classification = 'machine-local-path'
            destination = 'machine-local'
            ruleId = 'sync-machine-local-path'
            paths = [string[]]$machinePaths.ToArray()
            safeValue = Get-SafeSettingValueDisplay 'machine-local-path' $Value
        }
    }
    return [pscustomobject][ordered]@{
        classification = 'portable'
        destination = 'profile-recipe'
        ruleId = 'sync-portable-setting'
        paths = [string[]]@()
        safeValue = Get-SafeSettingValueDisplay 'portable' $Value
    }
}

function Test-PortableSettings {
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Source
    )
    foreach ($leaf in (Get-ValueLeaves -Value $Settings)) {
        $stringValue = if ($null -eq $leaf.Value) { '' } else { [string]$leaf.Value }
        if ($leaf.Value -is [string] -and (Get-PathValueKind -Value $stringValue)) {
            Add-ValidationItem -Result $Result -Level errors -Code 'portable-absolute-path' -Message 'Portable source contains an absolute or machine-local path.' -Source $Source -Path $leaf.Path
        }
        $placeholder = $stringValue -match '(?i)(<[^>]+>|example|placeholder|replace[- ]?me)'
        if (($leaf.Path -match $script:SensitivePattern -and $stringValue -and -not $placeholder) -or
            ($stringValue -match $script:CredentialValuePattern)) {
            Add-ValidationItem -Result $Result -Level errors -Code 'portable-likely-secret' -Message 'Portable component contains a likely secret or credential value.' -Source $Source -Path $leaf.Path
        }
        elseif ($leaf.Path -match $script:PrivateResourcePattern -and $stringValue -and -not $placeholder) {
            Add-ValidationItem -Result $Result -Level errors -Code 'portable-private-resource' -Message 'Portable component contains private connection, host, account, certificate, or authentication state.' -Source $Source -Path $leaf.Path
        }
    }
}

function Read-ExtensionFile {
    param([Parameter(Mandatory)][string]$Path)
    $entries = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $lineNumber++
        $value = $line.Trim()
        if (-not $value -or $value.StartsWith('#')) { continue }
        $entries.Add([pscustomobject]@{ Id = $value; Line = $lineNumber })
    }
    return $entries.ToArray()
}

function Get-ProfileDefinitions {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $profileRoot = Join-Path $RepositoryRoot 'profiles'
    if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $profileRoot -File | Where-Object Extension -in '.yaml', '.yml' | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Id = $_.BaseName; Path = $_.FullName }
    })
}

function Get-DefaultVSCodeUserDataPath {
    [CmdletBinding()]
    param()

    if ($IsWindows) {
        return [System.IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)) 'Code/User'))
    }
    if ($IsMacOS) {
        return [System.IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) 'Library/Application Support/Code/User'))
    }
    $configurationRoot = if ($env:XDG_CONFIG_HOME) {
        $env:XDG_CONFIG_HOME
    }
    else {
        Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.config'
    }
    return [System.IO.Path]::GetFullPath((Join-Path $configurationRoot 'Code/User'))
}

function Get-LiveVSCodeProfileDefinitions {
    [CmdletBinding()]
    param([string]$VSCodeUserDataPath)

    $userDataPath = if ($VSCodeUserDataPath) {
        [System.IO.Path]::GetFullPath($VSCodeUserDataPath)
    }
    else {
        Get-DefaultVSCodeUserDataPath
    }
    $storagePath = Join-Path $userDataPath 'globalStorage/storage.json'
    if (-not (Test-Path -LiteralPath $storagePath -PathType Leaf)) {
        throw "VS Code profile metadata was not found at '$storagePath'. Use -VSCodeUserDataPath to select the intended VS Code User directory."
    }

    $storage = Read-JsonCFile $storagePath
    if (-not (Test-IsDictionary $storage)) {
        throw "VS Code profile metadata '$storagePath' must have an object root."
    }

    $profiles = [System.Collections.Generic.List[object]]::new()
    $profiles.Add([pscustomobject][ordered]@{
        Id = 'default'
        Name = 'Default'
        IsDefault = $true
        UserDataPath = $userDataPath
    })
    if (-not $storage.Contains('userDataProfiles')) {
        return [object[]]$profiles.ToArray()
    }
    if ($storage.userDataProfiles -isnot [System.Array]) {
        throw "VS Code profile metadata '$storagePath' has an unsupported 'userDataProfiles' value."
    }

    foreach ($profile in $storage.userDataProfiles) {
        if (-not (Test-IsDictionary $profile) -or
            -not $profile.Contains('name') -or $profile.name -isnot [string] -or [string]::IsNullOrWhiteSpace($profile.name) -or
            -not $profile.Contains('location') -or $profile.location -isnot [string] -or [string]::IsNullOrWhiteSpace($profile.location)) {
            throw "VS Code profile metadata '$storagePath' contains an unsupported profile entry."
        }
        $location = [string]$profile.location
        $locationId = $null
        try {
            $uri = [uri]$location
            $locationPath = if ($uri.IsAbsoluteUri -and $uri.IsFile) { $uri.LocalPath } else { $uri.AbsolutePath }
            $locationId = [System.IO.Path]::GetFileName($locationPath.TrimEnd('/', '\'))
        }
        catch {
            $locationId = [System.IO.Path]::GetFileName($location.TrimEnd('/', '\'))
        }
        if ([string]::IsNullOrWhiteSpace($locationId)) {
            throw "VS Code profile metadata '$storagePath' contains a profile without a usable location ID."
        }
        $profiles.Add([pscustomobject][ordered]@{
            Id = $locationId
            Name = [string]$profile.name
            IsDefault = $false
            UserDataPath = $userDataPath
        })
    }
    return [object[]]@($profiles.ToArray() | Sort-Object @{ Expression = 'IsDefault'; Descending = $true }, Name)
}

function Get-VSCodeStatusText {
    [CmdletBinding()]
    param([string]$CodeCommand = 'code')

    try {
        $output = @(& $CodeCommand --status 2>&1)
        $exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    }
    catch {
        throw "Could not run VS Code status through '$CodeCommand': $($_.Exception.Message)"
    }
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        throw "VS Code status command '$CodeCommand --status' failed with exit code $exitCode."
    }
    return [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
}

function Resolve-ComposerProfileFromVSCodeStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$StatusText
    )

    $windowLines = @(
        $StatusText -split '\r?\n' |
            Where-Object { $_ -match '(?i)\bwindow(?:\s+\[\d+\])?\s+\(' }
    )
    $recipeMatches = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in (Get-ProfileDefinitions $RepositoryRoot)) {
        $recipe = Read-ProfileRecipe $definition.Path
        $candidateNames = @($definition.Id, $recipe.Name) | Select-Object -Unique
        $liveNames = [System.Collections.Generic.List[string]]::new()
        foreach ($candidateName in $candidateNames) {
            $escapedName = [regex]::Escape([string]$candidateName)
            $pattern = "(?i)\s-\s$escapedName\s-\s(?:Visual Studio Code|Code(?:\s-\sInsiders)?)(?:\s+\[[^\]]+\])?\)\s*$"
            if ($windowLines | Where-Object { $_ -match $pattern }) {
                $liveNames.Add([string]$candidateName)
            }
        }
        if ($liveNames.Count -gt 0) {
            $match = [pscustomobject][ordered]@{
                ProfileId = $definition.Id
                DisplayName = $recipe.Name
                LiveProfileNames = [string[]]$liveNames.ToArray()
            }
            $recipeMatches.Add($match)
        }
    }

    if ($recipeMatches.Count -eq 0) {
        throw 'No active VS Code profile name uniquely matches a repository recipe ID or display name. Supply the profile ID explicitly.'
    }
    if ($recipeMatches.Count -gt 1) {
        $ids = @($recipeMatches | ForEach-Object ProfileId) -join ', '
        throw "Active VS Code profile names match multiple repository recipes: $ids. Supply the profile ID explicitly."
    }
    return $recipeMatches[0]
}

function Test-ComposerId {
    param([Parameter(Mandatory)][string]$Id)
    return $Id -match '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

function Get-ComposerConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $path = Join-Path ([System.IO.Path]::GetFullPath($RepositoryRoot)) 'composer.jsonc'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required composer configuration 'composer.jsonc' is missing."
    }
    $configuration = Read-JsonCFile $path
    if (-not (Test-IsDictionary $configuration)) { throw "Composer configuration root must be an object in 'composer.jsonc'." }
    if (-not $configuration.Contains('sharedDefaultComponent') -or
        $configuration['sharedDefaultComponent'] -isnot [string] -or
        -not (Test-ComposerId ([string]$configuration['sharedDefaultComponent']))) {
        throw "Composer configuration must declare a valid 'sharedDefaultComponent' ID."
    }
    if ($configuration.Contains('defaultUiStateProfile') -and (
        $configuration['defaultUiStateProfile'] -isnot [string] -or
        -not (Test-ComposerId ([string]$configuration['defaultUiStateProfile']))
    )) {
        throw "Composer configuration 'defaultUiStateProfile' must be a valid profile ID."
    }
    return $configuration
}

function Get-SharedDefaultComponent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    return [string](Get-ComposerConfiguration -RepositoryRoot $RepositoryRoot)['sharedDefaultComponent']
}

function ConvertTo-YamlDoubleQuotedScalar {
    param([Parameter(Mandatory)][string]$Value)
    return ($Value | ConvertTo-Json -Compress)
}

function ConvertTo-ProfileRecipeText {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Components
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("name: $(ConvertTo-YamlDoubleQuotedScalar $Name)")
    $lines.Add('components:')
    foreach ($component in $Components) { $lines.Add("  - $component") }
    return ($lines -join "`n") + "`n"
}

function Get-MachineDefinitions {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $localRoot = Join-Path $RepositoryRoot 'machine/local'
    if (-not (Test-Path -LiteralPath $localRoot -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $localRoot -Filter '*.jsonc' -File | Sort-Object Name | ForEach-Object {
        $configuration = Read-MachineConfiguration -Path $_.FullName -ExpectedId $_.BaseName
        [pscustomobject][ordered]@{
            Id = $configuration.Id
            Name = $configuration.Name
            Platform = $configuration.Platform
            Path = $_.FullName
            SchemaVersion = $configuration.SchemaVersion
            Legacy = $configuration.Legacy
        }
    })
}

function Read-MachineConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedId
    )

    $value = Read-JsonCFile $Path
    if (-not (Test-IsDictionary $value)) {
        throw "Machine settings root must be an object in '$Path'."
    }
    $isEnvelope = $value.Contains('schemaVersion') -or $value.Contains('machine') -or $value.Contains('settings')
    if (-not $isEnvelope) {
        $legacyId = if ($ExpectedId) { $ExpectedId } else { [System.IO.Path]::GetFileNameWithoutExtension($Path) }
        return [pscustomobject][ordered]@{
            Id = $legacyId
            Name = $legacyId
            Platform = $null
            Hostnames = [string[]]@()
            Settings = $value
            SchemaVersion = 0
            Legacy = $true
            Document = $value
        }
    }

    foreach ($key in $value.Keys) {
        if ([string]$key -notin @('schemaVersion', 'machine', 'settings')) {
            throw "Machine definition '$Path' contains unknown schema field '$key'."
        }
    }
    if (-not $value.Contains('schemaVersion') -or
        ($value.schemaVersion -isnot [long] -and $value.schemaVersion -isnot [int]) -or
        [int]$value.schemaVersion -ne $script:MachineSchemaVersion) {
        throw "Machine definition '$Path' requires supported schemaVersion $($script:MachineSchemaVersion)."
    }
    if (-not $value.Contains('machine') -or -not (Test-IsDictionary $value.machine)) {
        throw "Machine definition '$Path' requires an object 'machine'."
    }
    if (-not $value.Contains('settings') -or -not (Test-IsDictionary $value.settings)) {
        throw "Machine definition '$Path' requires an object 'settings'."
    }
    foreach ($key in $value.machine.Keys) {
        if ([string]$key -notin @('id', 'name', 'platform', 'hostnames')) {
            throw "Machine definition '$Path' contains unknown machine field '$key'."
        }
    }
    foreach ($required in @('id', 'name', 'platform')) {
        if (-not $value.machine.Contains($required) -or
            $value.machine[$required] -isnot [string] -or
            [string]::IsNullOrWhiteSpace([string]$value.machine[$required])) {
            throw "Machine definition '$Path' requires non-empty machine.$required."
        }
    }
    $id = [string]$value.machine.id
    if (-not (Test-ComposerId $id)) { throw "Machine definition '$Path' has invalid machine.id '$id'." }
    if ($ExpectedId -and $id -cne $ExpectedId) {
        throw "Machine definition '$Path' has machine.id '$id', which must match filename ID '$ExpectedId'."
    }
    $platform = ([string]$value.machine.platform).ToLowerInvariant()
    if ($platform -notin @('windows', 'linux', 'macos', 'wsl', 'container', 'remote')) {
        throw "Machine definition '$Path' has unsupported machine.platform '$platform'."
    }
    $hostnames = [string[]]@()
    if ($value.machine.Contains('hostnames')) {
        if ($value.machine.hostnames -isnot [System.Array]) {
            throw "Machine definition '$Path' machine.hostnames must be an array."
        }
        $hostList = [System.Collections.Generic.List[string]]::new()
        $seenHosts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($hostname in $value.machine.hostnames) {
            if ($hostname -isnot [string] -or [string]::IsNullOrWhiteSpace($hostname)) {
                throw "Machine definition '$Path' machine.hostnames entries must be non-empty strings."
            }
            if (-not $seenHosts.Add([string]$hostname)) {
                throw "Machine definition '$Path' repeats hostname '$hostname'."
            }
            $hostList.Add([string]$hostname)
        }
        $hostnames = [string[]]$hostList.ToArray()
    }
    return [pscustomobject][ordered]@{
        Id = $id
        Name = [string]$value.machine.name
        Platform = $platform
        Hostnames = $hostnames
        Settings = $value.settings
        SchemaVersion = [int]$value.schemaVersion
        Legacy = $false
        Document = $value
    }
}

function Write-MachineConfiguration {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Configuration
    )

    $value = if ($Configuration.Legacy) { $Configuration.Settings } else { $Configuration.Document }
    Write-Utf8File $Path (ConvertTo-PrettyJson $value)
}

function Get-LocalDefaultMachinePath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'machine/local/.default-machine'))
}

function Get-LocalDefaultMachine {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $path = Get-LocalDefaultMachinePath $RepositoryRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $id = [System.IO.File]::ReadAllText($path).Trim()
    if (-not (Test-ComposerId $id)) {
        throw "Local default-machine selector '$path' must contain exactly one valid machine ID."
    }
    return $id
}

function Resolve-MachinePath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Machine,
        [string]$MachineFile
    )
    if ($Machine -and $MachineFile) { throw '-Machine and -MachineFile cannot be used together.' }
    if ($Machine) {
        if ($Machine -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Invalid machine ID '$Machine'." }
        return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot "machine/local/$Machine.jsonc"))
    }
    if (-not $MachineFile) { return $null }
    if ([System.IO.Path]::IsPathRooted($MachineFile)) { return [System.IO.Path]::GetFullPath($MachineFile) }
    return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $MachineFile))
}

function Resolve-SyncMachine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Platform,
        [string]$Machine,
        [string]$MachineFile
    )

    if ($Machine -and $MachineFile) { throw '-Machine and -MachineFile cannot be used together.' }
    $selection = $null
    $path = $null
    $id = $null
    if ($Machine -or $MachineFile) {
        $path = Resolve-MachinePath -RepositoryRoot $RepositoryRoot -Machine $Machine -MachineFile $MachineFile
        $id = if ($Machine) { $Machine } else { [System.IO.Path]::GetFileNameWithoutExtension($path) }
        $selection = if ($Machine) { 'explicit-machine' } else { 'explicit-file' }
    }
    else {
        $defaultMachine = Get-LocalDefaultMachine $RepositoryRoot
        if ($defaultMachine) {
            $path = Resolve-MachinePath -RepositoryRoot $RepositoryRoot -Machine $defaultMachine
            $id = $defaultMachine
            $selection = 'local-default'
        }
        else {
            $definitions = @(Get-MachineDefinitions $RepositoryRoot)
            $compatible = if ($Platform) {
                @($definitions | Where-Object { -not $_.Platform -or $_.Platform -ieq $Platform })
            }
            else {
                $definitions
            }
            if ($compatible.Count -eq 1) {
                $path = $compatible[0].Path
                $id = $compatible[0].Id
                $selection = if ($compatible[0].Platform) { 'unique-platform-match' } else { 'unique-local-machine' }
            }
            elseif ($compatible.Count -gt 1) {
                $ids = @($compatible | ForEach-Object Id) -join ', '
                throw "Machine target is ambiguous for platform '$Platform': $ids. Re-run with -Machine <id> or configure machine/local/.default-machine."
            }
            else {
                throw "No compatible machine target is available for platform '$Platform'. Re-run with -Machine <id> or configure machine/local/.default-machine."
            }
        }
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Selected machine '$id' does not exist at '$path'. Run 'ProfileComposer.ps1 list-machines' or choose another -Machine value."
    }
    $configuration = Read-MachineConfiguration -Path $path -ExpectedId $(if ($Machine -or $selection -ne 'explicit-file') { $id } else { $null })
    if ($Platform -and $configuration.Platform -and $configuration.Platform -ine $Platform) {
        throw "Machine '$($configuration.Id)' targets platform '$($configuration.Platform)', not selected platform '$Platform'."
    }
    return [pscustomobject][ordered]@{
        Id = $configuration.Id
        Name = $configuration.Name
        Platform = $configuration.Platform
        Path = $path
        Selection = $selection
        Configuration = $configuration
    }
}

function Get-MachineSettingIds {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Settings)

    $reserved = @('workbench.settings.applyToAllProfiles', 'settingsSync.ignoredSettings')
    return @($Settings.Keys | Where-Object { $reserved -cnotcontains [string]$_ } | ForEach-Object { [string]$_ })
}

function Add-MachineOwnershipValidation {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Settings,
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Source
    )

    foreach ($reservedKey in @('workbench.settings.applyToAllProfiles', 'settingsSync.ignoredSettings')) {
        if ($Settings.Contains($reservedKey)) {
            Add-ValidationItem $Result errors 'machine-ownership-setting' "Machine overlays cannot set '$reservedKey'; the composer owns this list." $Source "/$reservedKey"
        }
    }
}

function Add-MachinePrivacyValidation {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Settings,
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Source
    )

    foreach ($keyValue in $Settings.Keys) {
        $key = [string]$keyValue
        $classification = Get-SettingValueClassification -SettingKey $key -Value $Settings[$key]
        if ($classification.classification -eq 'secret-or-private') {
            Add-ValidationItem $Result errors 'machine-sensitive-setting' "Machine setting '$key' contains excluded credential or private-resource state. Use the owning extension or a dedicated secret store." $Source "/$key"
        }
    }
}

function Resolve-UiStateSeedPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot, [string]$UiStateFromProfile)
    if (-not $UiStateFromProfile) { return $null }
    if ([System.IO.Path]::IsPathRooted($UiStateFromProfile)) { return [System.IO.Path]::GetFullPath($UiStateFromProfile) }
    return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $UiStateFromProfile))
}

function Test-ComposerRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Platform,
        [string]$Machine,
        [string]$MachineFile
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $result = New-ValidationResult
    $componentRoot = Join-Path $root 'components'
    $profileRoot = Join-Path $root 'profiles'
    $buildRoot = [System.IO.Path]::GetFullPath((Join-Path $root 'build/profiles'))
    $globalSettingsPath = Join-Path $root 'global/settings.jsonc'
    $globalSettingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $sharedDefaultComponent = $null
    $defaultUiStateProfile = $null

    try {
        $configuration = Get-ComposerConfiguration -RepositoryRoot $root
        $sharedDefaultComponent = [string]$configuration['sharedDefaultComponent']
        if ($configuration.Contains('defaultUiStateProfile')) {
            $defaultUiStateProfile = [string]$configuration['defaultUiStateProfile']
        }
    }
    catch { Add-ValidationItem $result errors 'invalid-composer-configuration' $_.Exception.Message 'composer.jsonc' }

    if (-not (Test-Path -LiteralPath $globalSettingsPath -PathType Leaf)) {
        Add-ValidationItem $result errors 'missing-global-settings' "Required global settings source 'global/settings.jsonc' is missing."
    }
    else {
        $globalSource = Get-RelativeDisplayPath $root $globalSettingsPath
        try {
            $globalSettings = Read-JsonCFile $globalSettingsPath
            if (-not (Test-IsDictionary $globalSettings)) {
                Add-ValidationItem $result errors 'global-settings-root' 'Global settings root must be an object.' $globalSource
            }
            elseif (-not $globalSettings.Contains('workbench.settings.applyToAllProfiles') -or
                $globalSettings['workbench.settings.applyToAllProfiles'] -isnot [System.Array]) {
                Add-ValidationItem $result errors 'global-settings-list' "Global settings must contain an array 'workbench.settings.applyToAllProfiles'." $globalSource
            }
            elseif (-not $globalSettings.Contains('settingsSync.ignoredSettings') -or
                $globalSettings['settingsSync.ignoredSettings'] -isnot [System.Array]) {
                Add-ValidationItem $result errors 'global-sync-ignored-list' "Global settings must contain an array 'settingsSync.ignoredSettings'." $globalSource
            }
            else {
                foreach ($settingId in $globalSettings['workbench.settings.applyToAllProfiles']) {
                    if ($settingId -isnot [string] -or [string]::IsNullOrWhiteSpace($settingId)) {
                        Add-ValidationItem $result errors 'invalid-global-setting-id' 'Global settings list entries must be non-empty strings.' $globalSource
                        continue
                    }
                    if (-not $globalSettingIds.Add($settingId)) {
                        Add-ValidationItem $result errors 'duplicate-global-setting-id' "Global setting '$settingId' is listed more than once." $globalSource
                    }
                    if (-not $globalSettings.Contains($settingId)) {
                        Add-ValidationItem $result errors 'missing-global-setting-value' "Global setting '$settingId' is listed but has no value." $globalSource
                    }
                }
                foreach ($key in $globalSettings.Keys) {
                    if ($key -ne 'workbench.settings.applyToAllProfiles' -and -not $globalSettingIds.Contains([string]$key)) {
                        Add-ValidationItem $result errors 'unlisted-global-setting' "Global setting '$key' has a value but is not listed in workbench.settings.applyToAllProfiles." $globalSource
                    }
                }
                Test-PortableSettings $globalSettings $result $globalSource
            }
        }
        catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message $globalSource }
    }

    if (-not (Test-Path -LiteralPath $componentRoot -PathType Container)) {
        Add-ValidationItem $result errors 'missing-components-directory' "Required directory 'components' is missing."
    }
    if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) {
        Add-ValidationItem $result errors 'missing-profiles-directory' "Required directory 'profiles' is missing."
    }

    $componentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $extensionOwners = @{}
    $settingOwners = @{}
    if (Test-Path -LiteralPath $componentRoot -PathType Container) {
        foreach ($directory in (Get-ChildItem -LiteralPath $componentRoot -Directory | Sort-Object Name)) {
            if (-not $componentIds.Add($directory.Name)) {
                Add-ValidationItem $result errors 'duplicate-component-id' "Duplicate component ID '$($directory.Name)'." $directory.FullName
            }
            $settingsPath = Join-Path $directory.FullName 'settings.jsonc'
            if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
                $source = Get-RelativeDisplayPath $root $settingsPath
                try {
                    $settings = Read-JsonCFile $settingsPath
                    if (-not (Test-IsDictionary $settings)) {
                        Add-ValidationItem $result errors 'component-settings-root' 'Component settings root must be an object.' $source
                    }
                    else {
                        Test-PortableSettings $settings $result $source
                        foreach ($key in $settings.Keys) {
                            $normalizedKey = [string]$key
                            if (-not $settingOwners.ContainsKey($normalizedKey)) {
                                $settingOwners[$normalizedKey] = [System.Collections.Generic.List[string]]::new()
                            }
                            $settingOwners[$normalizedKey].Add($source)
                            if ($globalSettingIds.Contains([string]$key)) {
                                Add-ValidationItem $result errors 'global-setting-in-profile-source' "Setting '$key' is globally owned and must not be declared in a component." $source "/$key"
                            }
                        }
                    }
                }
                catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message $source }
            }
            $keybindingsPath = Join-Path $directory.FullName 'keybindings.jsonc'
            if (Test-Path -LiteralPath $keybindingsPath -PathType Leaf) {
                $source = Get-RelativeDisplayPath $root $keybindingsPath
                try {
                    $keybindings = Read-JsonCFile $keybindingsPath
                    if ($keybindings -isnot [System.Array]) {
                        Add-ValidationItem $result errors 'keybindings-root' 'Keybindings root must be an array.' $source
                    }
                }
                catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message $source }
            }
            $extensionsPath = Join-Path $directory.FullName 'extensions.txt'
            if (Test-Path -LiteralPath $extensionsPath -PathType Leaf) {
                $source = Get-RelativeDisplayPath $root $extensionsPath
                $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($entry in (Read-ExtensionFile $extensionsPath)) {
                    if ($entry.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$') {
                        Add-ValidationItem $result errors 'invalid-extension-id' "Invalid extension ID '$($entry.Id)' at line $($entry.Line)." $source
                    }
                    elseif (-not $seen.Add($entry.Id)) {
                        Add-ValidationItem $result warnings 'duplicate-extension-id' "Duplicate extension ID '$($entry.Id)' in one component." $source
                    }
                    $normalized = $entry.Id.ToLowerInvariant()
                    if (-not $extensionOwners.ContainsKey($normalized)) { $extensionOwners[$normalized] = [System.Collections.Generic.List[string]]::new() }
                    $extensionOwners[$normalized].Add($source)
                }
            }
        }
    }

    if ($sharedDefaultComponent -and -not $componentIds.Contains($sharedDefaultComponent)) {
        Add-ValidationItem $result errors 'missing-shared-default-component' "Configured shared default component '$sharedDefaultComponent' does not exist." 'composer.jsonc' '/sharedDefaultComponent'
    }

    foreach ($entry in $extensionOwners.GetEnumerator()) {
        $owners = @($entry.Value | Select-Object -Unique)
        if ($owners.Count -gt 1) {
            Add-ValidationItem $result warnings 'cross-component-extension-duplicate' "Extension '$($entry.Key)' is declared by multiple components: $($owners -join ', ')."
        }
    }
    foreach ($entry in $settingOwners.GetEnumerator()) {
        $owners = @($entry.Value | Select-Object -Unique)
        if ($owners.Count -gt 1) {
            Add-ValidationItem $result warnings 'cross-component-setting-ownership' "Setting '$($entry.Key)' is declared by multiple portable components: $($owners -join ', '). Later recipe order wins, but the duplicate ownership requires review."
        }
    }

    $profileIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($profile in (Get-ProfileDefinitions $root)) {
        $source = Get-RelativeDisplayPath $root $profile.Path
        if (-not $profileIds.Add($profile.Id)) {
            Add-ValidationItem $result errors 'duplicate-profile-id' "Duplicate profile ID '$($profile.Id)'." $source
        }
        if ($profile.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
            Add-ValidationItem $result errors 'invalid-profile-id' "Profile ID '$($profile.Id)' cannot be used as an output directory." $source
        }
        $outputPath = [System.IO.Path]::GetFullPath((Join-Path $buildRoot $profile.Id))
        $prefix = $buildRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $outputPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-ValidationItem $result errors 'output-path-escape' "Profile '$($profile.Id)' would escape the build directory." $source
        }
        try {
            $recipe = Read-ProfileRecipe $profile.Path
            try { Get-CodeProfileFileName -DisplayName $recipe.Name | Out-Null }
            catch { Add-ValidationItem $result errors 'invalid-export-filename' $_.Exception.Message $source }
            if ($recipe.Name -match '(?i)(ghp_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{12,}|(?:password|token|secret|api[_-]?key)\s*[:=]\s*\S+)') {
                Add-ValidationItem $result errors 'sensitive-profile-metadata' "Profile '$($profile.Id)' has a likely secret in its display name." $source
            }
            $seenComponents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($component in $recipe.Components) {
                if (-not $seenComponents.Add($component)) {
                    Add-ValidationItem $result errors 'duplicate-recipe-component' "Profile '$($profile.Id)' declares component '$component' more than once." $source
                }
                if (-not $componentIds.Contains($component)) {
                    Add-ValidationItem $result errors 'missing-recipe-component' "Profile '$($profile.Id)' references missing component '$component'." $source
                }
            }
            if ($sharedDefaultComponent) {
                $defaultCount = @($recipe.Components | Where-Object { $_ -ieq $sharedDefaultComponent }).Count
                if ($defaultCount -eq 0) {
                    Add-ValidationItem $result errors 'missing-recipe-shared-default' "Profile '$($profile.Id)' does not include configured shared default '$sharedDefaultComponent'." $source
                }
                elseif ($recipe.Components[0] -ine $sharedDefaultComponent) {
                    Add-ValidationItem $result errors 'shared-default-not-first' "Profile '$($profile.Id)' must declare configured shared default '$sharedDefaultComponent' first." $source
                }
                if ($defaultCount -gt 1) {
                    Add-ValidationItem $result errors 'duplicate-recipe-shared-default' "Profile '$($profile.Id)' declares configured shared default '$sharedDefaultComponent' more than once." $source
                }
            }
        }
        catch { Add-ValidationItem $result errors 'invalid-yaml' $_.Exception.Message $source }

        $overridePath = Join-Path $profileRoot "$($profile.Id).settings.jsonc"
        $overrideSettingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
            try {
                $override = Read-JsonCFile $overridePath
                if (-not (Test-IsDictionary $override)) { Add-ValidationItem $result errors 'profile-settings-root' 'Profile-local settings root must be an object.' (Get-RelativeDisplayPath $root $overridePath) }
                else {
                    Test-PortableSettings $override $result (Get-RelativeDisplayPath $root $overridePath)
                    foreach ($key in $override.Keys) {
                        $overrideSettingIds.Add([string]$key) | Out-Null
                        if ($globalSettingIds.Contains([string]$key)) {
                            Add-ValidationItem $result errors 'global-setting-in-profile-source' "Setting '$key' is globally owned and must not be declared in a profile override." (Get-RelativeDisplayPath $root $overridePath) "/$key"
                        }
                    }
                }
            }
            catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message (Get-RelativeDisplayPath $root $overridePath) }
        }

        $replacementSettingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $settingsReplacementPath = Join-Path $profileRoot "$($profile.Id).settings.replace.jsonc"
        if (Test-Path -LiteralPath $settingsReplacementPath -PathType Leaf) {
            try {
                $replacement = Read-JsonCFile $settingsReplacementPath
                if (-not (Test-IsDictionary $replacement)) {
                    Add-ValidationItem $result errors 'profile-settings-replacement-root' 'Profile-local settings replacement root must be an object.' (Get-RelativeDisplayPath $root $settingsReplacementPath)
                }
                else {
                    Test-PortableSettings $replacement $result (Get-RelativeDisplayPath $root $settingsReplacementPath)
                    foreach ($key in $replacement.Keys) {
                        $replacementSettingIds.Add([string]$key) | Out-Null
                        if ($globalSettingIds.Contains([string]$key)) {
                            Add-ValidationItem $result errors 'global-setting-in-profile-source' "Setting '$key' is globally owned and must not be declared in a profile replacement." (Get-RelativeDisplayPath $root $settingsReplacementPath) "/$key"
                        }
                        if ($overrideSettingIds.Contains([string]$key)) {
                            Add-ValidationItem $result errors 'conflicting-profile-setting-operation' "Setting '$key' cannot be both recursively overridden and exactly replaced by the same profile." (Get-RelativeDisplayPath $root $settingsReplacementPath) "/$key"
                        }
                    }
                }
            }
            catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message (Get-RelativeDisplayPath $root $settingsReplacementPath) }
        }

        $settingsRemovalPath = Join-Path $profileRoot "$($profile.Id).settings.remove.jsonc"
        if (Test-Path -LiteralPath $settingsRemovalPath -PathType Leaf) {
            try {
                foreach ($settingId in (Read-ProfileSettingsRemovals $settingsRemovalPath)) {
                    if ($globalSettingIds.Contains($settingId)) {
                        Add-ValidationItem $result errors 'global-setting-in-profile-source' "Globally owned setting '$settingId' cannot be removed by a profile." (Get-RelativeDisplayPath $root $settingsRemovalPath) "/$settingId"
                    }
                    if ($overrideSettingIds.Contains($settingId)) {
                        Add-ValidationItem $result errors 'conflicting-profile-setting-operation' "Setting '$settingId' cannot be both removed and overridden by the same profile." (Get-RelativeDisplayPath $root $settingsRemovalPath) "/$settingId"
                    }
                    if ($replacementSettingIds.Contains($settingId)) {
                        Add-ValidationItem $result errors 'conflicting-profile-setting-operation' "Setting '$settingId' cannot be both removed and replaced by the same profile." (Get-RelativeDisplayPath $root $settingsRemovalPath) "/$settingId"
                    }
                }
            }
            catch { Add-ValidationItem $result errors 'invalid-profile-settings-removals' $_.Exception.Message (Get-RelativeDisplayPath $root $settingsRemovalPath) }
        }

        $extensionOperationsPath = Join-Path $profileRoot "$($profile.Id).extensions.jsonc"
        if (Test-Path -LiteralPath $extensionOperationsPath -PathType Leaf) {
            try { Read-ProfileExtensionOperations $extensionOperationsPath | Out-Null }
            catch { Add-ValidationItem $result errors 'invalid-profile-extension-operations' $_.Exception.Message (Get-RelativeDisplayPath $root $extensionOperationsPath) }
        }

        $keybindingOperationsPath = Join-Path $profileRoot "$($profile.Id).keybindings.jsonc"
        if (Test-Path -LiteralPath $keybindingOperationsPath -PathType Leaf) {
            try { Read-ProfileKeybindingOperations $keybindingOperationsPath | Out-Null }
            catch { Add-ValidationItem $result errors 'invalid-profile-keybinding-operations' $_.Exception.Message (Get-RelativeDisplayPath $root $keybindingOperationsPath) }
        }
    }
    if ($defaultUiStateProfile -and -not $profileIds.Contains($defaultUiStateProfile)) {
        Add-ValidationItem $result errors 'missing-default-ui-state-profile' "Configured default UI-state profile '$defaultUiStateProfile' does not exist." 'composer.jsonc' '/defaultUiStateProfile'
    }

    $platformCandidates = [System.Collections.Generic.List[string]]::new()
    $platformRoot = Join-Path $root 'platform'
    if (Test-Path -LiteralPath $platformRoot -PathType Container) {
        foreach ($file in (Get-ChildItem -LiteralPath $platformRoot -Filter '*.jsonc' -File)) { $platformCandidates.Add($file.FullName) }
    }
    foreach ($path in $platformCandidates) {
        $source = Get-RelativeDisplayPath $root $path
        try {
            $value = Read-JsonCFile $path
            if (-not (Test-IsDictionary $value)) {
                Add-ValidationItem $result errors 'overlay-root' 'Platform settings root must be an object.' $source
            }
            else {
                Test-PortableSettings $value $result $source
                foreach ($key in $value.Keys) {
                    if ($globalSettingIds.Contains([string]$key)) {
                        Add-ValidationItem $result errors 'global-setting-in-profile-source' "Setting '$key' is globally owned and must not be declared in a platform overlay." $source "/$key"
                    }
                }
            }
        }
        catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message $source }
    }
    if (Test-Path -LiteralPath $platformRoot -PathType Container) {
        foreach ($path in (Get-ChildItem -LiteralPath $platformRoot -Filter '*.extensions.txt' -File)) {
            $source = Get-RelativeDisplayPath $root $path.FullName
            foreach ($entry in (Read-ExtensionFile $path.FullName)) {
                if ($entry.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$') {
                    Add-ValidationItem $result errors 'invalid-extension-id' "Invalid extension ID '$($entry.Id)' at line $($entry.Line)." $source
                }
            }
        }
    }

    $machineCandidates = [System.Collections.Generic.List[string]]::new()
    $machineLocalRoot = Join-Path $root 'machine/local'
    if (Test-Path -LiteralPath $machineLocalRoot -PathType Container) {
        foreach ($file in (Get-ChildItem -LiteralPath $machineLocalRoot -Filter '*.jsonc' -File)) { $machineCandidates.Add($file.FullName) }
    }
    $machineRoot = Join-Path $root 'machine'
    if (Test-Path -LiteralPath $machineRoot -PathType Container) {
        foreach ($file in (Get-ChildItem -LiteralPath $machineRoot -Filter '*.example.jsonc' -File)) { $machineCandidates.Add($file.FullName) }
    }
    foreach ($path in $machineCandidates) {
        $source = Get-RelativeDisplayPath $root $path
        try {
            $expectedId = if ($source.StartsWith('machine/local/', [System.StringComparison]::OrdinalIgnoreCase)) {
                [System.IO.Path]::GetFileNameWithoutExtension($path)
            }
            else { $null }
            $configuration = Read-MachineConfiguration -Path $path -ExpectedId $expectedId
            Add-MachineOwnershipValidation -Settings $configuration.Settings -Result $result -Source $source
            Add-MachinePrivacyValidation -Settings $configuration.Settings -Result $result -Source $source
        }
        catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message $source }
    }
    try {
        $defaultMachine = Get-LocalDefaultMachine $root
        if ($defaultMachine) {
            $defaultMachinePath = Resolve-MachinePath -RepositoryRoot $root -Machine $defaultMachine
            if (-not (Test-Path -LiteralPath $defaultMachinePath -PathType Leaf)) {
                Add-ValidationItem $result errors 'stale-default-machine' "Local default machine '$defaultMachine' does not exist. Update or remove machine/local/.default-machine." 'machine/local/.default-machine'
            }
        }
    }
    catch {
        Add-ValidationItem $result errors 'invalid-default-machine' $_.Exception.Message 'machine/local/.default-machine'
    }

    if ($Platform) {
        $platformPath = Join-Path $root "platform/$Platform.jsonc"
        if (-not (Test-Path -LiteralPath $platformPath -PathType Leaf)) {
            Add-ValidationItem $result errors 'missing-platform-overlay' "Requested platform overlay '$Platform' does not exist." "platform/$Platform.jsonc"
        }
    }
    if ($Machine -and $MachineFile) {
        Add-ValidationItem $result errors 'conflicting-machine-selection' '-Machine and -MachineFile cannot be used together.'
    }
    elseif ($Machine -or $MachineFile) {
        $resolvedMachine = Resolve-MachinePath -RepositoryRoot $root -Machine $Machine -MachineFile $MachineFile
        if (-not (Test-Path -LiteralPath $resolvedMachine -PathType Leaf)) {
            $requested = if ($Machine) { "machine '$Machine'" } else { 'machine overlay' }
            Add-ValidationItem $result errors 'missing-machine-overlay' "Requested $requested does not exist." (Get-RelativeDisplayPath $root $resolvedMachine)
        }
        elseif ($machineCandidates -notcontains $resolvedMachine) {
            $source = Get-RelativeDisplayPath $root $resolvedMachine
            try {
                $machineConfiguration = Read-MachineConfiguration -Path $resolvedMachine -ExpectedId $Machine
                Add-MachineOwnershipValidation -Settings $machineConfiguration.Settings -Result $result -Source $source
                Add-MachinePrivacyValidation -Settings $machineConfiguration.Settings -Result $result -Source $source
            }
            catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message $source }
        }
    }

    foreach ($sourceRootName in @('components', 'profiles', 'platform', 'machine')) {
        $sourceRoot = Join-Path $root $sourceRootName
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { continue }
        foreach ($uiFile in (Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object Name -match '(?i)^(global[-_.]?state|ui[-_.]?state)\.(jsonc?|ya?ml|txt)$')) {
            Add-ValidationItem $result errors 'unsupported-ui-state-source' 'UI-state files are not composable; VS Code owns live profile UI state.' (Get-RelativeDisplayPath $root $uiFile.FullName)
        }
    }

    $gitDirectory = Join-Path $root '.git'
    if (Test-Path -LiteralPath $gitDirectory) {
        try {
            $tracked = @(& git -C $root ls-files -- 'machine/local' 2>$null)
            foreach ($trackedPath in $tracked) {
                if ($trackedPath -and $trackedPath.Replace('\', '/') -ne 'machine/local/.gitkeep') {
                    Add-ValidationItem $result errors 'tracked-machine-local' "Machine-local file '$trackedPath' is tracked by Git." $trackedPath
                }
            }
        }
        catch { Add-ValidationItem $result warnings 'git-check-failed' 'Could not verify whether machine-local files are tracked by Git.' }
    }

    $routerPath = Get-ManagedOwnershipRouterPath $root
    if (-not (Test-Path -LiteralPath $routerPath -PathType Leaf)) {
        Add-ValidationItem $result errors 'missing-ownership-router' "Required managed router 'config/ownership-router.jsonc' is missing." 'config/ownership-router.jsonc'
    }
    else {
        try {
            $routerValidation = Test-OwnershipRouterDocument -Document (Read-OwnershipRouterFile $routerPath) -RepositoryRoot $root -Source 'config/ownership-router.jsonc'
            foreach ($item in $routerValidation.errors) { $result.errors.Add($item) }
            foreach ($item in $routerValidation.warnings) { $result.warnings.Add($item) }
            foreach ($item in $routerValidation.information) { $result.information.Add($item) }
        }
        catch {
            Add-ValidationItem $result errors 'invalid-ownership-router' $_.Exception.Message 'config/ownership-router.jsonc'
        }
    }

    Add-ValidationItem $result information 'validation-summary' "Validated $($componentIds.Count) components and $($profileIds.Count) profile recipes."
    return $result
}

function ConvertTo-JsonPointerSegment {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace('~', '~0').Replace('/', '~1')
}

function Set-SourceTree {
    param(
        [Parameter(Mandatory)][AllowNull()]$Value,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][hashtable]$SourceMap
    )
    $SourceMap[$Path] = $Source
    if (Test-IsDictionary $Value) {
        foreach ($key in $Value.Keys) {
            $child = "$Path/$(ConvertTo-JsonPointerSegment ([string]$key))"
            Set-SourceTree $Value[$key] $child $Source $SourceMap
        }
    }
}

function Remove-SourceDescendants {
    param([Parameter(Mandatory)][hashtable]$SourceMap, [Parameter(Mandatory)][string]$Path)
    foreach ($key in @($SourceMap.Keys)) {
        if ($key -eq $Path -or $key.StartsWith("$Path/", [System.StringComparison]::Ordinal)) { $SourceMap.Remove($key) }
    }
}

function Test-ValuesEqual {
    param($Left, $Right)
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    return ((ConvertTo-Json -InputObject $Left -Depth 100 -Compress) -ceq (ConvertTo-Json -InputObject $Right -Depth 100 -Compress))
}

function Copy-ComposerValue {
    param($Value)
    if (Test-IsDictionary $Value) {
        $copy = New-OrderedMap
        foreach ($key in $Value.Keys) { $copy[$key] = Copy-ComposerValue $Value[$key] }
        return ,$copy
    }
    if ($Value -is [System.Array]) {
        return ,@($Value | ForEach-Object { Copy-ComposerValue $_ })
    }
    return $Value
}

function Get-RedactedValue {
    param([Parameter(Mandatory)][string]$Path, $Value)
    if ($Path -match $script:SensitivePattern) { return '[REDACTED]' }
    return Copy-ComposerValue $Value
}

function Merge-Settings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.IDictionary]$Target,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.IDictionary]$Incoming,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][hashtable]$SourceMap,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Overrides,
        [string]$BasePath = ''
    )

    foreach ($key in $Incoming.Keys) {
        $segment = ConvertTo-JsonPointerSegment ([string]$key)
        $path = if ($BasePath) { "$BasePath/$segment" } else { "/$segment" }
        $incomingValue = $Incoming[$key]
        if ($Target.Contains($key)) {
            $currentValue = $Target[$key]
            if ((Test-IsDictionary $currentValue) -and (Test-IsDictionary $incomingValue)) {
                Merge-Settings $currentValue $incomingValue $Source $SourceMap $Overrides $path
                continue
            }
            if (-not (Test-ValuesEqual $currentValue $incomingValue)) {
                $previousSource = if ($SourceMap.ContainsKey($path)) { $SourceMap[$path] } else { '<unknown>' }
                $Overrides.Add([pscustomobject][ordered]@{
                    path = $path
                    previousSource = $previousSource
                    newSource = $Source
                    previousValue = Get-RedactedValue $path $currentValue
                    newValue = Get-RedactedValue $path $incomingValue
                    resolutionSource = $Source
                })
            }
            Remove-SourceDescendants $SourceMap $path
        }
        $Target[$key] = Copy-ComposerValue $incomingValue
        Set-SourceTree $Target[$key] $path $Source $SourceMap
    }
    return $Target
}

function Merge-Extensions {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Files)
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $extensions = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $Files) {
        foreach ($entry in (Read-ExtensionFile $file.Path)) {
            if ($seen.Add($entry.Id)) { $extensions.Add($entry.Id) }
        }
    }
    return [string[]]$extensions.ToArray()
}

function Merge-Keybindings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Files)
    $items = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($file in $Files) {
        $array = Read-JsonCFile $file.Path
        if ($array -isnot [System.Array]) { throw "Keybindings root must be an array in '$($file.Source)'." }
        $index = -1
        foreach ($item in $array) {
            $index++
            $canonical = $item | ConvertTo-Json -Depth 100 -Compress
            if ($seen.ContainsKey($canonical)) {
                $first = $seen[$canonical]
                $warnings.Add([pscustomobject][ordered]@{
                    code = 'identical-keybinding-duplicate'
                    message = 'Identical keybinding object appears more than once; entries are preserved.'
                    firstSource = $first.Source
                    duplicateSource = $file.Source
                    duplicateIndex = $index
                })
            }
            else { $seen[$canonical] = [pscustomobject]@{ Source = $file.Source; Index = $index } }
            $items.Add((Copy-ComposerValue $item))
        }
    }
    return [pscustomobject]@{ Items = [object[]]$items.ToArray(); Warnings = [object[]]$warnings.ToArray() }
}

function Write-Utf8File {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n"), $script:Utf8NoBom)
}

function ConvertTo-PrettyJson {
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()]$Value)
    return ((ConvertTo-Json -InputObject $Value -Depth 100) + "`n")
}

function ConvertTo-CompactJson {
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()]$Value)
    return (ConvertTo-Json -InputObject $Value -Depth 100 -Compress)
}

function Get-CodeProfileFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DisplayName)

    $name = $DisplayName.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { throw 'Profile display name cannot be empty.' }
    if ($name.Contains('/') -or $name.Contains('\') -or $name.Contains('..')) {
        throw "Profile display name '$DisplayName' could escape the export directory."
    }
    $safeName = [regex]::Replace($name, '\s+\+\s+', '-')
    $safeName = [regex]::Replace($safeName, '[<>:"/\\|?*\x00-\x1F]', '-')
    $safeName = [regex]::Replace($safeName, '\s+', '-')
    $safeName = [regex]::Replace($safeName, '-{2,}', '-').Trim(' ', '.', '-')
    if ([string]::IsNullOrWhiteSpace($safeName)) { throw "Profile display name '$DisplayName' does not produce a usable export filename." }
    if ($safeName -match '(?i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        throw "Profile display name '$DisplayName' is a reserved Windows filename."
    }
    return "$safeName.code-profile"
}

function Test-PathWithinDirectory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Directory)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullDirectory = [System.IO.Path]::GetFullPath($Directory)
    $prefix = $fullDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-CodeProfilePlatformValue {
    param([string]$Platform)
    if ($Platform) {
        switch -Regex ($Platform.ToLowerInvariant()) {
            '^windows$' { return 3 }
            '^linux$' { return 2 }
            '^(mac|macos|darwin)$' { return 1 }
            '^web$' { return 0 }
            default { throw "Platform '$Platform' cannot be represented in VS Code keybinding export metadata." }
        }
    }
    if ($IsWindows) { return 3 }
    if ($IsMacOS) { return 1 }
    if ($IsLinux) { return 2 }
    return 0
}

function New-CodeProfileTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$SettingsJson,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Extensions,
        [Parameter(Mandatory)][string]$KeybindingsJson,
        [string]$Platform,
        [string]$GlobalState
    )

    $extensionResources = @($Extensions | ForEach-Object {
        [ordered]@{ identifier = [ordered]@{ id = $_ } }
    })
    $template = [ordered]@{
        name = $DisplayName
        settings = ConvertTo-CompactJson ([ordered]@{ settings = $SettingsJson })
        keybindings = ConvertTo-CompactJson ([ordered]@{
            keybindings = $KeybindingsJson
            platform = Get-CodeProfilePlatformValue $Platform
        })
        extensions = ConvertTo-CompactJson ([object[]]$extensionResources)
    }
    if ($PSBoundParameters.ContainsKey('GlobalState')) { $template.globalState = $GlobalState }
    return $template
}

function Read-CodeProfileGlobalState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "UI-state seed profile '$Path' does not exist."
    }
    $template = Read-JsonCFile $Path
    if (-not (Test-IsDictionary $template)) { throw "UI-state seed profile '$Path' must have an object root." }
    if (-not $template.Contains('globalState') -or $template.globalState -isnot [string] -or [string]::IsNullOrWhiteSpace($template.globalState)) {
        throw "UI-state seed profile '$Path' does not contain a non-empty string 'globalState' resource."
    }
    $payload = ConvertFrom-JsonC $template.globalState "$Path#globalState"
    if (-not (Test-IsDictionary $payload)) { throw "UI-state seed profile '$Path' globalState payload must be an object." }
    return [string]$template.globalState
}

function Get-StoredUiStateSeedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Profile
    )

    if ($Profile -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Invalid profile ID '$Profile'." }
    return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot "machine/local/ui-state/$Profile/seed.code-profile"))
}

function Save-ProfileUiStateSeed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Profile,
        [Parameter(Mandatory)][string]$SourceProfileExport,
        [switch]$DryRun
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $definition = @(Get-ProfileDefinitions $root | Where-Object { $_.Id -ieq $Profile })
    if ($definition.Count -eq 0) { throw "Unknown profile '$Profile'." }
    if ($definition.Count -gt 1) { throw "Profile ID '$Profile' is ambiguous." }

    $sourcePath = if ([System.IO.Path]::IsPathRooted($SourceProfileExport)) {
        [System.IO.Path]::GetFullPath($SourceProfileExport)
    }
    else { [System.IO.Path]::GetFullPath((Join-Path $root $SourceProfileExport)) }
    $globalState = Read-CodeProfileGlobalState -Path $sourcePath
    $targetPath = Get-StoredUiStateSeedPath -RepositoryRoot $root -Profile $definition[0].Id
    $targetDirectory = Split-Path -Parent $targetPath
    $result = [ordered]@{
        profileId = $definition[0].Id
        outputPath = Get-RelativeDisplayPath $root $targetPath
        sha256 = Get-StringHashValue $globalState
        sourcePathRecorded = $false
        dryRun = [bool]$DryRun
    }
    if ($DryRun) { return [pscustomobject]$result }

    $parent = Split-Path -Parent $targetDirectory
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporaryDirectory = Join-Path $parent ".$($definition[0].Id).$([guid]::NewGuid().ToString('N')).tmp"
    [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
    try {
        $temporaryPath = Join-Path $temporaryDirectory 'seed.code-profile'
        $seed = [ordered]@{
            name = "Stored UI state seed for $($definition[0].Id)"
            globalState = $globalState
        }
        Write-Utf8File $temporaryPath (ConvertTo-PrettyJson -Value $seed)
        Read-CodeProfileGlobalState -Path $temporaryPath | Out-Null
        Invoke-SafeDirectoryReplace -TemporaryDirectory $temporaryDirectory -TargetDirectory $targetDirectory
    }
    catch {
        if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
        throw
    }
    return [pscustomobject]$result
}

function Test-CodeProfileTemplate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $template = Read-JsonCFile $Path
    if (-not (Test-IsDictionary $template)) { throw "VS Code profile export '$Path' must have an object root." }
    $allowedFields = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($field in @('name', 'icon', 'settings', 'keybindings', 'tasks', 'snippets', 'extensions', 'globalState')) { $allowedFields.Add($field) | Out-Null }
    foreach ($field in $template.Keys) {
        if (-not $allowedFields.Contains([string]$field)) { throw "VS Code profile export '$Path' contains unsupported metadata field '$field'." }
    }
    if (-not $template.Contains('name') -or $template.name -isnot [string] -or [string]::IsNullOrWhiteSpace($template.name)) {
        throw "VS Code profile export '$Path' requires a non-empty string 'name'."
    }
    if ($template.name -match '(?i)(ghp_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{12,}|(?:password|token|secret|api[_-]?key)\s*[:=]\s*\S+)') {
        throw "VS Code profile export '$Path' contains a likely secret in profile metadata."
    }
    if ($template.Contains('icon') -and $template.icon -isnot [string]) { throw "VS Code profile export '$Path' icon metadata must be a string." }
    if ($template.Contains('globalState')) {
        if ($template.globalState -isnot [string] -or [string]::IsNullOrWhiteSpace($template.globalState)) {
            throw "VS Code profile export '$Path' globalState resource must be a non-empty string."
        }
        $globalStateValue = ConvertFrom-JsonC $template.globalState "$Path#globalState"
        if (-not (Test-IsDictionary $globalStateValue)) { throw "VS Code profile export '$Path' globalState payload must be an object." }
    }
    foreach ($required in @('settings', 'extensions', 'keybindings')) {
        if (-not $template.Contains($required) -or $template[$required] -isnot [string]) {
            throw "VS Code profile export '$Path' requires string resource '$required'."
        }
    }

    $settingsResource = ConvertFrom-JsonC $template.settings "$Path#settings"
    if (-not (Test-IsDictionary $settingsResource) -or -not $settingsResource.Contains('settings') -or $settingsResource.settings -isnot [string]) {
        throw "VS Code profile export '$Path' has an invalid settings resource."
    }
    $settingsValue = ConvertFrom-JsonC $settingsResource.settings "$Path#settings.settings"
    if (-not (Test-IsDictionary $settingsValue)) { throw "VS Code profile export '$Path' settings payload must be an object." }

    $extensionsResource = ConvertFrom-JsonC $template.extensions "$Path#extensions"
    if ($extensionsResource -isnot [System.Array]) { throw "VS Code profile export '$Path' extensions resource must be an array." }
    $extensionIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($extension in $extensionsResource) {
        if (-not (Test-IsDictionary $extension) -or -not $extension.Contains('identifier') -or -not (Test-IsDictionary $extension.identifier) -or
            -not $extension.identifier.Contains('id') -or $extension.identifier.id -isnot [string] -or
            $extension.identifier.id -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$') {
            throw "VS Code profile export '$Path' has an invalid extension resource entry."
        }
        if (-not $extensionIds.Add($extension.identifier.id)) { throw "VS Code profile export '$Path' contains duplicate extension '$($extension.identifier.id)'." }
    }

    $keybindingsResource = ConvertFrom-JsonC $template.keybindings "$Path#keybindings"
    if (-not (Test-IsDictionary $keybindingsResource) -or -not $keybindingsResource.Contains('keybindings') -or
        $keybindingsResource.keybindings -isnot [string] -or -not $keybindingsResource.Contains('platform')) {
        throw "VS Code profile export '$Path' has an invalid keybindings resource."
    }
    $keybindingsValue = ConvertFrom-JsonC $keybindingsResource.keybindings "$Path#keybindings.keybindings"
    if ($keybindingsValue -isnot [System.Array]) { throw "VS Code profile export '$Path' keybindings payload must be an array." }
    if ($keybindingsResource.platform -isnot [long] -and $keybindingsResource.platform -isnot [int]) {
        throw "VS Code profile export '$Path' keybindings platform must be an integer."
    }
    $platformNumber = [int]$keybindingsResource.platform
    if ($platformNumber -lt 0 -or $platformNumber -gt 3) { throw "VS Code profile export '$Path' has an invalid keybindings platform value." }
    return $true
}

function Read-CodeProfileResources {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    Test-CodeProfileTemplate -Path $resolvedPath | Out-Null
    $template = Read-JsonCFile $resolvedPath
    foreach ($unsupportedResource in @('tasks', 'snippets')) {
        if ($template.Contains($unsupportedResource)) {
            throw "VS Code profile export '$resolvedPath' contains '$unsupportedResource', which the composer does not own and cannot sync safely."
        }
    }

    $settingsResource = ConvertFrom-JsonC $template.settings "$resolvedPath#settings"
    $settings = ConvertFrom-JsonC $settingsResource.settings "$resolvedPath#settings.settings"
    $extensionsResource = ConvertFrom-JsonC $template.extensions "$resolvedPath#extensions"
    $extensions = @($extensionsResource | ForEach-Object { [string]$_.identifier.id })
    $keybindingsResource = ConvertFrom-JsonC $template.keybindings "$resolvedPath#keybindings"
    $keybindings = ConvertFrom-JsonC $keybindingsResource.keybindings "$resolvedPath#keybindings.keybindings"
    foreach ($keybinding in @($keybindings)) {
        if (-not (Test-IsDictionary $keybinding)) {
            throw "VS Code profile export '$resolvedPath' contains a keybinding entry that is not an object."
        }
    }

    return [pscustomobject][ordered]@{
        Name = [string]$template.name
        Settings = $settings
        Extensions = [string[]]$extensions
        Keybindings = [object[]]@($keybindings)
        KeybindingsPlatform = [int]$keybindingsResource.platform
        GlobalState = if ($template.Contains('globalState')) { [string]$template.globalState } else { $null }
    }
}

function Get-CanonicalComposerValue {
    param([Parameter(Mandatory)][AllowNull()]$Value)
    return ConvertTo-Json -InputObject $Value -Depth 100 -Compress
}

function Read-ProfileSettingsRemovals {
    param([Parameter(Mandatory)][string]$Path)

    $value = Read-JsonCFile $Path
    if ($value -isnot [System.Array]) { throw "Profile settings-removal root must be an array in '$Path'." }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($settingId in $value) {
        if ($settingId -isnot [string] -or [string]::IsNullOrWhiteSpace($settingId)) {
            throw "Profile settings-removal entries must be non-empty strings in '$Path'."
        }
        if (-not $seen.Add($settingId)) { throw "Profile settings-removal '$settingId' is duplicated in '$Path'." }
        $result.Add([string]$settingId)
    }
    return [string[]]$result.ToArray()
}

function Read-ProfileExtensionOperations {
    param([Parameter(Mandatory)][string]$Path)

    $value = Read-JsonCFile $Path
    if (-not (Test-IsDictionary $value)) { throw "Profile extension operations root must be an object in '$Path'." }
    foreach ($key in $value.Keys) {
        if ([string]$key -notin @('add', 'remove')) { throw "Unsupported profile extension operation '$key' in '$Path'." }
    }
    $addValue = $null
    $removeValue = $null
    if ($value.Contains('add')) { $addValue = $value['add'] }
    if ($value.Contains('remove')) { $removeValue = $value['remove'] }
    if (($null -ne $addValue -and $addValue -isnot [System.Array]) -or
        ($null -ne $removeValue -and $removeValue -isnot [System.Array])) {
        $addType = if ($null -eq $addValue) { 'null' } else { $addValue.GetType().FullName }
        $removeType = if ($null -eq $removeValue) { 'null' } else { $removeValue.GetType().FullName }
        throw "Profile extension 'add' and 'remove' operations must be arrays in '$Path' (add: $addType; remove: $removeType)."
    }
    $add = @($addValue)
    $remove = @($removeValue)
    $seenAdd = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenRemove = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($add)) {
        if ($entry -isnot [string] -or $entry -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$') {
            throw "Invalid extension ID '$entry' in '$Path'."
        }
        if (-not $seenAdd.Add($entry)) { throw "Duplicate extension addition '$entry' in '$Path'." }
    }
    foreach ($entry in @($remove)) {
        if ($entry -isnot [string] -or $entry -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$') {
            throw "Invalid extension ID '$entry' in '$Path'."
        }
        if (-not $seenRemove.Add($entry)) { throw "Duplicate extension removal '$entry' in '$Path'." }
        if ($seenAdd.Contains($entry)) { throw "Extension '$entry' cannot be both added and removed in '$Path'." }
    }
    return [pscustomobject]@{ Add = [string[]]@($add); Remove = [string[]]@($remove) }
}

function Read-ProfileKeybindingOperations {
    param([Parameter(Mandatory)][string]$Path)

    $value = Read-JsonCFile $Path
    if (-not (Test-IsDictionary $value)) { throw "Profile keybinding operations root must be an object in '$Path'." }
    foreach ($key in $value.Keys) {
        if ([string]$key -notin @('add', 'remove', 'replace')) { throw "Unsupported profile keybinding operation '$key' in '$Path'." }
    }
    if ($value.Contains('replace')) {
        if ($value.Contains('add') -or $value.Contains('remove')) {
            throw "Profile keybinding 'replace' cannot be combined with 'add' or 'remove' in '$Path'."
        }
        if ($null -ne $value.replace -and $value.replace -isnot [System.Array]) { throw "Profile keybinding 'replace' must be an array in '$Path'." }
        $replace = [object[]]@($value.replace)
        foreach ($entry in $replace) {
            if (-not (Test-IsDictionary $entry)) { throw "Profile keybinding replacements must be objects in '$Path'." }
        }
        return [pscustomobject]@{ Replace = $replace; Add = @(); Remove = @() }
    }
    $addValue = $null
    $removeValue = $null
    if ($value.Contains('add')) { $addValue = $value['add'] }
    if ($value.Contains('remove')) { $removeValue = $value['remove'] }
    if (($null -ne $addValue -and $addValue -isnot [System.Array]) -or
        ($null -ne $removeValue -and $removeValue -isnot [System.Array])) {
        throw "Profile keybinding 'add' and 'remove' operations must be arrays in '$Path'."
    }
    $add = @($addValue)
    $remove = @($removeValue)
    $seenAdd = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $seenRemove = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @($add)) {
        if (-not (Test-IsDictionary $entry)) { throw "Profile keybinding additions must be objects in '$Path'." }
        $canonical = Get-CanonicalComposerValue $entry
        if (-not $seenAdd.Add($canonical)) { throw "Duplicate profile keybinding addition in '$Path'." }
    }
    foreach ($entry in @($remove)) {
        if (-not (Test-IsDictionary $entry)) { throw "Profile keybinding removals must be objects in '$Path'." }
        $canonical = Get-CanonicalComposerValue $entry
        if (-not $seenRemove.Add($canonical)) { throw "Duplicate profile keybinding removal in '$Path'." }
        if ($seenAdd.Contains($canonical)) { throw "A keybinding cannot be both added and removed in '$Path'." }
    }
    return [pscustomobject]@{ Replace = $null; Add = [object[]]@($add); Remove = [object[]]@($remove) }
}

function Get-StringHashValue {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:Utf8NoBom.GetBytes($Value)
        return [Convert]::ToHexString($algorithm.ComputeHash($bytes)).ToLowerInvariant()
    }
    finally { $algorithm.Dispose() }
}

function Invoke-SafeDirectoryReplace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TemporaryDirectory,
        [Parameter(Mandatory)][string]$TargetDirectory
    )
    $parent = Split-Path -Parent $TargetDirectory
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    $backup = "$TargetDirectory.backup.$([guid]::NewGuid().ToString('N'))"
    $hadTarget = Test-Path -LiteralPath $TargetDirectory -PathType Container
    try {
        if ($hadTarget) { Move-Item -LiteralPath $TargetDirectory -Destination $backup -ErrorAction Stop }
        Move-Item -LiteralPath $TemporaryDirectory -Destination $TargetDirectory -ErrorAction Stop
        if ($hadTarget -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Recurse -Force }
    }
    catch {
        if (-not (Test-Path -LiteralPath $TargetDirectory) -and (Test-Path -LiteralPath $backup)) {
            Move-Item -LiteralPath $backup -Destination $TargetDirectory -ErrorAction SilentlyContinue
        }
        throw "Could not replace generated profile '$TargetDirectory': $($_.Exception.Message)"
    }
}

function New-ComposerStagingRepository {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "VSCodeProfileComposer.$([guid]::NewGuid().ToString('N'))"
    [System.IO.Directory]::CreateDirectory($stagingRoot) | Out-Null
    try {
        foreach ($directory in @('components', 'profiles', 'global', 'platform', 'machine', 'config', 'migration-backups')) {
            $source = Join-Path $root $directory
            if (Test-Path -LiteralPath $source -PathType Container) {
                Copy-Item -LiteralPath $source -Destination (Join-Path $stagingRoot $directory) -Recurse -Force
            }
        }
        $configuration = Join-Path $root 'composer.jsonc'
        if (Test-Path -LiteralPath $configuration -PathType Leaf) {
            Copy-Item -LiteralPath $configuration -Destination (Join-Path $stagingRoot 'composer.jsonc') -Force
        }
        return $stagingRoot
    }
    catch {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
        throw
    }
}

function Move-ComposerItemCaseSafe {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)

    if ($Source -ceq $Destination) { return }
    if ($Source -ieq $Destination) {
        $temporary = "$Source.rename.$([guid]::NewGuid().ToString('N'))"
        Move-Item -LiteralPath $Source -Destination $temporary -ErrorAction Stop
        Move-Item -LiteralPath $temporary -Destination $Destination -ErrorAction Stop
        return
    }
    Move-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
}

function Assert-StagedRepositoryValid {
    param([Parameter(Mandatory)][string]$StagingRoot)
    $validation = Test-ComposerRepository -RepositoryRoot $StagingRoot
    if ($validation.errors.Count -gt 0) {
        $details = @($validation.errors | ForEach-Object { "$($_.code): $($_.message)" }) -join '; '
        throw "Planned repository change failed validation: $details"
    }
}

function Invoke-StagedRepositoryCommit {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$StagingRoot,
        [Parameter(Mandatory)][string[]]$RelativePaths
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $backupRoot = Join-Path $root ".composer-rollback.$([guid]::NewGuid().ToString('N'))"
    [System.IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    $applied = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($relativePath in $RelativePaths) {
            $target = [System.IO.Path]::GetFullPath((Join-Path $root $relativePath))
            $staged = [System.IO.Path]::GetFullPath((Join-Path $StagingRoot $relativePath))
            $backup = [System.IO.Path]::GetFullPath((Join-Path $backupRoot $relativePath))
            if (-not (Test-PathWithinDirectory $target $root)) { throw "Transaction target '$relativePath' escapes the repository." }
            if (-not (Test-PathWithinDirectory $staged $StagingRoot)) { throw "Staged target '$relativePath' escapes the staging repository." }
            if (-not (Test-Path -LiteralPath $staged)) { throw "Staged transaction source '$relativePath' is missing." }
            [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
            [System.IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
            $hadTarget = Test-Path -LiteralPath $target
            if ($hadTarget) { Move-Item -LiteralPath $target -Destination $backup -ErrorAction Stop }
            $applied.Add([pscustomobject]@{ Target = $target; Backup = $backup; HadTarget = $hadTarget })
            Move-Item -LiteralPath $staged -Destination $target -ErrorAction Stop
        }

        $validation = Test-ComposerRepository -RepositoryRoot $root
        if ($validation.errors.Count -gt 0) {
            $details = @($validation.errors | ForEach-Object { "$($_.code): $($_.message)" }) -join '; '
            throw "Repository validation failed after applying the transaction: $details"
        }
        Remove-Item -LiteralPath $backupRoot -Recurse -Force
    }
    catch {
        for ($index = $applied.Count - 1; $index -ge 0; $index--) {
            $entry = $applied[$index]
            if (Test-Path -LiteralPath $entry.Target) { Remove-Item -LiteralPath $entry.Target -Recurse -Force }
            if ($entry.HadTarget -and (Test-Path -LiteralPath $entry.Backup)) {
                [System.IO.Directory]::CreateDirectory((Split-Path -Parent $entry.Target)) | Out-Null
                Move-Item -LiteralPath $entry.Backup -Destination $entry.Target -ErrorAction SilentlyContinue
            }
        }
        if (Test-Path -LiteralPath $backupRoot) { Remove-Item -LiteralPath $backupRoot -Recurse -Force }
        throw "Repository transaction rolled back: $($_.Exception.Message)"
    }
}

function Rename-ComposerProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$OldId,
        [Parameter(Mandatory)][string]$NewId,
        [switch]$DryRun
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Test-ComposerId $OldId)) { throw "Invalid source profile ID '$OldId'." }
    if (-not (Test-ComposerId $NewId)) { throw "Invalid target profile ID '$NewId'." }
    if ($OldId -ceq $NewId) { throw 'Source and target profile IDs are identical.' }
    $preflight = Test-ComposerRepository -RepositoryRoot $root
    if ($preflight.errors.Count -gt 0) { throw "Profile rename requires a valid repository; found $($preflight.errors.Count) error(s)." }
    $definitions = @(Get-ProfileDefinitions $root)
    $source = @($definitions | Where-Object Id -ieq $OldId)
    if ($source.Count -eq 0) { throw "Profile '$OldId' does not exist." }
    if ($source.Count -gt 1) { throw "Profile ID '$OldId' is ambiguous." }
    if (@($definitions | Where-Object { $_.Id -ieq $NewId -and $_.Path -cne $source[0].Path }).Count -gt 0) {
        throw "Profile '$NewId' already exists."
    }

    $sourceId = $source[0].Id
    $extension = [System.IO.Path]::GetExtension($source[0].Path)
    $changes = [System.Collections.Generic.List[object]]::new()
    $changes.Add([pscustomobject]@{ action = 'move'; source = "profiles/$sourceId$extension"; target = "profiles/$NewId$extension" })
    $profileSidecars = @('settings.jsonc', 'settings.replace.jsonc', 'settings.remove.jsonc', 'extensions.jsonc', 'keybindings.jsonc')
    foreach ($suffix in $profileSidecars) {
        $sidecarSource = Join-Path $root "profiles/$sourceId.$suffix"
        $sidecarTarget = Join-Path $root "profiles/$NewId.$suffix"
        if ((Test-Path -LiteralPath $sidecarTarget) -and $sidecarSource -ine $sidecarTarget) {
            throw "Profile sidecar '$NewId.$suffix' already exists."
        }
        if (Test-Path -LiteralPath $sidecarSource -PathType Leaf) {
            $changes.Add([pscustomobject]@{ action = 'move'; source = "profiles/$sourceId.$suffix"; target = "profiles/$NewId.$suffix" })
        }
    }
    $uiSource = Join-Path $root "machine/local/ui-state/$sourceId"
    $uiTarget = Join-Path $root "machine/local/ui-state/$NewId"
    if ((Test-Path -LiteralPath $uiTarget) -and $uiSource -ine $uiTarget) { throw "Stored UI-state seed for '$NewId' already exists." }
    $hasUiState = Test-Path -LiteralPath $uiSource -PathType Container
    if ($hasUiState) {
        $changes.Add([pscustomobject]@{ action = 'move'; source = "machine/local/ui-state/$sourceId"; target = "machine/local/ui-state/$NewId" })
    }

    $configurationChanged = $false
    $stagingRoot = New-ComposerStagingRepository $root
    try {
        Move-ComposerItemCaseSafe (Join-Path $stagingRoot "profiles/$sourceId$extension") (Join-Path $stagingRoot "profiles/$NewId$extension")
        foreach ($suffix in $profileSidecars) {
            $stageSidecarSource = Join-Path $stagingRoot "profiles/$sourceId.$suffix"
            if (Test-Path -LiteralPath $stageSidecarSource) {
                Move-ComposerItemCaseSafe $stageSidecarSource (Join-Path $stagingRoot "profiles/$NewId.$suffix")
            }
        }
        if ($hasUiState) {
            Move-ComposerItemCaseSafe (Join-Path $stagingRoot "machine/local/ui-state/$sourceId") (Join-Path $stagingRoot "machine/local/ui-state/$NewId")
        }
        $configuration = Get-ComposerConfiguration $stagingRoot
        if ($configuration.Contains('defaultUiStateProfile') -and
            [string]$configuration['defaultUiStateProfile'] -ieq $sourceId) {
            $configuration['defaultUiStateProfile'] = $NewId
            Write-Utf8File (Join-Path $stagingRoot 'composer.jsonc') (ConvertTo-PrettyJson $configuration)
            $changes.Add([pscustomobject]@{ action = 'update'; source = 'composer.jsonc'; target = 'composer.jsonc' })
            $configurationChanged = $true
        }
        Assert-StagedRepositoryValid $stagingRoot
        if (-not $DryRun) {
            $commitPaths = [System.Collections.Generic.List[string]]::new()
            $commitPaths.Add('profiles')
            if ($hasUiState) { $commitPaths.Add('machine/local/ui-state') }
            if ($configurationChanged) { $commitPaths.Add('composer.jsonc') }
            Invoke-StagedRepositoryCommit $root $stagingRoot $commitPaths.ToArray()
        }
        return [pscustomobject]@{ operation = 'rename-profile'; oldId = $sourceId; newId = $NewId; changes = [object[]]$changes.ToArray(); dryRun = [bool]$DryRun }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
    }
}

function Rename-ComposerComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$OldId,
        [Parameter(Mandatory)][string]$NewId,
        [switch]$DryRun
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Test-ComposerId $OldId)) { throw "Invalid source component ID '$OldId'." }
    if (-not (Test-ComposerId $NewId)) { throw "Invalid target component ID '$NewId'." }
    if ($OldId -ceq $NewId) { throw 'Source and target component IDs are identical.' }
    $preflight = Test-ComposerRepository $root
    if ($preflight.errors.Count -gt 0) { throw "Component rename requires a valid repository; found $($preflight.errors.Count) error(s)." }
    $directories = @(Get-ChildItem -LiteralPath (Join-Path $root 'components') -Directory)
    $source = @($directories | Where-Object Name -ieq $OldId)
    if ($source.Count -eq 0) { throw "Component '$OldId' does not exist." }
    if ($source.Count -gt 1) { throw "Component ID '$OldId' is ambiguous." }
    if (@($directories | Where-Object { $_.Name -ieq $NewId -and $_.FullName -cne $source[0].FullName }).Count -gt 0) {
        throw "Component '$NewId' already exists."
    }

    $sourceId = $source[0].Name
    $changes = [System.Collections.Generic.List[object]]::new()
    $changes.Add([pscustomobject]@{ action = 'move'; source = "components/$sourceId"; target = "components/$NewId" })
    $stagingRoot = New-ComposerStagingRepository $root
    try {
        Move-ComposerItemCaseSafe (Join-Path $stagingRoot "components/$sourceId") (Join-Path $stagingRoot "components/$NewId")
        foreach ($definition in Get-ProfileDefinitions $stagingRoot) {
            $recipe = Read-ProfileRecipe $definition.Path
            $updated = @($recipe.Components | ForEach-Object { if ($_ -ieq $sourceId) { $NewId } else { $_ } })
            if (@($recipe.Components | Where-Object { $_ -ieq $sourceId }).Count -gt 0) {
                Write-Utf8File $definition.Path (ConvertTo-ProfileRecipeText $recipe.Name $updated)
                $changes.Add([pscustomobject]@{ action = 'update'; source = (Get-RelativeDisplayPath $stagingRoot $definition.Path); target = (Get-RelativeDisplayPath $stagingRoot $definition.Path) })
            }
        }
        $configuration = Get-ComposerConfiguration $stagingRoot
        $configurationChanged = [string]$configuration['sharedDefaultComponent'] -ieq $sourceId
        if ($configurationChanged) {
            $configuration['sharedDefaultComponent'] = $NewId
            Write-Utf8File (Join-Path $stagingRoot 'composer.jsonc') (ConvertTo-PrettyJson $configuration)
            $changes.Add([pscustomobject]@{ action = 'update'; source = 'composer.jsonc'; target = 'composer.jsonc' })
        }
        Assert-StagedRepositoryValid $stagingRoot
        if (-not $DryRun) {
            $paths = [System.Collections.Generic.List[string]]::new()
            $paths.Add('components')
            $paths.Add('profiles')
            if ($configurationChanged) { $paths.Add('composer.jsonc') }
            Invoke-StagedRepositoryCommit $root $stagingRoot $paths.ToArray()
        }
        return [pscustomobject]@{ operation = 'rename-component'; oldId = $sourceId; newId = $NewId; changes = [object[]]$changes.ToArray(); dryRun = [bool]$DryRun }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
    }
}

function Set-SharedDefaultComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Component,
        [switch]$DryRun
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Test-ComposerId $Component)) { throw "Invalid component ID '$Component'." }
    $preflight = Test-ComposerRepository $root
    if ($preflight.errors.Count -gt 0) { throw "Changing the shared default requires a valid repository; found $($preflight.errors.Count) error(s)." }
    $componentDirectory = @(Get-ChildItem -LiteralPath (Join-Path $root 'components') -Directory | Where-Object Name -ieq $Component)
    if ($componentDirectory.Count -eq 0) { throw "Component '$Component' does not exist." }
    if ($componentDirectory.Count -gt 1) { throw "Component ID '$Component' is ambiguous." }
    $componentId = $componentDirectory[0].Name
    $changes = [System.Collections.Generic.List[object]]::new()
    $stagingRoot = New-ComposerStagingRepository $root
    try {
        $configuration = Get-ComposerConfiguration $stagingRoot
        $configurationChanged = [string]$configuration['sharedDefaultComponent'] -cne $componentId
        if ($configurationChanged) {
            $configuration['sharedDefaultComponent'] = $componentId
            Write-Utf8File (Join-Path $stagingRoot 'composer.jsonc') (ConvertTo-PrettyJson $configuration)
            $changes.Add([pscustomobject]@{ action = 'update'; source = 'composer.jsonc'; target = 'composer.jsonc' })
        }
        foreach ($definition in Get-ProfileDefinitions $stagingRoot) {
            $recipe = Read-ProfileRecipe $definition.Path
            $updated = [System.Collections.Generic.List[string]]::new()
            $updated.Add($componentId)
            foreach ($id in $recipe.Components) {
                if ($id -ine $componentId) { $updated.Add($id) }
            }
            if (($recipe.Components -join "`0") -cne ($updated.ToArray() -join "`0")) {
                Write-Utf8File $definition.Path (ConvertTo-ProfileRecipeText $recipe.Name $updated.ToArray())
                $path = Get-RelativeDisplayPath $stagingRoot $definition.Path
                $changes.Add([pscustomobject]@{ action = 'update'; source = $path; target = $path })
            }
        }
        Assert-StagedRepositoryValid $stagingRoot
        if (-not $DryRun -and $changes.Count -gt 0) {
            Invoke-StagedRepositoryCommit $root $stagingRoot @('profiles', 'composer.jsonc')
        }
        return [pscustomobject]@{ operation = 'set-shared-default'; component = $componentId; changes = [object[]]$changes.ToArray(); dryRun = [bool]$DryRun }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
    }
}

function Normalize-ApplicationSettingsOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Settings,
        [switch]$EnsureIgnoredSettings
    )

    if (-not (Test-IsDictionary $Settings)) {
        throw 'Application settings root must be an object.'
    }

    $ownershipKey = 'workbench.settings.applyToAllProfiles'
    $ignoredKey = 'settingsSync.ignoredSettings'
    $normalizedSettings = Copy-ComposerValue $Settings
    $ownershipListCreated = -not $normalizedSettings.Contains($ownershipKey)
    if (-not $ownershipListCreated -and $normalizedSettings[$ownershipKey] -isnot [System.Array]) {
        throw "Application setting '$ownershipKey' must be an array."
    }
    if ($EnsureIgnoredSettings -and -not $normalizedSettings.Contains($ignoredKey)) {
        $normalizedSettings[$ignoredKey] = [string[]]@()
    }
    if ($normalizedSettings.Contains($ignoredKey) -and $normalizedSettings[$ignoredKey] -isnot [System.Array]) {
        throw "Application setting '$ignoredKey' must be an array."
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $ownership = [System.Collections.Generic.List[string]]::new()
    $removedDuplicates = [System.Collections.Generic.List[string]]::new()
    if (-not $ownershipListCreated) {
        foreach ($entry in @($normalizedSettings[$ownershipKey])) {
            if ($entry -isnot [string] -or [string]::IsNullOrWhiteSpace($entry)) {
                throw "Application setting '$ownershipKey' contains a non-string or empty entry."
            }
            $id = [string]$entry
            if ($id -ceq $ownershipKey) {
                throw "Application setting '$ownershipKey' cannot list itself."
            }
            if (-not $normalizedSettings.Contains($id)) {
                throw "Application setting '$id' is apply-to-all but has no value."
            }
            if ($seen.Add($id)) {
                $ownership.Add($id)
            }
            else {
                $removedDuplicates.Add($id)
            }
        }
    }

    $addedSettings = [System.Collections.Generic.List[string]]::new()
    foreach ($keyValue in $normalizedSettings.Keys) {
        $key = [string]$keyValue
        if ($key -ceq $ownershipKey) { continue }
        if ($seen.Add($key)) {
            $ownership.Add($key)
            $addedSettings.Add($key)
        }
    }

    $ordered = New-OrderedMap
    $ordered[$ownershipKey] = [string[]]$ownership.ToArray()
    foreach ($keyValue in $normalizedSettings.Keys) {
        $key = [string]$keyValue
        if ($key -ceq $ownershipKey) { continue }
        $ordered[$key] = Copy-ComposerValue $normalizedSettings[$key]
    }

    return [pscustomobject][ordered]@{
        settings = $ordered
        ownershipListCreated = $ownershipListCreated
        addedSettings = [string[]]$addedSettings.ToArray()
        removedDuplicates = [string[]]$removedDuplicates.ToArray()
        changed = $ownershipListCreated -or $addedSettings.Count -gt 0 -or $removedDuplicates.Count -gt 0
    }
}

function Repair-ComposerGlobalOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [switch]$DryRun
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $relativePath = 'global/settings.jsonc'
    $settingsPath = [System.IO.Path]::GetFullPath((Join-Path $root $relativePath))
    if (-not (Test-PathWithinDirectory $settingsPath $root)) {
        throw "Global settings path '$relativePath' escapes the repository."
    }
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        throw "Required global settings source '$relativePath' is missing."
    }

    $settings = Read-JsonCFile $settingsPath
    if (-not (Test-IsDictionary $settings)) {
        throw 'Global settings root must be an object.'
    }

    try {
        $normalization = Normalize-ApplicationSettingsOwnership -Settings $settings
    }
    catch {
        if ($_.Exception.Message -like "*apply-to-all but has no value*") {
            throw "Cannot safely repair global ownership because listed settings have no value. $($_.Exception.Message)"
        }
        throw
    }
    $changed = $normalization.changed
    $changes = [System.Collections.Generic.List[object]]::new()
    if ($changed) {
        $changes.Add([pscustomobject]@{
            action = 'update'
            source = $relativePath
            target = $relativePath
        })
    }

    if (-not $changed) {
        return [pscustomobject][ordered]@{
            operation = 'fix-global-ownership'
            ownershipListCreated = $normalization.ownershipListCreated
            addedSettings = [string[]]@()
            removedDuplicates = [string[]]@()
            changes = [object[]]@()
            dryRun = [bool]$DryRun
        }
    }

    $stagingRoot = New-ComposerStagingRepository $root
    try {
        $stagedPath = Join-Path $stagingRoot $relativePath
        Write-Utf8File $stagedPath (ConvertTo-PrettyJson $normalization.settings)
        Assert-StagedRepositoryValid $stagingRoot

        if (-not $DryRun) {
            Invoke-StagedRepositoryCommit $root $stagingRoot @($relativePath)
        }

        return [pscustomobject][ordered]@{
            operation = 'fix-global-ownership'
            ownershipListCreated = $normalization.ownershipListCreated
            addedSettings = [string[]]$normalization.addedSettings
            removedDuplicates = [string[]]$normalization.removedDuplicates
            changes = [object[]]$changes.ToArray()
            dryRun = [bool]$DryRun
        }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        }
    }
}

function Add-OwnershipIndexEntry {
    param(
        [Parameter(Mandatory)][hashtable]$Index,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Layer
    )

    $key = "$Kind|$($Item.ToLowerInvariant())"
    if (-not $Index.ContainsKey($key)) { $Index[$key] = [System.Collections.Generic.List[object]]::new() }
    $Index[$key].Add([pscustomobject][ordered]@{
        kind = $Kind
        item = $Item
        destination = $Destination
        path = $Path
        layer = $Layer
    })
}

function Get-RepositoryOwnershipIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Platform,
        [string]$MachinePath,
        [string]$Profile
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $index = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($directory in (Get-ChildItem -LiteralPath (Join-Path $root 'components') -Directory | Sort-Object Name)) {
        $destination = New-OwnershipDestination component $directory.Name
        $settingsPath = Join-Path $directory.FullName 'settings.jsonc'
        if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
            foreach ($key in (Read-JsonCFile $settingsPath).Keys) {
                Add-OwnershipIndexEntry $index setting ([string]$key) $destination (Get-RelativeDisplayPath $root $settingsPath) component
            }
        }
        $extensionsPath = Join-Path $directory.FullName 'extensions.txt'
        if (Test-Path -LiteralPath $extensionsPath -PathType Leaf) {
            foreach ($entry in (Read-ExtensionFile $extensionsPath)) {
                Add-OwnershipIndexEntry $index extension $entry.Id $destination (Get-RelativeDisplayPath $root $extensionsPath) component
            }
        }
    }

    if ($Platform) {
        $destination = New-OwnershipDestination platform $Platform
        $settingsPath = Join-Path $root "platform/$Platform.jsonc"
        if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
            foreach ($key in (Read-JsonCFile $settingsPath).Keys) {
                Add-OwnershipIndexEntry $index setting ([string]$key) $destination (Get-RelativeDisplayPath $root $settingsPath) platform
            }
        }
        $extensionsPath = Join-Path $root "platform/$Platform.extensions.txt"
        if (Test-Path -LiteralPath $extensionsPath -PathType Leaf) {
            foreach ($entry in (Read-ExtensionFile $extensionsPath)) {
                Add-OwnershipIndexEntry $index extension $entry.Id $destination (Get-RelativeDisplayPath $root $extensionsPath) platform
            }
        }
    }

    if ($MachinePath) {
        $configuration = Read-MachineConfiguration $MachinePath ([System.IO.Path]::GetFileNameWithoutExtension($MachinePath))
        $destination = New-OwnershipDestination machine
        foreach ($key in $configuration.Settings.Keys) {
            Add-OwnershipIndexEntry $index setting ([string]$key) $destination (Get-RelativeDisplayPath $root $MachinePath) machine
        }
    }

    if ($Profile) {
        $destination = New-OwnershipDestination profile $Profile
        foreach ($suffix in @('settings.jsonc', 'settings.replace.jsonc')) {
            $path = Join-Path $root "profiles/$Profile.$suffix"
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                foreach ($key in (Read-JsonCFile $path).Keys) {
                    Add-OwnershipIndexEntry $index setting ([string]$key) $destination (Get-RelativeDisplayPath $root $path) profile
                }
            }
        }
        $extensionsPath = Join-Path $root "profiles/$Profile.extensions.jsonc"
        if (Test-Path -LiteralPath $extensionsPath -PathType Leaf) {
            $operations = Read-ProfileExtensionOperations $extensionsPath
            foreach ($id in $operations.Add) {
                Add-OwnershipIndexEntry $index extension $id $destination (Get-RelativeDisplayPath $root $extensionsPath) profile
            }
        }
    }
    return $index
}

function Get-OwnershipIndexOwners {
    param(
        [Parameter(Mandatory)][hashtable]$Index,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Item
    )
    $key = "$Kind|$($Item.ToLowerInvariant())"
    if (-not $Index.ContainsKey($key)) { return @() }
    return [object[]]$Index[$key].ToArray()
}

function Get-RoutedDestinationPath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)]$Destination,
        [string]$MachinePath,
        [string]$ExistingPath
    )

    if ($ExistingPath) { return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $ExistingPath)) }
    $type = [string]$Destination.type
    $name = if ($Destination.Contains('name')) { [string]$Destination.name } else { $null }
    switch ("$Kind|$type") {
        'setting|component' { return Join-Path $RepositoryRoot "components/$name/settings.jsonc" }
        'setting|platform' { return Join-Path $RepositoryRoot "platform/$name.jsonc" }
        'setting|machine' { return $MachinePath }
        'setting|profile' { return Join-Path $RepositoryRoot "profiles/$name.settings.replace.jsonc" }
        'extension|component' { return Join-Path $RepositoryRoot "components/$name/extensions.txt" }
        'extension|platform' { return Join-Path $RepositoryRoot "platform/$name.extensions.txt" }
        'extension|profile' { return Join-Path $RepositoryRoot "profiles/$name.extensions.jsonc" }
        'extension|machine' { throw 'Machine-owned extensions are not composable by the current VS Code profile artifact. Route the extension to a component, platform, profile, or exclude it.' }
        default { return $null }
    }
}

function Remove-PreviousOwnership {
    param(
        [Parameter(Mandatory)][string]$StagingRoot,
        [Parameter(Mandatory)]$Resolution,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Changes,
        [Parameter(Mandatory)][hashtable]$ChangedRoots
    )

    $existingCandidates = @($Resolution.candidates | Where-Object source -eq 'existing')
    if ($existingCandidates.Count -ne 1) { return }
    $owner = $existingCandidates[0].owner
    if ((Get-OwnershipDestinationLabel $owner.destination) -ieq (Get-OwnershipDestinationLabel $Resolution.destination)) { return }
    $stagedPath = Join-Path $StagingRoot $owner.path
    if (-not (Test-Path -LiteralPath $stagedPath -PathType Leaf)) { return }
    if ($Resolution.kind -eq 'setting') {
        $map = Read-JsonCFile $stagedPath
        if ($map.Contains($Resolution.item)) {
            $map.Remove($Resolution.item)
            Write-Utf8File $stagedPath (ConvertTo-PrettyJson $map)
        }
    }
    elseif ($owner.destination.type -eq 'profile') {
        $operations = Read-ProfileExtensionOperations $stagedPath
        $add = @($operations.Add | Where-Object { $_ -ine $Resolution.item })
        if ($add.Count -eq 0 -and $operations.Remove.Count -eq 0) {
            Remove-Item -LiteralPath $stagedPath -Force
        }
        else {
            Write-Utf8File $stagedPath (ConvertTo-PrettyJson ([ordered]@{ add = [string[]]$add; remove = [string[]]$operations.Remove }))
        }
    }
    else {
        $ids = @((Read-ExtensionFile $stagedPath) | ForEach-Object Id | Where-Object { $_ -ine $Resolution.item })
        Write-Utf8File $stagedPath $(if ($ids.Count -gt 0) { ($ids -join "`n") + "`n" } else { '' })
    }
    $Changes.Add([pscustomobject]@{ action = 'move-from'; path = $owner.path; item = $Resolution.item; owner = (Get-OwnershipDestinationLabel $owner.destination) })
    $ChangedRoots[(($owner.path -split '/')[0])] = $true
}

function Set-RoutedSettingValue {
    param(
        [Parameter(Mandatory)][string]$StagingRoot,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Resolution,
        [Parameter(Mandatory)][AllowNull()]$Value,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Changes,
        [Parameter(Mandatory)][hashtable]$ChangedRoots,
        $ResolvedMachine
    )

    $existingOwner = if ($Resolution.winner -and $Resolution.winner.PSObject.Properties.Name -contains 'owner') { $Resolution.winner.owner } else { $null }
    $machinePath = if ($ResolvedMachine) { $ResolvedMachine.Path } else { $null }
    $originalPath = Get-RoutedDestinationPath $RepositoryRoot setting $Resolution.destination -MachinePath $machinePath -ExistingPath $(if ($existingOwner) { $existingOwner.path } else { $null })
    if (-not $originalPath) { return }
    $relative = Get-RelativeDisplayPath $RepositoryRoot $originalPath
    $stagedPath = Join-Path $StagingRoot $relative

    if ($Resolution.destination.type -eq 'machine') {
        $configuration = Read-MachineConfiguration $stagedPath $ResolvedMachine.Id
        $same = $configuration.Settings.Contains($Resolution.item) -and (Test-ValuesEqual $configuration.Settings[$Resolution.item] $Value)
        if (-not $same) {
            $exists = $configuration.Settings.Contains($Resolution.item)
            $configuration.Settings[$Resolution.item] = Copy-ComposerValue $Value
            Write-MachineConfiguration $stagedPath $configuration
            $Changes.Add([pscustomobject]@{ action = if ($exists) { 'update' } else { 'create' }; path = $relative; item = $Resolution.item; owner = 'machine' })
            $ChangedRoots[$relative] = $true
        }
        return
    }

    $map = if (Test-Path -LiteralPath $stagedPath -PathType Leaf) { Read-JsonCFile $stagedPath } else { New-OrderedMap }
    $same = $map.Contains($Resolution.item) -and (Test-ValuesEqual $map[$Resolution.item] $Value)
    if (-not $same) {
        $exists = $map.Contains($Resolution.item)
        $map[$Resolution.item] = Copy-ComposerValue $Value
        Write-Utf8File $stagedPath (ConvertTo-PrettyJson $map)
        $Changes.Add([pscustomobject]@{ action = if ($exists) { 'update' } else { 'create' }; path = $relative; item = $Resolution.item; owner = (Get-OwnershipDestinationLabel $Resolution.destination) })
        $rootName = ($relative -split '/')[0]
        $ChangedRoots[$rootName] = $true
    }
}

function Set-RoutedExtensionValue {
    param(
        [Parameter(Mandatory)][string]$StagingRoot,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Resolution,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Changes,
        [Parameter(Mandatory)][hashtable]$ChangedRoots
    )

    $existingOwner = if ($Resolution.winner -and $Resolution.winner.PSObject.Properties.Name -contains 'owner') { $Resolution.winner.owner } else { $null }
    $originalPath = Get-RoutedDestinationPath $RepositoryRoot extension $Resolution.destination -ExistingPath $(if ($existingOwner) { $existingOwner.path } else { $null })
    if (-not $originalPath) { return }
    $relative = Get-RelativeDisplayPath $RepositoryRoot $originalPath
    $stagedPath = Join-Path $StagingRoot $relative
    if ($Resolution.destination.type -eq 'profile') {
        $operations = if (Test-Path -LiteralPath $stagedPath -PathType Leaf) {
            Read-ProfileExtensionOperations $stagedPath
        }
        else { [pscustomobject]@{ Add = @(); Remove = @() } }
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($id in $operations.Add) { $set.Add($id) | Out-Null }
        if ($set.Add($Resolution.item)) {
            $remove = @($operations.Remove | Where-Object { $_ -ine $Resolution.item })
            Write-Utf8File $stagedPath (ConvertTo-PrettyJson ([ordered]@{ add = [string[]]@($operations.Add + $Resolution.item); remove = [string[]]$remove }))
            $Changes.Add([pscustomobject]@{ action = 'create'; path = $relative; item = $Resolution.item; owner = (Get-OwnershipDestinationLabel $Resolution.destination) })
            $ChangedRoots['profiles'] = $true
        }
        return
    }

    $ids = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $stagedPath -PathType Leaf) {
        foreach ($entry in (Read-ExtensionFile $stagedPath)) {
            if ($seen.Add($entry.Id)) { $ids.Add($entry.Id) }
        }
    }
    if ($seen.Add($Resolution.item)) {
        $ids.Add($Resolution.item)
        Write-Utf8File $stagedPath (($ids.ToArray() -join "`n") + "`n")
        $Changes.Add([pscustomobject]@{ action = 'create'; path = $relative; item = $Resolution.item; owner = (Get-OwnershipDestinationLabel $Resolution.destination) })
        $ChangedRoots[(($relative -split '/')[0])] = $true
    }
}

function Get-UnresolvedOwnershipGroups {
    param([Parameter(Mandatory)][object[]]$Items)

    return @($Items | Group-Object {
        $value = [string]$_.item
        $prefix = ($value -split '\.', 2)[0]
        if ([string]::IsNullOrWhiteSpace($prefix)) { 'other' } else { $prefix.ToLowerInvariant() }
    } | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name
            items = [object[]]@($_.Group | Sort-Object item)
        }
    })
}

function ConvertFrom-InteractiveDestination {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Profile
    )

    $value = $Text.Trim()
    if ($value -ieq 'machine') { return New-OwnershipDestination machine }
    if ($value -ieq 'exclude') { return New-OwnershipDestination exclude }
    if ($value -ieq 'unresolved') { return New-OwnershipDestination unresolved }
    if ($value -match '^(?i)(component|platform|profile)/([A-Za-z0-9][A-Za-z0-9._-]*)$') {
        return New-OwnershipDestination $Matches[1].ToLowerInvariant() $Matches[2]
    }
    if ($value -ieq 'profile') { return New-OwnershipDestination profile $Profile }
    throw "Invalid destination '$Text'. Use component/<name>, platform/<name>, machine, profile/<name>, exclude, or unresolved."
}

function Resolve-OwnershipInteractively {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][string]$Profile,
        [scriptblock]$ResolutionProvider,
        $ManagedRouter,
        [hashtable]$OwnershipIndex,
        [string]$RepositoryRoot,
        [switch]$DryRun
    )

    $decisions = [System.Collections.Generic.List[object]]::new()
    $savedRoutes = [System.Collections.Generic.List[object]]::new()
    if (-not $ResolutionProvider) {
        Write-Host "$($Items.Count) item(s) require ownership decisions."
        Write-Host '[R] Resolve interactively'
        Write-Host '[E] Export unresolved routing file'
        Write-Host '[A] Abort'
        $initialChoice = Read-Host 'Choice [R/E/A]'
        if ($initialChoice -match '^(?i)e$') {
            $defaultPath = if ($RepositoryRoot) { Join-Path $RepositoryRoot 'unresolved-routes.jsonc' } else { 'unresolved-routes.jsonc' }
            $requestedPath = Read-Host "Output path [$defaultPath]"
            $outputPath = if ([string]::IsNullOrWhiteSpace($requestedPath)) { $defaultPath } else { $requestedPath }
            Write-OwnershipRouterFile $outputPath (ConvertTo-UnresolvedRouterDocument $Items)
            throw "Unresolved routes were written to '$outputPath'. Review the file and retry with -RoutingFile."
        }
        if ($initialChoice -notmatch '^(?i)r$') { throw 'Interactive ownership resolution was aborted.' }
    }

    foreach ($group in (Get-UnresolvedOwnershipGroups $Items)) {
        $repositoryMatches = [System.Collections.Generic.List[string]]::new()
        if ($OwnershipIndex) {
            foreach ($indexKey in $OwnershipIndex.Keys) {
                $parts = [string]$indexKey -split '\|', 2
                if ($parts.Count -eq 2 -and $parts[1].StartsWith("$($group.name).", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $repositoryMatches.Add($parts[1])
                }
            }
        }
        $overlappingRoutes = [System.Collections.Generic.List[string]]::new()
        if ($ManagedRouter) {
            foreach ($route in @($ManagedRouter.routes)) {
                if ($route.status -ne 'approved' -or $route.match.type -notin @('prefix', 'publisher')) { continue }
                $proposed = if ($route.kind -eq 'extension') { $group.name } else { "$($group.name)." }
                $existing = [string]$route.match.value
                if ($proposed.StartsWith($existing, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $existing.StartsWith($proposed, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $overlappingRoutes.Add([string]$route.id)
                }
            }
        }
        $context = [pscustomobject]@{
            group = $group.name
            items = $group.items
            suggestedDestination = if ($group.name -in @('python', 'eslint')) {
                New-OwnershipDestination component $(if ($group.name -eq 'python') { 'python' } else { 'web' })
            }
            else { $null }
            matchingRepositoryItems = [string[]]@($repositoryMatches | Sort-Object -Unique)
            overlappingRouteIds = [string[]]@($overlappingRoutes | Sort-Object -Unique)
            dryRun = [bool]$DryRun
        }
        if ($ResolutionProvider) {
            $answer = & $ResolutionProvider $context
        }
        else {
            Write-Host ''
            Write-Host "Group: $($group.name) ($($group.items.Count) item(s))"
            foreach ($item in $group.items) { Write-Host "  $($item.kind): $($item.item)" }
            if ($context.suggestedDestination) {
                Write-Host "Suggestion: $(Get-OwnershipDestinationLabel $context.suggestedDestination) (namespace association; confirmation required)"
            }
            Write-Host '[G] Apply one destination to the whole group'
            Write-Host '[I] Route items individually'
            if ($context.suggestedDestination) { Write-Host '[A] Accept the suggested destination' }
            Write-Host '[S] Skip and leave unresolved'
            $scope = Read-Host 'Choice [G/I/A/S]'
            if ($scope -match '^(?i)i$') {
                $individual = [System.Collections.Generic.List[object]]::new()
                foreach ($item in $group.items) {
                    $destinationText = Read-Host "Destination for $($item.item) [component/<name>|platform/<name>|machine|profile/<name>|exclude|unresolved]"
                    $persistence = Read-Host 'Persistence [run|exact]'
                    if ($persistence -notmatch '^(?i)(run|exact)$') { throw "Invalid individual persistence '$persistence'." }
                    $individual.Add([pscustomobject]@{
                        kind = $item.kind
                        item = $item.item
                        destination = ConvertFrom-InteractiveDestination $destinationText $Profile
                        persistence = $persistence
                    })
                }
                $answer = [pscustomobject]@{ decisions = [object[]]$individual.ToArray() }
            }
            else {
                $destination = if ($scope -match '^(?i)a$' -and $context.suggestedDestination) {
                    $context.suggestedDestination
                }
                elseif ($scope -match '^(?i)s$') {
                    New-OwnershipDestination unresolved
                }
                elseif ($scope -match '^(?i)g$') {
                    $destinationText = Read-Host 'Destination [component/<name>|platform/<name>|machine|profile/<name>|exclude|unresolved]'
                    ConvertFrom-InteractiveDestination $destinationText $Profile
                }
                else { throw "Invalid group choice '$scope'." }
                $persistence = if ($scope -match '^(?i)s$') { 'run' } else { Read-Host 'Persistence [run|exact|prefix]' }
                $answer = [pscustomobject]@{
                    destination = $destination
                    persistence = $persistence
                    confirmBroadRule = $false
                }
            }
            if ($answer.PSObject.Properties.Name -contains 'persistence' -and $answer.persistence -ieq 'prefix') {
                Write-Host "Proposed prefix: $($group.name)."
                Write-Host 'Imported items currently matched:'
                foreach ($item in $group.items) { Write-Host "  $($item.item)" }
                Write-Host 'Existing repository items that would also match:'
                if ($context.matchingRepositoryItems.Count -eq 0) { Write-Host '  (none)' }
                else { foreach ($item in $context.matchingRepositoryItems) { Write-Host "  $item" } }
                Write-Host 'Overlapping approved routes:'
                if ($context.overlappingRouteIds.Count -eq 0) { Write-Host '  (none)' }
                else { foreach ($routeId in $context.overlappingRouteIds) { Write-Host "  $routeId" } }
                $answer.confirmBroadRule = (Read-Host 'Save this approved broad rule? [y/N]') -match '^(?i)y(es)?$'
            }
        }

        if (-not $answer) { throw "Interactive resolution aborted for group '$($group.name)'." }
        $answerEntries = [System.Collections.Generic.List[object]]::new()
        if ($answer.PSObject.Properties.Name -contains 'decisions') {
            foreach ($entry in @($answer.decisions)) {
                if (-not $entry.destination -or [string]::IsNullOrWhiteSpace([string]$entry.item)) {
                    throw "An individual decision for group '$($group.name)' is incomplete."
                }
                $matchingItem = @($group.items | Where-Object {
                    $_.item -ieq [string]$entry.item -and
                    (-not ($entry.PSObject.Properties.Name -contains 'kind') -or $_.kind -ieq [string]$entry.kind)
                })
                if ($matchingItem.Count -ne 1) { throw "Individual decision item '$($entry.item)' does not uniquely identify an item in group '$($group.name)'." }
                $answerEntries.Add([pscustomobject]@{
                    item = $matchingItem[0]
                    destination = $entry.destination
                    persistence = if ($entry.PSObject.Properties.Name -contains 'persistence') { [string]$entry.persistence } else { 'run' }
                })
            }
            if ($answerEntries.Count -ne $group.items.Count) {
                throw "Individual decisions for group '$($group.name)' must cover every item or explicitly route it to unresolved."
            }
        }
        else {
            if (-not ($answer.PSObject.Properties.Name -contains 'destination') -or -not $answer.destination) {
                throw "Interactive resolution aborted for group '$($group.name)'."
            }
            foreach ($item in $group.items) {
                $answerEntries.Add([pscustomobject]@{
                    item = $item
                    destination = $answer.destination
                    persistence = if ($answer.PSObject.Properties.Name -contains 'persistence') { [string]$answer.persistence } else { 'run' }
                })
            }
        }

        foreach ($entry in $answerEntries) {
            $item = $entry.item
            $decisions.Add([pscustomobject]@{ kind = $item.kind; item = $item.item; destination = $entry.destination })
            if ($entry.persistence -ieq 'exact') {
                $id = "user-$($item.kind)-$(([string]$item.item).ToLowerInvariant() -replace '[^a-z0-9._-]', '-')"
                $savedRoutes.Add((New-OwnershipRoute $id $item.kind exact $item.item $entry.destination user-confirmed approved 'Confirmed during interactive synchronization.'))
            }
            elseif ($entry.persistence -notin @('run', 'prefix')) {
                throw "Invalid persistence '$($entry.persistence)' for '$($item.item)'."
            }
        }

        $prefixEntries = @($answerEntries | Where-Object persistence -ieq 'prefix')
        if ($prefixEntries.Count -gt 0) {
            if ($prefixEntries.Count -ne $group.items.Count) { throw "A broad route must apply to the whole '$($group.name)' group." }
            if (-not ($answer.PSObject.Properties.Name -contains 'confirmBroadRule') -or -not $answer.confirmBroadRule) {
                throw "Broad route for '$($group.name)' was not confirmed."
            }
            $destinations = @($prefixEntries | ForEach-Object { Get-OwnershipDestinationLabel $_.destination } | Select-Object -Unique)
            if ($destinations.Count -ne 1) { throw "A broad route for '$($group.name)' requires one destination." }
            $kinds = @($group.items | ForEach-Object kind | Select-Object -Unique)
            foreach ($kind in $kinds) {
                $matchType = if ($kind -eq 'extension') { 'publisher' } else { 'prefix' }
                $matchValue = if ($kind -eq 'extension') { $group.name } else { "$($group.name)." }
                $id = "user-$kind-$($group.name)-rule"
                $savedRoutes.Add((New-OwnershipRoute $id $kind $matchType $matchValue $prefixEntries[0].destination user-confirmed approved 'Confirmed broad rule during interactive synchronization.'))
            }
        }
    }
    return [pscustomobject]@{ decisions = [object[]]$decisions.ToArray(); routes = [object[]]$savedRoutes.ToArray() }
}

function New-SyncSettingDiagnostic {
    param(
        [Parameter(Mandatory)][string]$Heading,
        [Parameter(Mandatory)][string]$SettingKey,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)]$Classification,
        [string]$Platform,
        [string]$MachineId,
        [string]$Owner,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$RecommendedCommand
    )

    $targetMachine = if ($MachineId) { $MachineId } else { 'not resolved' }
    $targetPlatform = if ($Platform) { $Platform } else { 'not selected' }
    $owningSource = if ($Owner) { $Owner } else { 'unowned export setting' }
    return @"
$Heading

  Setting: $SettingKey
  Source: $SourcePath#settings
  Value: $($Classification.safeValue)
  Classification: $($Classification.classification)
  Proposed destination: $($Classification.destination)
  Target platform: $targetPlatform
  Target machine: $targetMachine
  Owning component or file: $owningSource
  Validation rule: $($Classification.ruleId)
  Reason: $Reason

Recommended command:

  $RecommendedCommand
"@
}

function Sync-ComposerProfileFromExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Profile,
        [Parameter(Mandatory)][string]$SourceProfileExport,
        [string]$Platform,
        [string]$Machine,
        [string]$MachineFile,
        [string]$VSCodeUserDataPath,
        [string]$RoutingFile,
        [ValidateSet('Supplement', 'Override', 'Isolated')][string]$RoutingMode = 'Supplement',
        [switch]$NonInteractive,
        [string]$WriteUnresolved,
        [scriptblock]$ResolutionProvider,
        [switch]$PersistDryRunDecisions,
        [switch]$SkipGlobal,
        [switch]$SkipUiState,
        [switch]$DryRun
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $sourcePath = if ([System.IO.Path]::IsPathRooted($SourceProfileExport)) {
        [System.IO.Path]::GetFullPath($SourceProfileExport)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $root $SourceProfileExport))
    }
    $resources = Read-CodeProfileResources -Path $sourcePath
    if (-not $SkipUiState -and [string]::IsNullOrWhiteSpace([string]$resources.GlobalState)) {
        throw 'The profile export does not contain UI layout state. Export the UI State resource or use -SkipUiState.'
    }

    if ($Machine -and $MachineFile) { throw '-Machine and -MachineFile cannot be used together.' }
    $preflight = Test-ComposerRepository -RepositoryRoot $root -Platform $Platform
    if ($preflight.errors.Count -gt 0) {
        throw "Profile sync requires a valid repository; found $($preflight.errors.Count) error(s)."
    }
    $definitions = @(Get-ProfileDefinitions $root)
    if ($Profile) {
        $matches = @($definitions | Where-Object Id -ieq $Profile)
        if ($matches.Count -eq 0) { throw "Unknown profile recipe '$Profile'." }
        if ($matches.Count -gt 1) { throw "Profile recipe ID '$Profile' is ambiguous." }
        $definition = $matches[0]
    }
    else {
        $matches = [System.Collections.Generic.List[object]]::new()
        foreach ($candidate in $definitions) {
            $recipe = Read-ProfileRecipe $candidate.Path
            if ($candidate.Id -ieq $resources.Name -or $recipe.Name -ieq $resources.Name) { $matches.Add($candidate) }
        }
        if ($matches.Count -eq 0) {
            throw "Exported profile name '$($resources.Name)' does not match a repository recipe ID or display name. Supply the recipe ID explicitly."
        }
        if ($matches.Count -gt 1) {
            $ids = @($matches | ForEach-Object Id) -join ', '
            throw "Exported profile name '$($resources.Name)' matches multiple repository recipes: $ids. Supply the recipe ID explicitly."
        }
        $definition = $matches[0]
    }

    $profileId = $definition.Id
    $recipe = Read-ProfileRecipe $definition.Path
    $keybindingFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($component in $recipe.Components) {
        $componentPath = Join-Path $root "components/$component"
        $path = Join-Path $componentPath 'keybindings.jsonc'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $keybindingFiles.Add([pscustomobject]@{ Path = $path; Source = (Get-RelativeDisplayPath $root $path) })
        }
    }
    $componentKeybindings = @((Merge-Keybindings $keybindingFiles.ToArray()).Items)

    $trackedGlobal = Read-JsonCFile (Join-Path $root 'global/settings.jsonc')
    $globalSettingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($id in @($trackedGlobal['workbench.settings.applyToAllProfiles'])) { $globalSettingIds.Add([string]$id) | Out-Null }
    $newGlobal = $null
    $machineOwnedGlobalCount = 0
    $applicationOwnershipAddedCount = 0
    $applicationOwnershipDuplicateCount = 0
    $applicationMachineClassifiedCount = 0
    $applicationSensitiveExcludedCount = 0
    $machineOwnedSettingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if (-not $SkipGlobal) {
        $userDataPath = if ($VSCodeUserDataPath) {
            [System.IO.Path]::GetFullPath($VSCodeUserDataPath)
        }
        else {
            Get-DefaultVSCodeUserDataPath
        }
        $applicationSettingsPath = Join-Path $userDataPath 'settings.json'
        if (-not (Test-Path -LiteralPath $applicationSettingsPath -PathType Leaf)) {
            throw "VS Code application settings were not found at '$applicationSettingsPath'. Use -VSCodeUserDataPath or -SkipGlobal."
        }
        $applicationSettings = Read-JsonCFile $applicationSettingsPath
        try {
            $applicationNormalization = Normalize-ApplicationSettingsOwnership -Settings $applicationSettings -EnsureIgnoredSettings
        }
        catch {
            throw "VS Code application settings '$applicationSettingsPath' could not be normalized: $($_.Exception.Message)"
        }
        $applicationSettings = $applicationNormalization.settings
        $applicationOwnershipAddedCount = $applicationNormalization.addedSettings.Count
        $applicationOwnershipDuplicateCount = $applicationNormalization.removedDuplicates.Count

        $syncIgnored = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $normalizedIgnored = [System.Collections.Generic.List[string]]::new()
        $seenIgnoredEntries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($id in @($applicationSettings['settingsSync.ignoredSettings'])) {
            if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id)) {
                throw "VS Code application settings contain an invalid 'settingsSync.ignoredSettings' entry."
            }
            $ignoredId = [string]$id
            if ($seenIgnoredEntries.Add($ignoredId)) { $normalizedIgnored.Add($ignoredId) }
            if (-not $ignoredId.StartsWith('-')) { $syncIgnored.Add($ignoredId) | Out-Null }
        }
        $seenGlobal = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $filteredGlobalIds = [System.Collections.Generic.List[string]]::new()
        $newGlobal = New-OrderedMap
        $globalSettingIds.Clear()
        foreach ($idValue in @($applicationSettings['workbench.settings.applyToAllProfiles'])) {
            if ($idValue -isnot [string] -or [string]::IsNullOrWhiteSpace($idValue)) {
                throw 'VS Code application settings contain an invalid apply-to-all setting ID.'
            }
            $id = [string]$idValue
            if (-not $seenGlobal.Add($id)) { throw "VS Code application settings list global setting '$id' more than once." }
            if (-not $applicationSettings.Contains($id)) { throw "VS Code application setting '$id' is apply-to-all but has no value." }
            $classification = if ($id -eq 'settingsSync.ignoredSettings') {
                [pscustomobject]@{ classification = 'portable' }
            }
            else {
                Get-SettingValueClassification -SettingKey $id -Value $applicationSettings[$id]
            }
            if ($classification.classification -eq 'secret-or-private') {
                $applicationSensitiveExcludedCount++
                continue
            }
            $machineOwned = $id -ne 'settingsSync.ignoredSettings' -and (
                $syncIgnored.Contains($id) -or $classification.classification -eq 'machine-local-path'
            )
            if ($machineOwned) {
                $machineOwnedGlobalCount++
                $machineOwnedSettingIds.Add($id) | Out-Null
                if (-not $syncIgnored.Contains($id)) {
                    $syncIgnored.Add($id) | Out-Null
                    if ($seenIgnoredEntries.Add($id)) { $normalizedIgnored.Add($id) }
                    $applicationMachineClassifiedCount++
                }
                continue
            }
            $filteredGlobalIds.Add($id)
            $globalSettingIds.Add($id) | Out-Null
        }
        if (-not $seenGlobal.Contains('settingsSync.ignoredSettings')) {
            throw "VS Code application settings must apply 'settingsSync.ignoredSettings' to all profiles."
        }
        $applicationSettings['settingsSync.ignoredSettings'] = [string[]]$normalizedIgnored.ToArray()
        $newGlobal['workbench.settings.applyToAllProfiles'] = [string[]]$filteredGlobalIds.ToArray()
        foreach ($id in $filteredGlobalIds) { $newGlobal[$id] = Copy-ComposerValue $applicationSettings[$id] }
    }

    $managedRouterPath = Get-ManagedOwnershipRouterPath $root
    $managedRouter = Read-OwnershipRouterFile $managedRouterPath
    $managedValidation = Test-OwnershipRouterDocument $managedRouter -RepositoryRoot $root -Source 'config/ownership-router.jsonc'
    if ($managedValidation.errors.Count -gt 0) {
        throw "Managed ownership router is invalid: $(@($managedValidation.errors | ForEach-Object message) -join '; ')"
    }
    $customRouter = $null
    if ($RoutingFile) {
        $routingPath = if ([System.IO.Path]::IsPathRooted($RoutingFile)) { $RoutingFile } else { Join-Path $root $RoutingFile }
        $customRouter = Read-OwnershipRouterFile $routingPath
        $customValidation = Test-OwnershipRouterDocument $customRouter -RepositoryRoot $root -Source (Get-RelativeDisplayPath $root $routingPath) -Custom
        if ($customValidation.errors.Count -gt 0) {
            throw "Custom ownership router is invalid: $(@($customValidation.errors | ForEach-Object message) -join '; ')"
        }
    }

    $ownershipIndex = Get-RepositoryOwnershipIndex -RepositoryRoot $root -Platform $Platform -Profile $profileId
    $resolutions = [System.Collections.Generic.List[object]]::new()
    $unresolved = [System.Collections.Generic.List[object]]::new()
    $globalSettingsIgnored = 0
    foreach ($keyValue in $resources.Settings.Keys) {
        $key = [string]$keyValue
        if ($globalSettingIds.Contains($key) -or $machineOwnedSettingIds.Contains($key)) {
            $globalSettingsIgnored++
            continue
        }
        $resolution = Resolve-OwnershipItem -Kind setting -Item $key -Value $resources.Settings[$key] `
            -ExistingOwners (Get-OwnershipIndexOwners $ownershipIndex setting $key) `
            -ManagedRouter $managedRouter -CustomRouter $customRouter -RoutingMode $RoutingMode
        if ($resolution.resolved) { $resolutions.Add($resolution) } else { $unresolved.Add($resolution) }
    }
    foreach ($keyValue in $machineOwnedSettingIds) {
        $key = [string]$keyValue
        $value = Copy-ComposerValue $applicationSettings[$key]
        $resources.Settings[$key] = $value
        $resolution = Resolve-OwnershipItem -Kind setting -Item $key -Value $value `
            -ExistingOwners (Get-OwnershipIndexOwners $ownershipIndex setting $key) `
            -ManagedRouter $managedRouter -CustomRouter $customRouter -RoutingMode $RoutingMode `
            -ExplicitDestination (New-OwnershipDestination machine)
        if ($resolution.resolved) { $resolutions.Add($resolution) } else { $unresolved.Add($resolution) }
    }
    foreach ($id in $resources.Extensions) {
        $resolution = Resolve-OwnershipItem -Kind extension -Item $id -Value $null `
            -ExistingOwners (Get-OwnershipIndexOwners $ownershipIndex extension $id) `
            -ManagedRouter $managedRouter -CustomRouter $customRouter -RoutingMode $RoutingMode
        if ($resolution.resolved) { $resolutions.Add($resolution) } else { $unresolved.Add($resolution) }
    }

    $interactiveRoutes = [object[]]@()
    if ($unresolved.Count -gt 0) {
        if ($WriteUnresolved) {
            $unresolvedPath = if ([System.IO.Path]::IsPathRooted($WriteUnresolved)) { $WriteUnresolved } else { Join-Path $root $WriteUnresolved }
            $unresolvedDocument = ConvertTo-UnresolvedRouterDocument $unresolved.ToArray()
            $unresolvedValidation = Test-OwnershipRouterDocument $unresolvedDocument -RepositoryRoot $root -Source $unresolvedPath -Custom
            if ($unresolvedValidation.errors.Count -gt 0) { throw "Could not generate unresolved router: $(@($unresolvedValidation.errors.message) -join '; ')" }
            Write-OwnershipRouterFile $unresolvedPath $unresolvedDocument
        }
        $effectiveNonInteractive = $NonInteractive -or (-not $ResolutionProvider -and [Console]::IsInputRedirected)
        if ($effectiveNonInteractive) {
            $items = @($unresolved | ForEach-Object { "$($_.kind):$($_.item)" }) -join ', '
            throw "Unresolved ownership remains in non-interactive mode: $items$(if ($WriteUnresolved) { ". Review '$WriteUnresolved' and retry with -RoutingFile." })"
        }
        $interactive = Resolve-OwnershipInteractively -Items $unresolved.ToArray() -Profile $profileId `
            -ResolutionProvider $ResolutionProvider -ManagedRouter $managedRouter `
            -OwnershipIndex $ownershipIndex -RepositoryRoot $root -DryRun:$DryRun
        $decisionMap = @{}
        foreach ($decision in $interactive.decisions) { $decisionMap["$($decision.kind)|$($decision.item.ToLowerInvariant())"] = $decision.destination }
        foreach ($item in $unresolved) {
            $destination = $decisionMap["$($item.kind)|$($item.item.ToLowerInvariant())"]
            if (-not $destination -or $destination.type -eq 'unresolved') {
                throw "Ownership remains unresolved for $($item.kind) '$($item.item)'."
            }
            $value = if ($item.kind -eq 'setting') { $resources.Settings[$item.item] } else { $null }
            $resolutions.Add((Resolve-OwnershipItem -Kind $item.kind -Item $item.item -Value $value `
                -ExistingOwners (Get-OwnershipIndexOwners $ownershipIndex $item.kind $item.item) `
                -ManagedRouter $managedRouter -CustomRouter $customRouter -RoutingMode $RoutingMode -ExplicitDestination $destination))
        }
        $interactiveRoutes = $interactive.routes
        if ($interactiveRoutes.Count -gt 0) {
            $combined = [System.Collections.Generic.List[object]]::new()
            foreach ($route in $managedRouter.routes) { $combined.Add($route) }
            foreach ($route in $interactiveRoutes) {
                if (@($combined | Where-Object id -ieq $route.id).Count -gt 0) {
                    throw "Interactive route ID '$($route.id)' already exists; no router changes were written."
                }
                $combined.Add($route)
            }
            $managedRouter['routes'] = [object[]]$combined.ToArray()
            $combinedValidation = Test-OwnershipRouterDocument $managedRouter -RepositoryRoot $root -Source 'config/ownership-router.jsonc'
            if ($combinedValidation.errors.Count -gt 0) {
                throw "Interactive router update is invalid: $(@($combinedValidation.errors.message) -join '; ')"
            }
        }
    }

    $needsMachine = @($resolutions | Where-Object { $_.destination.type -eq 'machine' }).Count -gt 0
    $resolvedSyncMachine = $null
    $machineRelativePath = $null
    if ($needsMachine -or $Machine -or $MachineFile) {
        try {
            $resolvedSyncMachine = Resolve-SyncMachine -RepositoryRoot $root -Platform $Platform -Machine $Machine -MachineFile $MachineFile
        }
        catch {
            $affected = @($resolutions | Where-Object { $_.destination.type -eq 'machine' } | ForEach-Object item) -join ', '
            throw "Machine-owned items require a resolvable target ($affected). $($_.Exception.Message) Retry with: vscomp sync `"$sourcePath`" -Platform $(if ($Platform) { $Platform } else { '<platform>' }) -Machine <machine-id>"
        }
        $machineLocalRoot = [System.IO.Path]::GetFullPath((Join-Path $root 'machine/local'))
        if (-not (Test-PathWithinDirectory $resolvedSyncMachine.Path $machineLocalRoot)) {
            throw 'Sync machine routing requires a target under machine/local. Use -Machine <id>.'
        }
        $machineRelativePath = Get-RelativeDisplayPath $root $resolvedSyncMachine.Path
    }

    $componentKeybindingSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $componentKeybindings) { $componentKeybindingSet.Add((Get-CanonicalComposerValue $item)) | Out-Null }
    $liveKeybindingSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $resources.Keybindings) { $liveKeybindingSet.Add((Get-CanonicalComposerValue $item)) | Out-Null }
    $keybindingAdditions = @($resources.Keybindings | Where-Object { -not $componentKeybindingSet.Contains((Get-CanonicalComposerValue $_)) })
    $keybindingRemovals = @($componentKeybindings | Where-Object { -not $liveKeybindingSet.Contains((Get-CanonicalComposerValue $_)) })
    $predictedKeybindings = @(
        $componentKeybindings | Where-Object { $liveKeybindingSet.Contains((Get-CanonicalComposerValue $_)) }
        $keybindingAdditions
    )
    $predictedOrder = @($predictedKeybindings | ForEach-Object { Get-CanonicalComposerValue $_ }) -join "`n"
    $liveOrder = @($resources.Keybindings | ForEach-Object { Get-CanonicalComposerValue $_ }) -join "`n"
    $replaceKeybindings = $predictedOrder -cne $liveOrder

    $changes = [System.Collections.Generic.List[object]]::new()
    $changedRoots = @{}
    $globalChanged = $false
    $uiStateChanged = $false
    $stagingRoot = New-ComposerStagingRepository $root
    try {
        foreach ($resolution in $resolutions) {
            if ($resolution.destination.type -in @('exclude', 'unresolved')) { continue }
            Remove-PreviousOwnership -StagingRoot $stagingRoot -Resolution $resolution -Changes $changes -ChangedRoots $changedRoots
            if ($resolution.kind -eq 'setting') {
                Set-RoutedSettingValue -StagingRoot $stagingRoot -RepositoryRoot $root -Resolution $resolution `
                    -Value $resources.Settings[$resolution.item] -Changes $changes -ChangedRoots $changedRoots -ResolvedMachine $resolvedSyncMachine
            }
            else {
                Set-RoutedExtensionValue -StagingRoot $stagingRoot -RepositoryRoot $root -Resolution $resolution `
                    -Changes $changes -ChangedRoots $changedRoots
            }
        }
        if (($resources.Keybindings.Count -gt 0 -or $componentKeybindings.Count -gt 0) -and
            ($replaceKeybindings -or $keybindingAdditions.Count -gt 0)) {
            $keybindingPath = Join-Path $stagingRoot "profiles/$profileId.keybindings.jsonc"
            $value = if ($replaceKeybindings) {
                [ordered]@{ replace = [object[]]$resources.Keybindings }
            }
            else { [ordered]@{ add = [object[]]$keybindingAdditions; remove = [object[]]@() } }
            $same = (Test-Path -LiteralPath $keybindingPath -PathType Leaf) -and (Test-ValuesEqual (Read-JsonCFile $keybindingPath) $value)
            if (-not $same) {
                Write-Utf8File $keybindingPath (ConvertTo-PrettyJson $value)
                $changes.Add([pscustomobject]@{ action = 'update'; path = "profiles/$profileId.keybindings.jsonc"; item = 'keybindings'; owner = "profile/$profileId" })
                $changedRoots['profiles'] = $true
            }
        }
        if ($interactiveRoutes.Count -gt 0 -and (-not $DryRun -or $PersistDryRunDecisions)) {
            $stagedRouterPath = Get-ManagedOwnershipRouterPath $stagingRoot
            Write-OwnershipRouterFile $stagedRouterPath $managedRouter
            $changes.Add([pscustomobject]@{ action = 'update'; path = 'config/ownership-router.jsonc'; item = 'interactive routes'; owner = 'managed-router' })
            $changedRoots['config'] = $true
        }

        if (-not $SkipGlobal) {
            $stagedGlobalPath = Join-Path $stagingRoot 'global/settings.jsonc'
            if (-not (Test-ValuesEqual (Read-JsonCFile $stagedGlobalPath) $newGlobal)) {
                Write-Utf8File $stagedGlobalPath (ConvertTo-PrettyJson $newGlobal)
                $changes.Add([pscustomobject]@{ action = 'update'; path = 'global/settings.jsonc' })
                $globalChanged = $true
                $changedRoots['global'] = $true
            }
        }
        if (-not $SkipUiState) {
            $uiDirectory = Join-Path $stagingRoot "machine/local/ui-state/$profileId"
            [System.IO.Directory]::CreateDirectory($uiDirectory) | Out-Null
            $seed = [ordered]@{
                name = "Stored UI state seed for $profileId"
                globalState = [string]$resources.GlobalState
            }
            $uiPath = Join-Path $uiDirectory 'seed.code-profile'
            $sameUiState = (Test-Path -LiteralPath $uiPath -PathType Leaf) -and
                ((Read-CodeProfileGlobalState $uiPath) -ceq [string]$resources.GlobalState)
            if (-not $sameUiState) {
                Write-Utf8File $uiPath (ConvertTo-PrettyJson $seed)
                Read-CodeProfileGlobalState $uiPath | Out-Null
                $changes.Add([pscustomobject]@{ action = if (Test-Path -LiteralPath (Join-Path $root "machine/local/ui-state/$profileId/seed.code-profile")) { 'update' } else { 'create' }; path = "machine/local/ui-state/$profileId/seed.code-profile" })
                $uiStateChanged = $true
                $changedRoots['machine/local/ui-state'] = $true
            }
        }

        Assert-StagedRepositoryValid $stagingRoot
        if (-not $DryRun) {
            $commitPaths = [string[]]@($changedRoots.Keys | Sort-Object)
            if ($commitPaths.Count -gt 0) {
                Invoke-StagedRepositoryCommit $root $stagingRoot $commitPaths
            }
        }
        elseif ($PersistDryRunDecisions -and $interactiveRoutes.Count -gt 0) {
            Invoke-StagedRepositoryCommit $root $stagingRoot @('config')
        }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
    }

    return [pscustomobject][ordered]@{
        operation = 'sync-profile'
        profileId = $profileId
        displayName = $recipe.Name
        exportName = $resources.Name
        changes = [object[]]$changes.ToArray()
        routes = [object[]]@($resolutions | ForEach-Object {
            $routeResolution = $_
            [pscustomobject][ordered]@{
                kind = $routeResolution.kind
                item = $routeResolution.item
                destination = Get-OwnershipDestinationLabel $routeResolution.destination
                ruleId = $routeResolution.winner.id
                precedence = $routeResolution.winner.precedence
                classification = if ($routeResolution.classification) { $routeResolution.classification.classification } else { 'extension' }
                changed = @($changes | Where-Object {
                    $_.PSObject.Properties.Name -contains 'item' -and $_.item -eq $routeResolution.item
                }).Count -gt 0
                candidates = $routeResolution.candidates
            }
        })
        machine = if ($resolvedSyncMachine) {
            [pscustomobject][ordered]@{
                id = $resolvedSyncMachine.Id
                name = $resolvedSyncMachine.Name
                platform = $resolvedSyncMachine.Platform
                selection = $resolvedSyncMachine.Selection
                path = $machineRelativePath
            }
        }
        else { $null }
        counts = [pscustomobject][ordered]@{
            settingsRouted = @($resolutions | Where-Object kind -eq 'setting').Count
            extensionsRouted = @($resolutions | Where-Object { $_.kind -eq 'extension' }).Count
            excluded = @($resolutions | Where-Object { $_.destination.type -eq 'exclude' }).Count
            unresolved = 0
            settingReplacements = @($changes | Where-Object {
                $_.PSObject.Properties.Name -contains 'item' -and
                $_.item -and
                $_.item -ne 'keybindings' -and
                $_.path -match '(settings|components|platform|machine)'
            }).Count
            settingRemovals = 0
            extensionAdditions = @($changes | Where-Object { $_.path -match 'extensions' }).Count
            extensionRemovals = 0
            keybindingAdditions = $keybindingAdditions.Count
            keybindingRemovals = 0
            keybindingsReplacedForOrder = [bool]$replaceKeybindings
            globalSettings = if ($SkipGlobal) { 0 } else { $newGlobal.Count - 1 }
            machineOwnedGlobalSettingsSkipped = $machineOwnedGlobalCount
            applicationSettingsAddedToApplyToAll = $applicationOwnershipAddedCount
            applicationOwnershipDuplicatesRemoved = $applicationOwnershipDuplicateCount
            applicationSettingsClassifiedAsMachine = $applicationMachineClassifiedCount
            applicationSensitiveSettingsExcluded = $applicationSensitiveExcludedCount
            exportGlobalSettingsIgnored = $globalSettingsIgnored
            platformSettingsIgnored = 0
            machineSettingsRouted = @($resolutions | Where-Object { $_.destination.type -eq 'machine' }).Count
            machineSettingsAdded = @($changes | Where-Object {
                $_.PSObject.Properties.Name -contains 'owner' -and $_.owner -eq 'machine' -and $_.action -eq 'create'
            }).Count
            machineSettingsUpdated = @($changes | Where-Object {
                $_.PSObject.Properties.Name -contains 'owner' -and $_.owner -eq 'machine' -and $_.action -eq 'update'
            }).Count
            machineSettingsRetained = @($resolutions | Where-Object { $_.destination.type -eq 'machine' }).Count - @($changes | Where-Object {
                $_.PSObject.Properties.Name -contains 'owner' -and $_.owner -eq 'machine'
            }).Count
        }
        uiStateUpdated = $uiStateChanged
        dryRun = [bool]$DryRun
    }
}

function Get-ManagedOwnershipRouter {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    return Read-OwnershipRouterFile (Get-ManagedOwnershipRouterPath $RepositoryRoot)
}

function Set-ManagedOwnershipRouter {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Document,
        [switch]$DryRun
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $validation = Test-OwnershipRouterDocument $Document -RepositoryRoot $root -Source 'config/ownership-router.jsonc'
    if ($validation.errors.Count -gt 0) {
        throw "Router update rejected: $(@($validation.errors.message) -join '; ')"
    }
    $current = Get-ManagedOwnershipRouter $root
    if (Test-ValuesEqual $current $Document) {
        return [pscustomobject]@{ operation = 'router-update'; changes = @(); dryRun = [bool]$DryRun }
    }
    $stagingRoot = New-ComposerStagingRepository $root
    try {
        Write-OwnershipRouterFile (Get-ManagedOwnershipRouterPath $stagingRoot) $Document
        Assert-StagedRepositoryValid $stagingRoot
        if (-not $DryRun) { Invoke-StagedRepositoryCommit $root $stagingRoot @('config') }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
    }
    return [pscustomobject]@{
        operation = 'router-update'
        changes = @([pscustomobject]@{ action = 'update'; path = 'config/ownership-router.jsonc' })
        dryRun = [bool]$DryRun
    }
}

function Add-ManagedOwnershipRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Route,
        [switch]$DryRun
    )

    $document = Get-ManagedOwnershipRouter $RepositoryRoot
    if (@($document.routes | Where-Object id -ieq $Route.id).Count -gt 0) {
        throw "Route ID '$($Route.id)' already exists."
    }
    $sameMatch = @($document.routes | Where-Object {
        $_.kind -ieq $Route.kind -and $_.match.type -ieq $Route.match.type -and $_.match.value -ieq $Route.match.value
    })
    if ($sameMatch.Count -gt 0) {
        throw "A route already exists for $($Route.kind) $($Route.match.type) '$($Route.match.value)': $(@($sameMatch.id) -join ', ')."
    }
    $document['routes'] = [object[]]@($document.routes + $Route)
    return Set-ManagedOwnershipRouter $RepositoryRoot $document -DryRun:$DryRun
}

function Set-ManagedOwnershipRouteStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$RouteId,
        [Parameter(Mandatory)][ValidateSet('approved', 'provisional', 'disabled')][string]$Status,
        [switch]$DryRun
    )

    $document = Get-ManagedOwnershipRouter $RepositoryRoot
    $matches = @($document.routes | Where-Object id -ieq $RouteId)
    if ($matches.Count -ne 1) { throw "Route '$RouteId' was not found or is ambiguous." }
    $matches[0]['status'] = $Status
    return Set-ManagedOwnershipRouter $RepositoryRoot $document -DryRun:$DryRun
}

function Remove-ManagedOwnershipRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$RouteId,
        [switch]$DryRun
    )

    $document = Get-ManagedOwnershipRouter $RepositoryRoot
    $remaining = @($document.routes | Where-Object id -ine $RouteId)
    if ($remaining.Count -eq $document.routes.Count) { throw "Route '$RouteId' was not found." }
    $document['routes'] = [object[]]$remaining
    return Set-ManagedOwnershipRouter $RepositoryRoot $document -DryRun:$DryRun
}

function Import-ManagedOwnershipRoutes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Path,
        [switch]$DryRun
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $root $Path }
    $custom = Read-OwnershipRouterFile $resolvedPath
    $customValidation = Test-OwnershipRouterDocument $custom -RepositoryRoot $root -Source $resolvedPath -Custom
    if ($customValidation.errors.Count -gt 0) { throw "Custom route import rejected: $(@($customValidation.errors.message) -join '; ')" }
    $managed = Get-ManagedOwnershipRouter $root
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $signatures = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($route in $managed.routes) {
        $ids.Add([string]$route.id) | Out-Null
        $signatures.Add("$($route.kind)|$($route.match.type)|$($route.match.value)") | Out-Null
    }
    $combined = [System.Collections.Generic.List[object]]::new()
    foreach ($route in $managed.routes) { $combined.Add($route) }
    foreach ($route in $custom.routes) {
        $signature = "$($route.kind)|$($route.match.type)|$($route.match.value)"
        if (-not $ids.Add([string]$route.id)) { throw "Imported route ID '$($route.id)' already exists." }
        if (-not $signatures.Add($signature)) { throw "Imported route match '$signature' already exists." }
        $copy = Copy-ComposerValue $route
        $copy['source'] = 'custom-file'
        $combined.Add($copy)
    }
    $managed['routes'] = [object[]]$combined.ToArray()
    return Set-ManagedOwnershipRouter $root $managed -DryRun:$DryRun
}

function Invoke-OwnershipRouterAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$RoutingFile,
        [string]$Platform
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $path = if ($RoutingFile) {
        if ([System.IO.Path]::IsPathRooted($RoutingFile)) { $RoutingFile } else { Join-Path $root $RoutingFile }
    }
    else { Get-ManagedOwnershipRouterPath $root }
    $document = Read-OwnershipRouterFile $path
    $result = Test-OwnershipRouterDocument $document -RepositoryRoot $root -Source (Get-RelativeDisplayPath $root $path) -Custom:$([bool]$RoutingFile)
    $index = Get-RepositoryOwnershipIndex -RepositoryRoot $root -Platform $Platform
    $routerDisplayPath = Get-RelativeDisplayPath $root $path
    foreach ($indexKey in $index.Keys) {
        $owners = @($index[$indexKey].ToArray())
        if ($owners.Count -gt 1) {
            $parts = [string]$indexKey -split '\|', 2
            $ownerPaths = @($owners | ForEach-Object path) -join ', '
            Add-ValidationItem $result errors 'router-duplicate-ownership' "Repository $($parts[0]) '$($parts[1])' has multiple exact owners: $ownerPaths." $routerDisplayPath
        }
    }
    $repositoryItems = @($index.Keys | ForEach-Object {
        $parts = [string]$_ -split '\|', 2
        [pscustomobject]@{ kind = $parts[0]; item = $parts[1] }
    })
    foreach ($route in @($document.routes)) {
        $currentMatches = @($repositoryItems | Where-Object {
            Test-OwnershipRouteMatch $route $_.kind $_.item
        })
        if ($currentMatches.Count -eq 0) {
            $level = if ($route.match.type -eq 'exact') { 'information' } else { 'warnings' }
            $diagnosticCode = if ($route.match.type -eq 'exact') { 'router-orphan-exact' } else { 'router-stale-pattern' }
            Add-ValidationItem $result $level $diagnosticCode "Route '$($route.id)' matches no current repository-owned item for the selected audit scope; retain it only if it intentionally targets future imports." $routerDisplayPath
        }
        if ($route.kind -eq 'extension' -and $route.destination.type -eq 'machine') {
            Add-ValidationItem $result errors 'router-uncomposable-extension' "Route '$($route.id)' sends an extension to machine ownership, which the current profile artifact cannot compose." $routerDisplayPath
        }
    }
    foreach ($route in @($document.routes | Where-Object { $_.match.type -eq 'exact' })) {
        $owners = @(Get-OwnershipIndexOwners $index $route.kind $route.match.value)
        if ($owners.Count -gt 0) {
            $destinations = @($owners | ForEach-Object { Get-OwnershipDestinationLabel $_.destination } | Select-Object -Unique)
            $routeDestination = Get-OwnershipDestinationLabel $route.destination
            if ($destinations -inotcontains $routeDestination) {
                Add-ValidationItem $result warnings 'router-disagrees-with-owner' "Route '$($route.id)' targets '$routeDestination', but existing ownership is $($destinations -join ', ')." $routerDisplayPath
            }
            else {
                Add-ValidationItem $result information 'router-shadowed-by-owner' "Route '$($route.id)' agrees with exact ownership and is normally shadowed by it." $routerDisplayPath
            }
        }
        if ($route.kind -eq 'setting' -and $owners.Count -eq 1) {
            $ownerPath = Join-Path $root $owners[0].path
            if (Test-Path -LiteralPath $ownerPath -PathType Leaf -and $ownerPath -match '\.jsonc?$') {
                $settings = Read-JsonCFile $ownerPath
                if (Test-IsDictionary $settings -and $settings.Contains($route.match.value)) {
                    $classification = Get-SettingValueClassification $route.match.value $settings[$route.match.value]
                    if ($classification.classification -eq 'machine-local-path' -and $route.destination.type -in @('component', 'platform', 'profile')) {
                        Add-ValidationItem $result errors 'router-machine-to-portable' "Route '$($route.id)' sends a machine-local value to a portable destination." $routerDisplayPath
                    }
                    if ($classification.classification -eq 'secret-or-private' -and $route.destination.type -ne 'exclude') {
                        Add-ValidationItem $result errors 'router-sensitive-to-storage' "Route '$($route.id)' sends sensitive/private state to repository storage." $routerDisplayPath
                    }
                }
            }
        }
    }
    return $result
}

function Explain-OwnershipRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Item,
        [ValidateSet('setting', 'extension')][string]$Kind,
        [string]$Platform,
        [string]$RoutingFile,
        [ValidateSet('Supplement', 'Override', 'Isolated')][string]$RoutingMode = 'Supplement',
        [AllowNull()]$Value
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $managed = Get-ManagedOwnershipRouter $root
    $custom = if ($RoutingFile) {
        $path = if ([System.IO.Path]::IsPathRooted($RoutingFile)) { $RoutingFile } else { Join-Path $root $RoutingFile }
        Read-OwnershipRouterFile $path
    }
    else { $null }
    $index = Get-RepositoryOwnershipIndex -RepositoryRoot $root -Platform $Platform
    if (-not $Kind) {
        $Kind = if (@(Get-OwnershipIndexOwners $index extension $Item).Count -gt 0 -or $Item -match '^[^.]+\.[^.]+$' -and $Item -notmatch '(?i)^(editor|workbench|terminal|files|window)\.') { 'extension' } else { 'setting' }
    }
    $owners = @(Get-OwnershipIndexOwners $index $Kind $Item)
    if ($Kind -eq 'setting' -and $null -eq $Value -and $owners.Count -eq 1) {
        $ownerPath = Join-Path $root $owners[0].path
        if ($ownerPath -match '\.jsonc?$') {
            $map = Read-JsonCFile $ownerPath
            if (Test-IsDictionary $map -and $map.Contains($Item)) { $Value = $map[$Item] }
        }
    }
    $resolution = Resolve-OwnershipItem -Kind $Kind -Item $Item -Value $Value -ExistingOwners $owners `
        -ManagedRouter $managed -CustomRouter $custom -RoutingMode $RoutingMode
    $destinationPath = if ($resolution.resolved -and $resolution.destination.type -notin @('machine', 'exclude')) {
        Get-RelativeDisplayPath $root (Get-RoutedDestinationPath $root $Kind $resolution.destination)
    }
    else { $null }
    return [pscustomobject][ordered]@{
        item = $Item
        kind = $Kind
        candidates = $resolution.candidates
        winner = $resolution.winner
        destination = Get-OwnershipDestinationLabel $resolution.destination
        destinationFile = $destinationPath
        existingOwnership = $owners
        classification = if ($resolution.classification) { $resolution.classification.classification } else { 'extension' }
        validation = if ($resolution.destination.type -eq 'unresolved') { 'unresolved' } else { 'passed' }
    }
}

function Archive-LegacySyncSidecars {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$BackupName = 'legacy-sync-manual',
        [switch]$ConfirmArchive,
        [switch]$DryRun
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Test-ComposerId $BackupName)) { throw "Invalid migration backup name '$BackupName'." }
    $profileRoot = Join-Path $root 'profiles'
    $sidecars = @(Get-ChildItem -LiteralPath $profileRoot -File | Where-Object {
        $_.Name -match '\.(settings(\.replace|\.remove)?|extensions|keybindings)\.jsonc$'
    } | Sort-Object Name)
    $changes = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $sidecars) {
        $changes.Add([pscustomobject]@{
            action = if ($ConfirmArchive) { 'archive' } else { 'candidate' }
            source = "profiles/$($file.Name)"
            target = "migration-backups/$BackupName/$($file.Name)"
        })
    }
    if (-not $ConfirmArchive -or $sidecars.Count -eq 0) {
        return [pscustomobject]@{
            operation = 'archive-legacy-sync-sidecars'
            changes = [object[]]$changes.ToArray()
            dryRun = $true
            confirmationRequired = $sidecars.Count -gt 0
        }
    }

    $stagingRoot = New-ComposerStagingRepository $root
    try {
        $backupRoot = Join-Path $stagingRoot "migration-backups/$BackupName"
        [System.IO.Directory]::CreateDirectory($backupRoot) | Out-Null
        foreach ($file in $sidecars) {
            $stagedSource = Join-Path $stagingRoot "profiles/$($file.Name)"
            $stagedBackup = Join-Path $backupRoot $file.Name
            if (Test-Path -LiteralPath $stagedBackup -PathType Leaf) {
                if ([System.IO.File]::ReadAllText($stagedBackup) -cne [System.IO.File]::ReadAllText($stagedSource)) {
                    throw "Migration backup collision at 'migration-backups/$BackupName/$($file.Name)'. Choose another -BackupName."
                }
                Remove-Item -LiteralPath $stagedSource -Force
            }
            else {
                Move-Item -LiteralPath $stagedSource -Destination $stagedBackup
            }
        }
        Write-Utf8File (Join-Path $backupRoot 'README.md') @"
# Archived legacy sync sidecars

These files were archived by ``vscomp migrate legacy-sync``. They are not
composed. Review each item and reintroduce it only through an explicit owner or
approved route.
"@
        Assert-StagedRepositoryValid $stagingRoot
        if (-not $DryRun) { Invoke-StagedRepositoryCommit $root $stagingRoot @('profiles', 'migration-backups') }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
    }
    return [pscustomobject]@{
        operation = 'archive-legacy-sync-sidecars'
        changes = [object[]]$changes.ToArray()
        dryRun = [bool]$DryRun
        confirmationRequired = $false
    }
}

function Invoke-GlobalSettingsComposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Machine,
        [string]$MachineFile,
        [switch]$DryRun,
        [switch]$Strict
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ($Machine -and $MachineFile) { throw '-Machine and -MachineFile cannot be used together.' }
    $validation = Test-ComposerRepository -RepositoryRoot $root -Machine $Machine -MachineFile $MachineFile
    if ($validation.errors.Count -gt 0 -or ($Strict -and $validation.warnings.Count -gt 0)) {
        $reason = if ($validation.errors.Count -gt 0) { "$($validation.errors.Count) validation error(s)" } else { "$($validation.warnings.Count) warning(s) in strict mode" }
        throw "Global settings composition stopped because repository validation found $reason."
    }

    $sourcePath = Join-Path $root 'global/settings.jsonc'
    $settings = Read-JsonCFile $sourcePath
    $resolvedMachine = Resolve-MachinePath -RepositoryRoot $root -Machine $Machine -MachineFile $MachineFile
    $machineConfiguration = if ($resolvedMachine) {
        Read-MachineConfiguration -Path $resolvedMachine -ExpectedId $Machine
    }
    else { $null }
    $machineSettings = if ($machineConfiguration) { $machineConfiguration.Settings } else { $null }
    $machineSettingIds = @()
    if ($resolvedMachine) { $machineSettingIds = @(Get-MachineSettingIds $machineSettings) }
    $machineId = if ($Machine) { $Machine } elseif ($resolvedMachine) { [System.IO.Path]::GetFileNameWithoutExtension($resolvedMachine) } else { $null }
    $overrides = [System.Collections.Generic.List[object]]::new()

    if ($resolvedMachine) {
        $sourceMap = [hashtable]::new([System.StringComparer]::Ordinal)
        foreach ($key in $settings.Keys) { Set-SourceTree $settings[$key] "/$(ConvertTo-JsonPointerSegment ([string]$key))" 'global/settings.jsonc' $sourceMap }
        Merge-Settings $settings $machineSettings (Get-RelativeDisplayPath $root $resolvedMachine) $sourceMap $overrides | Out-Null

        $ignored = [System.Collections.Generic.List[string]]::new()
        $ignoredSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($id in @($settings['settingsSync.ignoredSettings'])) {
            if ($machineSettingIds -ccontains ([string]$id).TrimStart('-')) { continue }
            if ($ignoredSet.Add([string]$id)) { $ignored.Add([string]$id) }
        }
        foreach ($id in $machineSettingIds) {
            if ($ignoredSet.Add($id)) { $ignored.Add($id) }
        }
        $settings['settingsSync.ignoredSettings'] = [string[]]$ignored.ToArray()
    }
    $settings = (Normalize-ApplicationSettingsOwnership -Settings $settings -EnsureIgnoredSettings).settings

    $targetDirectory = [System.IO.Path]::GetFullPath((Join-Path $root 'build/global'))
    if ($DryRun) {
        return [pscustomobject][ordered]@{
            outputDirectory = Get-RelativeDisplayPath $root $targetDirectory
            settingsPath = Get-RelativeDisplayPath $root (Join-Path $targetDirectory 'settings.json')
            sourcePath = Get-RelativeDisplayPath $root $sourcePath
            settingCount = $settings.Count - 1
            machineId = $machineId
            machineSettingCount = $machineSettingIds.Count
            overrideCount = $overrides.Count
            dryRun = $true
        }
    }

    $buildRoot = Join-Path $root 'build'
    [System.IO.Directory]::CreateDirectory($buildRoot) | Out-Null
    $temporaryDirectory = Join-Path $buildRoot ".global.$([guid]::NewGuid().ToString('N')).tmp"
    [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
    try {
        $settingsPath = Join-Path $temporaryDirectory 'settings.json'
        Write-Utf8File $settingsPath (ConvertTo-PrettyJson -Value $settings)
        $generated = Read-JsonCFile $settingsPath
        if (-not (Test-IsDictionary $generated)) { throw 'Generated global settings did not validate as a JSON object.' }
        Invoke-SafeDirectoryReplace $temporaryDirectory $targetDirectory
    }
    catch {
        if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
        throw
    }

    return [pscustomobject][ordered]@{
        outputDirectory = Get-RelativeDisplayPath $root $targetDirectory
        settingsPath = Get-RelativeDisplayPath $root (Join-Path $targetDirectory 'settings.json')
        sourcePath = Get-RelativeDisplayPath $root $sourcePath
        settingCount = $settings.Count - 1
        machineId = $machineId
        machineSettingCount = $machineSettingIds.Count
        overrideCount = $overrides.Count
        dryRun = $false
    }
}

function Invoke-ProfileComposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Profile,
        [string]$Platform,
        [string]$Machine,
        [string]$MachineFile,
        [switch]$DryRun,
        [string]$UiStateFromProfile,
        [string]$UiStateProfile,
        [switch]$NoUiState,
        [switch]$Strict
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ($UiStateFromProfile -and $UiStateProfile) { throw '-UiStateFromProfile and -UiStateProfile cannot be used together.' }
    if ($NoUiState -and ($UiStateFromProfile -or $UiStateProfile)) { throw '-NoUiState cannot be combined with an explicit UI-state source.' }
    if ($Machine -and $MachineFile) { throw '-Machine and -MachineFile cannot be used together.' }
    $validation = Test-ComposerRepository -RepositoryRoot $root -Platform $Platform -Machine $Machine -MachineFile $MachineFile
    if ($validation.errors.Count -gt 0 -or ($Strict -and $validation.warnings.Count -gt 0)) {
        $reason = if ($validation.errors.Count -gt 0) { "$($validation.errors.Count) validation error(s)" } else { "$($validation.warnings.Count) warning(s) in strict mode" }
        throw "Composition stopped because repository validation found $reason."
    }

    $definition = @(Get-ProfileDefinitions $root | Where-Object { $_.Id -ieq $Profile })
    if ($definition.Count -eq 0) { throw "Unknown profile '$Profile'." }
    if ($definition.Count -gt 1) { throw "Profile ID '$Profile' is ambiguous." }
    $profileId = $definition[0].Id
    $configuration = Get-ComposerConfiguration -RepositoryRoot $root
    $configuredUiStateProfile = if ($configuration.Contains('defaultUiStateProfile')) {
        [string]$configuration['defaultUiStateProfile']
    }
    else { $null }
    $uiStateSource = 'none'
    $resolvedUiStateSeed = if ($NoUiState) {
        $uiStateSource = 'disabled'
        $null
    }
    elseif ($UiStateProfile) {
        $uiDefinition = @(Get-ProfileDefinitions $root | Where-Object { $_.Id -ieq $UiStateProfile })
        if ($uiDefinition.Count -eq 0) { throw "Unknown UI-state profile '$UiStateProfile'." }
        if ($uiDefinition.Count -gt 1) { throw "UI-state profile ID '$UiStateProfile' is ambiguous." }
        $uiStateSource = "explicit-profile:$($uiDefinition[0].Id)"
        Get-StoredUiStateSeedPath -RepositoryRoot $root -Profile $uiDefinition[0].Id
    }
    elseif ($UiStateFromProfile) {
        $uiStateSource = 'explicit-export'
        Resolve-UiStateSeedPath -RepositoryRoot $root -UiStateFromProfile $UiStateFromProfile
    }
    elseif ($configuredUiStateProfile) {
        $configuredSeedPath = Get-StoredUiStateSeedPath -RepositoryRoot $root -Profile $configuredUiStateProfile
        if (Test-Path -LiteralPath $configuredSeedPath -PathType Leaf) {
            $uiStateSource = "configured-default:$configuredUiStateProfile"
            $configuredSeedPath
        }
        else {
            $uiStateSource = "configured-default-missing:$configuredUiStateProfile"
            $null
        }
    }
    else { $null }
    $uiState = if ($resolvedUiStateSeed) { Read-CodeProfileGlobalState -Path $resolvedUiStateSeed } else { $null }
    $recipe = Read-ProfileRecipe $definition[0].Path
    $inputFiles = [System.Collections.Generic.List[object]]::new()
    $settingsLayers = [System.Collections.Generic.List[object]]::new()
    $extensionFiles = [System.Collections.Generic.List[object]]::new()
    $keybindingFiles = [System.Collections.Generic.List[object]]::new()

    $recipeSource = Get-RelativeDisplayPath $root $definition[0].Path
    $inputFiles.Add([pscustomobject]@{ type = 'recipe'; path = $recipeSource })
    foreach ($component in $recipe.Components) {
        $componentPath = Join-Path $root "components/$component"
        foreach ($spec in @(
            @{ Name = 'settings.jsonc'; Type = 'settings' },
            @{ Name = 'extensions.txt'; Type = 'extensions' },
            @{ Name = 'keybindings.jsonc'; Type = 'keybindings' }
        )) {
            $path = Join-Path $componentPath $spec.Name
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $source = Get-RelativeDisplayPath $root $path
            $record = [pscustomobject]@{ Path = $path; Source = $source }
            $inputFiles.Add([pscustomobject]@{ type = $spec.Type; path = $source })
            switch ($spec.Type) {
                settings { $settingsLayers.Add($record) }
                extensions { $extensionFiles.Add($record) }
                keybindings { $keybindingFiles.Add($record) }
            }
        }
    }

    $profileOverrideRecord = $null
    $profileOverridePath = Join-Path $root "profiles/$profileId.settings.jsonc"
    if (Test-Path -LiteralPath $profileOverridePath -PathType Leaf) {
        $source = Get-RelativeDisplayPath $root $profileOverridePath
        $profileOverrideRecord = [pscustomobject]@{ Path = $profileOverridePath; Source = $source }
        $inputFiles.Add([pscustomobject]@{ type = 'profile-settings'; path = $source })
    }
    $profileSettingsReplacementPath = Join-Path $root "profiles/$profileId.settings.replace.jsonc"
    if (Test-Path -LiteralPath $profileSettingsReplacementPath -PathType Leaf) {
        $inputFiles.Add([pscustomobject]@{ type = 'profile-settings-replacements'; path = (Get-RelativeDisplayPath $root $profileSettingsReplacementPath) })
    }
    $profileSettingsRemovalPath = Join-Path $root "profiles/$profileId.settings.remove.jsonc"
    if (Test-Path -LiteralPath $profileSettingsRemovalPath -PathType Leaf) {
        $inputFiles.Add([pscustomobject]@{ type = 'profile-settings-removals'; path = (Get-RelativeDisplayPath $root $profileSettingsRemovalPath) })
    }
    $profileExtensionOperationsPath = Join-Path $root "profiles/$profileId.extensions.jsonc"
    if (Test-Path -LiteralPath $profileExtensionOperationsPath -PathType Leaf) {
        $inputFiles.Add([pscustomobject]@{ type = 'profile-extension-operations'; path = (Get-RelativeDisplayPath $root $profileExtensionOperationsPath) })
    }
    $profileKeybindingOperationsPath = Join-Path $root "profiles/$profileId.keybindings.jsonc"
    if (Test-Path -LiteralPath $profileKeybindingOperationsPath -PathType Leaf) {
        $inputFiles.Add([pscustomobject]@{ type = 'profile-keybinding-operations'; path = (Get-RelativeDisplayPath $root $profileKeybindingOperationsPath) })
    }
    $platformRecord = $null
    $platformPath = $null
    if ($Platform) {
        $platformPath = Join-Path $root "platform/$Platform.jsonc"
        $source = Get-RelativeDisplayPath $root $platformPath
        $platformRecord = [pscustomobject]@{ Path = $platformPath; Source = $source }
        $inputFiles.Add([pscustomobject]@{ type = 'platform-settings'; path = $source })
        $platformExtensionsPath = Join-Path $root "platform/$Platform.extensions.txt"
        if (Test-Path -LiteralPath $platformExtensionsPath -PathType Leaf) {
            $extensionSource = Get-RelativeDisplayPath $root $platformExtensionsPath
            $extensionFiles.Add([pscustomobject]@{ Path = $platformExtensionsPath; Source = $extensionSource })
            $inputFiles.Add([pscustomobject]@{ type = 'platform-extensions'; path = $extensionSource })
        }
    }
    $resolvedMachine = Resolve-MachinePath -RepositoryRoot $root -Machine $Machine -MachineFile $MachineFile
    $machineId = if ($Machine) { $Machine } elseif ($resolvedMachine) { [System.IO.Path]::GetFileNameWithoutExtension($resolvedMachine) } else { $null }
    $machineSettingIds = @()
    if ($resolvedMachine) {
        $source = Get-RelativeDisplayPath $root $resolvedMachine
        $machineSettings = (Read-MachineConfiguration -Path $resolvedMachine -ExpectedId $Machine).Settings
        $machineSettingIds = @(Get-MachineSettingIds $machineSettings)
        $inputFiles.Add([pscustomobject]@{ type = 'machine-application-settings'; path = $source })
    }

    $settings = New-OrderedMap
    $sourceMap = [hashtable]::new([System.StringComparer]::Ordinal)
    $overrides = [System.Collections.Generic.List[object]]::new()
    foreach ($layer in $settingsLayers) {
        $incoming = Read-JsonCFile $layer.Path
        if (-not (Test-IsDictionary $incoming)) { throw "Settings root must be an object in '$($layer.Source)'." }
        Merge-Settings $settings $incoming $layer.Source $sourceMap $overrides | Out-Null
    }
    if (Test-Path -LiteralPath $profileSettingsRemovalPath -PathType Leaf) {
        foreach ($settingId in (Read-ProfileSettingsRemovals $profileSettingsRemovalPath)) {
            if ($settings.Contains($settingId)) {
                $settings.Remove($settingId)
                Remove-SourceDescendants $sourceMap "/$(ConvertTo-JsonPointerSegment $settingId)"
            }
        }
    }
    if ($null -ne $profileOverrideRecord) {
        $incoming = Read-JsonCFile $profileOverrideRecord.Path
        if (-not (Test-IsDictionary $incoming)) { throw "Settings root must be an object in '$($profileOverrideRecord.Source)'." }
        Merge-Settings $settings $incoming $profileOverrideRecord.Source $sourceMap $overrides | Out-Null
    }
    if (Test-Path -LiteralPath $profileSettingsReplacementPath -PathType Leaf) {
        $replacementSource = Get-RelativeDisplayPath $root $profileSettingsReplacementPath
        $replacement = Read-JsonCFile $profileSettingsReplacementPath
        if (-not (Test-IsDictionary $replacement)) { throw "Settings replacement root must be an object in '$replacementSource'." }
        foreach ($key in $replacement.Keys) {
            $path = "/$(ConvertTo-JsonPointerSegment ([string]$key))"
            if ($settings.Contains($key) -and -not (Test-ValuesEqual $settings[$key] $replacement[$key])) {
                $overrides.Add([pscustomobject][ordered]@{
                    path = $path
                    previousSource = if ($sourceMap.ContainsKey($path)) { $sourceMap[$path] } else { 'component-settings' }
                    source = $replacementSource
                    previousValue = Get-RedactedValue $path $settings[$key]
                    value = Get-RedactedValue $path $replacement[$key]
                })
            }
            $settings[$key] = Copy-ComposerValue $replacement[$key]
            Remove-SourceDescendants $sourceMap $path
            Set-SourceTree $settings[$key] $path $replacementSource $sourceMap
        }
    }
    if ($null -ne $platformRecord) {
        $incoming = Read-JsonCFile $platformRecord.Path
        if (-not (Test-IsDictionary $incoming)) { throw "Settings root must be an object in '$($platformRecord.Source)'." }
        Merge-Settings $settings $incoming $platformRecord.Source $sourceMap $overrides | Out-Null
    }
    foreach ($settingId in $machineSettingIds) {
        $machinePath = "/$(ConvertTo-JsonPointerSegment $settingId)"
        if ($settings.Contains($settingId)) {
            $settings.Remove($settingId)
            Remove-SourceDescendants $sourceMap $machinePath
        }
        for ($index = $overrides.Count - 1; $index -ge 0; $index--) {
            if ($overrides[$index].path -eq $machinePath -or $overrides[$index].path.StartsWith("$machinePath/", [System.StringComparison]::Ordinal)) {
                $overrides.RemoveAt($index)
            }
        }
    }
    $extensions = @(Merge-Extensions -Files $extensionFiles.ToArray())
    if (Test-Path -LiteralPath $profileExtensionOperationsPath -PathType Leaf) {
        $operations = Read-ProfileExtensionOperations $profileExtensionOperationsPath
        $removedExtensions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($id in $operations.Remove) { $removedExtensions.Add($id) | Out-Null }
        $extensionResult = [System.Collections.Generic.List[string]]::new()
        $extensionSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($id in $extensions) {
            if (-not $removedExtensions.Contains($id) -and $extensionSet.Add($id)) { $extensionResult.Add($id) }
        }
        foreach ($id in $operations.Add) {
            if ($extensionSet.Add($id)) { $extensionResult.Add($id) }
        }
        $extensions = [string[]]$extensionResult.ToArray()
    }
    $keybindingsResult = Merge-Keybindings -Files $keybindingFiles.ToArray()
    $keybindings = @($keybindingsResult.Items)
    $mergeWarnings = @($keybindingsResult.Warnings)
    if (Test-Path -LiteralPath $profileKeybindingOperationsPath -PathType Leaf) {
        $operations = Read-ProfileKeybindingOperations $profileKeybindingOperationsPath
        if ($null -ne $operations.Replace) {
            $keybindings = [object[]]@($operations.Replace | ForEach-Object { Copy-ComposerValue $_ })
        }
        else {
            $removedKeybindings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($item in $operations.Remove) { $removedKeybindings.Add((Get-CanonicalComposerValue $item)) | Out-Null }
            $keybindingResult = [System.Collections.Generic.List[object]]::new()
            $keybindingSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($item in $keybindings) {
                $canonical = Get-CanonicalComposerValue $item
                if (-not $removedKeybindings.Contains($canonical) -and $keybindingSet.Add($canonical)) {
                    $keybindingResult.Add((Copy-ComposerValue $item))
                }
            }
            foreach ($item in $operations.Add) {
                $canonical = Get-CanonicalComposerValue $item
                if ($keybindingSet.Add($canonical)) { $keybindingResult.Add((Copy-ComposerValue $item)) }
            }
            $keybindings = [object[]]$keybindingResult.ToArray()
        }
    }
    $targetDirectory = [System.IO.Path]::GetFullPath((Join-Path $root "build/profiles/$profileId"))
    $codeProfileFileName = Get-CodeProfileFileName -DisplayName $recipe.Name
    $codeProfileTargetPath = [System.IO.Path]::GetFullPath((Join-Path $targetDirectory $codeProfileFileName))
    if (-not (Test-PathWithinDirectory $codeProfileTargetPath $targetDirectory)) {
        throw "VS Code profile export path '$codeProfileTargetPath' escapes its generated profile directory."
    }

    if ($DryRun) {
        return [pscustomobject][ordered]@{
            profileId = $profileId
            displayName = $recipe.Name
            outputDirectory = Get-RelativeDisplayPath $root $targetDirectory
            codeProfileExportPath = Get-RelativeDisplayPath $root $codeProfileTargetPath
            uiStateSeeded = ($null -ne $uiState)
            uiStateSource = $uiStateSource
            machineId = $machineId
            inputFiles = [object[]]$inputFiles.ToArray()
            counts = [pscustomobject][ordered]@{
                settings = $settings.Count
                extensions = $extensions.Count
                keybindings = $keybindings.Count
                overrides = $overrides.Count
                warnings = $validation.warnings.Count + $mergeWarnings.Count
            }
            dryRun = $true
        }
    }

    $buildRoot = Join-Path $root 'build/profiles'
    [System.IO.Directory]::CreateDirectory($buildRoot) | Out-Null
    $temporaryDirectory = Join-Path $buildRoot ".$profileId.$([guid]::NewGuid().ToString('N')).tmp"
    [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
    try {
        $settingsJson = ConvertTo-PrettyJson -Value $settings
        $keybindingsJson = ConvertTo-PrettyJson -Value ([object[]]$keybindings)
        $generatedSettings = ConvertFrom-JsonC -Content $settingsJson -Source '<composed settings>'
        if (-not (Test-IsDictionary $generatedSettings)) { throw 'Generated settings did not validate as a JSON object.' }
        $generatedKeybindings = ConvertFrom-JsonC -Content $keybindingsJson -Source '<composed keybindings>'
        if ($generatedKeybindings -isnot [System.Array]) { throw 'Generated keybindings did not validate as a JSON array.' }

        $codeProfileTemporaryPath = Join-Path $temporaryDirectory $codeProfileFileName
        if (-not (Test-PathWithinDirectory $codeProfileTemporaryPath $temporaryDirectory)) {
            throw "VS Code profile export path '$codeProfileTemporaryPath' escapes the temporary profile directory."
        }
        $templateParameters = @{
            DisplayName = $recipe.Name
            SettingsJson = $settingsJson
            Extensions = [string[]]$extensions
            KeybindingsJson = $keybindingsJson
            Platform = $Platform
        }
        if ($null -ne $uiState) { $templateParameters.GlobalState = $uiState }
        $template = New-CodeProfileTemplate @templateParameters
        Write-Utf8File $codeProfileTemporaryPath (ConvertTo-PrettyJson -Value $template)
        Test-CodeProfileTemplate $codeProfileTemporaryPath | Out-Null
        Invoke-SafeDirectoryReplace $temporaryDirectory $targetDirectory
    }
    catch {
        if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
        throw
    }

    return [pscustomobject][ordered]@{
        profileId = $profileId
        displayName = $recipe.Name
        outputDirectory = Get-RelativeDisplayPath $root $targetDirectory
        codeProfileExportPath = Get-RelativeDisplayPath $root $codeProfileTargetPath
        uiStateSeeded = ($null -ne $uiState)
        uiStateSource = $uiStateSource
        machineId = $machineId
        counts = [pscustomobject][ordered]@{
            settings = $settings.Count
            extensions = $extensions.Count
            keybindings = $keybindings.Count
            overrides = $overrides.Count
            warnings = $validation.warnings.Count + $mergeWarnings.Count
        }
        dryRun = $false
    }
}

Export-ModuleMember -Function ConvertFrom-JsonC, Read-ProfileRecipe, Get-ProfileDefinitions, Get-MachineDefinitions, Read-MachineConfiguration, Get-LocalDefaultMachine, Get-SettingValueClassification, Get-DefaultVSCodeUserDataPath, Get-LiveVSCodeProfileDefinitions, Get-VSCodeStatusText, Resolve-ComposerProfileFromVSCodeStatus, Get-SharedDefaultComponent, Test-ComposerRepository, Merge-Settings, Merge-Extensions, Merge-Keybindings, Get-CodeProfileFileName, New-CodeProfileTemplate, Read-CodeProfileResources, Read-CodeProfileGlobalState, Get-StoredUiStateSeedPath, Save-ProfileUiStateSeed, Test-CodeProfileTemplate, Invoke-SafeDirectoryReplace, Rename-ComposerProfile, Rename-ComposerComponent, Set-SharedDefaultComponent, Repair-ComposerGlobalOwnership, Sync-ComposerProfileFromExport, New-OwnershipDestination, New-OwnershipRoute, Get-OwnershipDestinationLabel, Get-ManagedOwnershipRouter, Add-ManagedOwnershipRoute, Set-ManagedOwnershipRouteStatus, Remove-ManagedOwnershipRoute, Import-ManagedOwnershipRoutes, Invoke-OwnershipRouterAudit, Explain-OwnershipRoute, Archive-LegacySyncSidecars, Invoke-GlobalSettingsComposition, Invoke-ProfileComposition
