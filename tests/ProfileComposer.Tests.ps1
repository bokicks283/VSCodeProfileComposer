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
        Get-ChildItem -LiteralPath (Join-Path $fixture 'machine/local') -Filter '*.jsonc' -File -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Remove-Item -LiteralPath (Join-Path $fixture 'machine/local/.default-machine') -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'composer.jsonc') -Destination $fixture
        return $fixture
    }

    function Write-TestFile {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    }

    function New-VSCodeUserDataFixture {
        param(
            [Parameter(Mandatory)][string]$Name,
            [object[]]$Profiles = @(
                [ordered]@{ location = 'file:///C:/fixture/profiles/main-id'; name = 'Main' },
                [ordered]@{ location = 'file:///C:/fixture/profiles/python-id'; name = 'Python' }
            )
        )
        $userDataPath = Join-Path $TestDrive $Name
        $storagePath = Join-Path $userDataPath 'globalStorage/storage.json'
        Write-TestFile $storagePath (ConvertTo-Json -InputObject ([ordered]@{ userDataProfiles = $Profiles }) -Depth 10)
        return $userDataPath
    }

    function New-MachineDefinition {
        param(
            [Parameter(Mandatory)][string]$RepositoryRoot,
            [Parameter(Mandatory)][string]$Id,
            [Parameter(Mandatory)][string]$Platform,
            [Parameter(Mandatory)][System.Collections.IDictionary]$Settings,
            [string]$Name = $Id
        )
        $path = Join-Path $RepositoryRoot "machine/local/$Id.jsonc"
        $value = [ordered]@{
            schemaVersion = 1
            machine = [ordered]@{
                id = $Id
                name = $Name
                platform = $Platform
                hostnames = @()
            }
            settings = $Settings
        }
        Write-TestFile $path (ConvertTo-Json -InputObject $value -Depth 100)
        return $path
    }

    function New-SyncExport {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][System.Collections.IDictionary]$Settings,
            [string]$Name = 'Python',
            [switch]$NoUiState
        )
        $parameters = @{
            DisplayName = $Name
            SettingsJson = ConvertTo-Json -InputObject $Settings -Depth 100 -Compress
            Extensions = @()
            KeybindingsJson = '[]'
            Platform = 'windows'
        }
        if (-not $NoUiState) { $parameters.GlobalState = '{"layout":true}' }
        $template = New-CodeProfileTemplate @parameters
        Write-TestFile $Path (ConvertTo-Json -InputObject $template -Depth 100)
        return $Path
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

    It 'keeps cSpell out of Problems and uses the inline correction menu globally' {
        $path = Join-Path $script:RepositoryRoot 'global/settings.jsonc'
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($path))
        $settings['cSpell.useCustomDecorations'] | Should -BeTrue
        $settings['cSpell.suggestionMenuType'] | Should -BeExactly 'quickFix'
    }

    It 'owns persistent terminal history and the new-window profile globally' {
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $script:RepositoryRoot 'global/settings.jsonc')))
        $mainSettings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $script:RepositoryRoot 'components/main/settings.jsonc')))
        foreach ($id in @('terminal.integrated.persistentSessionScrollback', 'window.newWindowProfile')) {
            $settings['workbench.settings.applyToAllProfiles'] | Should -Contain $id
            $settings.Contains($id) | Should -BeTrue
            $mainSettings.Contains($id) | Should -BeFalse
        }
    }

    It 'rejects globally owned settings in profile component sources' {
        $fixture = New-ComposerFixture 'global-setting-in-component'
        $path = Join-Path $fixture 'components/main/settings.jsonc'
        Write-TestFile $path '{ "terminal.integrated.confirmOnKill": "always" }'
        (Test-ComposerRepository $fixture).errors.code | Should -Contain 'global-setting-in-profile-source'
    }

    It 'rejects missing global values and unlisted global values' {
        $fixture = New-ComposerFixture 'invalid-global-settings'
        $path = Join-Path $fixture 'global/settings.jsonc'
        Write-TestFile $path '{ "workbench.settings.applyToAllProfiles": ["settingsSync.ignoredSettings", "one.setting"], "settingsSync.ignoredSettings": [], "other.setting": true }'
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'missing-global-setting-value'
        $result.errors.code | Should -Contain 'unlisted-global-setting'
    }

    It 'dry-runs and transactionally repairs duplicate and unlisted global ownership entries' {
        $fixture = New-ComposerFixture 'repair-global-ownership'
        $path = Join-Path $fixture 'global/settings.jsonc'
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($path))
        $firstId = [string]$settings['workbench.settings.applyToAllProfiles'][0]
        $settings['workbench.settings.applyToAllProfiles'] = [string[]]@(
            $settings['workbench.settings.applyToAllProfiles']
            $firstId
        )
        $settings['fixture.unlistedGlobal'] = $true
        Write-TestFile $path (ConvertTo-Json -InputObject $settings -Depth 100)
        $before = [System.IO.File]::ReadAllText($path)

        $plan = Repair-ComposerGlobalOwnership $fixture -DryRun
        $plan.dryRun | Should -BeTrue
        $plan.addedSettings | Should -Be @('fixture.unlistedGlobal')
        $plan.removedDuplicates | Should -Be @($firstId)
        [System.IO.File]::ReadAllText($path) | Should -BeExactly $before

        $result = Repair-ComposerGlobalOwnership $fixture
        $result.changes.Count | Should -Be 1
        $repaired = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($path))
        @($repaired['workbench.settings.applyToAllProfiles'] | Where-Object { $_ -ceq $firstId }).Count | Should -Be 1
        $repaired['workbench.settings.applyToAllProfiles'][-1] | Should -BeExactly 'fixture.unlistedGlobal'
        (Test-ComposerRepository $fixture).errors.Count | Should -Be 0
    }

    It 'creates a missing ownership array and refuses to guess a listed setting value' {
        $fixture = New-ComposerFixture 'repair-missing-global-list'
        $path = Join-Path $fixture 'global/settings.jsonc'
        Write-TestFile $path '{ "settingsSync.ignoredSettings": [], "fixture.global": true }'

        $result = Repair-ComposerGlobalOwnership $fixture
        $result.ownershipListCreated | Should -BeTrue
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($path))
        $settings['workbench.settings.applyToAllProfiles'] | Should -Be @('settingsSync.ignoredSettings', 'fixture.global')

        Write-TestFile $path '{ "workbench.settings.applyToAllProfiles": ["settingsSync.ignoredSettings", "missing.value"], "settingsSync.ignoredSettings": [] }'
        $before = [System.IO.File]::ReadAllText($path)
        { Repair-ComposerGlobalOwnership $fixture } | Should -Throw '*listed settings have no value*'
        [System.IO.File]::ReadAllText($path) | Should -BeExactly $before
    }

    It 'leaves source unchanged when a planned ownership repair exposes a cross-layer conflict' {
        $fixture = New-ComposerFixture 'repair-global-conflict'
        $path = Join-Path $fixture 'global/settings.jsonc'
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($path))
        $settings['fixture.conflictingGlobal'] = $true
        Write-TestFile $path (ConvertTo-Json -InputObject $settings -Depth 100)
        Write-TestFile (Join-Path $fixture 'components/main/settings.jsonc') '{ "fixture.conflictingGlobal": false }'
        $before = [System.IO.File]::ReadAllText($path)

        { Repair-ComposerGlobalOwnership $fixture } | Should -Throw '*failed validation*global-setting-in-profile-source*'
        [System.IO.File]::ReadAllText($path) | Should -BeExactly $before
    }

    It 'generates a separate built-in Default settings artifact' {
        $fixture = New-ComposerFixture 'global-output'
        $result = Invoke-GlobalSettingsComposition $fixture
        $output = Join-Path $fixture 'build/global'
        Test-Path -LiteralPath (Join-Path $output 'settings.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $output 'manifest.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $output 'overrides.json') | Should -BeTrue
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'settings.json')))
        $result.settingCount | Should -Be @($settings['workbench.settings.applyToAllProfiles']).Count
        $settings['terminal.integrated.confirmOnKill'] | Should -Be 'never'
    }

    It 'delivers machine settings through built-in Default and protects them from Settings Sync' {
        $fixture = New-ComposerFixture 'global-machine-output'
        $machine = Join-Path $fixture 'machine/local/test.jsonc'
        Write-TestFile $machine '{ "machine.tool.path": "D:\\Tools\\tool.exe", "window.zoomLevel": 2, "terminal.integrated.confirmOnKill": "always" }'
        $result = Invoke-GlobalSettingsComposition $fixture -MachineFile $machine
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/global/settings.json')))
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/global/manifest.json')))
        $overrideReport = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/global/overrides.json')))

        $settings['machine.tool.path'] | Should -Be 'D:\Tools\tool.exe'
        $settings['window.zoomLevel'] | Should -Be 2
        $settings['terminal.integrated.confirmOnKill'] | Should -Be 'always'
        $settings['workbench.settings.applyToAllProfiles'] | Should -Contain 'machine.tool.path'
        $settings['workbench.settings.applyToAllProfiles'] | Should -Contain 'window.zoomLevel'
        $settings['settingsSync.ignoredSettings'] | Should -Contain 'machine.tool.path'
        $settings['settingsSync.ignoredSettings'] | Should -Contain 'window.zoomLevel'
        $settings['settingsSync.ignoredSettings'] | Should -Not -Contain '-window.zoomLevel'
        $result.machineSettingCount | Should -Be 3
        $result.overrideCount | Should -Be 1
        $overrideReport.overrides[0].path | Should -Be '/terminal.integrated.confirmOnKill'
        $overrideReport.overrides[0].previousSource | Should -Be 'global/settings.jsonc'
        $manifest.machineOverlay.valuesRecorded | Should -BeFalse
        $manifest.settingsSyncPolicy | Should -Be 'machine-settings-ignored-and-applied-to-all-profiles'
    }

    It 'rejects machine overlays that try to manage composer-owned lists' {
        $fixture = New-ComposerFixture 'machine-ownership-list'
        Write-TestFile (Join-Path $fixture 'machine/local/test.jsonc') '{ "settingsSync.ignoredSettings": ["something"] }'
        (Test-ComposerRepository $fixture -Machine test).errors.code | Should -Contain 'machine-ownership-setting'
    }

    It 'omits globally applied settings from generated named profiles' {
        $fixture = New-ComposerFixture 'global-not-in-profile'
        Invoke-ProfileComposition $fixture main -Platform windows | Out-Null
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/settings.json')))
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
        $recipe.Components | Should -Be @('main', 'cpp', 'unreal')
    }

    It 'uses the configured shared default as the first component in every recipe' {
        $sharedDefault = Get-SharedDefaultComponent $script:RepositoryRoot
        $sharedDefault | Should -BeExactly 'main'
        foreach ($definition in Get-ProfileDefinitions $script:RepositoryRoot) {
            $recipe = Read-ProfileRecipe $definition.Path
            $recipe.Components[0] | Should -BeExactly $sharedDefault
            @($recipe.Components | Where-Object { $_ -ieq $sharedDefault }).Count | Should -Be 1
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
        Write-TestFile (Join-Path $fixture 'profiles/broken.yaml') "name: Broken`ncomponents: [main]`n"
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'invalid-yaml'
    }

    It 'detects duplicate component IDs in a recipe' {
        $fixture = New-ComposerFixture 'duplicate-components'
        Write-TestFile (Join-Path $fixture 'profiles/broken.yaml') "name: Broken`ncomponents:`n  - main`n  - MAIN`n"
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'duplicate-recipe-component'
    }

    It 'detects absolute personal paths in portable settings' {
        $fixture = New-ComposerFixture 'absolute-path'
        Write-TestFile (Join-Path $fixture 'components/main/settings.jsonc') '{ "tool.path": "C:\\Users\\person\\tool.exe" }'
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'portable-absolute-path'
    }

    It 'detects likely secrets in portable settings' {
        $fixture = New-ComposerFixture 'secret'
        Write-TestFile (Join-Path $fixture 'components/main/settings.jsonc') '{ "service.apiKey": "not-a-real-key-but-must-not-be-portable" }'
        $result = Test-ComposerRepository $fixture
        $result.errors.code | Should -Contain 'portable-likely-secret'
    }

    It 'passes repository-wide validation for the current source' {
        $result = Test-ComposerRepository $script:RepositoryRoot
        $result.errors.Count | Should -Be 0
    }
}

