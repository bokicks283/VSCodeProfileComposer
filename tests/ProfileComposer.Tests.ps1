BeforeAll {
    $script:RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    Import-Module (Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.psm1') -Force

    function New-ComposerFixture {
        param([Parameter(Mandatory)][string]$Name)
        $fixture = Join-Path $TestDrive $Name
        [System.IO.Directory]::CreateDirectory($fixture) | Out-Null
        foreach ($directory in @('components', 'profiles', 'platform', 'machine', 'global')) {
            Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot $directory) -Destination $fixture -Recurse
        }
        return $fixture
    }

    function Write-TestFile {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    }
}

Describe 'Global settings ownership' {
    It 'keeps every global value paired with one unique apply-to-all entry' {
        $path = Join-Path $script:RepositoryRoot 'global/settings.jsonc'
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($path))
        $ids = @($settings['workbench.settings.applyToAllProfiles'])
        $ids.Count | Should -BeGreaterThan 0
        @($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
        foreach ($id in $ids) { $settings.Contains($id) | Should -BeTrue }
        @($settings.Keys | Where-Object { $_ -ne 'workbench.settings.applyToAllProfiles' }).Count | Should -Be $ids.Count
    }

    It 'rejects globally owned settings in profile component sources' {
        $fixture = New-ComposerFixture 'global-setting-in-component'
        $path = Join-Path $fixture 'components/default/settings.jsonc'
        Write-TestFile $path '{ "terminal.integrated.confirmOnKill": "always" }'
        (Test-ComposerRepository $fixture).errors.code | Should -Contain 'global-setting-in-profile-source'
    }

    It 'rejects missing global values and unlisted global values' {
        $fixture = New-ComposerFixture 'invalid-global-settings'
        $path = Join-Path $fixture 'global/settings.jsonc'
        Write-TestFile $path '{ "workbench.settings.applyToAllProfiles": ["one.setting"], "other.setting": true }'
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'missing-global-setting-value'
        $result.errors.code | Should -Contain 'unlisted-global-setting'
    }

    It 'generates a separate built-in Default settings artifact' {
        $fixture = New-ComposerFixture 'global-output'
        $result = Invoke-GlobalSettingsComposition $fixture
        $output = Join-Path $fixture 'build/global'
        Test-Path -LiteralPath (Join-Path $output 'settings.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $output 'manifest.json') | Should -BeTrue
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'settings.json')))
        $result.settingCount | Should -Be @($settings['workbench.settings.applyToAllProfiles']).Count
        $settings['terminal.integrated.confirmOnKill'] | Should -Be 'never'
    }

    It 'omits globally applied settings from generated named profiles' {
        $fixture = New-ComposerFixture 'global-not-in-profile'
        Invoke-ProfileComposition $fixture default -Platform windows | Out-Null
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/default/settings.json')))
        $settings.Contains('terminal.integrated.confirmOnKill') | Should -BeFalse
        $settings.Contains('workbench.settings.applyToAllProfiles') | Should -BeFalse
    }

    It 'preserves previous global output when regeneration fails' {
        $fixture = New-ComposerFixture 'global-failed-preserves'
        Invoke-GlobalSettingsComposition $fixture | Out-Null
        $settingsPath = Join-Path $fixture 'build/global/settings.json'
        $before = [System.IO.File]::ReadAllText($settingsPath)
        Write-TestFile (Join-Path $fixture 'global/settings.jsonc') '{ invalid jsonc'
        { Invoke-GlobalSettingsComposition $fixture } | Should -Throw
        [System.IO.File]::ReadAllText($settingsPath) | Should -BeExactly $before
    }
}

