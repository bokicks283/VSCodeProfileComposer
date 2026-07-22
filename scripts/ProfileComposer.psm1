Set-StrictMode -Version Latest

$script:ComposerVersion = '0.5.0'
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
        }
        catch { Add-ValidationItem $result errors 'invalid-yaml' $_.Exception.Message $source }

        $overridePath = Join-Path $profileRoot "$($profile.Id).settings.jsonc"
        if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
            try {
                $override = Read-JsonCFile $overridePath
                if (-not (Test-IsDictionary $override)) { Add-ValidationItem $result errors 'profile-settings-root' 'Profile-local settings root must be an object.' (Get-RelativeDisplayPath $root $overridePath) }
                else {
                    Test-PortableSettings $override $result (Get-RelativeDisplayPath $root $overridePath)
                    foreach ($key in $override.Keys) {
                        if ($globalSettingIds.Contains([string]$key)) {
                            Add-ValidationItem $result errors 'global-setting-in-profile-source' "Setting '$key' is globally owned and must not be declared in a profile override." (Get-RelativeDisplayPath $root $overridePath) "/$key"
                        }
                    }
                }
            }
            catch { Add-ValidationItem $result errors 'invalid-jsonc' $_.Exception.Message (Get-RelativeDisplayPath $root $overridePath) }
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
        [switch]$Strict
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ($UiStateFromProfile -and -not $ExportCodeProfile) { throw '-UiStateFromProfile requires -ExportCodeProfile.' }
    if ($Machine -and $MachineFile) { throw '-Machine and -MachineFile cannot be used together.' }
    $validation = Test-ComposerRepository -RepositoryRoot $root -Platform $Platform -Machine $Machine -MachineFile $MachineFile
    if ($validation.errors.Count -gt 0 -or ($Strict -and $validation.warnings.Count -gt 0)) {
        $reason = if ($validation.errors.Count -gt 0) { "$($validation.errors.Count) validation error(s)" } else { "$($validation.warnings.Count) warning(s) in strict mode" }
        throw "Composition stopped because repository validation found $reason."
    }

    $definition = @(Get-ProfileDefinitions $root | Where-Object { $_.Id -ieq $Profile })
    if ($definition.Count -eq 0) { throw "Unknown profile '$Profile'." }
    if ($definition.Count -gt 1) { throw "Profile ID '$Profile' is ambiguous." }
    $resolvedUiStateSeed = Resolve-UiStateSeedPath -RepositoryRoot $root -UiStateFromProfile $UiStateFromProfile
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

    $profileOverridePath = Join-Path $root "profiles/$profileId.settings.jsonc"
    if (Test-Path -LiteralPath $profileOverridePath -PathType Leaf) {
        $source = Get-RelativeDisplayPath $root $profileOverridePath
        $settingsLayers.Add([pscustomobject]@{ Path = $profileOverridePath; Source = $source })
        $inputFiles.Add([pscustomobject]@{ type = 'profile-settings'; path = $source })
    }
    $platformPath = $null
    if ($Platform) {
        $platformPath = Join-Path $root "platform/$Platform.jsonc"
        $source = Get-RelativeDisplayPath $root $platformPath
        $settingsLayers.Add([pscustomobject]@{ Path = $platformPath; Source = $source })
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
    $keybindingsResult = Merge-Keybindings -Files $keybindingFiles.ToArray()
    $keybindings = @($keybindingsResult.Items)
    $mergeWarnings = @($keybindingsResult.Warnings)
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
                    uiStateSeed = if ($null -ne $uiState) { [ordered]@{ sha256 = $uiStateHash; sourcePathRecorded = $false } } else { $null }
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

Export-ModuleMember -Function ConvertFrom-JsonC, Read-ProfileRecipe, Get-ProfileDefinitions, Get-MachineDefinitions, Test-ComposerRepository, Merge-Settings, Merge-Extensions, Merge-Keybindings, Get-CodeProfileFileName, New-CodeProfileTemplate, Read-CodeProfileGlobalState, Test-CodeProfileTemplate, Invoke-SafeDirectoryReplace, Invoke-GlobalSettingsComposition, Invoke-ProfileComposition