Describe 'Repository keybinding ownership' {
    It 'inherits the shared custom bindings through Main' {
        $fixture = New-ComposerFixture 'shared-keybindings'
        Invoke-ProfileComposition $fixture main -Platform windows | Out-Null
        $bindings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/keybindings.json')))
        $bindings.Count | Should -Be 22
        $bindings.command | Should -Contain 'cSpell.suggestSpellingCorrections'
        $bindings.command | Should -Contain 'editor.foldAll'
        $bindings.command | Should -Contain 'workbench.action.toggleMaximizedPanel'
        $bindings.command | Should -Not -Contain 'mssql.rebuildIntelliSenseCache'
        $spellBinding = @($bindings | Where-Object command -eq 'cSpell.suggestSpellingCorrections')
        $spellBinding.Count | Should -Be 1
        $spellBinding[0].key | Should -BeExactly 'ctrl+shift+s'
        @($bindings | ForEach-Object { $_ | ConvertTo-Json -Depth 100 -Compress } | Sort-Object -Unique).Count | Should -Be $bindings.Count
    }

    It 'adds SQL Server-only bindings only to recipes that declare that component' {
        $fixture = New-ComposerFixture 'focused-keybindings'
        Invoke-ProfileComposition $fixture sql-server -Platform windows | Out-Null
        Invoke-ProfileComposition $fixture python -Platform windows | Out-Null
        $sqlBindings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/sql-server/keybindings.json')))
        $pythonBindings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/python/keybindings.json')))
        $sqlBindings.Count | Should -Be 23
        $sqlBindings.command | Should -Contain 'mssql.rebuildIntelliSenseCache'
        $pythonBindings.command | Should -Not -Contain 'mssql.rebuildIntelliSenseCache'
    }
}

