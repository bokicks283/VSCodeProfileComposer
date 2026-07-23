Set-StrictMode -Version Latest

$script:ComposerVersion = '0.9.0'
$script:ManifestVersion = 1
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:SensitivePattern = '(?i)(password|(?<!semantic)token|secret|credential|connectionstring|api[_-]?key|private[_-]?key)'
$script:CodeProfileSchema = 'vscode-user-data-profile-template'
$script:CodeProfileSchemaVersion = 'unversioned'
$script:CodeProfileVerifiedVersion = '1.129.1'
$script:CodeProfileVerifiedCommit = '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8'

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

function Test-PortableSettings {
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Source
    )
    foreach ($leaf in (Get-ValueLeaves -Value $Settings)) {
        $stringValue = if ($null -eq $leaf.Value) { '' } else { [string]$leaf.Value }
        if ($stringValue -match '(?i)([A-Z]:[\\/]+Users[\\/]+|/home/|/Users/)') {
            Add-ValidationItem -Result $Result -Level errors -Code 'portable-absolute-path' -Message 'Portable component contains an absolute personal path.' -Source $Source -Path $leaf.Path
        }
        $placeholder = $stringValue -match '(?i)(<[^>]+>|example|placeholder|replace[- ]?me)'
        if (($leaf.Path -match $script:SensitivePattern -and $stringValue -and -not $placeholder) -or
            ($stringValue -match '(?i)(ghp_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{12,}|(?:password|token|secret|api[_-]?key)\s*[:=]\s*\S+)')) {
            Add-ValidationItem -Result $Result -Level errors -Code 'portable-likely-secret' -Message 'Portable component contains a likely secret or credential value.' -Source $Source -Path $leaf.Path
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
        [pscustomobject]@{ Id = $_.BaseName; Path = $_.FullName }
    })
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

    try { $sharedDefaultComponent = Get-SharedDefaultComponent -RepositoryRoot $root }
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

    $jsoncCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($directoryName in @('platform', 'machine/local')) {
        $directoryPath = Join-Path $root $directoryName
        if (Test-Path -LiteralPath $directoryPath -PathType Container) {
            foreach ($file in (Get-ChildItem -LiteralPath $directoryPath -Filter '*.jsonc' -File)) { $jsoncCandidates.Add($file.FullName) }
        }
    }
    $machineRoot = Join-Path $root 'machine'
    if (Test-Path -LiteralPath $machineRoot -PathType Container) {
        foreach ($file in (Get-ChildItem -LiteralPath $machineRoot -Filter '*.example.jsonc' -File)) { $jsoncCandidates.Add($file.FullName) }
    }
    foreach ($path in $jsoncCandidates) {
        $source = Get-RelativeDisplayPath $root $path
        try {
            $value = Read-JsonCFile $path
            if (-not (Test-IsDictionary $value)) { Add-ValidationItem $result errors 'overlay-root' 'Platform and machine settings roots must be objects.' $source }
            elseif ($source.StartsWith('platform/', [System.StringComparison]::OrdinalIgnoreCase)) {
                foreach ($key in $value.Keys) {
                    if ($globalSettingIds.Contains([string]$key)) {
                        Add-ValidationItem $result errors 'global-setting-in-profile-source' "Setting '$key' is globally owned and must not be declared in a platform overlay." $source "/$key"
                    }
                }
            }
            elseif ($source.StartsWith('machine/', [System.StringComparison]::OrdinalIgnoreCase)) {
                Add-MachineOwnershipValidation -Settings $value -Result $result -Source $source
            }
        }
        catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message $source }
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
        elseif ($jsoncCandidates -notcontains $resolvedMachine) {
            $source = Get-RelativeDisplayPath $root $resolvedMachine
            try {
                $machineSettings = Read-JsonCFile $resolvedMachine
                if (-not (Test-IsDictionary $machineSettings)) {
                    Add-ValidationItem $result errors 'overlay-root' 'Platform and machine settings roots must be objects.' $source
                }
                else { Add-MachineOwnershipValidation -Settings $machineSettings -Result $result -Source $source }
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

function Get-FileHashValue {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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

function Get-GitCommit {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot '.git'))) { return $null }
    try {
        $sha = (& git -C $RepositoryRoot rev-parse HEAD 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0) { return [string]$sha }
    }
    catch { }
    return $null
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
        foreach ($directory in @('components', 'profiles', 'global', 'platform', 'machine')) {
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
        Assert-StagedRepositoryValid $stagingRoot
        if (-not $DryRun) {
            $commitPaths = [System.Collections.Generic.List[string]]::new()
            $commitPaths.Add('profiles')
            if ($hasUiState) { $commitPaths.Add('machine/local/ui-state') }
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

function Sync-ComposerProfileFromExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Profile,
        [Parameter(Mandatory)][string]$SourceProfileExport,
        [string]$Platform,
        [string]$VSCodeUserDataPath,
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
    $componentSettings = New-OrderedMap
    $componentSettingSources = [hashtable]::new([System.StringComparer]::Ordinal)
    $componentOverrides = [System.Collections.Generic.List[object]]::new()
    $extensionFiles = [System.Collections.Generic.List[object]]::new()
    $keybindingFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($component in $recipe.Components) {
        $componentPath = Join-Path $root "components/$component"
        $settingsPath = Join-Path $componentPath 'settings.jsonc'
        if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
            $incoming = Read-JsonCFile $settingsPath
            Merge-Settings $componentSettings $incoming (Get-RelativeDisplayPath $root $settingsPath) $componentSettingSources $componentOverrides | Out-Null
        }
        foreach ($spec in @(
            @{ Name = 'extensions.txt'; Target = $extensionFiles },
            @{ Name = 'keybindings.jsonc'; Target = $keybindingFiles }
        )) {
            $path = Join-Path $componentPath $spec.Name
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $spec.Target.Add([pscustomobject]@{ Path = $path; Source = (Get-RelativeDisplayPath $root $path) })
            }
        }
    }
    $componentExtensions = @(Merge-Extensions $extensionFiles.ToArray())
    $componentKeybindings = @((Merge-Keybindings $keybindingFiles.ToArray()).Items)

    $platformSettingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ($Platform) {
        $platformSettings = Read-JsonCFile (Join-Path $root "platform/$Platform.jsonc")
        foreach ($key in $platformSettings.Keys) { $platformSettingIds.Add([string]$key) | Out-Null }
    }

    $trackedGlobal = Read-JsonCFile (Join-Path $root 'global/settings.jsonc')
    $globalSettingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($id in @($trackedGlobal['workbench.settings.applyToAllProfiles'])) { $globalSettingIds.Add([string]$id) | Out-Null }
    $newGlobal = $null
    $machineOwnedGlobalCount = 0
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
        if (-not (Test-IsDictionary $applicationSettings)) { throw "VS Code application settings '$applicationSettingsPath' must have an object root." }
        if (-not $applicationSettings.Contains('workbench.settings.applyToAllProfiles') -or
            $applicationSettings['workbench.settings.applyToAllProfiles'] -isnot [System.Array]) {
            throw "VS Code application settings must contain the authoritative 'workbench.settings.applyToAllProfiles' array."
        }
        if (-not $applicationSettings.Contains('settingsSync.ignoredSettings') -or
            $applicationSettings['settingsSync.ignoredSettings'] -isnot [System.Array]) {
            throw "VS Code application settings must contain the 'settingsSync.ignoredSettings' array."
        }

        $syncIgnored = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($id in @($applicationSettings['settingsSync.ignoredSettings'])) {
            if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id)) {
                throw "VS Code application settings contain an invalid 'settingsSync.ignoredSettings' entry."
            }
            if (-not $id.StartsWith('-')) { $syncIgnored.Add([string]$id) | Out-Null }
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
            if ($id -ne 'settingsSync.ignoredSettings' -and $syncIgnored.Contains($id)) {
                $machineOwnedGlobalCount++
                $machineOwnedSettingIds.Add($id) | Out-Null
                continue
            }
            $filteredGlobalIds.Add($id)
            $globalSettingIds.Add($id) | Out-Null
        }
        if (-not $seenGlobal.Contains('settingsSync.ignoredSettings')) {
            throw "VS Code application settings must apply 'settingsSync.ignoredSettings' to all profiles."
        }
        $newGlobal['workbench.settings.applyToAllProfiles'] = [string[]]$filteredGlobalIds.ToArray()
        foreach ($id in $filteredGlobalIds) { $newGlobal[$id] = Copy-ComposerValue $applicationSettings[$id] }
    }

    $settingsReplacements = New-OrderedMap
    $settingsRemovals = [System.Collections.Generic.List[string]]::new()
    $globalSettingsIgnored = 0
    $platformSettingsIgnored = 0
    foreach ($key in $componentSettings.Keys) {
        if ($globalSettingIds.Contains([string]$key) -or
            $machineOwnedSettingIds.Contains([string]$key) -or
            $platformSettingIds.Contains([string]$key)) { continue }
        if (-not $resources.Settings.Contains($key)) { $settingsRemovals.Add([string]$key) }
    }
    foreach ($key in $resources.Settings.Keys) {
        if ($machineOwnedSettingIds.Contains([string]$key)) {
            $globalSettingsIgnored++
            continue
        }
        if ($globalSettingIds.Contains([string]$key)) {
            $globalSettingsIgnored++
            continue
        }
        if ($platformSettingIds.Contains([string]$key)) {
            $platformSettingsIgnored++
            continue
        }
        if (-not $componentSettings.Contains($key) -or -not (Test-ValuesEqual $componentSettings[$key] $resources.Settings[$key])) {
            $settingsReplacements[[string]$key] = Copy-ComposerValue $resources.Settings[$key]
        }
    }

    $componentExtensionSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $componentExtensions) { $componentExtensionSet.Add($id) | Out-Null }
    $liveExtensionSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $resources.Extensions) { $liveExtensionSet.Add($id) | Out-Null }
    $extensionAdditions = @($resources.Extensions | Where-Object { -not $componentExtensionSet.Contains($_) })
    $extensionRemovals = @($componentExtensions | Where-Object { -not $liveExtensionSet.Contains($_) })

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
    $stagingRoot = New-ComposerStagingRepository $root
    try {
        $stagedProfiles = Join-Path $stagingRoot 'profiles'
        $legacyOverridePath = Join-Path $stagedProfiles "$profileId.settings.jsonc"
        if (Test-Path -LiteralPath $legacyOverridePath -PathType Leaf) {
            Remove-Item -LiteralPath $legacyOverridePath -Force
            $changes.Add([pscustomobject]@{ action = 'remove'; path = "profiles/$profileId.settings.jsonc" })
        }

        $resourcePlans = @(
            @{
                Path = Join-Path $stagedProfiles "$profileId.settings.replace.jsonc"
                Relative = "profiles/$profileId.settings.replace.jsonc"
                Present = $settingsReplacements.Count -gt 0
                Value = $settingsReplacements
            },
            @{
                Path = Join-Path $stagedProfiles "$profileId.settings.remove.jsonc"
                Relative = "profiles/$profileId.settings.remove.jsonc"
                Present = $settingsRemovals.Count -gt 0
                Value = [string[]]$settingsRemovals.ToArray()
            },
            @{
                Path = Join-Path $stagedProfiles "$profileId.extensions.jsonc"
                Relative = "profiles/$profileId.extensions.jsonc"
                Present = ($extensionAdditions.Count + $extensionRemovals.Count) -gt 0
                Value = [ordered]@{ add = [string[]]$extensionAdditions; remove = [string[]]$extensionRemovals }
            },
            @{
                Path = Join-Path $stagedProfiles "$profileId.keybindings.jsonc"
                Relative = "profiles/$profileId.keybindings.jsonc"
                Present = ($resources.Keybindings.Count -gt 0 -or $componentKeybindings.Count -gt 0) -and
                    ($replaceKeybindings -or ($keybindingAdditions.Count + $keybindingRemovals.Count) -gt 0)
                Value = if ($replaceKeybindings) {
                    [ordered]@{ replace = [object[]]$resources.Keybindings }
                }
                else {
                    [ordered]@{ add = [object[]]$keybindingAdditions; remove = [object[]]$keybindingRemovals }
                }
            }
        )
        foreach ($plan in $resourcePlans) {
            $existed = Test-Path -LiteralPath $plan.Path -PathType Leaf
            if ($plan.Present) {
                Write-Utf8File $plan.Path (ConvertTo-PrettyJson $plan.Value)
                $changes.Add([pscustomobject]@{ action = if ($existed) { 'update' } else { 'create' }; path = $plan.Relative })
            }
            elseif ($existed) {
                Remove-Item -LiteralPath $plan.Path -Force
                $changes.Add([pscustomobject]@{ action = 'remove'; path = $plan.Relative })
            }
        }

        if (-not $SkipGlobal) {
            Write-Utf8File (Join-Path $stagingRoot 'global/settings.jsonc') (ConvertTo-PrettyJson $newGlobal)
            $changes.Add([pscustomobject]@{ action = 'update'; path = 'global/settings.jsonc' })
        }
        if (-not $SkipUiState) {
            $uiDirectory = Join-Path $stagingRoot "machine/local/ui-state/$profileId"
            [System.IO.Directory]::CreateDirectory($uiDirectory) | Out-Null
            $seed = [ordered]@{
                name = "Stored UI state seed for $profileId"
                globalState = [string]$resources.GlobalState
            }
            $uiPath = Join-Path $uiDirectory 'seed.code-profile'
            Write-Utf8File $uiPath (ConvertTo-PrettyJson $seed)
            Read-CodeProfileGlobalState $uiPath | Out-Null
            $changes.Add([pscustomobject]@{ action = 'update'; path = "machine/local/ui-state/$profileId/seed.code-profile" })
        }

        Assert-StagedRepositoryValid $stagingRoot
        if (-not $DryRun) {
            $commitPaths = [System.Collections.Generic.List[string]]::new()
            $commitPaths.Add('profiles')
            if (-not $SkipGlobal) { $commitPaths.Add('global') }
            if (-not $SkipUiState) { $commitPaths.Add('machine/local/ui-state') }
            Invoke-StagedRepositoryCommit $root $stagingRoot $commitPaths.ToArray()
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
        counts = [pscustomobject][ordered]@{
            settingReplacements = $settingsReplacements.Count
            settingRemovals = $settingsRemovals.Count
            extensionAdditions = $extensionAdditions.Count
            extensionRemovals = $extensionRemovals.Count
            keybindingAdditions = $keybindingAdditions.Count
            keybindingRemovals = $keybindingRemovals.Count
            keybindingsReplacedForOrder = [bool]$replaceKeybindings
            globalSettings = if ($SkipGlobal) { 0 } else { $newGlobal.Count - 1 }
            machineOwnedGlobalSettingsSkipped = $machineOwnedGlobalCount
            exportGlobalSettingsIgnored = $globalSettingsIgnored
            platformSettingsIgnored = $platformSettingsIgnored
        }
        uiStateUpdated = -not [bool]$SkipUiState
        dryRun = [bool]$DryRun
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
    $machineSettings = if ($resolvedMachine) { Read-JsonCFile $resolvedMachine } else { $null }
    $machineSettingIds = @()
    if ($resolvedMachine) { $machineSettingIds = @(Get-MachineSettingIds $machineSettings) }
    $machineId = if ($Machine) { $Machine } elseif ($resolvedMachine) { [System.IO.Path]::GetFileNameWithoutExtension($resolvedMachine) } else { $null }
    $overrides = [System.Collections.Generic.List[object]]::new()

    if ($resolvedMachine) {
        $sourceMap = [hashtable]::new([System.StringComparer]::Ordinal)
        foreach ($key in $settings.Keys) { Set-SourceTree $settings[$key] "/$(ConvertTo-JsonPointerSegment ([string]$key))" 'global/settings.jsonc' $sourceMap }
        Merge-Settings $settings $machineSettings (Get-RelativeDisplayPath $root $resolvedMachine) $sourceMap $overrides | Out-Null

        $applyToAll = [System.Collections.Generic.List[string]]::new()
        $applySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($id in @($settings['workbench.settings.applyToAllProfiles'])) {
            if ($applySet.Add([string]$id)) { $applyToAll.Add([string]$id) }
        }
        foreach ($id in $machineSettingIds) {
            if ($applySet.Add($id)) { $applyToAll.Add($id) }
        }
        $settings['workbench.settings.applyToAllProfiles'] = [string[]]$applyToAll.ToArray()

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

    $targetDirectory = [System.IO.Path]::GetFullPath((Join-Path $root 'build/global'))
    if ($DryRun) {
        return [pscustomobject][ordered]@{
            outputDirectory = Get-RelativeDisplayPath $root $targetDirectory
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
        $overridesPath = Join-Path $temporaryDirectory 'overrides.json'
        Write-Utf8File $overridesPath (ConvertTo-PrettyJson -Value ([ordered]@{
            artifact = 'vscode-built-in-default-settings'
            overrides = [object[]]$overrides.ToArray()
            warnings = @()
        }))
        $generated = Read-JsonCFile $settingsPath
        if (-not (Test-IsDictionary $generated)) { throw 'Generated global settings did not validate as a JSON object.' }
        Read-JsonCFile $overridesPath | Out-Null
        $manifest = [ordered]@{
            manifestVersion = $script:ManifestVersion
            artifact = 'vscode-built-in-default-settings'
            generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            composerVersion = $script:ComposerVersion
            gitCommit = Get-GitCommit $root
            source = 'global/settings.jsonc'
            machineOverlay = if ($resolvedMachine) {
                [ordered]@{
                    id = $machineId
                    path = Get-RelativeDisplayPath $root $resolvedMachine
                    selection = if ($Machine) { 'named-machine' } else { 'explicit-file' }
                    settingCount = $machineSettingIds.Count
                    valuesRecorded = $false
                }
            }
            else { $null }
            applicationTarget = 'vscode-built-in-default-profile'
            applicationMethod = 'manual-application-settings-json-merge'
            settingsSyncPolicy = 'machine-settings-ignored-and-applied-to-all-profiles'
            settingCount = $settings.Count - 1
            overrideCount = $overrides.Count
            outputHashes = [ordered]@{
                'settings.json' = Get-FileHashValue $settingsPath
                'overrides.json' = Get-FileHashValue $overridesPath
            }
            validation = [ordered]@{
                result = 'passed'
                errors = $validation.errors.Count
                warnings = $validation.warnings.Count
                information = $validation.information.Count
            }
        }
        Write-Utf8File (Join-Path $temporaryDirectory 'manifest.json') (ConvertTo-PrettyJson -Value $manifest)
        Read-JsonCFile (Join-Path $temporaryDirectory 'manifest.json') | Out-Null
        Invoke-SafeDirectoryReplace $temporaryDirectory $targetDirectory
    }
    catch {
        if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
        throw
    }

    return [pscustomobject][ordered]@{
        outputDirectory = Get-RelativeDisplayPath $root $targetDirectory
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
        [switch]$ExportCodeProfile,
        [string]$UiStateFromProfile,
        [string]$UiStateProfile,
        [switch]$Strict
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (($UiStateFromProfile -or $UiStateProfile) -and -not $ExportCodeProfile) { throw 'UI-state seeding requires -ExportCodeProfile.' }
    if ($UiStateFromProfile -and $UiStateProfile) { throw '-UiStateFromProfile and -UiStateProfile cannot be used together.' }
    if ($Machine -and $MachineFile) { throw '-Machine and -MachineFile cannot be used together.' }
    $validation = Test-ComposerRepository -RepositoryRoot $root -Platform $Platform -Machine $Machine -MachineFile $MachineFile
    if ($validation.errors.Count -gt 0 -or ($Strict -and $validation.warnings.Count -gt 0)) {
        $reason = if ($validation.errors.Count -gt 0) { "$($validation.errors.Count) validation error(s)" } else { "$($validation.warnings.Count) warning(s) in strict mode" }
        throw "Composition stopped because repository validation found $reason."
    }

    $definition = @(Get-ProfileDefinitions $root | Where-Object { $_.Id -ieq $Profile })
    if ($definition.Count -eq 0) { throw "Unknown profile '$Profile'." }
    if ($definition.Count -gt 1) { throw "Profile ID '$Profile' is ambiguous." }
    $resolvedUiStateSeed = if ($UiStateProfile) {
        $uiDefinition = @(Get-ProfileDefinitions $root | Where-Object { $_.Id -ieq $UiStateProfile })
        if ($uiDefinition.Count -eq 0) { throw "Unknown UI-state profile '$UiStateProfile'." }
        if ($uiDefinition.Count -gt 1) { throw "UI-state profile ID '$UiStateProfile' is ambiguous." }
        Get-StoredUiStateSeedPath -RepositoryRoot $root -Profile $uiDefinition[0].Id
    }
    else { Resolve-UiStateSeedPath -RepositoryRoot $root -UiStateFromProfile $UiStateFromProfile }
    $uiState = if ($resolvedUiStateSeed) { Read-CodeProfileGlobalState -Path $resolvedUiStateSeed } else { $null }
    $uiStateHash = if ($null -ne $uiState) { Get-StringHashValue $uiState } else { $null }
    $profileId = $definition[0].Id
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
    }
    $resolvedMachine = Resolve-MachinePath -RepositoryRoot $root -Machine $Machine -MachineFile $MachineFile
    $machineId = if ($Machine) { $Machine } elseif ($resolvedMachine) { [System.IO.Path]::GetFileNameWithoutExtension($resolvedMachine) } else { $null }
    $machineSettingIds = @()
    if ($resolvedMachine) {
        $source = Get-RelativeDisplayPath $root $resolvedMachine
        $machineSettings = Read-JsonCFile $resolvedMachine
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
    $codeProfileFileName = if ($ExportCodeProfile) { Get-CodeProfileFileName -DisplayName $recipe.Name } else { $null }
    $codeProfileTargetPath = if ($codeProfileFileName) { [System.IO.Path]::GetFullPath((Join-Path $targetDirectory $codeProfileFileName)) } else { $null }
    if ($codeProfileTargetPath -and -not (Test-PathWithinDirectory $codeProfileTargetPath $targetDirectory)) {
        throw "VS Code profile export path '$codeProfileTargetPath' escapes its generated profile directory."
    }

    if ($DryRun) {
        return [pscustomobject][ordered]@{
            profileId = $profileId
            displayName = $recipe.Name
            outputDirectory = Get-RelativeDisplayPath $root $targetDirectory
            codeProfileExportPath = if ($codeProfileTargetPath) { Get-RelativeDisplayPath $root $codeProfileTargetPath } else { $null }
            uiStateSeeded = ($null -ne $uiState)
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
        Write-Utf8File (Join-Path $temporaryDirectory 'settings.json') (ConvertTo-PrettyJson -Value $settings)
        $extensionText = if ($extensions.Count -gt 0) { ($extensions -join "`n") + "`n" } else { '' }
        Write-Utf8File (Join-Path $temporaryDirectory 'extensions.txt') $extensionText
        Write-Utf8File (Join-Path $temporaryDirectory 'keybindings.json') (ConvertTo-PrettyJson -Value ([object[]]$keybindings))
        $overrideReport = [ordered]@{
            profileId = $profileId
            overrides = [object[]]$overrides.ToArray()
            warnings = [object[]]$mergeWarnings
        }
        Write-Utf8File (Join-Path $temporaryDirectory 'overrides.json') (ConvertTo-PrettyJson -Value $overrideReport)
        Write-Utf8File (Join-Path $temporaryDirectory 'validation.json') (ConvertTo-PrettyJson -Value $validation)

        $generatedSettings = Read-JsonCFile (Join-Path $temporaryDirectory 'settings.json')
        if (-not (Test-IsDictionary $generatedSettings)) { throw 'Generated settings did not validate as a JSON object.' }
        $generatedKeybindings = Read-JsonCFile (Join-Path $temporaryDirectory 'keybindings.json')
        if ($generatedKeybindings -isnot [System.Array]) { throw 'Generated keybindings did not validate as a JSON array.' }

        $codeProfileTemporaryPath = $null
        $codeProfileHash = $null
        if ($ExportCodeProfile) {
            $codeProfileTemporaryPath = Join-Path $temporaryDirectory $codeProfileFileName
            if (-not (Test-PathWithinDirectory $codeProfileTemporaryPath $temporaryDirectory)) {
                throw "VS Code profile export path '$codeProfileTemporaryPath' escapes the temporary profile directory."
            }
            $templateParameters = @{
                DisplayName = $recipe.Name
                SettingsJson = [System.IO.File]::ReadAllText((Join-Path $temporaryDirectory 'settings.json'))
                Extensions = [string[]]$extensions
                KeybindingsJson = [System.IO.File]::ReadAllText((Join-Path $temporaryDirectory 'keybindings.json'))
                Platform = $Platform
            }
            if ($null -ne $uiState) { $templateParameters.GlobalState = $uiState }
            $template = New-CodeProfileTemplate @templateParameters
            Write-Utf8File $codeProfileTemporaryPath (ConvertTo-PrettyJson -Value $template)
            Test-CodeProfileTemplate $codeProfileTemporaryPath | Out-Null
            $codeProfileHash = Get-FileHashValue $codeProfileTemporaryPath
        }

        $hashes = New-OrderedMap
        foreach ($name in @('settings.json', 'extensions.txt', 'keybindings.json', 'overrides.json', 'validation.json')) {
            $hashes[$name] = Get-FileHashValue (Join-Path $temporaryDirectory $name)
        }
        if ($ExportCodeProfile) { $hashes[$codeProfileFileName] = $codeProfileHash }
        $machineDisplay = if ($resolvedMachine) { Get-RelativeDisplayPath $root $resolvedMachine } else { $null }
        $manifest = [ordered]@{
            manifestVersion = $script:ManifestVersion
            profileId = $profileId
            displayName = $recipe.Name
            generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            composerVersion = $script:ComposerVersion
            gitCommit = Get-GitCommit $root
            declaredComponents = [string[]]$recipe.Components
            inputFiles = [object[]]$inputFiles.ToArray()
            platformOverlay = if ($Platform) { [ordered]@{ id = $Platform; path = Get-RelativeDisplayPath $root $platformPath } } else { $null }
            machineOverlayPath = $machineDisplay
            machineOverlay = if ($resolvedMachine) {
                [ordered]@{
                    id = $machineId
                    path = $machineDisplay
                    selection = if ($Machine) { 'named-machine' } else { 'explicit-file' }
                    settingCount = $machineSettingIds.Count
                    appliedTo = 'build/global/settings.json'
                    includedInProfileSettings = $false
                    includedInCodeProfile = $false
                }
            }
            else { $null }
            codeProfileExportRequested = [bool]$ExportCodeProfile
            codeProfileExport = if ($ExportCodeProfile) {
                [ordered]@{
                    fileName = $codeProfileFileName
                    sha256 = $codeProfileHash
                    schema = $script:CodeProfileSchema
                    schemaVersion = $script:CodeProfileSchemaVersion
                    verifiedAgainst = [ordered]@{
                        version = $script:CodeProfileVerifiedVersion
                        commit = $script:CodeProfileVerifiedCommit
                    }
                    machineOverlayIncluded = $false
                    machineSettingsDelivery = if ($resolvedMachine) { 'built-in-default-application-settings' } else { 'not-requested' }
                    portability = if ($null -ne $uiState) { 'ui-state-seed-included' }
                        else { 'portable' }
                    uiStatePolicy = if ($null -ne $uiState) { 'seed-on-import-then-managed-by-vscode' } else { 'managed-by-vscode' }
                    uiStateSeeded = ($null -ne $uiState)
                    uiStateSeed = if ($null -ne $uiState) {
                        [ordered]@{
                            sha256 = $uiStateHash
                            sourcePathRecorded = $false
                            source = if ($UiStateProfile) { 'stored-local-profile-ui-state' } else { 'explicit-profile-export' }
                            profileId = if ($UiStateProfile) { $UiStateProfile } else { $null }
                        }
                    }
                    else { $null }
                    importMethod = 'manual-vscode-profile-import'
                }
            }
            else { $null }
            outputHashes = $hashes
            validation = [ordered]@{
                result = 'passed'
                errors = $validation.errors.Count
                warnings = $validation.warnings.Count + $mergeWarnings.Count
                information = $validation.information.Count
            }
            counts = [ordered]@{
                settings = $settings.Count
                extensions = $extensions.Count
                keybindings = $keybindings.Count
                overrides = $overrides.Count
                warnings = $validation.warnings.Count + $mergeWarnings.Count
            }
        }
        Write-Utf8File (Join-Path $temporaryDirectory 'manifest.json') (ConvertTo-PrettyJson -Value $manifest)
        Read-JsonCFile (Join-Path $temporaryDirectory 'manifest.json') | Out-Null
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
        codeProfileExportPath = if ($codeProfileTargetPath) { Get-RelativeDisplayPath $root $codeProfileTargetPath } else { $null }
        uiStateSeeded = ($null -ne $uiState)
        machineId = $machineId
        counts = $manifest.counts
        dryRun = $false
    }
}

Export-ModuleMember -Function ConvertFrom-JsonC, Read-ProfileRecipe, Get-ProfileDefinitions, Get-MachineDefinitions, Get-DefaultVSCodeUserDataPath, Get-LiveVSCodeProfileDefinitions, Get-VSCodeStatusText, Resolve-ComposerProfileFromVSCodeStatus, Get-SharedDefaultComponent, Test-ComposerRepository, Merge-Settings, Merge-Extensions, Merge-Keybindings, Get-CodeProfileFileName, New-CodeProfileTemplate, Read-CodeProfileResources, Read-CodeProfileGlobalState, Get-StoredUiStateSeedPath, Save-ProfileUiStateSeed, Test-CodeProfileTemplate, Invoke-SafeDirectoryReplace, Rename-ComposerProfile, Rename-ComposerComponent, Set-SharedDefaultComponent, Sync-ComposerProfileFromExport, Invoke-GlobalSettingsComposition, Invoke-ProfileComposition
