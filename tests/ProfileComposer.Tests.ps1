BeforeAll {
    $script:RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    Import-Module (Join-Path $script:RepositoryRoot 'scripts/ProfileComposer.psm1') -Force

    function New-ComposerFixture {
        param([Parameter(Mandatory)][string]$Name)
        $fixture = Join-Path $TestDrive $Name
        [System.IO.Directory]::CreateDirectory($fixture) | Out-Null
        foreach ($directory in @('components', 'profiles', 'platform', 'machine')) {
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

Describe 'Recipe parsing and repository validation' {
    It 'parses the current ordered recipe format' {
        $recipe = Read-ProfileRecipe (Join-Path $script:RepositoryRoot 'profiles/unreal.yaml')
        $recipe.Name | Should -Be 'Unreal Engine'
        $recipe.Components | Should -Be @('suggested-baseline', 'cpp', 'unreal')
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