Describe 'Safe repository transformations' {
    It 'dry-runs and applies a profile rename with its optional override and stored UI-state seed' {
        $fixture = New-ComposerFixture 'rename-profile'
        Write-TestFile (Join-Path $fixture 'profiles/python.settings.jsonc') '{ "python.analysis.typeCheckingMode": "strict" }'
        Write-TestFile (Join-Path $fixture 'profiles/python.settings.replace.jsonc') '{ "python.analysis.diagnosticMode": "workspace" }'
        Write-TestFile (Join-Path $fixture 'profiles/python.settings.remove.jsonc') '["python.analysis.autoImportCompletions"]'
        Write-TestFile (Join-Path $fixture 'profiles/python.extensions.jsonc') '{ "add": ["sample.extension"], "remove": [] }'
        Write-TestFile (Join-Path $fixture 'profiles/python.keybindings.jsonc') '{ "add": [{"key":"ctrl+alt+p","command":"sample.command"}], "remove": [] }'
        Write-TestFile (Join-Path $fixture 'machine/local/ui-state/python/seed.code-profile') '{ "name": "seed", "globalState": "{\"layout\":true}" }'

        $plan = Rename-ComposerProfile $fixture python python-work -DryRun
        $plan.changes.source | Should -Contain 'profiles/python.yaml'
        $plan.changes.source | Should -Contain 'profiles/python.settings.jsonc'
        $plan.changes.source | Should -Contain 'profiles/python.settings.replace.jsonc'
        $plan.changes.source | Should -Contain 'profiles/python.settings.remove.jsonc'
        $plan.changes.source | Should -Contain 'profiles/python.extensions.jsonc'
        $plan.changes.source | Should -Contain 'profiles/python.keybindings.jsonc'
        $plan.changes.source | Should -Contain 'machine/local/ui-state/python'
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.yaml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python-work.yaml') | Should -BeFalse

        Rename-ComposerProfile $fixture python python-work | Out-Null
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.yaml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python-work.yaml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python-work.settings.jsonc') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python-work.settings.replace.jsonc') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python-work.settings.remove.jsonc') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python-work.extensions.jsonc') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python-work.keybindings.jsonc') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'machine/local/ui-state/python-work/seed.code-profile') | Should -BeTrue
        (Test-ComposerRepository $fixture).errors.Count | Should -Be 0
    }

    It 'renames a component, preserves recipe order, and updates configured-default ownership' {
        $fixture = New-ComposerFixture 'rename-component'
        $before = (Read-ProfileRecipe (Join-Path $fixture 'profiles/unreal.yaml')).Components
        $plan = Rename-ComposerComponent $fixture main shared -DryRun
        $plan.changes.target | Should -Contain 'components/shared'
        Get-SharedDefaultComponent $fixture | Should -BeExactly 'main'

        Rename-ComposerComponent $fixture main shared | Out-Null
        Test-Path -LiteralPath (Join-Path $fixture 'components/main') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixture 'components/shared') | Should -BeTrue
        Get-SharedDefaultComponent $fixture | Should -BeExactly 'shared'
        $after = (Read-ProfileRecipe (Join-Path $fixture 'profiles/unreal.yaml')).Components
        $after | Should -Be @('shared', $before[1], $before[2])
        (Test-ComposerRepository $fixture).errors.Count | Should -Be 0
    }

    It 'sets the shared default first without duplicates and preserves remaining order' {
        $fixture = New-ComposerFixture 'set-default'
        $before = (Read-ProfileRecipe (Join-Path $fixture 'profiles/python-database.yaml')).Components
        $plan = Set-SharedDefaultComponent $fixture database -DryRun
        $plan.changes.target | Should -Contain 'composer.jsonc'
        Get-SharedDefaultComponent $fixture | Should -BeExactly 'main'

        Set-SharedDefaultComponent $fixture database | Out-Null
        Get-SharedDefaultComponent $fixture | Should -BeExactly 'database'
        $after = (Read-ProfileRecipe (Join-Path $fixture 'profiles/python-database.yaml')).Components
        $after | Should -Be @('database', $before[0], $before[1])
        @($after | Where-Object { $_ -ieq 'database' }).Count | Should -Be 1
        foreach ($definition in Get-ProfileDefinitions $fixture) {
            (Read-ProfileRecipe $definition.Path).Components[0] | Should -BeExactly 'database'
        }
        (Test-ComposerRepository $fixture).errors.Count | Should -Be 0
    }

    It 'refuses ID collisions without changing source paths' {
        $fixture = New-ComposerFixture 'rename-collision'
        $before = [System.IO.File]::ReadAllText((Join-Path $fixture 'profiles/python.yaml'))
        { Rename-ComposerProfile $fixture python main } | Should -Throw '*already exists*'
        { Rename-ComposerComponent $fixture python main } | Should -Throw '*already exists*'
        [System.IO.File]::ReadAllText((Join-Path $fixture 'profiles/python.yaml')) | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $fixture 'components/python') | Should -BeTrue
    }

    It 'rolls back every swapped source path when post-commit validation fails' {
        $fixture = New-ComposerFixture 'rename-rollback'
        $beforeRecipe = [System.IO.File]::ReadAllText((Join-Path $fixture 'profiles/unreal.yaml'))
        InModuleScope ProfileComposer -Parameters @{ FixtureRoot = $fixture } {
            param($FixtureRoot)
            $script:ValidationCall = 0
            Mock Test-ComposerRepository {
                $script:ValidationCall++
                $errors = [System.Collections.Generic.List[object]]::new()
                if ($script:ValidationCall -eq 3) { $errors.Add([pscustomobject]@{ code = 'forced'; message = 'forced post-commit failure' }) }
                [pscustomobject]@{
                    errors = $errors
                    warnings = [System.Collections.Generic.List[object]]::new()
                    information = [System.Collections.Generic.List[object]]::new()
                }
            }
            { Rename-ComposerComponent $FixtureRoot cpp native-cpp } | Should -Throw '*rolled back*'
        }
        Test-Path -LiteralPath (Join-Path $fixture 'components/cpp') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'components/native-cpp') | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $fixture 'profiles/unreal.yaml')) | Should -BeExactly $beforeRecipe
    }

    It 'detects missing configured defaults and recipe/default inconsistencies' {
        $fixture = New-ComposerFixture 'invalid-default-ownership'
        Write-TestFile (Join-Path $fixture 'composer.jsonc') '{ "sharedDefaultComponent": "missing" }'
        (Test-ComposerRepository $fixture).errors.code | Should -Contain 'missing-shared-default-component'
        Write-TestFile (Join-Path $fixture 'composer.jsonc') '{ "sharedDefaultComponent": "main" }'
        Write-TestFile (Join-Path $fixture 'profiles/python.yaml') "name: Python`ncomponents:`n  - python`n  - main`n"
        (Test-ComposerRepository $fixture).errors.code | Should -Contain 'shared-default-not-first'
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
        Write-TestFile (Join-Path $fixture 'profiles/main.settings.jsonc') '{ "terminal.integrated.defaultProfile.windows": "Profile Shell" }'
        Invoke-ProfileComposition $fixture main -Platform windows | Out-Null
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/settings.json')))
        $settings['terminal.integrated.defaultProfile.windows'] | Should -Be 'PowerShell 7'
    }

    It 'omits machine-owned settings from named profiles even when a platform declares them' {
        $fixture = New-ComposerFixture 'machine-order'
        $machine = Join-Path $fixture 'machine/local/test.jsonc'
        Write-TestFile $machine '{ "terminal.integrated.defaultProfile.windows": "Machine Shell" }'
        Invoke-ProfileComposition $fixture main -Platform windows -MachineFile $machine | Out-Null
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/settings.json')))
        $settings.Contains('terminal.integrated.defaultProfile.windows') | Should -BeFalse
    }

    It 'selects a named machine overlay and records application-level delivery' {
        $fixture = New-ComposerFixture 'named-machine'
        Write-TestFile (Join-Path $fixture 'machine/local/gaming-server.jsonc') '{ "todo-tree.ripgrep.ripgrep": "D:\\Tools\\rg.exe" }'
        $result = Invoke-ProfileComposition $fixture main -Platform windows -Machine gaming-server
        $settings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/settings.json')))
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/manifest.json')))
        $settings.Contains('todo-tree.ripgrep.ripgrep') | Should -BeFalse
        $result.machineId | Should -Be 'gaming-server'
        $manifest.machineOverlay.id | Should -Be 'gaming-server'
        $manifest.machineOverlay.selection | Should -Be 'named-machine'
        $manifest.machineOverlay.appliedTo | Should -Be 'build/global/settings.json'
        $manifest.machineOverlay.includedInProfileSettings | Should -BeFalse
    }

    It 'lists named machines and rejects missing or conflicting selections' {
        $fixture = New-ComposerFixture 'machine-selection-validation'
        Write-TestFile (Join-Path $fixture 'machine/local/main-windows.jsonc') '{}'
        (Get-MachineDefinitions $fixture).Id | Should -Contain 'main-windows'
        (Test-ComposerRepository $fixture -Machine missing).errors.code | Should -Contain 'missing-machine-overlay'
        { Invoke-ProfileComposition $fixture main -Machine main-windows -MachineFile './machine/local/main-windows.jsonc' } | Should -Throw '*cannot be used together*'
    }

    It 'replaces only the generated target directory' {
        $fixture = New-ComposerFixture 'safe-replace'
        Invoke-ProfileComposition $fixture main | Out-Null
        $sentinel = Join-Path $fixture 'build/profiles/main/stale.txt'
        Write-TestFile $sentinel 'stale'
        Invoke-ProfileComposition $fixture main | Out-Null
        Test-Path -LiteralPath $sentinel | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixture 'build/profiles/main/manifest.json') | Should -BeTrue
    }

    It 'preserves the previous valid output when composition fails' {
        $fixture = New-ComposerFixture 'failed-preserves'
        Invoke-ProfileComposition $fixture main | Out-Null
        $settingsPath = Join-Path $fixture 'build/profiles/main/settings.json'
        $before = [System.IO.File]::ReadAllText($settingsPath)
        Write-TestFile (Join-Path $fixture 'components/main/settings.jsonc') '{ invalid jsonc'
        { Invoke-ProfileComposition $fixture main } | Should -Throw
        [System.IO.File]::ReadAllText($settingsPath) | Should -BeExactly $before
    }

    It 'does not create output during dry run' {
        $fixture = New-ComposerFixture 'dry-run'
        $result = Invoke-ProfileComposition $fixture main -Platform windows -DryRun
        $result.dryRun | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'build') | Should -BeFalse
    }
}