Describe 'Recipe parsing and repository validation' {
    It 'parses the current ordered recipe format' {
        $recipe = Read-ProfileRecipe (Join-Path $script:RepositoryRoot 'profiles/unreal.yaml')
        $recipe.Name | Should -Be 'Unreal Engine'
        $recipe.Components | Should -Be @('default', 'cpp', 'unreal')
    }

    It 'uses Default as the shared first component in every recipe' {
        foreach ($definition in Get-ProfileDefinitions $script:RepositoryRoot) {
            $recipe = Read-ProfileRecipe $definition.Path
            $recipe.Components[0] | Should -BeExactly 'default'
        }
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'components/suggested-baseline') | Should -BeFalse
    }

    It 'detects missing recipe components' {
        $fixture = New-ComposerFixture 'missing-component'
        Write-TestFile (Join-Path $fixture 'profiles/broken.yaml') "name: Broken`ncomponents:`n  - does-not-exist`n"
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'missing-recipe-component'
    }

    It 'rejects invalid YAML' {
        $fixture = New-ComposerFixture 'invalid-yaml'
        Write-TestFile (Join-Path $fixture 'profiles/broken.yaml') "name: Broken`ncomponents: [default]`n"
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'invalid-yaml'
    }

    It 'detects duplicate component IDs in a recipe' {
        $fixture = New-ComposerFixture 'duplicate-components'
        Write-TestFile (Join-Path $fixture 'profiles/broken.yaml') "name: Broken`ncomponents:`n  - default`n  - DEFAULT`n"
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'duplicate-recipe-component'
    }

    It 'detects absolute personal paths in portable settings' {
        $fixture = New-ComposerFixture 'absolute-path'
        Write-TestFile (Join-Path $fixture 'components/default/settings.jsonc') '{ "tool.path": "C:\\Users\\person\\tool.exe" }'
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'portable-absolute-path'
    }

    It 'detects likely secrets in portable settings' {
        $fixture = New-ComposerFixture 'secret'
        Write-TestFile (Join-Path $fixture 'components/default/settings.jsonc') '{ "service.apiKey": "not-a-real-key-but-must-not-be-portable" }'
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'portable-likely-secret'
    }

    It 'passes repository-wide validation for the current source' {
        $result = Test-ComposerRepository $script:RepositoryRoot
        $result.errors.Count | Should -Be 0
    }
}

Describe 'JSONC parsing and merge behavior' {
    It 'parses line comments, block comments, and trailing commas' {
        $value = ConvertFrom-JsonC @'
{
  // line comment
  "one": 1,
  /* block comment */
  "items": ["a", "b",],
}
'@
        $value['one'] | Should -Be 1
        $value['items'] | Should -Be @('a', 'b')
    }

    It 'recursively merges objects' {
        $target = ConvertFrom-JsonC '{ "files.associations": { "*.ps1": "powershell" } }'
        $incoming = ConvertFrom-JsonC '{ "files.associations": { "*.inl": "cpp" } }'
        $sources = @{}
        $overrides = [System.Collections.Generic.List[object]]::new()
        Merge-Settings $target $incoming 'cpp' $sources $overrides | Out-Null
        $target['files.associations']['*.ps1'] | Should -Be 'powershell'
        $target['files.associations']['*.inl'] | Should -Be 'cpp'
    }

    It 'replaces scalar values from later layers' {
        $target = ConvertFrom-JsonC '{ "editor.tabSize": 2 }'
        $incoming = ConvertFrom-JsonC '{ "editor.tabSize": 4 }'
        $sources = @{ '/editor.tabSize' = 'baseline' }
        $overrides = [System.Collections.Generic.List[object]]::new()
        Merge-Settings $target $incoming 'cpp' $sources $overrides | Out-Null
        $target['editor.tabSize'] | Should -Be 4
    }

    It 'replaces arrays rather than unioning them' {
        $target = ConvertFrom-JsonC '{ "setting": [1, 2] }'
        $incoming = ConvertFrom-JsonC '{ "setting": [3] }'
        $sources = @{ '/setting' = 'first' }
        $overrides = [System.Collections.Generic.List[object]]::new()
        Merge-Settings $target $incoming 'second' $sources $overrides | Out-Null
        $target['setting'] | Should -Be @(3)
    }

    It 'treats null as an explicit replacement value' {
        $target = ConvertFrom-JsonC '{ "setting": "value" }'
        $incoming = ConvertFrom-JsonC '{ "setting": null }'
        $sources = @{ '/setting' = 'first' }
        $overrides = [System.Collections.Generic.List[object]]::new()
        Merge-Settings $target $incoming 'second' $sources $overrides | Out-Null
        $target.Contains('setting') | Should -BeTrue
        $target['setting'] | Should -BeNullOrEmpty
        $overrides.Count | Should -Be 1
    }

    It 'records override source, values, and resolution' {
        $target = ConvertFrom-JsonC '{ "editor.tabSize": 2 }'
        $incoming = ConvertFrom-JsonC '{ "editor.tabSize": 4 }'
        $sources = @{ '/editor.tabSize' = 'baseline' }
        $overrides = [System.Collections.Generic.List[object]]::new()
        Merge-Settings $target $incoming 'cpp' $sources $overrides | Out-Null
        $overrides.Count | Should -Be 1
        $overrides[0].path | Should -Be '/editor.tabSize'
        $overrides[0].previousSource | Should -Be 'baseline'
        $overrides[0].newSource | Should -Be 'cpp'
        $overrides[0].previousValue | Should -Be 2
        $overrides[0].newValue | Should -Be 4
        $overrides[0].resolutionSource | Should -Be 'cpp'
    }

    It 'redacts sensitive override values in reports' {
        $target = ConvertFrom-JsonC '{ "service.token": "old-value" }'
        $incoming = ConvertFrom-JsonC '{ "service.token": "new-value" }'
        $sources = @{ '/service.token' = 'first' }
        $overrides = [System.Collections.Generic.List[object]]::new()
        Merge-Settings $target $incoming 'machine' $sources $overrides | Out-Null
        $overrides[0].previousValue | Should -Be '[REDACTED]'
        $overrides[0].newValue | Should -Be '[REDACTED]'
        $target['service.token'] | Should -Be 'new-value'
    }
}