Describe 'Current profile acceptance compositions' {
    It 'composes the current Main profile in isolation' {
        $fixture = New-ComposerFixture 'compose-main'
        { Invoke-ProfileComposition $fixture main -Platform windows } | Should -Not -Throw
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
        Invoke-ProfileComposition $fixture main -Platform windows | Out-Null
        $output = Join-Path $fixture 'build/profiles/main'
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

    It 'generates an export for Main' {
        $fixture = New-ComposerFixture 'export-main'
        $result = Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile
        $result.codeProfileExportPath | Should -Be 'build/profiles/main/Main.code-profile'
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
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/main'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Main.code-profile')))
        $resource = ConvertFrom-JsonC $profile.settings
        $resource.settings | Should -BeExactly ([System.IO.File]::ReadAllText((Join-Path $output 'settings.json')))
    }

    It 'converts extension IDs to VS Code identifier resources' {
        $fixture = New-ComposerFixture 'export-extensions'
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/main'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Main.code-profile')))
        $resources = ConvertFrom-JsonC $profile.extensions
        $expected = [System.IO.File]::ReadAllLines((Join-Path $output 'extensions.txt'))[0]
        $resources[0].identifier.id | Should -BeExactly $expected
        $resources[0].identifier.Contains('uuid') | Should -BeFalse
    }

    It 'embeds generated keybindings and Windows platform metadata' {
        $fixture = New-ComposerFixture 'export-keybindings'
        Write-TestFile (Join-Path $fixture 'components/main/keybindings.jsonc') '[{ "key": "ctrl+alt+t", "command": "workbench.action.files.newUntitledFile" }]'
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/main'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Main.code-profile')))
        $resource = ConvertFrom-JsonC $profile.keybindings
        $keys = ConvertFrom-JsonC $resource.keybindings
        $keys[0].command | Should -Be 'workbench.action.files.newUntitledFile'
        $resource.platform | Should -Be 3
    }

    It 'uses VS Code empty-array keybinding representation when no bindings exist' {
        $fixture = New-ComposerFixture 'export-empty-keybindings'
        Write-TestFile (Join-Path $fixture 'components/main/keybindings.jsonc') '[]'
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile | Out-Null
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/Main.code-profile')))
        $resource = ConvertFrom-JsonC $profile.keybindings
        $keys = ConvertFrom-JsonC $resource.keybindings
        $keys -is [System.Array] | Should -BeTrue
        $keys.Count | Should -Be 0
    }

    It 'keeps explicitly requested machine settings out of portable exports' {
        $fixture = New-ComposerFixture 'export-machine'
        $machine = Join-Path $fixture 'machine/local/test.jsonc'
        Write-TestFile $machine '{ "terminal.integrated.defaultProfile.windows": "Machine Shell" }'
        Invoke-ProfileComposition $fixture main -Platform windows -MachineFile $machine -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/main'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Main.code-profile')))
        $settingsResource = ConvertFrom-JsonC $profile.settings
        $settings = ConvertFrom-JsonC $settingsResource.settings
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'manifest.json')))
        $settings.Contains('terminal.integrated.defaultProfile.windows') | Should -BeFalse
        $manifest.codeProfileExport.machineOverlayIncluded | Should -BeFalse
        $manifest.codeProfileExport.machineSettingsDelivery | Should -Be 'built-in-default-application-settings'
        $manifest.codeProfileExport.portability | Should -Be 'portable'
    }

    It 'classifies an export without a machine overlay as portable' {
        $fixture = New-ComposerFixture 'export-portable'
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile | Out-Null
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/manifest.json')))
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
        Write-TestFile (Join-Path $fixture 'profiles/escape.yaml') "name: ../escape`ncomponents:`n  - main`n"
        $validation = Test-ComposerRepository $fixture
        $validation.errors.code | Should -Contain 'invalid-export-filename'
    }

    It 'reports the planned export but writes nothing during dry run' {
        $fixture = New-ComposerFixture 'export-dry-run'
        $result = Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile -DryRun
        $result.codeProfileExportPath | Should -Be 'build/profiles/main/Main.code-profile'
        Test-Path -LiteralPath (Join-Path $fixture 'build') | Should -BeFalse
    }

    It 'preserves the previous valid export when a later generation fails' {
        $fixture = New-ComposerFixture 'export-failed-preserves'
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile | Out-Null
        $exportPath = Join-Path $fixture 'build/profiles/main/Main.code-profile'
        $before = [System.IO.File]::ReadAllText($exportPath)
        Write-TestFile (Join-Path $fixture 'components/main/settings.jsonc') '{ invalid jsonc'
        { Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile } | Should -Throw
        [System.IO.File]::ReadAllText($exportPath) | Should -BeExactly $before
    }

    It 'records the exact export hash and schema metadata in the manifest' {
        $fixture = New-ComposerFixture 'export-hash'
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile | Out-Null
        $output = Join-Path $fixture 'build/profiles/main'
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'manifest.json')))
        $actual = (Get-FileHash -LiteralPath (Join-Path $output 'Main.code-profile') -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest.codeProfileExport.sha256 | Should -BeExactly $actual
        $manifest.codeProfileExport.schema | Should -Be 'vscode-user-data-profile-template'
        $manifest.codeProfileExport.schemaVersion | Should -Be 'unversioned'
    }

    It 'parses generated exports as valid JSON and validates nested resources' {
        $fixture = New-ComposerFixture 'export-valid-json'
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile | Out-Null
        $path = Join-Path $fixture 'build/profiles/main/Main.code-profile'
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
        Write-TestFile (Join-Path $fixture 'profiles/sensitive.yaml') "name: `"token=abcdefghijklmnop`"`ncomponents:`n  - main`n"
        (Test-ComposerRepository $fixture).errors.code | Should -Contain 'sensitive-profile-metadata'
    }

    It 'fails closed on unknown export fields instead of discarding newer data' {
        $path = Join-Path $TestDrive 'unknown-export-field.code-profile'
        $template = New-CodeProfileTemplate -DisplayName 'Fixture' -SettingsJson '{}' -Extensions @() -KeybindingsJson '[]' -Platform windows
        $template['futureResource'] = '{"value":true}'
        Write-TestFile $path (ConvertTo-Json -InputObject $template -Depth 20)
        { Test-CodeProfileTemplate $path } | Should -Throw '*unsupported metadata field*futureResource*'
    }

    It 'omits UI state and rejects accidental UI-state source files' {
        $fixture = New-ComposerFixture 'export-no-ui-state'
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile | Out-Null
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/Main.code-profile')))
        $profile.Contains('globalState') | Should -BeFalse
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/main/manifest.json')))
        $manifest.codeProfileExport.uiStatePolicy | Should -Be 'managed-by-vscode'
        Write-TestFile (Join-Path $fixture 'components/main/ui-state.jsonc') '{}'
        (Test-ComposerRepository $fixture).errors.code | Should -Contain 'unsupported-ui-state-source'
    }

    It 'copies an explicitly supplied UI-state seed without copying other resources' {
        $fixture = New-ComposerFixture 'export-ui-seed'
        $seedPath = Join-Path $TestDrive 'layout-seed.code-profile'
        $expectedGlobalState = New-UiStateSeedExport $seedPath
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile -UiStateFromProfile $seedPath | Out-Null

        $output = Join-Path $fixture 'build/profiles/main'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Main.code-profile')))
        $settings = ConvertFrom-JsonC (ConvertFrom-JsonC $profile.settings).settings
        $extensionIds = @((ConvertFrom-JsonC $profile.extensions) | ForEach-Object { $_.identifier.id })
        $profile.globalState | Should -BeExactly $expectedGlobalState
        $settings.Contains('seed.setting.mustBeIgnored') | Should -BeFalse
        $extensionIds | Should -Not -Contain 'seed.extension-must-be-ignored'
        Test-CodeProfileTemplate (Join-Path $output 'Main.code-profile') | Should -BeTrue
    }

    It 'stores only UI state under ignored local profile data and reuses it by profile ID' {
        $fixture = New-ComposerFixture 'stored-ui-state'
        $sourcePath = Join-Path $TestDrive 'adjusted-main.code-profile'
        $expectedGlobalState = New-UiStateSeedExport $sourcePath

        $saved = Save-ProfileUiStateSeed -RepositoryRoot $fixture -Profile main -SourceProfileExport $sourcePath
        $storedPath = Join-Path $fixture $saved.outputPath
        $storedText = [System.IO.File]::ReadAllText($storedPath)
        $stored = ConvertFrom-JsonC $storedText
        $stored.Keys | Should -Be @('name', 'globalState')
        $stored.globalState | Should -BeExactly $expectedGlobalState
        $storedText | Should -Not -Match ([regex]::Escape($sourcePath))

        Invoke-ProfileComposition $fixture python-database -Platform windows -ExportCodeProfile -UiStateProfile main | Out-Null
        $output = Join-Path $fixture 'build/profiles/python-database'
        $profile = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'Python-Database.code-profile')))
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'manifest.json')))
        $profile.globalState | Should -BeExactly $expectedGlobalState
        $manifest.codeProfileExport.uiStateSeed.source | Should -Be 'stored-local-profile-ui-state'
        $manifest.codeProfileExport.uiStateSeed.profileId | Should -Be 'main'
    }

    It 'validates stored UI-state capture and selection without partial writes' {
        $fixture = New-ComposerFixture 'stored-ui-state-validation'
        $sourcePath = Join-Path $TestDrive 'valid-source.code-profile'
        New-UiStateSeedExport $sourcePath | Out-Null

        $storedDirectory = Join-Path $fixture 'machine/local/ui-state/main'
        $storedPath = Join-Path $storedDirectory 'seed.code-profile'
        $existedBefore = Test-Path -LiteralPath $storedPath -PathType Leaf
        $contentBefore = if ($existedBefore) { [System.IO.File]::ReadAllText($storedPath) } else { $null }

        $preview = Save-ProfileUiStateSeed -RepositoryRoot $fixture -Profile main -SourceProfileExport $sourcePath -DryRun
        $preview.dryRun | Should -BeTrue
        (Test-Path -LiteralPath $storedPath -PathType Leaf) | Should -Be $existedBefore
        if ($existedBefore) { [System.IO.File]::ReadAllText($storedPath) | Should -BeExactly $contentBefore }
        { Save-ProfileUiStateSeed -RepositoryRoot $fixture -Profile missing -SourceProfileExport $sourcePath } | Should -Throw '*Unknown profile*'
        { Invoke-ProfileComposition $fixture main -UiStateProfile main } | Should -Throw '*requires -ExportCodeProfile*'
        Write-TestFile (Join-Path $fixture 'profiles/no-ui-seed.yaml') "name: No UI Seed`ncomponents:`n  - main`n"
        { Invoke-ProfileComposition $fixture no-ui-seed -ExportCodeProfile -UiStateProfile no-ui-seed } | Should -Throw '*does not exist*'
        { Invoke-ProfileComposition $fixture main -ExportCodeProfile -UiStateProfile main -UiStateFromProfile $sourcePath } | Should -Throw '*cannot be used together*'
    }

    It 'records only UI-state seed policy and content hash, never its source path' {
        $fixture = New-ComposerFixture 'export-ui-seed-manifest'
        $privateDirectory = Join-Path $TestDrive 'personal-private-location'
        $seedPath = Join-Path $privateDirectory 'signed-in-layout.code-profile'
        $globalState = New-UiStateSeedExport $seedPath
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile -UiStateFromProfile $seedPath | Out-Null

        $output = Join-Path $fixture 'build/profiles/main'
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
        { Invoke-ProfileComposition $fixture main -UiStateFromProfile $missing } | Should -Throw '*requires -ExportCodeProfile*'
        { Invoke-ProfileComposition $fixture main -ExportCodeProfile -UiStateFromProfile $missing } | Should -Throw '*does not exist*'

        $noState = Join-Path $TestDrive 'no-state.code-profile'
        Write-TestFile $noState '{"name":"No State"}'
        { Invoke-ProfileComposition $fixture main -ExportCodeProfile -UiStateFromProfile $noState } | Should -Throw '*does not contain*globalState*'

        $malformedState = Join-Path $TestDrive 'malformed-state.code-profile'
        New-UiStateSeedExport $malformedState -GlobalState '{bad json' | Out-Null
        { Invoke-ProfileComposition $fixture main -ExportCodeProfile -UiStateFromProfile $malformedState } | Should -Throw '*Invalid JSONC*globalState*'
    }

    It 'validates a UI-state seed during dry run without writing output' {
        $fixture = New-ComposerFixture 'export-ui-seed-dry-run'
        $seedPath = Join-Path $TestDrive 'dry-layout.code-profile'
        New-UiStateSeedExport $seedPath | Out-Null
        $result = Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile -UiStateFromProfile $seedPath -DryRun
        $result.uiStateSeeded | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'build') | Should -BeFalse
    }

    It 'preserves the previous valid seeded export when a later UI seed is invalid' {
        $fixture = New-ComposerFixture 'export-ui-seed-failed-preserves'
        $seedPath = Join-Path $TestDrive 'valid-layout.code-profile'
        New-UiStateSeedExport $seedPath | Out-Null
        Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile -UiStateFromProfile $seedPath | Out-Null
        $exportPath = Join-Path $fixture 'build/profiles/main/Main.code-profile'
        $before = [System.IO.File]::ReadAllText($exportPath)

        $badSeedPath = Join-Path $TestDrive 'bad-layout.code-profile'
        New-UiStateSeedExport $badSeedPath -GlobalState '[]' | Out-Null
        { Invoke-ProfileComposition $fixture main -Platform windows -ExportCodeProfile -UiStateFromProfile $badSeedPath } | Should -Throw '*must be an object*'
        [System.IO.File]::ReadAllText($exportPath) | Should -BeExactly $before
    }

    It 'keeps ordinary composition export-free and otherwise unchanged' {
        $fixture = New-ComposerFixture 'non-export-unchanged'
        Invoke-ProfileComposition $fixture main -Platform windows | Out-Null
        $output = Join-Path $fixture 'build/profiles/main'
        @(Get-ChildItem -LiteralPath $output -Filter '*.code-profile').Count | Should -Be 0
        $manifest = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $output 'manifest.json')))
        $manifest.codeProfileExportRequested | Should -BeFalse
        $manifest.codeProfileExport | Should -BeNullOrEmpty
    }
}

Describe 'Unified CLI and compatibility wrappers' {
    It 'shows general and command-specific help with examples' {
        $cli = Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.ps1'
        $general = @(& pwsh -NoProfile -File $cli help 2>&1)
        $LASTEXITCODE | Should -Be 0
        $general -join "`n" | Should -Match 'rename-component'
        $general -join "`n" | Should -Match 'fix global'
        $specific = @(& pwsh -NoProfile -File $cli help compose 2>&1)
        $LASTEXITCODE | Should -Be 0
        $specific -join "`n" | Should -Match 'Python-Database|python-database'
        $fixHelp = @(& pwsh -NoProfile -File $cli help fix 2>&1)
        $LASTEXITCODE | Should -Be 0
        $fixHelp -join "`n" | Should -Match 'removes duplicate'
    }

    It 'dispatches list, validation, and dry-run rename commands against an isolated fixture' {
        $fixture = New-ComposerFixture 'cli-dispatch'
        $cli = Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.ps1'
        $list = @(& pwsh -NoProfile -File $cli list profiles -RepositoryRoot $fixture 2>&1)
        $LASTEXITCODE | Should -Be 0
        $list -join "`n" | Should -Match 'python-database'
        $validation = @(& pwsh -NoProfile -File $cli validate -RepositoryRoot $fixture -Strict 2>&1)
        $LASTEXITCODE | Should -Be 0
        $validation -join "`n" | Should -Match '0 error'
        $compose = @(& pwsh -NoProfile -File $cli compose main -RepositoryRoot $fixture -Platform windows -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $compose -join "`n" | Should -Match "planned 'main'"
        $rename = @(& pwsh -NoProfile -File $cli rename profile python python-work -RepositoryRoot $fixture -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $rename -join "`n" | Should -Match 'MOVE profiles/python.yaml -> profiles/python-work.yaml'
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.yaml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python-work.yaml') | Should -BeFalse

        $globalPath = Join-Path $fixture 'global/settings.jsonc'
        $globalSettings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($globalPath))
        $globalSettings['fixture.cliUnlisted'] = $true
        Write-TestFile $globalPath (ConvertTo-Json -InputObject $globalSettings -Depth 100)
        $fix = @(& pwsh -NoProfile -File $cli fix global -RepositoryRoot $fixture -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $fix -join "`n" | Should -Match 'Added missing ownership: fixture.cliUnlisted'
        (ConvertFrom-JsonC ([System.IO.File]::ReadAllText($globalPath)))['workbench.settings.applyToAllProfiles'] |
            Should -Not -Contain 'fixture.cliUnlisted'
    }

    It 'returns nonzero with an actionable error for invalid dispatch' {
        $cli = Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.ps1'
        $output = @(& pwsh -NoProfile -File $cli definitely-not-a-command 2>&1)
        $LASTEXITCODE | Should -Be 1
        $output -join "`n" | Should -Match 'Unknown command'
        $output -join "`n" | Should -Match 'help'
    }

    It 'keeps both legacy entry scripts usable as dry-run wrappers' {
        $compose = Join-Path $script:RepositoryRoot 'scripts/Compose-Profile.ps1'
        $composeOutput = @(& pwsh -NoProfile -File $compose -Profile main -Platform windows -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $composeOutput -join "`n" | Should -Match 'DRY RUN'

        $seed = Join-Path $TestDrive 'wrapper-seed.code-profile'
        Write-TestFile $seed '{ "name": "seed", "globalState": "{\"layout\":true}" }'
        $save = Join-Path $script:RepositoryRoot 'scripts/Save-ProfileUiState.ps1'
        $saveOutput = @(& pwsh -NoProfile -File $save -Profile main -SourceProfileExport $seed -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $saveOutput -join "`n" | Should -Match 'DRY RUN'
    }
}

Describe 'VS Code profile guidance and automatic UI-state capture selection' {
    It 'lists live profile metadata without reading profile resource values' {
        $userDataPath = New-VSCodeUserDataFixture 'live-profile-list'
        $profiles = @(Get-LiveVSCodeProfileDefinitions -VSCodeUserDataPath $userDataPath)

        $profiles.Name | Should -Be @('Default', 'Main', 'Python')
        $profiles[0].IsDefault | Should -BeTrue
        $profiles[1].Id | Should -BeExactly 'main-id'
        $profiles[2].Id | Should -BeExactly 'python-id'
        $profiles.PSObject.Properties.Name | Should -Not -Contain 'Settings'
    }

    It 'matches exactly one active VS Code display name to its repository recipe' {
        $fixture = New-ComposerFixture 'active-profile-match'
        $status = '    0  120  1234  window [1] (main.py - Project - Python + Database - Visual Studio Code)'
        $match = Resolve-ComposerProfileFromVSCodeStatus -RepositoryRoot $fixture -StatusText $status

        $match.ProfileId | Should -BeExactly 'python-database'
        $match.DisplayName | Should -BeExactly 'Python + Database'
    }

    It 'requires an explicit recipe when active names have zero or multiple matches' {
        $fixture = New-ComposerFixture 'active-profile-ambiguous'
        { Resolve-ComposerProfileFromVSCodeStatus -RepositoryRoot $fixture -StatusText 'window [1] (Project - Unknown Profile - Visual Studio Code)' } |
            Should -Throw '*Supply the profile ID explicitly*'

        Write-TestFile (Join-Path $fixture 'profiles/python-duplicate.yaml') "name: Python`ncomponents:`n  - main`n"
        { Resolve-ComposerProfileFromVSCodeStatus -RepositoryRoot $fixture -StatusText 'window [1] (Project - Python - Visual Studio Code)' } |
            Should -Throw '*multiple repository recipes*'
    }

    It 'captures UI state by an automatically matched active recipe in an isolated fixture' {
        $fixture = New-ComposerFixture 'capture-auto-profile'
        $sourcePath = Join-Path $TestDrive 'auto-profile-seed.code-profile'
        Write-TestFile $sourcePath '{ "name": "Private Export", "globalState": "{\"layout\":true}" }'
        $fakeCode = Join-Path $TestDrive 'fake-code-status.ps1'
        Write-TestFile $fakeCode @'
'    0  120  1234  window [1] (main.py - Project - Python + Database - Visual Studio Code)'
'@
        $cli = Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.ps1'
        $output = @(& pwsh -NoProfile -File $cli capture-ui-state $sourcePath -CodeCommand $fakeCode -RepositoryRoot $fixture -DryRun 2>&1)

        $LASTEXITCODE | Should -Be 0
        $output -join "`n" | Should -Match "Matched active VS Code profile 'Python \+ Database'"
        $output -join "`n" | Should -Match "UI state for 'python-database'"
        Test-Path -LiteralPath (Join-Path $fixture 'machine/local/ui-state/python-database/seed.code-profile') | Should -BeFalse
    }

    It 'dispatches guided live-profile commands only against isolated metadata' {
        $fixture = New-ComposerFixture 'vscode-guidance'
        $userDataPath = New-VSCodeUserDataFixture 'vscode-guidance-user-data'
        $cli = Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.ps1'

        $list = @(& pwsh -NoProfile -File $cli vscode list -VSCodeUserDataPath $userDataPath 2>&1)
        $LASTEXITCODE | Should -Be 0
        $list -join "`n" | Should -Match 'Main \[location main-id\]'

        $open = @(& pwsh -NoProfile -File $cli vscode open Main -VSCodeUserDataPath $userDataPath -CodeCommand code -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $open -join "`n" | Should -Match 'code --new-window --profile Main'

        $import = @(& pwsh -NoProfile -File $cli vscode import python-database -RepositoryRoot $fixture -Platform windows -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $import -join "`n" | Should -Match "recipe 'python-database'"
        $import -join "`n" | Should -Match 'Profiles: Import Profile'

        $replace = @(& pwsh -NoProfile -File $cli vscode replace python-database -LiveProfile Main -VSCodeUserDataPath $userDataPath -RepositoryRoot $fixture -Platform windows -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $replace -join "`n" | Should -Match 'Live target: Main'
        $replace -join "`n" | Should -Match 'No live VS Code profile'

        $delete = @(& pwsh -NoProfile -File $cli vscode delete Main -VSCodeUserDataPath $userDataPath -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $delete -join "`n" | Should -Match "deletion target 'Main'"
    }

    It 'protects built-in and missing live profiles from guided destructive actions' {
        $userDataPath = New-VSCodeUserDataFixture 'vscode-guidance-errors'
        $cli = Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.ps1'

        $defaultDelete = @(& pwsh -NoProfile -File $cli vscode delete Default -VSCodeUserDataPath $userDataPath -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 1
        $defaultDelete -join "`n" | Should -Match 'cannot be deleted'

        $missingDelete = @(& pwsh -NoProfile -File $cli vscode delete Missing -VSCodeUserDataPath $userDataPath -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 1
        $missingDelete -join "`n" | Should -Match 'was not found'
    }
}

Describe 'Profile export synchronization' {
    It 'syncs recipe deltas, application-owned settings, and opaque UI state transactionally' {
        $fixture = New-ComposerFixture 'sync-profile-export'
        Invoke-ProfileComposition $fixture python -Platform windows -ExportCodeProfile | Out-Null
        $generatedExport = Join-Path $fixture 'build/profiles/python/Python.code-profile'
        $template = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($generatedExport))

        $settingsResource = ConvertFrom-JsonC $template.settings
        $liveSettings = ConvertFrom-JsonC $settingsResource.settings
        $componentSettings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'components/main/settings.jsonc')))
        $removedSetting = [string]@($componentSettings.Keys)[0]
        $liveSettings.Remove($removedSetting)
        $liveSettings['sync.fixture.setting'] = [ordered]@{ enabled = $true; modes = @('one', 'two') }
        $liveSettings['machine.fixture.path'] = 'C:\Private\tool.exe'
        $settingsResource.settings = ConvertTo-Json -InputObject $liveSettings -Depth 100
        $template.settings = ConvertTo-Json -InputObject $settingsResource -Depth 100 -Compress

        $liveExtensions = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in (ConvertFrom-JsonC $template.extensions)) { $liveExtensions.Add($entry) }
        $removedExtension = [string]$liveExtensions[0].identifier.id
        $liveExtensions.RemoveAt(0)
        $liveExtensions.Add([ordered]@{ identifier = [ordered]@{ id = 'sample.synced-extension' } })
        $template.extensions = ConvertTo-Json -InputObject ([object[]]$liveExtensions.ToArray()) -Depth 100 -Compress

        $keybindingResource = ConvertFrom-JsonC $template.keybindings
        $liveKeybindings = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in (ConvertFrom-JsonC $keybindingResource.keybindings)) { $liveKeybindings.Add($entry) }
        $lastBinding = $liveKeybindings[$liveKeybindings.Count - 1]
        $liveKeybindings.RemoveAt($liveKeybindings.Count - 1)
        $liveKeybindings.Insert(0, $lastBinding)
        $liveKeybindings.Add([ordered]@{ key = 'ctrl+alt+y'; command = 'sample.syncedCommand' })
        $keybindingResource.keybindings = ConvertTo-Json -InputObject ([object[]]$liveKeybindings.ToArray()) -Depth 100
        $template.keybindings = ConvertTo-Json -InputObject $keybindingResource -Depth 100 -Compress
        $template.globalState = '{"layout":"synced"}'
        $sourceExport = Join-Path $TestDrive 'Python-sync.code-profile'
        Write-TestFile $sourceExport (ConvertTo-Json -InputObject $template -Depth 100)

        $userDataPath = New-VSCodeUserDataFixture 'sync-profile-user-data'
        $applicationSettings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'global/settings.jsonc')))
        $applicationSettings['terminal.integrated.confirmOnKill'] = 'editor'
        $applicationSettings['sync.fixture.global'] = 42
        $applicationSettings['machine.fixture.path'] = 'C:\Private\tool.exe'
        $applicationSettings['workbench.settings.applyToAllProfiles'] = [string[]]@(
            $applicationSettings['workbench.settings.applyToAllProfiles']
            'sync.fixture.global'
            'machine.fixture.path'
        )
        $applicationSettings['settingsSync.ignoredSettings'] = [string[]]@(
            $applicationSettings['settingsSync.ignoredSettings']
            'machine.fixture.path'
        )
        Write-TestFile (Join-Path $userDataPath 'settings.json') (ConvertTo-Json -InputObject $applicationSettings -Depth 100)
        New-MachineDefinition -RepositoryRoot $fixture -Id test-windows -Platform windows -Settings ([ordered]@{}) | Out-Null

        $result = Sync-ComposerProfileFromExport -RepositoryRoot $fixture -SourceProfileExport $sourceExport -Platform windows -Machine test-windows -VSCodeUserDataPath $userDataPath

        $result.profileId | Should -BeExactly 'python'
        $result.counts.settingReplacements | Should -BeGreaterThan 0
        $result.counts.settingRemovals | Should -BeGreaterThan 0
        $result.counts.extensionAdditions | Should -Be 1
        $result.counts.extensionRemovals | Should -Be 1
        $result.counts.keybindingsReplacedForOrder | Should -BeTrue
        $result.counts.machineOwnedGlobalSettingsSkipped | Should -Be 1
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.settings.replace.jsonc') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.settings.remove.jsonc') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.extensions.jsonc') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.keybindings.jsonc') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'machine/local/ui-state/python/seed.code-profile') | Should -BeTrue

        $global = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'global/settings.jsonc')))
        $global['terminal.integrated.confirmOnKill'] | Should -BeExactly 'editor'
        $global['sync.fixture.global'] | Should -Be 42
        $global.Contains('machine.fixture.path') | Should -BeFalse
        $global['workbench.settings.applyToAllProfiles'] | Should -Not -Contain 'machine.fixture.path'
        $replacementSettings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'profiles/python.settings.replace.jsonc')))
        $replacementSettings.Contains('machine.fixture.path') | Should -BeFalse
        $machine = Read-MachineConfiguration (Join-Path $fixture 'machine/local/test-windows.jsonc') test-windows
        $machine.Settings['machine.fixture.path'] | Should -BeExactly 'C:\Private\tool.exe'
        $result.counts.machineSettingsAdded | Should -Be 1

        Invoke-ProfileComposition $fixture python -Platform windows | Out-Null
        $composedSettings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/python/settings.json')))
        $composedSettings.Contains($removedSetting) | Should -BeFalse
        $composedSettings['sync.fixture.setting'].enabled | Should -BeTrue
        $composedExtensions = [System.IO.File]::ReadAllLines((Join-Path $fixture 'build/profiles/python/extensions.txt'))
        $composedExtensions | Should -Contain 'sample.synced-extension'
        $composedExtensions | Should -Not -Contain $removedExtension
        $composedKeybindings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'build/profiles/python/keybindings.json')))
        @($composedKeybindings | ForEach-Object { $_ | ConvertTo-Json -Depth 100 -Compress }) |
            Should -Be @($liveKeybindings | ForEach-Object { $_ | ConvertTo-Json -Depth 100 -Compress })
        (Test-ComposerRepository $fixture -Platform windows).errors.Count | Should -Be 0
    }

    It 'supports a no-write dry run and rejects unsafe staged values without partial changes' {
        $fixture = New-ComposerFixture 'sync-profile-safety'
        $template = New-CodeProfileTemplate -DisplayName 'Python' -SettingsJson '{"sync.fixture.setting":true}' -Extensions @('sample.extension') -KeybindingsJson '[]' -Platform windows -GlobalState '{"layout":true}'
        $sourceExport = Join-Path $TestDrive 'sync-safety.code-profile'
        Write-TestFile $sourceExport (ConvertTo-Json -InputObject $template -Depth 100)

        $plan = Sync-ComposerProfileFromExport -RepositoryRoot $fixture -SourceProfileExport $sourceExport -Platform windows -SkipGlobal -DryRun
        $plan.profileId | Should -BeExactly 'python'
        $plan.dryRun | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.settings.replace.jsonc') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixture 'machine/local/ui-state/python/seed.code-profile') | Should -BeFalse

        $unsafeTemplate = New-CodeProfileTemplate -DisplayName 'Python' -SettingsJson '{"service.apiToken":"do-not-track-this-secret-value"}' -Extensions @() -KeybindingsJson '[]' -Platform windows -GlobalState '{"layout":true}'
        Write-TestFile $sourceExport (ConvertTo-Json -InputObject $unsafeTemplate -Depth 100)
        $beforeGlobal = [System.IO.File]::ReadAllText((Join-Path $fixture 'global/settings.jsonc'))
        { Sync-ComposerProfileFromExport -RepositoryRoot $fixture -SourceProfileExport $sourceExport -Platform windows -SkipGlobal } |
            Should -Throw '*Sensitive or private setting*sync-sensitive-setting*'
        [System.IO.File]::ReadAllText((Join-Path $fixture 'global/settings.jsonc')) | Should -BeExactly $beforeGlobal
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.settings.replace.jsonc') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixture 'machine/local/ui-state/python/seed.code-profile') | Should -BeFalse
    }

    It 'dispatches sync through the unified CLI and requires UI state unless explicitly skipped' {
        $fixture = New-ComposerFixture 'sync-profile-cli'
        $template = New-CodeProfileTemplate -DisplayName 'Python' -SettingsJson '{"sync.fixture.cli":true}' -Extensions @() -KeybindingsJson '[]' -Platform windows
        $sourceExport = Join-Path $TestDrive 'sync-cli.code-profile'
        Write-TestFile $sourceExport (ConvertTo-Json -InputObject $template -Depth 100)
        $cli = Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.ps1'

        $missingUi = @(& pwsh -NoProfile -File $cli sync $sourceExport -RepositoryRoot $fixture -Platform windows -SkipGlobal -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 1
        $missingUi -join "`n" | Should -Match 'does not contain UI layout state'

        $output = @(& pwsh -NoProfile -File $cli sync $sourceExport -RepositoryRoot $fixture -Platform windows -SkipGlobal -SkipUiState -DryRun 2>&1)
        $LASTEXITCODE | Should -Be 0
        $output -join "`n" | Should -Match "planned sync.*recipe 'python'"
        $output -join "`n" | Should -Match 'Settings:'
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.settings.replace.jsonc') | Should -BeFalse
    }
}