Describe 'Extension and keybinding composition' {
    It 'unions extensions case-insensitively in first-appearance order' {
        $first = Join-Path $TestDrive 'extensions-first.txt'
        $second = Join-Path $TestDrive 'extensions-second.txt'
        Write-TestFile $first "# comment`nms-vscode.cpptools`n Example.Tool `n"
        Write-TestFile $second "MS-VSCODE.CPPTOOLS`nsecond.publisher`n"
        $files = @(
            [pscustomobject]@{ Path = $first; Source = 'first' },
            [pscustomobject]@{ Path = $second; Source = 'second' }
        )
        Merge-Extensions $files | Should -Be @('ms-vscode.cpptools', 'Example.Tool', 'second.publisher')
    }

    It 'concatenates keybinding arrays without semantic deduplication' {
        $first = Join-Path $TestDrive 'keys-first.jsonc'
        $second = Join-Path $TestDrive 'keys-second.jsonc'
        Write-TestFile $first '[{ "key": "ctrl+a", "command": "one" }]'
        Write-TestFile $second '[{ "key": "ctrl+a", "command": "two" }]'
        $result = Merge-Keybindings @(
            [pscustomobject]@{ Path = $first; Source = 'first' },
            [pscustomobject]@{ Path = $second; Source = 'second' }
        )
        $result.Items.Count | Should -Be 2
        $result.Items[1]['command'] | Should -Be 'two'
    }

    It 'warns about identical duplicate keybinding objects while preserving them' {
        $first = Join-Path $TestDrive 'keys-duplicate.jsonc'
        Write-TestFile $first '[{ "key": "ctrl+a", "command": "one" }, { "key": "ctrl+a", "command": "one" }]'
        $result = Merge-Keybindings @([pscustomobject]@{ Path = $first; Source = 'one' })
        $result.Items.Count | Should -Be 2
        $result.Warnings.code | Should -Contain 'identical-keybinding-duplicate'
    }
}