Describe 'Sync classification, machine schema, and routed planning' {
    It 'classifies supported path forms recursively without confusing executable names or path-like labels' {
        $machineValues = @(
            'C:\Users\person\tool.exe'
            'C:/Users/person/tool.exe'
            '\\server\share\tool.exe'
            '/home/person/bin/tool'
            '/Users/person/bin/tool'
            '~/Library/Application Support/tool'
            '%USERPROFILE%\bin\tool.exe'
            '$HOME/bin/tool'
            'file:///C:/Users/person/tool.exe'
        )
        foreach ($value in $machineValues) {
            (Get-SettingValueClassification -SettingKey 'fixture.path' -Value $value).classification |
                Should -BeExactly 'machine-local-path'
        }
        (Get-SettingValueClassification -SettingKey 'fixture.object' -Value ([ordered]@{ nested = [ordered]@{ path = '/opt/private/tool' } })).classification |
            Should -BeExactly 'machine-local-path'
        (Get-SettingValueClassification -SettingKey 'fixture.array' -Value @('rg', 'C:\Tools\rg.exe')).classification |
            Should -BeExactly 'machine-local-path'
        foreach ($value in @('rg', 'pwsh', 'publisher/extension', 'C:relative', 'namespace:value', '/error|warning/g')) {
            (Get-SettingValueClassification -SettingKey 'fixture.value' -Value $value).classification |
                Should -BeExactly 'portable'
        }
    }

    It 'preserves the full VS Code JSON value domain and excludes nested private data' {
        foreach ($value in @($null, $true, 42, 'portable', @('one', 2), ([ordered]@{ enabled = $true }))) {
            (Get-SettingValueClassification -SettingKey 'fixture.value' -Value $value).classification |
                Should -BeExactly 'portable'
        }
        $secret = Get-SettingValueClassification -SettingKey 'database.connection' -Value ([ordered]@{
            username = 'private-user'
            password = 'must-not-print'
        })
        $secret.classification | Should -BeExactly 'secret-or-private'
        $secret.destination | Should -BeExactly 'excluded-private'
        $secret.safeValue | Should -Not -Match 'private-user|must-not-print'
    }

    It 'validates versioned machine identity and rejects missing, unknown, newer, or mismatched schema fields' {
        $valid = New-ComposerFixture 'machine-schema-valid'
        New-MachineDefinition -RepositoryRoot $valid -Id main-windows -Platform windows -Settings ([ordered]@{ 'fixture.path' = 'C:\Tools\tool.exe' }) | Out-Null
        $definition = @(Get-MachineDefinitions $valid)[0]
        $definition.Id | Should -BeExactly 'main-windows'
        $definition.Platform | Should -BeExactly 'windows'
        $definition.SchemaVersion | Should -Be 1
        (Test-ComposerRepository $valid).errors.Count | Should -Be 0

        $missing = New-ComposerFixture 'machine-schema-missing-id'
        Write-TestFile (Join-Path $missing 'machine/local/broken.jsonc') '{"schemaVersion":1,"machine":{"name":"Broken","platform":"windows"},"settings":{}}'
        ((Test-ComposerRepository $missing).errors.message -join "`n") | Should -Match 'machine.id'

        $unknown = New-ComposerFixture 'machine-schema-unknown'
        Write-TestFile (Join-Path $unknown 'machine/local/broken.jsonc') '{"schemaVersion":1,"machine":{"id":"broken","name":"Broken","platform":"windows"},"settings":{},"future":true}'
        ((Test-ComposerRepository $unknown).errors.message -join "`n") | Should -Match 'unknown schema field'

        $newer = New-ComposerFixture 'machine-schema-newer'
        Write-TestFile (Join-Path $newer 'machine/local/broken.jsonc') '{"schemaVersion":2,"machine":{"id":"broken","name":"Broken","platform":"windows"},"settings":{}}'
        ((Test-ComposerRepository $newer).errors.message -join "`n") | Should -Match 'supported schemaVersion 1'

        $mismatch = New-ComposerFixture 'machine-schema-id-mismatch'
        Write-TestFile (Join-Path $mismatch 'machine/local/file-id.jsonc') '{"schemaVersion":1,"machine":{"id":"other-id","name":"Other","platform":"windows"},"settings":{}}'
        ((Test-ComposerRepository $mismatch).errors.message -join "`n") | Should -Match 'must match filename ID'

        $stale = New-ComposerFixture 'machine-schema-stale-default'
        Write-TestFile (Join-Path $stale 'machine/local/.default-machine') 'deleted-machine'
        (Test-ComposerRepository $stale).errors.code | Should -Contain 'stale-default-machine'

        $private = New-ComposerFixture 'machine-schema-private-state'
        New-MachineDefinition -RepositoryRoot $private -Id private-windows -Platform windows -Settings ([ordered]@{
            'service.token' = 'must-not-live-in-machine-json'
        }) | Out-Null
        (Test-ComposerRepository $private).errors.code | Should -Contain 'machine-sensitive-setting'
    }

    It 'routes an explicit machine path, preserves portable changes, and is idempotent' {
        $fixture = New-ComposerFixture 'sync-route-explicit'
        $mainSettingsPath = Join-Path $fixture 'components/main/settings.jsonc'
        $mainSettings = ConvertFrom-JsonC ([System.IO.File]::ReadAllText($mainSettingsPath))
        $mainSettings['fixture.machinePath'] = 'rg'
        Write-TestFile $mainSettingsPath (ConvertTo-Json -InputObject $mainSettings -Depth 100)
        New-MachineDefinition -RepositoryRoot $fixture -Id main-windows -Platform windows -Settings ([ordered]@{}) | Out-Null
        $export = New-SyncExport -Path (Join-Path $TestDrive 'route-explicit.code-profile') -Settings ([ordered]@{
            'fixture.portable' = [ordered]@{ enabled = $true; modes = @('one', 2) }
            'fixture.machinePath' = 'C:\Users\person\bin\tool.exe'
        })

        $preview = Sync-ComposerProfileFromExport $fixture -SourceProfileExport $export -Platform windows -Machine main-windows -SkipGlobal -DryRun
        $result = Sync-ComposerProfileFromExport $fixture -SourceProfileExport $export -Platform windows -Machine main-windows -SkipGlobal
        $preview.changes.action | Should -Be $result.changes.action
        $preview.changes.path | Should -Be $result.changes.path
        $preview.routes.action | Should -Be $result.routes.action
        $result.machine.id | Should -BeExactly 'main-windows'
        $result.machine.selection | Should -BeExactly 'explicit-machine'
        $result.counts.machineSettingsAdded | Should -Be 1
        $result.routes[0].action | Should -BeExactly 'add'
        $result.routes[0].portableOwner | Should -BeExactly 'components/main/settings.jsonc'
        $machine = Read-MachineConfiguration (Join-Path $fixture 'machine/local/main-windows.jsonc') main-windows
        $machine.Settings['fixture.machinePath'] | Should -BeExactly 'C:\Users\person\bin\tool.exe'
        $replacement = ConvertFrom-JsonC ([System.IO.File]::ReadAllText((Join-Path $fixture 'profiles/python.settings.replace.jsonc')))
        $replacement['fixture.portable'].enabled | Should -BeTrue
        $replacement.Contains('fixture.machinePath') | Should -BeFalse
        (Get-ChildItem (Join-Path $fixture 'profiles') -File | Select-String -Pattern 'C:\\Users\\person').Count | Should -Be 0

        $again = Sync-ComposerProfileFromExport $fixture -SourceProfileExport $export -Platform windows -Machine main-windows -SkipGlobal
        $again.counts.machineSettingsRetained | Should -Be 1
        $again.changes.Count | Should -Be 0
        $again.uiStateUpdated | Should -BeFalse
    }

    It 'updates a different machine value and reports earlier platform ownership without leaking values' {
        $fixture = New-ComposerFixture 'sync-route-update'
        New-MachineDefinition -RepositoryRoot $fixture -Id main-windows -Platform windows -Settings ([ordered]@{
            'terminal.integrated.defaultProfile.windows' = 'C:\Old\pwsh.exe'
            'fixture.unrelated' = $true
        }) | Out-Null
        $export = New-SyncExport -Path (Join-Path $TestDrive 'route-update.code-profile') -Settings ([ordered]@{
            'terminal.integrated.defaultProfile.windows' = 'C:\New\pwsh.exe'
        })

        $result = Sync-ComposerProfileFromExport $fixture -SourceProfileExport $export -Platform windows -Machine main-windows -SkipGlobal -SkipUiState
        $result.counts.machineSettingsUpdated | Should -Be 1
        $result.routes[0].portableOwner | Should -BeExactly 'platform/windows.jsonc'
        ($result.routes[0] | ConvertTo-Json -Depth 20) | Should -Not -Match 'C:\\Old|C:\\New'
        (Read-MachineConfiguration (Join-Path $fixture 'machine/local/main-windows.jsonc') main-windows).Settings['terminal.integrated.defaultProfile.windows'] |
            Should -BeExactly 'C:\New\pwsh.exe'
        (Read-MachineConfiguration (Join-Path $fixture 'machine/local/main-windows.jsonc') main-windows).Settings['fixture.unrelated'] |
            Should -BeTrue
    }

    It 'resolves explicit, local-default, and unique machines in order and rejects ambiguity or platform mismatch' {
        $fixture = New-ComposerFixture 'sync-machine-resolution'
        New-MachineDefinition -RepositoryRoot $fixture -Id first-windows -Platform windows -Settings ([ordered]@{ 'fixture.path' = 'C:\First\tool.exe' }) | Out-Null
        New-MachineDefinition -RepositoryRoot $fixture -Id second-windows -Platform windows -Settings ([ordered]@{ 'fixture.path' = 'C:\Second\tool.exe' }) | Out-Null
        Write-TestFile (Join-Path $fixture 'machine/local/.default-machine') 'first-windows'
        $export = New-SyncExport -Path (Join-Path $TestDrive 'machine-resolution.code-profile') -Settings ([ordered]@{
            'fixture.path' = 'C:\Tools\tool.exe'
        })

        $explicit = Sync-ComposerProfileFromExport $fixture -SourceProfileExport $export -Platform windows -Machine second-windows -SkipGlobal -SkipUiState -DryRun
        $explicit.machine.id | Should -BeExactly 'second-windows'
        $explicit.machine.selection | Should -BeExactly 'explicit-machine'
        $defaulted = Sync-ComposerProfileFromExport $fixture -SourceProfileExport $export -Platform windows -SkipGlobal -SkipUiState -DryRun
        $defaulted.machine.id | Should -BeExactly 'first-windows'
        $defaulted.machine.selection | Should -BeExactly 'local-default'

        Remove-Item -LiteralPath (Join-Path $fixture 'machine/local/.default-machine') -Force
        { Sync-ComposerProfileFromExport $fixture -SourceProfileExport $export -Platform windows -SkipGlobal -SkipUiState -DryRun } |
            Should -Throw '*Setting: fixture.path*sync-machine-local-path*Machine target is ambiguous*Recommended command*'
        { Sync-ComposerProfileFromExport $fixture -SourceProfileExport $export -Platform windows -Machine missing -SkipGlobal -SkipUiState -DryRun } |
            Should -Throw '*Selected machine*does not exist*Recommended command*'

        $linux = New-ComposerFixture 'sync-machine-platform-mismatch'
        New-MachineDefinition -RepositoryRoot $linux -Id linux-box -Platform linux -Settings ([ordered]@{}) | Out-Null
        { Sync-ComposerProfileFromExport $linux -SourceProfileExport $export -Platform windows -Machine linux-box -SkipGlobal -SkipUiState -DryRun } |
            Should -Throw "*targets platform 'linux'*"

        $unique = New-ComposerFixture 'sync-machine-unique'
        New-MachineDefinition -RepositoryRoot $unique -Id only-windows -Platform windows -Settings ([ordered]@{}) | Out-Null
        $automatic = Sync-ComposerProfileFromExport $unique -SourceProfileExport $export -Platform windows -SkipGlobal -SkipUiState -DryRun
        $automatic.machine.selection | Should -BeExactly 'unique-platform-match'
    }

    It 'fails sensitive values with redacted actionable diagnostics before any write' {
        $fixture = New-ComposerFixture 'sync-sensitive-redaction'
        New-MachineDefinition -RepositoryRoot $fixture -Id main-windows -Platform windows -Settings ([ordered]@{}) | Out-Null
        $export = New-SyncExport -Path (Join-Path $TestDrive 'sensitive.code-profile') -Settings ([ordered]@{
            'service.credentials' = [ordered]@{ token = 'do-not-print-this-token-value' }
        })
        $before = [System.IO.File]::ReadAllText((Join-Path $fixture 'machine/local/main-windows.jsonc'))
        $message = $null
        try {
            Sync-ComposerProfileFromExport $fixture -SourceProfileExport $export -Platform windows -Machine main-windows -SkipGlobal -SkipUiState | Out-Null
        }
        catch { $message = $_.Exception.Message }
        $message | Should -Match 'Sensitive or private setting|sync-sensitive-setting|excluded-private'
        $message | Should -Not -Match 'do-not-print-this-token-value'
        [System.IO.File]::ReadAllText((Join-Path $fixture 'machine/local/main-windows.jsonc')) | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.settings.replace.jsonc') | Should -BeFalse
    }

    It 'rolls back profile and machine files when post-commit validation fails' {
        $fixture = New-ComposerFixture 'sync-machine-rollback'
        New-MachineDefinition -RepositoryRoot $fixture -Id main-windows -Platform windows -Settings ([ordered]@{
            'fixture.path' = 'C:\Old\tool.exe'
        }) | Out-Null
        $machinePath = Join-Path $fixture 'machine/local/main-windows.jsonc'
        $beforeMachine = [System.IO.File]::ReadAllText($machinePath)
        $export = New-SyncExport -Path (Join-Path $TestDrive 'rollback.code-profile') -Settings ([ordered]@{
            'fixture.portable' = $true
            'fixture.path' = 'C:\New\tool.exe'
        })

        InModuleScope ProfileComposer -Parameters @{ FixtureRoot = $fixture; ExportPath = $export } {
            param($FixtureRoot, $ExportPath)
            $script:ValidationCall = 0
            Mock Test-ComposerRepository {
                $script:ValidationCall++
                $errors = [System.Collections.Generic.List[object]]::new()
                if ($script:ValidationCall -eq 3) {
                    $errors.Add([pscustomobject]@{ code = 'forced'; message = 'forced post-commit failure' })
                }
                [pscustomobject]@{
                    errors = $errors
                    warnings = [System.Collections.Generic.List[object]]::new()
                    information = [System.Collections.Generic.List[object]]::new()
                }
            }
            { Sync-ComposerProfileFromExport $FixtureRoot -SourceProfileExport $ExportPath -Platform windows -Machine main-windows -SkipGlobal -SkipUiState } |
                Should -Throw '*rolled back*'
        }
        [System.IO.File]::ReadAllText($machinePath) | Should -BeExactly $beforeMachine
        Test-Path -LiteralPath (Join-Path $fixture 'profiles/python.settings.replace.jsonc') | Should -BeFalse
    }

    It 'warns when portable setting ownership is duplicated across components' {
        $fixture = New-ComposerFixture 'duplicate-portable-setting-owner'
        Write-TestFile (Join-Path $fixture 'components/main/settings.jsonc') '{"fixture.duplicate":true}'
        Write-TestFile (Join-Path $fixture 'components/python/settings.jsonc') '{"fixture.duplicate":false}'
        (Test-ComposerRepository $fixture).warnings.code | Should -Contain 'cross-component-setting-ownership'
    }
}