Describe 'Layer ordering and safe output' {
    It 'applies the platform overlay after the profile-local override' {
        $fixture = New-ComposerFixture 'platform-order'
        Write-TestFile (Join-Path $fixture 'profiles/default.settings.jsonc') '{ "terminal.integrated.defaultProfile.windows": "Profile Shell" }'
        Invoke-ProfileComposition $fixture default -Platform windows | Out-Null
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/default/settings.json')))
        $settings['terminal.integrated.defaultProfile.windows'] | Should -Be 'PowerShell 7'
    }

    It 'applies the machine overlay after the platform overlay' {
        $fixture = New-ComposerFixture 'machine-order'
        $machine = Join-Path $fixture 'machine/local/test.jsonc'
        Write-TestFile $machine '{ "terminal.integrated.defaultProfile.windows": "Machine Shell" }'
        Invoke-ProfileComposition $fixture default -Platform windows -MachineFile $machine | Out-Null
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/default/settings.json')))
        $settings['terminal.integrated.defaultProfile.windows'] | Should -Be 'Machine Shell'
    }

    It 'selects a named machine overlay and records its identity' {
        $fixture = New-ComposerFixture 'named-machine'
        Write-TestFile (Join-Path $fixture 'machine/local/gaming-server.jsonc') '{ "todo-tree.ripgrep.ripgrep": "D:\\Tools\\rg.exe" }'
        $result = Invoke-ProfileComposition $fixture default -Platform windows -Machine gaming-server
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/default/settings.json')))
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/default/manifest.json')))
        $settings['todo-tree.ripgrep.ripgrep'] | Should -Be 'D:\Tools\rg.exe'
        $result.machineId | Should -Be 'gaming-server'
        $manifest.machineOverlay.id | Should -Be 'gaming-server'
        $manifest.machineOverlay.selection | Should -Be 'named-machine'
    }

    It 'lists named machines and rejects missing or conflicting selections' {
        $fixture = New-ComposerFixture 'machine-selection-validation'
        Write-TestFile (Join-Path $fixture 'machine/local/main-windows.jsonc') '{}'
        (Get-MachineDefinitions $fixture).Id | Should -Contain 'main-windows'
        (Test-ComposerRepository $fixture -Machine missing).errors.code | Should -Contain 'missing-machine-overlay'
        { Invoke-ProfileComposition $fixture default -Machine main-windows -MachineFile './machine/local/main-windows.jsonc' } | Should -Throw '*cannot be used together*'
    }

    It 'replaces only the generated target directory' {
        $fixture = New-ComposerFixture 'safe-replace'
        Invoke-ProfileComposition $fixture default | Out-Null
        $sentinel = Join-Path $fixture 'build/profiles/default/stale.txt'
        Write-TestFile $sentinel 'stale'
        Invoke-ProfileComposition $fixture default | Out-Null
        Test-Path -LiteralPath $sentinel | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixture 'build/profiles/default/manifest.json') | Should -BeTrue
    }

    It 'preserves the previous valid output when composition fails' {
        $fixture = New-ComposerFixture 'failed-preserves'
        Invoke-ProfileComposition $fixture default | Out-Null
        $settingsPath = Join-Path $fixture 'build/profiles/default/settings.json'
        $before = [System.IO.File]::ReadAllText($settingsPath)
        Write-TestFile (Join-Path $fixture 'components/default/settings.jsonc') '{ invalid jsonc'
        { Invoke-ProfileComposition $fixture default } | Should -Throw
        [System.IO.File]::ReadAllText($settingsPath) | Should -BeExactly $before
    }

    It 'does not create output during dry run' {
        $fixture = New-ComposerFixture 'dry-run'
        $result = Invoke-ProfileComposition $fixture default -Platform windows -DryRun
        $result.dryRun | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'build') | Should -BeFalse
    }
}