Describe 'Forwarding function and alias compatibility' {
    It 'preserves platform, machine, and quoted export arguments and matches direct planning' {
        $fixture = New-ComposerFixture 'wrapper compatibility'
        New-MachineDefinition -RepositoryRoot $fixture -Id main-windows -Platform windows -Settings ([ordered]@{}) | Out-Null
        $exportDirectory = Join-Path $TestDrive 'profile exports with spaces'
        $export = New-SyncExport -Path (Join-Path $exportDirectory 'Adjusted Python.code-profile') -Settings ([ordered]@{
            'fixture.portable' = $true
            'fixture.path' = 'C:\Tools\tool.exe'
        })
        $cli = Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.ps1'
        $wrapper = Join-Path $TestDrive 'invoke-vscomp-wrapper.ps1'
        $escapedCli = $cli.Replace("'", "''")
        Write-TestFile $wrapper @"
function composer {
    & '$escapedCli' @args
}
Set-Alias vscomp composer
vscomp @args
exit `$LASTEXITCODE
"@
        $arguments = @('sync', $export, '-RepositoryRoot', $fixture, '-Platform', 'windows', '-Machine', 'main-windows', '-SkipGlobal', '-SkipUiState', '-DryRun')
        $direct = @(& pwsh -NoProfile -File $cli @arguments 2>&1)
        $directExit = $LASTEXITCODE
        $wrapped = @(& pwsh -NoProfile -File $wrapper @arguments 2>&1)
        $wrappedExit = $LASTEXITCODE

        $directExit | Should -Be 0
        $wrappedExit | Should -Be 0
        ($wrapped -join "`n") | Should -BeExactly ($direct -join "`n")
        ($wrapped -join "`n") | Should -Match 'Selected machine: main-windows'
        ($wrapped -join "`n") | Should -Not -Match 'portable-absolute-path'

        $unknown = @(& pwsh -NoProfile -File $wrapper sync $export -NoSuchOption 2>&1)
        $LASTEXITCODE | Should -Be 1
        $unknown -join "`n" | Should -Match "Unknown option '-NoSuchOption'"
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