Describe 'Current profile acceptance compositions' {
    It 'composes the current Default profile in isolation' {
        $fixture = New-ComposerFixture 'compose-default'
        { Invoke-ProfileComposition $fixture default -Platform windows } | Should -Not -Throw
    }

    It 'composes the current Unreal profile in isolation' {
        $fixture = New-ComposerFixture 'compose-unreal'
        { Invoke-ProfileComposition $fixture unreal -Platform windows } | Should -Not -Throw
    }

    It 'composes the current Web profile in isolation' {
        $fixture = New-ComposerFixture 'compose-web'
        { Invoke-ProfileComposition $fixture web -Platform windows } | Should -Not -Throw
    }

    It 'composes the current Python profile in isolation' {
        $fixture = New-ComposerFixture 'compose-python'
        { Invoke-ProfileComposition $fixture python -Platform windows } | Should -Not -Throw
    }

    It 'writes the complete expected output structure' {
        $fixture = New-ComposerFixture 'output-structure'
        Invoke-ProfileComposition $fixture default -Platform windows | Out-Null
        $output = Join-Path $fixture 'build/profiles/default'
        foreach ($name in @('settings.json', 'extensions.txt', 'keybindings.json', 'manifest.json', 'overrides.json', 'validation.json')) {
            Test-Path -LiteralPath (Join-Path $output $name) | Should -BeTrue
        }
        (ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'keybindings.json')))) -is [System.Array] | Should -BeTrue
    }
}

Describe 'VS Code .code-profile export' {
    BeforeAll {
        function New-UiStateSeedExport {
            param(
                [Parameter(Mandatory)][string]$Path,
                [string]$GlobalState = '{"storage":{"workbench.activity.pinnedViewlets2":"[]"}}'
            )
            $seed = [ordered]@{
                name = 'Private Layout Seed'
                settings = '{"settings":"{\"seed.setting.mustBeIgnored\":true}"}'
                extensions = '[{"identifier":{"id":"seed.extension-must-be-ignored"}}]'
                globalState = $GlobalState
            }
            Write-TestFile $Path (ConvertTo-Json -InputObject $seed -Depth 20)
            return $GlobalState
        }
    }

    It 'generates an export for Default' {
        $fixture = New-ComposerFixture 'export-default'
        $result = Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile
        $result.codeProfileExportPath | Should -Be 'build/profiles/default/Default.code-profile'
        Test-Path -LiteralPath (Join-Path $fixture $result.codeProfileExportPath) | Should -BeTrue
    }

    It 'generates an export for Unreal' {
        $fixture = New-ComposerFixture 'export-unreal'
        $result = Invoke-ProfileComposition $fixture unreal -Platform windows -ExportCodeProfile
        $result.codeProfileExportPath | Should -Be 'build/profiles/unreal/Unreal-Engine.code-profile'
        { Test-CodeProfileTemplate (Join-Path $fixture $result.codeProfileExportPath) } | Should -Not -Throw
    }

    It 'embeds the complete generated settings JSON' {
        $fixture = New-ComposerFixture 'export-settings'
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/default'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Default.code-profile')))
        $resource = ConvertFrom-JsonC $profile.settings
        $resource.settings | Should -BeExactly ([System.IO.File]::ReadAllText((Join-Path $output 'settings.json')))
    }

    It 'converts extension IDs to VS Code identifier resources' {
        $fixture = New-ComposerFixture 'export-extensions'
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/default'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Default.code-profile')))
        $resources = ConvertFrom-JsonC $profile.extensions
        $expected = [System.IO.File]::ReadAllLines((Join-Path $output 'extensions.txt'))[0]
        $resources[0].identifier.id | Should -BeExactly $expected
        $resources[0].identifier.Contains('uuid') | Should -BeFalse
    }

    It 'embeds generated keybindings and Windows platform metadata' {
        $fixture = New-ComposerFixture 'export-keybindings'
        Write-TestFile (Join-Path $fixture 'components/default/keybindings.jsonc') '[{ "key": "ctrl+alt+t", "command": "workbench.action.files.newUntitledFile" }]'
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/default'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Default.code-profile')))
        $resource = ConvertFrom-JsonC $profile.keybindings
        $keys = ConvertFrom-JsonC $resource.keybindings
        $keys[0].command | Should -Be 'workbench.action.files.newUntitledFile'
        $resource.platform | Should -Be 3
    }

    It 'uses VS Code empty-array keybinding representation when no bindings exist' {
        $fixture = New-ComposerFixture 'export-empty-keybindings'
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile | Out-Null
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/default/Default.code-profile')))
        $resource = ConvertFrom-JsonC $profile.keybindings
        $keys = ConvertFrom-JsonC $resource.keybindings
        $keys -is [System.Array] | Should -BeTrue
        $keys.Count | Should -Be 0
    }

    It 'includes explicitly requested machine settings and classifies the export' {
        $fixture = New-ComposerFixture 'export-machine'
        $machine = Join-Path $fixture 'machine/local/test.jsonc'
        Write-TestFile $machine '{ "terminal.integrated.defaultProfile.windows": "Machine Shell" }'
        Invoke-ProfileComposition $fixture default -Platform windows -MachineFile $machine -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/default'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Default.code-profile')))
        $settingsResource = ConvertFrom-JsonC $profile.settings
        $settings = ConvertFrom-JsonC $settingsResource.settings
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'manifest.json')))
        $settings['terminal.integrated.defaultProfile.windows'] | Should -Be 'Machine Shell'
        $manifest.codeProfileExport.machineOverlayIncluded | Should -BeTrue
        $manifest.codeProfileExport.portability | Should -Be 'machine-overlay-included'
    }

    It 'classifies an export without a machine overlay as portable' {
        $fixture = New-ComposerFixture 'export-portable'
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile | Out-Null
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/default/manifest.json')))
        $manifest.codeProfileExport.machineOverlayIncluded | Should -BeFalse
        $manifest.codeProfileExport.portability | Should -Be 'portable'
    }

    It 'creates deterministic safe filenames' {
        Get-CodeProfileFileName 'Python Database' | Should -Be 'Python-Database.code-profile'
        Get-CodeProfileFileName 'Python + Database' | Should -Be 'Python-Database.code-profile'
        Get-CodeProfileFileName 'C++: Tools' | Should -Be 'C++-Tools.code-profile'
    }

    It 'rejects path traversal in an export filename source' {
        { Get-CodeProfileFileName '../escape' } | Should -Throw '*escape the export directory*'
        $fixture = New-ComposerFixture 'export-traversal'
        Write-TestFile (Join-Path $fixture 'profiles/escape.yaml') "name: ../escape`ncomponents:`n  - default`n"
        $validation = Test-ComposerRepository $fixture
        $validation.errors.code | Should -Contain 'invalid-export-filename'
    }

    It 'reports the planned export but writes nothing during dry run' {
        $fixture = New-ComposerFixture 'export-dry-run'
        $result = Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile -DryRun
        $result.codeProfileExportPath | Should -Be 'build/profiles/default/Default.code-profile'
        Test-Path -LiteralPath (Join-Path $fixture 'build') | Should -BeFalse
    }

    It 'preserves the previous valid export when a later generation fails' {
        $fixture = New-ComposerFixture 'export-failed-preserves'
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile | Out-Null
        $exportPath = Join-Path $fixture 'build/profiles/default/Default.code-profile'
        $before = [System.IO.File]::ReadAllText($exportPath)
        Write-TestFile (Join-Path $fixture 'components/default/settings.jsonc') '{ invalid jsonc'
        { Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile } | Should -Throw
        [System.IO.File]::ReadAllText($exportPath) | Should -BeExactly $before
    }

    It 'records the exact export hash and schema metadata in the manifest' {
        $fixture = New-ComposerFixture 'export-hash'
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/default'
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'manifest.json')))
        $actual = (Get-FileHash -LiteralPath (Join-Path $output 'Default.code-profile') -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest.codeProfileExport.sha256 | Should -BeExactly $actual
        $manifest.codeProfileExport.schema | Should -Be 'vscode-user-data-profile-template'
        $manifest.codeProfileExport.schemaVersion | Should -Be 'unversioned'
    }

    It 'parses generated exports as valid JSON and validates nested resources' {
        $fixture = New-ComposerFixture 'export-valid-json'
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile | Out-Null
        $path = Join-Path $fixture 'build/profiles/default/Default.code-profile'
        { [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($path)).Dispose() } | Should -Not -Throw
        Test-CodeProfileTemplate $path | Should -BeTrue
    }

    It 'matches the verified VS Code 1.129.1 schema fixture' {
        $fixturePath = Join-Path $script:RepositoryRoot 'tests/fixtures/vscode-1.129.1-minimal.code-profile'
        Test-CodeProfileTemplate $fixturePath | Should -BeTrue
        $fixture = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($fixturePath))
        $fixture.Keys | Should -Be @('name', 'settings', 'keybindings', 'extensions')
        foreach ($resource in @('settings', 'keybindings', 'extensions')) { $fixture[$resource] | Should -BeOfType [string] }
    }

    It 'rejects duplicate extension resources and sensitive metadata' {
        $path = Join-Path $TestDrive 'invalid-export.code-profile'
        $template = New-CodeProfileTemplate -DisplayName 'Fixture' -SettingsJson '{}' -Extensions @('sample.extension') -KeybindingsJson '[]' -Platform windows
        $template.extensions = '[{"identifier":{"id":"sample.extension"}},{"identifier":{"id":"SAMPLE.EXTENSION"}}]'
        Write-TestFile $path (ConvertTo-Json -InputObject $template -Depth 20)
        { Test-CodeProfileTemplate $path } | Should -Throw '*duplicate extension*'

        $fixture = New-ComposerFixture 'export-sensitive-metadata'
        Write-TestFile (Join-Path $fixture 'profiles/sensitive.yaml') "name: `"token=abcdefghijklmnop`"`ncomponents:`n  - default`n"
        (Test-ComposerRepository $fixture).errors.code | Should -Contain 'sensitive-profile-metadata'
    }

    It 'omits UI state and rejects accidental UI-state source files' {
        $fixture = New-ComposerFixture 'export-no-ui-state'
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile | Out-Null
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/default/Default.code-profile')))
        $profile.Contains('globalState') | Should -BeFalse
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/default/manifest.json')))
        $manifest.codeProfileExport.uiStatePolicy | Should -Be 'managed-by-vscode'
        Write-TestFile (Join-Path $fixture 'components/default/ui-state.jsonc') '{}'
        (Test-ComposerRepository $fixture).errors.code | Should -Contain 'unsupported-ui-state-source'
    }

    It 'copies an explicitly supplied UI-state seed without copying other resources' {
        $fixture = New-ComposerFixture 'export-ui-seed'
        $seedPath = Join-Path $TestDrive 'layout-seed.code-profile'
        $expectedGlobalState = New-UiStateSeedExport $seedPath
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile -UiStateFromProfile $seedPath | Out-Null

        $output = Join-Path $fixture 'build/profiles/default'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Default.code-profile')))
        $settings = ConvertFrom-JsonC (ConvertFrom-JsonC $profile.settings).settings
        $extensionIds = @((ConvertFrom-JsonC $profile.extensions) | ForEach-Object { $_.identifier.id })
        $profile.globalState | Should -BeExactly $expectedGlobalState
        $settings.Contains('seed.setting.mustBeIgnored') | Should -BeFalse
        $extensionIds | Should -Not -Contain 'seed.extension-must-be-ignored'
        Test-CodeProfileTemplate (Join-Path $output 'Default.code-profile') | Should -BeTrue
    }

    It 'records only UI-state seed policy and content hash, never its source path' {
        $fixture = New-ComposerFixture 'export-ui-seed-manifest'
        $privateDirectory = Join-Path $TestDrive 'personal-private-location'
        $seedPath = Join-Path $privateDirectory 'signed-in-layout.code-profile'
        $globalState = New-UiStateSeedExport $seedPath
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile -UiStateFromProfile $seedPath | Out-Null

        $output = Join-Path $fixture 'build/profiles/default'
        $manifestText = [System.IO.File]::ReadAllText((Join-Path $output 'manifest.json'))
        $manifest = ConvertFrom-JsonC $manifestText
        $expectedHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.UTF8Encoding]::new($false).GetBytes($globalState))).ToLowerInvariant()
        $manifest.codeProfileExport.uiStateSeeded | Should -BeTrue
        $manifest.codeProfileExport.uiStatePolicy | Should -Be 'seed-on-import-then-managed-by-vscode'
        $manifest.codeProfileExport.portability | Should -Be 'ui-state-seed-included'
        $manifest.codeProfileExport.uiStateSeed.sha256 | Should -BeExactly $expectedHash
        $manifest.codeProfileExport.uiStateSeed.sourcePathRecorded | Should -BeFalse
        $manifestText | Should -Not -Match ([regex]::Escape($seedPath))
        $manifestText | Should -Not -Match 'personal-private-location'
    }

    It 'requires export mode and a valid profile export containing globalState' {
        $fixture = New-ComposerFixture 'export-ui-seed-validation'
        $missing = Join-Path $TestDrive 'missing.code-profile'
        { Invoke-ProfileComposition $fixture default -UiStateFromProfile $missing } | Should -Throw '*requires -ExportCodeProfile*'
        { Invoke-ProfileComposition $fixture default -ExportCodeProfile -UiStateFromProfile $missing } | Should -Throw '*does not exist*'

        $noState = Join-Path $TestDrive 'no-state.code-profile'
        Write-TestFile $noState '{"name":"No State"}'
        { Invoke-ProfileComposition $fixture default -ExportCodeProfile -UiStateFromProfile $noState } | Should -Throw '*does not contain*globalState*'

        $malformedState = Join-Path $TestDrive 'malformed-state.code-profile'
        New-UiStateSeedExport $malformedState -GlobalState '{bad json' | Out-Null
        { Invoke-ProfileComposition $fixture default -ExportCodeProfile -UiStateFromProfile $malformedState } | Should -Throw '*Invalid JSONC*globalState*'
    }

    It 'validates a UI-state seed during dry run without writing output' {
        $fixture = New-ComposerFixture 'export-ui-seed-dry-run'
        $seedPath = Join-Path $TestDrive 'dry-layout.code-profile'
        New-UiStateSeedExport $seedPath | Out-Null
        $result = Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile -UiStateFromProfile $seedPath -DryRun
        $result.uiStateSeeded | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'build') | Should -BeFalse
    }

    It 'preserves the previous valid seeded export when a later UI seed is invalid' {
        $fixture = New-ComposerFixture 'export-ui-seed-failed-preserves'
        $seedPath = Join-Path $TestDrive 'valid-layout.code-profile'
        New-UiStateSeedExport $seedPath | Out-Null
        Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile -UiStateFromProfile $seedPath | Out-Null
        $exportPath = Join-Path $fixture 'build/profiles/default/Default.code-profile'
        $before = [System.IO.File]::ReadAllText($exportPath)

        $badSeedPath = Join-Path $TestDrive 'bad-layout.code-profile'
        New-UiStateSeedExport $badSeedPath -GlobalState '[]' | Out-Null
        { Invoke-ProfileComposition $fixture default -Platform windows -ExportCodeProfile -UiStateFromProfile $badSeedPath } | Should -Throw '*must be an object*'
        [System.IO.File]::ReadAllText($exportPath) | Should -BeExactly $before
    }

    It 'keeps ordinary composition export-free and otherwise unchanged' {
        $fixture = New-ComposerFixture 'non-export-unchanged'
        Invoke-ProfileComposition $fixture default -Platform windows | Out-Null
        $output = Join-Path $fixture 'build/profiles/default'
        @(Get-ChildItem -LiteralPath $output -Filter '*.code-profile').Count | Should -Be 0
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'manifest.json')))
        $manifest.codeProfileExportRequested | Should -BeFalse
        $manifest.codeProfileExport | Should -BeNullOrEmpty
    }
}

Describe 'Historical extension reference' {
    It 'preserves the sanitized Extension Library Staging inventory' {
        $path = Join-Path $script:RepositoryRoot 'reference/extensions/extension-library-staging.txt'
        $ids = @(
            [System.IO.File]::ReadAllLines($path) |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and -not $_.StartsWith('#') }
        )

        $ids.Count | Should -Be 150
        @($ids | Sort-Object -Unique).Count | Should -Be 150
        foreach ($id in $ids) {
            $id | Should -Match '^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$'
        }
    }
}
