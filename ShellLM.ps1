<#
.SYNOPSIS
    This script is a PowerShell implementation of a chatbot using OpenAI's GPT models, Google's Gemini, and Anthropic's Claude 3.

.DESCRIPTION
    The script allows users to interact with the chatbot by sending messages and receiving responses from the LLM. It supports multiple commands and provides a conversational interface.

.PARAMETER Query
    Specifies the user's message/query to be sent to the chatbot.

.PARAMETER Model
    Specifies the large language model to use for generating responses.

.PARAMETER ImageModel
    Specifies the DALL-E model to use for generating images. The available options are "dall-e-2" and "dall-e-3". The default value is "dall-e-3".

.PARAMETER Load
    Specifies a file containing a conversation to load. This can be used to continue a previous conversation.

.PARAMETER Key
    Specifies the OpenAI API key to use for making API calls to the OpenAI chat/completions endpoint.
    If not provided, the script will prompt the user to enter the API key. It will also automatically set the API key as an environment variable.

.PARAMETER GeminiKey
    Specifies the Google API key to use for making API calls to the Google Gemini endpoint.
    If not provided, the script will prompt the user to enter the API key. It will also automatically set the API key as an environment variable.

.PARAMETER AnthropicKey
    Specifies the Anthropic API key to use for making API calls to the Anthropic Claude 3 endpoint.
    If not provided, the script will prompt the user to enter the API key. It will also automatically set the API key as an environment variable.

.PARAMETER Clear
    Clears the AskLLM context, including the last query and response.

.PARAMETER ConfigFile
    Specifies the path to the configuration file that stores the settings for the chatbot. The default value is "config.json".

.PARAMETER ConversationsDir
    Specifies the directory where conversation files are stored. The default value is "conversations\".

.PARAMETER ImagesDir
    Specifies the directory where image files are stored. The default value is "images\".

.NOTES
    Version 2.8
    - This script requires an OpenAI API key to make API calls to the OpenAI chat/completions endpoint.
    - The script uses ANSI escape codes for color formatting in the terminal.
    - The script supports various commands that can be used to interact with the chatbot.
    - The script provides a conversational history and allows exporting the conversation to a JSON file.

.EXAMPLE
    PS C:\> .\ShellLM.ps1 -Model "gpt-4" -Query "What is the capital of ecuador?"

    This example runs the script using the "gpt-4" model and asks the question "What is the capital of ecuador?".

.EXAMPLE
    PS C:\> .\ShellLM.ps1 -Load conversation

    This example loads a conversation from the "conversation.json" file within the conversations dir and continues the conversation.
#>

[CmdletBinding(PositionalBinding=$false)] # Important as it make it so you can throw the model param anywhere
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet(
        "gpt",
        "gpt-3",
        "gpt-3.5",
        "gpt-3.5-turbo",
        "gpt-4",
        "gpt-4o",
        "gpt-4o-mini",
        "gemini",
        "gemini-pro",
        "gemini-1.5-pro",
        "gemini-1.5",
        "gemini-1.5-flash",
        "claude",
        "claude-3",
        "claude-3.5",
        "claude-3-haiku", 
        "claude-3-sonnet", 
        "claude-3-opus",
        "claude-3.5-sonnet"
    )]
    [string] $Model,

    [Parameter(Mandatory=$false)]
    [ValidateSet(
        "dall-e-2",
        "dall-e-3"
    )]
    [string] $ImageModel,

    [Parameter(ValueFromRemainingArguments)]
    [string] $Query,

    [Parameter(Mandatory=$false)]
    [Alias("l", "Import", "File", "Conversation")]
    [string] $Load,

    [Parameter(Mandatory=$false)]
    [Alias("k")]
    [string] $Key,

    [Parameter(Mandatory=$false)]
    [string] $GeminiKey,

    [Parameter(Mandatory=$false)]
    [string] $AnthropicKey,

    [Parameter(Mandatory=$false)]
    [switch] $Clear,

    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = (Join-Path $PSScriptRoot "\config.json"),

    [Parameter(Mandatory=$false)]
    [string]$ConversationsDir = (Join-Path $PSScriptRoot "\conversations\"),

    [Parameter(Mandatory=$false)]
    [string]$ImagesDir = (Join-Path $PSScriptRoot "\images\")
)

$MODELS = "gpt-3.5-turbo", "gpt-4o-mini", "gpt-4o", "gemini", "gemini-1.5-pro", "gemini-1.5-flash", "claude-3-opus", "claude-3-sonnet", "claude-3-haiku", "claude-3.5-sonnet"
$IMAGE_MODELS = "dall-e-2", "dall-e-3"

$ESC = [char]27 # Escape char for colors

if (!($PSVersionTable.PSCompatibleVersions -contains "7.0")) {
    Write-Host "This script requires PowerShell 7.0 or later." -ForegroundColor Red
    exit
}

# Added this part because the bot will always remember the last interaction and sometimes this is undesirable if you want a different output
if ($Clear) { # Do this first so the user doesn't have to wait for the model to load
    $global:LastQuery = ""
    $global:LastResponse = ""
    Write-Host "AskLLM context cleared" -ForegroundColor Yellow
    if (!$Query) {
        exit
    }
}

function HandleDirectories {
    if ($script:PSScriptRoot) {
        if (!(Test-Path $script:ConversationsDir)) {
            New-Item -ItemType Directory -Path $script:ConversationsDir | Out-Null
        }

        $script:ConversationsDir = Resolve-Path ($script:ConversationsDir)

        if (!(Test-Path $script:ImagesDir)) {
            New-Item -ItemType Directory -Path $script:ImagesDir | Out-Null
        }

        $script:ImagesDir = Resolve-Path ($script:ImagesDir)
    } else {
        $script:ConversationsDir = Resolve-Path ".\conversations\"
        $script:ImagesDir = Resolve-Path ".\images\"
        $script:ConfigFile = Resolve-Path ".\config.json"
    }
}

function HandleOpenAIKeyState { # Just to group it together, this is the only place it's used
    if ($env:OPENAI_API_KEY -and $script:Key) {
        return
    }

    if (!$env:OPENAI_API_KEY -and !$script:Key) {
        Write-Host "OPEN AI API KEY NOT FOUND. GET ONE HERE: https://platform.openai.com/api-keys" -ForegroundColor Red
        Write-Host "Please input API key, or set it as an environment variable."
        Write-Host "> " -NoNewline
        $script:Key = $Host.UI.ReadLine()
    }
    
    if (!$script:Key) {
        $script:Key = $env:OPENAI_API_KEY
    }
    
    # This is just to confirm the key is valid, does not actually use the list of models.
    try {
        Invoke-WebRequest `
            -Uri https://api.openai.com/v1/models `
            -Headers @{
                "Authorization" = "Bearer $($script:Key)"
            } | Out-Null
    } catch {
        if (($_ | ConvertFrom-Json).error.code -eq "invalid_api_key") {
            Write-Host "Invalid API key. Please try again." -ForegroundColor Red
        } else {
            Write-Host "Could not connect to OpenAI servers: $_"
        }
    
        exit
    }
    
    if ($script:Key -ne $env:OPENAI_API_KEY) {
        [System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $script:Key, "User")
    }
}

function HandleGeminiKeyState { # This will only be called if the model is gemini
    if ($env:GOOGLE_API_KEY -and $script:GeminiKey) {
        return
    }
    
    if (!$env:GOOGLE_API_KEY -and !$script:GeminiKey) {
        Write-Host "GOOGLE API KEY NOT FOUND. GET ONE HERE: https://aistudio.google.com/app/apikey" -ForegroundColor Red
        Write-Host "Please input API key, or set it as an environment variable."
        Write-Host "> " -NoNewline
        $script:GeminiKey = $Host.UI.ReadLine()
    }

    if (!$script:GeminiKey) {
        $script:GeminiKey = $env:GOOGLE_API_KEY
    }

    # There doesn't seem to be a simple way to test the key :(

    if ($script:GeminiKey -ne $env:GOOGLE_API_KEY) {
        [System.Environment]::SetEnvironmentVariable("GOOGLE_API_KEY", $script:GeminiKey, "User")
    }
}

function HandleAnthropicKeyState { # This will only be called if the model is claude-3
    if ($env:ANTHROPIC_API_KEY -and $script:AnthropicKey) {
        return
    }
    
    if (!$env:ANTHROPIC_API_KEY -and !$script:AnthropicKey) {
        Write-Host "ANTHROPIC API KEY NOT FOUND. GET ONE HERE: https://console.anthropic.com/settings/keys" -ForegroundColor Red
        Write-Host "Please input API key, or set it as an environment variable."
        Write-Host "> " -NoNewline
        $script:AnthropicKey = $Host.UI.ReadLine()
    }

    if (!$script:AnthropicKey) {
        $script:AnthropicKey = $env:ANTHROPIC_API_KEY
    }

    if ($script:AnthropicKey -ne $env:ANTHROPIC_API_KEY) {
        [System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $script:AnthropicKey, "User")
    }
}

function HandleModelState { # the turbo models are better than the base models and are less expensive
    if ($script:Model -in "gpt-3", "gpt-3.5", "gpt") {
        $script:Model = "gpt-3.5-turbo"
    }

    if ($script:Model -eq "gpt-4") {
        $script:Model = "gpt-4o"
    }

    if ($script:Model -in "claude-3") {
        $script:Model = "claude-3-sonnet"
    }

    if ($script:Model -eq "claude", "claude-3.5") {
        $script:Model = "claude-3.5-sonnet"
    }

    if ($script:Model -eq "gemini-pro") {
        $script:Model = "gemini"
    }

    if ($script:Model -eq "gemini-1.5") {
        $script:Model = "gemini-1.5-pro"
    }

    # Asign the global values from the config file
    if (!$script:Model) {
        $script:Model = [Config]::Get("DefaultModel")
    }
    
    if (!$script:ImageModel) {
        $script:ImageModel = [Config]::Get("ImageModel")
    }

    if ($script:Model -eq "gemini") {
        HandleGeminiKeyState
    } elseif ($script:Model -like "claude*") {
        HandleAnthropicKeyState
    }
}

$SYSTEM_MESSAGE = (
    'You are a helpful assistant communicating through the terminal. Do not use markdown syntax. Give detailed responses. ' +
    'You can use `§COLOR§` to change the color of your text for emphasis or whatever you want, and §RESET§ to go back to your default color. ' +
    'If you write code, do not use "```". Use colors for syntax highlighting instead. ' +
    'Colors available are RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE, GRAY, RESET. ' +
    'You can also use DARK colors using §DARKCOLOR§. (E.g. §DARKRED§Hello§RESET§).' 
)

# Colors for the terminal
$COLORS = @{
    DARKRED = "$ESC[31m"
    DARKGREEN = "$ESC[32m"
    DARKYELLOW = "$ESC[33m"
    DARKBLUE = "$ESC[34m"
    DARKMAGENTA = "$ESC[35m"
    DARKCYAN = "$ESC[36m"
    GRAY = "$ESC[37m"
    DARKGRAY = "$ESC[90m"
    RED = "$ESC[91m"
    GREEN = "$ESC[92m"
    YELLOW = "$ESC[93m"
    BLUE = "$ESC[94m"
    MAGENTA = "$ESC[95m"
    CYAN = "$ESC[96m"
    WHITE = "$ESC[97m"
    DARKWHITE = "$ESC[37m" # not a real color
    BLACK = "$ESC[90m"
    DARKBLACK = "$ESC[90m"
    # Bright colors (just the same as the normal colors)
    BRIGHTRED = "$ESC[91m"
    BRIGHTGREEN = "$ESC[92m"
    BRIGHTYELLOW = "$ESC[93m"
    BRIGHTBLUE = "$ESC[94m"
    BRIGHTMAGENTA = "$ESC[95m"
    BRIGHTCYAN = "$ESC[96m"
    BRIGHTWHITE = "$ESC[97m"
    BRIGHTBLACK = "$ESC[37m"
}

function WrapText {
    # Home grown stand in for python's textwrap (ansiwrap)
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$Text,

        [string]$FirstIndent,
        [int]$Indent
    )

    $Width = $Host.UI.RawUI.BufferSize.Width - ($Indent)

    # First indent should be the same as the indent when not specified
    $wrappedText = $FirstIndent ? $FirstIndent : (" " * $Indent)

    $lines = $Text -split '\r?\n'

    $lineCount = 0
    $totalLines = $lines.Length

    foreach ($line in $lines) {
        # capture spaces in the split
        $lineWords = $line -split '(\s+)'

        $lineLength = 0

        foreach ($word in $lineWords) {
            if ($lineLength + $word.Length -ge $Width) {
                # hackish to make sure we don't wrap spaces
                if ($word -eq " ") {
                    continue
                }
                
                $wrappedText += "`n" + (" " * $Indent)
                $lineLength = 0
            } 

            $wrappedText += $word
            $lineLength += $word.Length
        }

        # Append newline only if it's not the last line
        if ($lineCount -lt $totalLines - 1) {
            $wrappedText += "`n" + (" " * $Indent)  # Preserve newline characters
        }

        $lineCount++
    }

    return $wrappedText
}

class Config {
    [string]$Name
    $Value
    [string]$Category

    [string[]]$ValidateSet
    [string]$ValidateString # funcional, but not used
    [int]$ValidateMax
    [int]$ValidateMin

    $DefaultValue

    static [System.Collections.Generic.List[Config]] $Settings = @()

    static [bool]$IsYaml

    Config ([string]$Name, $Value) { # Not used
        $this.Name = $Name

        $this.Value = $Value
        $this.DefaultValue = $Value

        $this.Category = "Misc"

        [Config]::Settings.Add($this)
    }

    Config ([string]$Name, [bool]$Value, [string]$Category) {
        $this.Name = $Name

        [bool]$this.Value = $Value
        [bool]$this.DefaultValue = $Value

        $this.Category = $Category

        [Config]::Settings.Add($this)
    }

    Config ([string]$Name, [string]$Value, [string]$Category, [string[]]$ValidateSet) {
        $this.Name = $Name

        [string]$this.Value = $Value
        [string]$this.DefaultValue = $Value

        $this.Category = $Category
        $this.ValidateSet = $ValidateSet

        [Config]::Settings.Add($this)
    }

    Config ([string]$Name, [double]$Value, [string]$Category, [int]$ValidateMin, [int]$ValidateMax) {
        $this.Name = $Name
        
        [double]$this.Value = $Value
        [double]$this.DefaultValue = $Value

        $this.Category = $Category

        $this.ValidateMax = $ValidateMax
        $this.ValidateMin = $ValidateMin

        [Config]::Settings.Add($this)
    }

    # Find a setting by name, returns a list of matching settings
    static [Config[]] Find ([string]$Name) {
        $setting = [Config]::Settings | Where-Object { $_.Name -like "$Name*" }

        if (!$setting) {
            return $null
        }

        return $setting
    }

    static [object] Get ([string]$Name) {
        $matchingSettings = [Config]::Find($Name)

        if (!$matchingSettings) {
            Write-Host "Setting matching '$Name' not found." -ForegroundColor Red
            return $null
        }

        $setting = $matchingSettings[0]

        if ($setting) {
            return $setting.Value
        }

        return $null
    }

    [bool] SetValue ($NewValue) { # returns true if successful
        if ($this.ValidateSet) {
            if ($NewValue -notin $this.ValidateSet) {
                foreach ($item in $this.ValidateSet) {
                    if ($item -like "$NewValue*") {
                        $NewValue = $item
                    }
                }
            }

            if ($NewValue -notin $this.ValidateSet) {
                Write-Host (WrapText "Invalid value. Valid values are: $($this.ValidateSet -join ", ")") -ForegroundColor Red
                return $false
            }
        } 
        elseif ($this.ValidateMax -or $this.ValidateMin) { # Won't trigger if both values are 0, but that shouldn't happen
            if ($NewValue -lt $this.ValidateMin -or $NewValue -gt $this.ValidateMax) {
                Write-Host (WrapText "Invalid value. Value must be between $($this.ValidateMin) and $($this.ValidateMax)") -ForegroundColor Red
                return $false
            }
        }
        elseif ($this.ValidateString) {
            if ($NewValue -notlike $this.ValidateString) {
                Write-Host (WrapText "Invalid value. Value must match the pattern: $($this.ValidateString)") -ForegroundColor Red
                return $false
            }
        }
        else {
            # Boolean values are a special case
            [bool]$NewValue = ("true" -like "$NewValue*" -or $NewValue -eq 1)
            Write-Debug $NewValue.GetType().Name
        }

        $this.Value = $NewValue
        return $true
    }

    static SetValue ([string]$Name, $Value) {
        if (![Config]::Find($Name)) {
            Write-Host "Setting matching '$Name' not found." -ForegroundColor Red
            return
        }

        $setting = [Config]::Find($Name)[0]

        if ($setting) {
            $setting.SetValue($Value)
        } else {
            [Config]::new($Name, $Value)
        }
    }

    static ChangeSettings () {
        while ($true) {
            #Sort settings by category
            $config = [Config]::Settings | Sort-Object Category

            $currentCategory = ""

            # Write out each setting in it's category
            foreach ($setting in $config) {
                if ($setting.Category -ne $currentCategory) {
                    $currentCategory = $setting.Category
                    Write-Host "`n  [$currentCategory]" -ForegroundColor DarkYellow
                }

                $index = $config.IndexOf($setting) + 1

                $tab = if ($index -lt 10) { "   " } else { "  " }

                $color = if ($setting.Value -is [bool]) {
                    if ($setting.Value) { "Green" } else { "Red" }
                } else {
                    "Yellow"
                }

                Write-Host "    [$index]$tab" -NoNewline
                Write-Host "$($setting.Name): " -NoNewline -ForegroundColor DarkCyan
                Write-Host "$($setting.Value)" -ForegroundColor $color

                # back option
                if ($index -eq $config.Count) {
                    Write-Host "`n    [0]$($tab)Save and go back" -ForegroundColor White
                }
            }

            Write-Host "`nSelect a setting to change its value." -ForegroundColor DarkYellow
            Write-Host "> " -NoNewline
            $settingName = $global:Host.UI.ReadLine()

            # check if it's a number
            if ([int]::TryParse($settingName, [ref]$null)) {
                if ([int]$settingName -eq 0) {
                    break
                }

                $settingName = $config[[int]$settingName - 1].Name
            }

            # if the user wants to go back
            if ($settingName -in "back", "quit", "exit", "cancel", "save") {
                break
            }

            # Find the setting
            $setting = [Config]::Find($settingName)

            if (!$setting) {
                Write-Host "`nSetting matching '$settingName' not found." -ForegroundColor Red
                continue
            }

            # Find returns a list of settings, so we can show the user the error of their ways
            if ($setting.Count -gt 1) {
                Write-Host "Setting name ""$settingName"" is ambiguous.`n" -ForegroundColor Red
                Write-Host "Matching settings:" -ForegroundColor DarkYellow
                foreach ($setting in $setting) {
                    Write-Host "   $($setting.Name)" -ForegroundColor Yellow
                }
                continue
            }

            # Powershell freaks out when you try to call the method of a list, even if it's one item
            $setting = $setting[0]

            if ($setting.Value -is [bool]) {
                $setting.SetValue((!$setting.Value))
                Write-Host "`nSetting changed." -ForegroundColor Green
                continue
            }

            # Show the current value and prompt for a new one
            Write-Host "`n[$($setting.Name)] Current value: " -ForegroundColor DarkYellow -NoNewline
            Write-Host "$($setting.Value)" -ForegroundColor Yellow

            # Show the valid values if they exist
            if ($setting.ValidateSet) {
                Write-Host "`nValid values:" -ForegroundColor DarkYellow

                foreach ($value in $setting.ValidateSet) {
                    $index = $setting.ValidateSet.IndexOf($value) + 1
                    # change color if selected
                    $color = if ($value -eq $setting.value) { "Green" } else { "DarkYellow" }
                    Write-Host "  [$index]`t$value" -ForegroundColor $color
                }
            }
            elseif ($setting.ValidateMax -or $setting.ValidateMin) {
                Write-Host "`nValid Range: [$($setting.ValidateMin) - $($setting.ValidateMax)]" -ForegroundColor DarkYellow
            }
            elseif ($setting.ValidateString -and $setting.ValidateString -ne "*") {
                Write-Host "`nValid Pattern: $($setting.ValidateString)" -ForegroundColor DarkYellow
            }
            elseif ($setting.Value -is [bool]) {
                Write-Host "`nValid values: True or False" -ForegroundColor DarkYellow
            }

            Write-Host "`nNew value:" -ForegroundColor Blue
            Write-Host "> " -NoNewline -ForegroundColor Blue

            [string]$newValue = $global:Host.UI.ReadLine()

            # A way to cancel the change
            if ($newValue -in "back", "quit", "exit", "cancel", "save") {
                continue
            }
            
            # check if it's a number
            if ($setting.ValidateSet -and [int]::TryParse($newValue, [ref]$null)) {
                $newValue = $setting.ValidateSet[[int]$newValue - 1]
            }

            if ($setting.SetValue($newValue)) {
                Write-Host "`nSetting changed." -ForegroundColor Green
            }
        }

        [Config]::WriteConfig()
        Write-Host "`nSettings saved.`n" -ForegroundColor Green
    }

    static WriteConfig () {
        $config = [System.Collections.Hashtable]::new()

        foreach ($setting in [Config]::Settings) {
            if ($setting.Value -ne $setting.DefaultValue) {
                $config[$setting.Name] = $setting.Value
            }
        }

        if ([Config]::IsYaml) {
            $config | ConvertTo-Yaml | Set-Content -Path $script:ConfigFile
        } else {
            $config | ConvertTo-Json | Set-Content -Path $script:ConfigFile
        }
    }

    static ReadConfig () {
        if ((Get-Module -Name powershell-yaml)) {
            # Yaml is easier to use, so is preferable, but only if you have the module preinstalled
            $script:ConfigFile = $script:ConfigFile -replace "\.json", ".yaml"
        }

        [Config]::IsYaml = $script:ConfigFile -like "*.yaml"

        if (Test-Path $script:ConfigFile) {
            if ([Config]::IsYaml) {
                $config = [pscustomobject] (Get-Content -Path $script:ConfigFile | ConvertFrom-Yaml)
            } else {
                $config = Get-Content -Path $script:ConfigFile | ConvertFrom-Json
            }
            foreach ($setting in $config.PSObject.Properties) {
                [Config]::SetValue($setting.Name, $setting.Value)
            }
        }
    }
}

class Command {
    [string[]]$Keywords; # The different keywords that can be used to trigger the command, the first one is the one shown to user
    [string]$Description; # Short description of the command when /help is called
    [scriptblock]$Action; # The action to be executed when the command is called
    [int]$ArgsNum; # Number of arguments the command expects
    [string]$Usage; # Usage example for the command without the command itself

    # I don't think argsNum is doing anything anymore, but I'm afraid to remove it...

    static [System.Collections.Generic.List[Command]] $Commands = @()

    Command([string[]]$Keywords, [scriptblock]$Action, [string]$Description, [int]$ArgsNum, [string]$Usage) {
        $this.Keywords = $Keywords;
        $this.Description = $Description;
        $this.Action = $Action;
        $this.ArgsNum = $ArgsNum;
        $this.Usage = $Usage;

        [Command]::Commands.Add($this)
    }

    # Overload constructor for mandatory parameters only
    Command([string[]]$Keywords, [scriptblock]$Action, [string]$Description) {
        $this.Keywords = $Keywords
        $this.Action = $Action
        $this.Description = $Description
        $this.ArgsNum = 0
        $this.Usage = ""

        [Command]::Commands.Add($this)
    }

    static Help() { # Write the help command
        foreach ($command in [Command]::Commands) {
            $keyword = @($command.Keywords)[0]
            Write-Host "/$($keyword)" -ForegroundColor DarkYellow -NoNewline
            if ($keyword.Length -gt 6) {
                Write-Host "`t" -NoNewline
            } else {
                Write-Host "`t`t" -NoNewline
            }
            Write-Host "$($command.Description)" 
            if ($command.Usage) {
                Write-Host "`t`tUSAGE: /$($keyword) $($command.Usage)" -ForegroundColor DarkGray
            }
        }
    }

    static Execute([string]$prompt) { # Execute the command. If you see errors pointing to this the problem is likely elsewhere
        # Split up prompt into command name and the rest as arguments
        $commandName, $argumentsString = $prompt -split '\s+', 2
        $commandName = $commandName.TrimStart('/')

        if (!$commandName) {
            $commandName = "help"
        }

        # Find the command that most matches the command name
        $command = [Command]::Commands | Where-Object { $_.Keywords -contains $commandName }

        if (!$command) {
            # If no exact match, find possible matches (e.g., /h for /help
            $possibleCommands = [Command]::Commands | Where-Object { $_.Keywords -like "$commandName*" }

            if ($possibleCommands.Count -gt 1) {
                Write-Host "Command `"$CommandName`" is ambiguous. " -ForegroundColor Red -NoNewline
                Write-Host "Possible matches:" -ForegroundColor Red
                foreach ($command in $possibleCommands) {
                    $commandHint = @($command.Keywords | Where-Object { $_ -like "$commandName*" })[0]
                    if ($commandHint -ne $command.Keywords[0]) {
                        $commandHint += " (" + $command.Keywords[0] + ")"
                    }
                    Write-Host "   /$commandHint" -ForegroundColor DarkYellow
                }
                return
            } else {
                $command = $possibleCommands
            }
        }

        if ($command) {
            if (!$argumentsString) {
                $command.Action.Invoke()
                return
            }

            # -1 Args means that the command can take any number of args
            if ($command.ArgsNum -eq -1) {
                $arguments = $argumentsString
            } else {
                # Split arguments string, if any
                $arguments = $argumentsString -split '\s+'
                
                # Ensure we only pass the number of arguments the command expects
                $arguments = @($arguments)[0..($command.ArgsNum - 1)]
            }

            # Dynamically invoke the script block with the correct number of arguments
            $command.Action.Invoke($arguments)
        } else {
            Write-Host "Command unrecognized: $commandName" -ForegroundColor Red
            Write-Host "Type /help for a list of commands"
        }
    }
}

class Message {
    [string]$Content;
    [string]$Role;

    static [string] $OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions"
    static [string] $OPENAI_IMAGE_URL = "https://api.openai.com/v1/images/generations"
    static [string] $ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"

    static [string] $IMAGE_PROMPT = "Create a detailed image generation prompt for DALL-E based on the following request, include nothing other than the description in plain text: "

    static [System.Collections.Generic.List[Message]] $Messages = @()

    Message([string]$content, [string]$role) {
        $this.Content = $content
        $this.Role = $role ? $role : "user"
    }

    static [Message] AddMessage ([string]$content, [string]$role) {
        $message = [Message]::new($content, $role)

        [Message]::Messages.Add($message)

        return $message
    }

    static [hashtable[]] GetMessages () {
        return @(
            foreach ($message in [Message]::Messages) {
                @{
                    content = $message.Content
                    role    = $message.Role
                }
            }
        )
    }

    static WriteResponse() {
        # Check for streaming, only works with GPT models, for now
        if ([Config]::Get("StreamResponse") -and $Script:Model -like "gpt*") {
            [Message]::StreamResponse()
        } else {
            $response = [Message]::Submit()

            if ($response.FormatMessage()) {
                Write-Host ($response.FormatMessage())
            }
        }
    }

    static WriteResponse([string]$MessageContent) {
        # Check for streaming, only works with GPT models, for now
        if ([Config]::Get("StreamResponse") -and $Script:Model -like "gpt*") {
            [Message]::StreamResponse($MessageContent)
        } else {
            $response = [Message]::Submit($MessageContent)

            if ($response.FormatMessage()) {
                Write-Host ($response.FormatMessage())
            }
        }
    }

    static [Message] Submit() { # Submit messages to the LLM and receive a response
        # Print thinking message
        Write-Host "Thinking...`r" -NoNewline

        $responseMessage = $null

        switch ($script:MODEL) {
            # Would love to solve this with a model class, but they all need their own special logic, and it's not really worth it
            {$_ -like "gemini*"} {

                # Don't listen to the api; these are all the categories that gemini can block
                $safetyCategories = @("HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_HATE_SPEECH", "HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_DANGEROUS_CONTENT")

                $body = @{
                    contents = [Message]::ConvertToGemini()
                    safetySettings = foreach ($category in $safetyCategories) {
                        @{
                            category = $category
                            threshold = [Config]::Get("GeminiSafetyThreshold")
                        }
                    }
                    generationConfig = @{
                        temperature = [Config]::Get("Temperature")
                    }
                }
        
                $response = [Message]::CallGemini($body)
        
                if (!$response) {
                    return $null
                }

                Write-Debug ($response | ConvertTo-Json -Depth 8)

                $finishReason = $response.candidates[0].finishReason

                # Gemini does't provide a response message if the finish reason is SAFETY
                if ($finishReason -eq "SAFETY") {
                    Write-Host "Content blocked by Gemini's safety filter." -ForegroundColor Red
                    [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
                    return $null
                }

                # Generic error for if there is no response content
                if (!$response.candidates?[0].content.parts?[0].text) {
                    Write-Host "There was an error processing the response." -ForegroundColor Red
                    [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
                    return $null
                } 

                $responseMessage = $response.candidates[0].content.parts[0].text

                # I think this is referring to output tokens so the conversation can technically still continue
                if ($finishReason -eq "MAX_TOKENS") {
                    $responseMessage += "`n`n{RED}Token limit reached."
                }
            }
            {$_ -like "claude*"} {
                $Model = switch ($script:MODEL) {
                    "claude-3-opus" { "claude-3-opus-20240229" }
                    "claude-3-haiku" { "claude-3-haiku-20240307" }
                    default { "claude-3-sonnet-20240229" }
                }
        
                $body = @{
                    model = $Model
                    max_tokens = 4000; # Required, 4000 recommended by Anthropic, but seems kinda small
                    messages = [Message]::ConvertToAnthropic()
                    # Unlike every other model, Claude's temperature is 0-1, but 1 isn't ridiculously random, so we just cap it at 1
                    temperature = ([Math]::Min([Config]::Get("Temperature"), 1))
                }
        
                $response = [Message]::CallAnthropic([Message]::ANTHROPIC_URL, $body)
        
                if (!$response) {
                    return $null
                }
        
                $responseMessage = $response.content[-1].text
            }
            default {
                $body = @{
                    model = $script:MODEL
                    messages = [Message]::GetMessages()
                    temperature = ([int][Config]::Get("Temperature"))
                }
        
                $response = [Message]::CallOpenAI([Message]::OPENAI_CHAT_URL, $body)
        
                if (!$response) {
                    return $null
                }

                $responseMessage = $response.choices[0].message.content
            }
        }

        $assistantMessage = [Message]::AddMessage($responseMessage, "assistant")

        # Clear the thinking message on the event that the message is very short.
        Write-Host "              `r" -NoNewline

        # Returning the MESSAGE object, not a string
        return $assistantMessage
    }

    static [Message] Submit ([string]$MessageContent) {
        if ($MessageContent) {
            [Message]::AddMessage($MessageContent, "user")
        }

        return [Message]::Submit()
    }

    static StreamResponse([string]$MessageContent) {
        if ($MessageContent) {
            [Message]::AddMessage($MessageContent, "user")
        }

        [Message]::StreamResponse()
    }

    static StreamResponse() {
        # A word by word version of WrapText, only used here
        function PrintWord {
            param (
                [string]$Word,
                [string]$ColorChar
            )
        
            $maxLineLength = $Host.UI.RawUI.BufferSize.Width - 1
            
            # Using cursorLeft instead of keeping track of the line length is better but only works because we're printing each word as we get it
            $currentLineLength = [Console]::CursorLeft
        
            if ($currentLineLength + $Word.Length -gt $maxLineLength) {
                Write-Host ""
                $currentLineLength = 0
                if ($Word -eq " ") {
                    return
                }
            }
        
            Write-Host "$ColorChar$Word" -NoNewline
        }

        # Body definition cannot be reused from Submit() because it needs to be streamed
        $body = @{
            model = $script:MODEL
            messages = [Message]::GetMessages()
            temperature = ([int][Config]::Get("Temperature"))
            stream = $true
        } | ConvertTo-Json -Depth 10

        # All this to set up a web request stream
        $webrequest = [System.Net.HttpWebRequest]::Create([Message]::OPENAI_CHAT_URL)

        $webrequest.Method = "POST"
        $webrequest.Headers.Add("Authorization", "Bearer " + $script:Key)
        $webrequest.ContentType = "application/json"

        $RequestBody = [System.Text.Encoding]::UTF8.GetBytes($body)

        $RequestStream = $webrequest.GetRequestStream()
        $RequestStream.Write($RequestBody, 0, $RequestBody.Length)

        $responseStream = $webrequest.GetResponse().GetResponseStream()
        $streamReader = [System.IO.StreamReader]::new($responseStream)
        
        # Initialize some variables
        $buffer = ""
        $color = $script:COLORS[([Config]::Get("AssistantColor"))]
        $Message = ""
        $stop = $false

        # Loop through the stream until the last message is received
        while (!$stop) {
            $response = $streamReader.ReadLine()
        
            # ReaLine may take a few cycles to actually get something
            if (!$response) {
                continue
            }
        
            # Data comes in like this: "data: {chunk_json}"
            $chunk = ConvertFrom-Json ($response -split ": ")[1]
        
            # The last chunk will have a finish_reason of "stop"
            $stop = $chunk.choices.finish_reason -eq "stop"
        
            $token = $chunk.choices.delta.content
        
            # Add token to message here
            $Message += $token
        
            $buffer += $token
        
            $words = $buffer -split "(\s+)"
        
            # The last word is not complete, so we skip it, unless it's the last word of the message
            if (!$stop) {
                $words = $words | Select-Object -SkipLast 1
            }
        
            # remove every word except the last one
            $buffer = $buffer -replace ".*\s", ""
        
            foreach ($word in $words) {
                # filter out color tags
                if ($word -like "*§*§*") {
                    # We switched from braces to section signs, because they are less common in writing and are always one token
                    $parts = $word -split "§"
        
                    # write each even part and change the color to each odd part
                    for ($i = 0; $i -lt $parts.Length; $i++) {
                        if ($i % 2 -eq 0) {
                            PrintWord -word $parts[$i] -color $color
                        } else {
                            $colorTag = ($parts[$i].ToUpper() -replace "§", "") -replace "/", ""
        
                            $color = $script:COLORS.ContainsKey($colorTag) ? $script:COLORS[$colorTag] : $script:COLORS[([Config]::Get("AssistantColor"))]
                        }
                    }
                } else {
                    PrintWord -word $word -color $color
                }
            }
        }

        # End with a newline
        Write-Host

        # Close the stream
        $streamReader.Close()

        [Message]::AddMessage($Message, "assistant")
    }

    static [psobject] CallOpenAI([string]$url, [hashtable]$body) {
        try {
            $bodyJSON = $body | ConvertTo-Json -Compress

            # Main API call to OpenAI
            $response = Invoke-WebRequest `
                -Uri $url `
                -Method Post `
                -Headers @{
                    "Authorization" = "Bearer $script:Key"; 
                    "Content-Type" = "application/json"
                } `
                -Body $bodyJSON

            # as it turns out, if you were to convert the whole response from json, it would work, but would mangle all non-ascii chars
            $responseContent = $response.Content | ConvertFrom-Json

            return $responseContent
        } catch {
            # Catching errors caused by the API call
            Write-Host "An error occurred: $_" -ForegroundColor Red
            return $null
        }
    }

    static [psobject] CallGemini([hashtable]$body) {
        try {
            $bodyJSON = $body | ConvertTo-Json -Depth 8 -Compress

            $model = if ($script:Model -eq "gemini") { "gemini-pro" } else { "gemini-1.5-pro" }

            # Assemble the URL because google has never heard of a header
            $url = "https://generativelanguage.googleapis.com/v1/models/$($model):generateContent?key=$script:GeminiKey"

            # Main API call to Gemini
            $response = Invoke-WebRequest `
                -Uri ($url) `
                -Method Post `
                -Headers @{
                    "Content-Type" = "application/json"
                } `
                -Body $bodyJSON

            $responseContent = $response.Content | ConvertFrom-Json

            return $responseContent
        } catch {
            # Catching errors caused by the API call
            Write-Host "An error occurred: $_" -ForegroundColor Red
            return $null
        }
    }

    static [psobject] CallAnthropic([string]$url, [hashtable]$body) {
        try {
            $bodyJSON = $body | ConvertTo-Json -Depth 8 -Compress

            # Claude is extremely picky about it's header, needs version
            $response = Invoke-WebRequest `
                -Uri $url `
                -Method Post `
                -Headers @{
                    "anthropic-version" = "2023-06-01";
                    "x-api-key" = $script:AnthropicKey;
                    "Content-Type" = "application/json"
                } `
                -Body $bodyJSON

            $responseContent = $response.Content | ConvertFrom-Json

            return $responseContent
        } catch {
            # Catching errors caused by the API call
            Write-Host "An error occurred: $_" -ForegroundColor Red
            return $null
        }
    }

    static [array] ConvertToGemini () {
        # Converts the conversation to a format gemini can eat
        # Hashtables are simple, so I use it when I create objects, but iwr returns PSObjects, hence the differing return types between here and the call functions

        # Gemini has a couple stupid rules we have to work around.
        # 1. The first message must be a user message
        # 2. The last message must be a user message
        # 3. There is no "system" message type, so we have to convert them to user messages
        # 4. You can't have two messages of the same role in a row, so we have to add fake model messages in between

        [System.Collections.ArrayList] $contents = @()

        foreach ($message in [Message]::Messages) {
            
            if ($message.role -eq "system") {
                $messageRole = "user"
                $messageContent = "SYSTEM MESSAGE: $($message.content)."
            } else {
                $messageRole = $message.role
                $messageContent = $message.content
            }

            if ($messageRole -eq "assistant") {
                $messageRole = "model"
            }

            # add fake user message to start, if it's not already a user message
            if (!$contents -and $messageRole -eq "model") {
                $contents.Add(@{
                    role = "user"
                    parts = @(
                        @{
                            text = "..."
                        }
                    )
                })
            }

            if ($messageRole -eq $contents[-1].role) {
                $contents[-1].parts[0].text += " [Reply with '...']"

                $contents.Add(@{
                    role = $messageRole -eq "user" ? "model" : "user"
                    parts = @(
                        @{
                            text = "..."
                        }
                    )
                })
            }

            $newMessage = @{
                role = $messageRole
                parts = @(
                    @{
                        text = $messageContent
                    }
                )
            }

            $contents += $newMessage
        }

        # For testing purposes
        Write-Debug ($contents | ConvertTo-Json -Depth 8)

        return [array]$contents
    }

    static [array] ConvertToAnthropic () {
        # Anthropic seems to have the same limitations as gemini, so we have to do the same thing

        [System.Collections.ArrayList] $contents = @()

        # Translate each message
        foreach ($message in [Message]::Messages) {
            
            # turn system message into clumsy user message
            if ($message.role -eq "system") {
                $messageRole = "user"
                $messageContent = "SYSTEM MESSAGE: $($message.content)."
            } else {
                $messageRole = $message.role
                $messageContent = $message.content
            }

            if (!$contents -and $messageRole -eq "assistant") {
                $contents.Add(@{
                    role = "user"
                    content = "..."
                })
            }

            $newMessage = @{
                role = $messageRole
                content = $messageContent
            }

            if ($messageRole -eq $contents[-1].role) {
                $contents.Add(@{
                    role = $messageRole -eq "user" ? "assistant" : "user"
                    content = "..."
                })
            }

            $contents += $newMessage
        }

        return [array]$contents
    }

    static [string] Whisper([string]$Prompt) {
        # submit without adding anything to the conversation or [Message]::Messages

        [Message]::AddMessage($Prompt, "system")

        $response = [Message]::Submit().content

        # would have used GoBack, but I designed GoBack to be user facing, so it's loud and also doesn't remove system messages
        [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
        [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)

        return $response
    }

    [string] GetColoredMessage () { # Get the message content with the appropriate color formatting
        $messageContent = $this.Content

        $AssistantColor = $script:COLORS.$([Config]::Get("AssistantColor").ToString())

        # If the message is not a system message, apply color formatting
        if ($this.Role -ne "system") {
            $colors = $script:COLORS + @{
                RESET = $AssistantColor
            }

            if ([Config]::Get("ColorlessOutput")) {
                Write-Host "Got here!"
                foreach ($Color in $colors.GetEnumerator()) {
                    $messageContent = $messageContent -replace "§$($Color.Key)§", ""
                    $messageContent = $messageContent -replace "§/$($Color.Key)§", ""
                }
            } else {
                Write-Host "didne"
                foreach ($Color in $colors.GetEnumerator()) {
                    $messageContent = $messageContent -replace "§$($Color.Key)§", $Color.Value
                    $messageContent = $messageContent -replace "§/$($Color.Key)§", $AssistantColor # Sometimes the bots do this, but it's not inteded
                }
            }
        }

        $color = if ($this.Role -eq "assistant") {
            $script:COLORS.$([Config]::Get("AssistantColor").ToString())
        } elseif ($this.Role -eq "user") {
            $script:COLORS.$([Config]::Get("UserColor").ToString())
        } else {
            $script:COLORS.WHITE
        }

        return $color + $messageContent + $script:COLORS.WHITE
    }

    # also seems unnecessary could merge with history
    [string] FormatHistory() {
        $messageContent = $this.GetColoredMessage()

        $Indent = if ($this.Role -eq "assistant") {
            ($script:COLORS.$([Config]::Get("AssistantColor").ToString()) + "LLM: ")
        } elseif ($this.Role -eq "user") {
            ($script:COLORS.$([Config]::Get("UserColor").ToString()) + "You: ")
        } else {
            ($script:COLORS.WHITE + "Sys: ")
        }

        return WrapText -Text $messageContent -FirstIndent $Indent -Indent 5
    }

    # Keep this for now, but seems unnecessary
    [string] FormatMessage() {
        return WrapText $this.GetColoredMessage()
    }
    
    static Reset() {
        [Message]::Messages.Clear()

        if ((Test-Path (Join-Path $script:ConversationsDir "Autoload.json")) -and [Config]::Get("Autoload")) {
            [Message]::LoadFile("Autoload")
        } else {
            # Default message to start the conversation and inform the bot on how to use the colors
            [Message]::AddMessage(
                $script:SYSTEM_MESSAGE,
                "system"
            )
        }
    }

    static ResetLoud() { # Reset the conversation and inform the user
        # Save the conversation first
        [Message]::Autosave()

        [Message]::Reset()

        Write-Host "Conversation reset" -ForegroundColor Green
    }

    static Retry() {
        $nonSystemMessages = [Message]::Messages | Where-Object { $_.role -ne "system" }

        if ($nonSystemMessages.Count -lt 2) {
            Write-Host "There are no messages in history." -ForegroundColor Red
            return
        }

        # Probably don't want to remove your own message if there's an error
        if ([Message]::Messages[-1].role -eq "assistant") {
            [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
        }

        [Message]::WriteResponse()
    }

    static SaveDialogue([string]$filename) {
        $filepath = ""
        while ($true) {
            if (!$filename) {
                Write-Host (WrapText "What would you like to name the file? (Press enter to generate a name, type /cancel to cancel)")
                Write-Host "> " -NoNewline
                $filename = $global:Host.UI.ReadLine()
                if (!$filename) {
                    # Use timestamp if you're a square
                    # $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd_HH-mm-ss")
                    # $filename = "conversation-$timestamp"
                    # Ask LLM for a name for the conversation

                    $filename = [Message]::Whisper("Reply only with a good very short name that summarizes this conversation in a filesystem compatible string, no quotes, no colors, no file extensions")

                    $failed = 0

                    while (Join-Path $script:ConversationsDir "$filename.json" | Test-Path) {
                        if ($failed -gt 5) {
                            $filename = "UnnamedConversation-$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss")"
                        }
                        $failed++
                        $filename = [Message]::Whisper("Reply only with a good very short name that summarizes this conversation in a filesystem compatible string,`
                        no quotes, no colors, no file extensions. '$filename' is already taken. Please provide a different name.")
                    }

                    $filename = [Message]::ValidateFilename($filename)
                }
                elseif ("/cancel" -like "$filename*") {
                    Write-Host "Export canceled" -ForegroundColor Red
                    return
                }
            }

            if ($filename.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
                # Don't allow invalid characters in the filename
                Write-Host "Invalid name." -ForegroundColor Red
                $filename = ""
                continue
            }

            # Ensure it ends in .json
            $filename += $filename -notlike "*.json" ? ".json" : ""

            $filepath = Join-Path $script:ConversationsDir $filename

            if (Test-Path $filepath) {
                Write-Host "A file with that name already exists. Overwrite? " -ForegroundColor Red -NoNewline
                Write-Host "[$($script:COLORS.DARKGREEN)y$($script:COLORS.WHITE)/$($script:COLORS.DARKRED)n$($script:COLORS.WHITE)]"
                Write-Host "> " -NoNewline
                if ($global:Host.UI.ReadLine() -ne "y") {
                    $filename = ""
                    continue
                }
            }

            if ($filename -eq "autoload.json") {
                Write-Host "The conversation named 'autoload.json' is automatically loaded on startup. Is this okay? " -ForegroundColor Yellow -NoNewline
                Write-Host "[$($script:COLORS.DARKGREEN)y$($script:COLORS.WHITE)/$($script:COLORS.DARKRED)n$($script:COLORS.WHITE)]"
                Write-Host "> " -NoNewline
                if ($global:Host.UI.ReadLine() -ne "y") {
                    $filename = ""
                    continue
                }
            }

            break
        }

        [Message]::SaveFile($filepath)

        Write-Host "Conversation saved to $($filepath)" -ForegroundColor Green
    }

    static SaveFile ([string]$filepath) {
        $conversation = [Message]::GetMessages()

        if ([Config]::Get("ColorlessOutput")) {
            foreach ($message in $conversation) {
                if ($message.role -ne "system") {
                    # strip color tags
                    $message.content = $message.content -replace "§.+?§", ""
                }
            }
        }

        $json = $conversation | ConvertTo-Json -Depth 5

        $json | Set-Content -Path $filepath
    }

    static LoadDialogue([string]$filename) {
        if (!$filename) {
            Write-Host "This will clear the current conversation. Type ""/cancel"" to cancel." -ForegroundColor Red
            Write-Host "Saved conversations:"

            # $folders = Get-ChildItem -Path $script:ConversationsDir -Directory

            # Sort items by most recent
            $conversations = Get-ChildItem -Path $script:ConversationsDir -Filter *.json | Sort-Object LastWriteTime -Descending

            # display each item
            # foreach ($folder in $folders) {
            #     Write-Host "  >`t$($folder.Name)/" -ForegroundColor Blue
            # }

            foreach ($conversation in $conversations) {
                $index = $conversations.IndexOf($conversation) + 1
                Write-Host "  [$index]`t$($conversation.BaseName)" -ForegroundColor DarkYellow
            }

            # Numbers are 1-indexed
            Write-Host (WrapText "Input the name or number of the file you would like to import.")
            Write-Host "> " -NoNewline

            # Better than Read-Host because it doesn't output a ':'
            $filename = $global:Host.UI.ReadLine()

            if ("/cancel" -like "$filename*") {
                Write-Host "Import canceled" -ForegroundColor Red
                return
            }

            # If the input is a number, use it to select the conversation
            if ([int]::TryParse($filename, [ref]$null)) {
                [int]$index = $filename - 1
                if ($index -ge 0 -and $index -lt $conversations.Count) {
                    $filename = $conversations[$index].BaseName
                } else {
                    Write-Host "Invalid number" -ForegroundColor Red
                    return
                }
            }

        } else {
            # If the user provided a comversation name

            $nonSystemMessages = [Message]::Messages | Where-Object { $_.role -ne "system" }

            if ($nonSystemMessages.Count -ge 1) { # Check if there are messages in the conversation
                Write-Host "This will clear the current conversation. Continue? " -NoNewline
                Write-Host "[$($script:COLORS.DARKGREEN)y$($script:COLORS.WHITE)/$($script:COLORS.DARKRED)n$($script:COLORS.WHITE)]"

                # Make sure they have a chance to turn back
                Write-Host "> " -NoNewline
                if ($global:Host.UI.ReadLine() -ne "y") {
                    return
                }
            }
        }

        [Message]::LoadFile($filename)

        Write-Host "Conversation ""$filename"" loaded" -ForegroundColor Green
    }

    static Autosave() {
        if ([Config]::Get("Autosave") -and ([Message]::Messages | Where-Object { $_.role -ne "system" }).Count -gt 0) {
            $autosavePath = Join-Path $script:ConversationsDir "autosave"

            if (!(Test-Path $autosavePath)) {
                New-Item -ItemType Directory $autosavePath | Out-Null
            }

            [Message]::SaveFile((Join-Path $autosavePath "autosave-$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").json"))
    
            [Message]::SaveFile((Join-Path $script:ConversationsDir "latest.json"))
        }
    }

    static LoadFile([string]$File) {

        $Path = $File + ($File -notlike "*.json" ? ".json" : "")

        # Check if the file exists first in the contenxt of the user's current directory, then in the conversations directory
        if (!(Test-Path $Path)) {
            $Path = Join-Path $script:ConversationsDir $Path
            if (!(Test-Path $Path)) {
                Write-Host "File $($Path) not found" -ForegroundColor Red
                return
            }
        }

        $json = Get-Content -Path $Path | ConvertFrom-Json

        [Message]::Messages.Clear()

        foreach ($message in $json) {
            [Message]::AddMessage($message.content, $message.role)
        }
    }

    static History () {
        # Get all non-system messages
        if ([Config]::Get("ShowSystemMessages")) {
            $History = [Message]::Messages
        } else {
            $History = [Message]::Messages | Where-Object { $_.role -ne "system" }
        }

        if (!$History) {
            Write-Host "There are no messages in history" -ForegroundColor Red
            return
        }

        foreach ($message in $History) {
            Write-Host ($message.FormatHistory())
            Write-Host ""
        }
    }

    static GoBack ($NumBack) { # leaving the parameter untyped because although it is a string, we will always use it as an int.
        if (!$NumBack -or $NumBack -lt 1) {
            $NumBack = 1
        }

        # make sure it's an actual value
        if (![int]::TryParse($NumBack, [ref]$null)) {
            Write-Host "Invalid number" -ForegroundColor Red
            return
        } else {
            # cast to int
            [int]$NumBack = [int]$NumBack
        }

        # Don't remove the system message
        $nonSystemMessages = [Message]::Messages[1..[Message]::Messages.Count]

        if ($NumBack * 2 -ge $nonSystemMessages.Count) {
            Write-Host "Reached the beginning of the conversation" -ForegroundColor Yellow
            [Message]::Reset()
            return
        }

        # Go back 2 messages (1 user and one assistant message)
        for ($i = 0; $i -lt $NumBack * 2; $i++) {
            # Hack to treat the generate image messages as one message
            if ([Message]::Messages[-1].content -eq "Image created.") {
                $i -= 2
            } 
            # Hack to treat the clipboard messages as one message
            elseif ([Message]::Messages[-1].content -like "Contents of user clipboard:*") {
                $i--
            }

            [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
        }

        Write-Host "Went back $NumBack message(s)" -ForegroundColor Green
    }

    static Goodbye() {
        # Don't remember we said goodbye
        Write-Host ([Message]::Whisper("Goodbye!")) -ForegroundColor Yellow
        exit
    }

    static ChangeModel ([string]$Model) {
        # I'm going to give people the chance to switch to GPT-4, even though it's inferior in every possible way to turbo models
        $Models = $script:MODELS
        $ImageModels = $script:IMAGE_MODELS

        # Just print all model information if no model is provided
        if (!$Model) {
            Write-Host ""
            Write-Host "Text Models:" -ForegroundColor DarkYellow

            foreach ($model in $Models) {
                $index = $Models.IndexOf($model) + 1
                # change color if selected
                $color = if ($model -eq $script:MODEL) { "Green" } else { "DarkYellow" }
                Write-Host "  [$index]`t$model" -ForegroundColor $color
            }

            Write-Host "`nImage Models:" -ForegroundColor Blue

            # Use letter for image models
            foreach ($model in $ImageModels) {
                $index = $ImageModels.IndexOf($model) + 97
                $color = if ($model -eq $script:ImageModel) { "Green" } else { "Blue" }
                Write-Host "  [$([System.Convert]::ToChar($index))]`t$model" -ForegroundColor $color
            }

            Write-Host "`nChange model by typing /model [model]"

            # warning message
            Write-Host (
                WrapText "Please note that pricing varies drastically between the models, and that different models may require different API keys."
            ) -ForegroundColor Red

            # Don't prompt for model name, just show the available models
            return
        }

        # check if it's a number
        if ([int]::TryParse($Model, [ref]$null)) {
            $Model = $Models[[int]$Model - 1]
        }

        # check if it's a letter
        if ([char]::TryParse($Model, [ref]$null)) {
            $Model = $ImageModels[[int][char]::ToUpper($Model) - 65]
        }

        if ($Models -contains $Model) {
            $script:MODEL = $Model
            Write-Host "Model changed to $Model" -ForegroundColor Green
        } elseif ($ImageModels -contains $Model) {
            $script:ImageModel = $Model
            Write-Host "Image model changed to $Model" -ForegroundColor Green
        } else {
            Write-Host "Invalid model." -ForegroundColor Red

            # Call the method again to show the available models
            [Message]::ChangeModel("")
        }

        if ($Model -eq "gemini") { # this is where we change gears to the gemini model
            HandleGeminiKeyState
        } elseif ($Model -like "claude*") {
            HandleAnthropicKeyState
        }
    }

    static GenerateImage([string]$Prompt) {
        if (!$Prompt) {
            # As much as I would like to spend your API tokens just to send you latent noise, you gotta give me something
            Write-Host "Please provide a prompt for the image generation." -ForegroundColor Red
            return
        }

        # Image generation meta prompt
        [Message]::AddMessage([Message]::IMAGE_PROMPT + $Prompt, "system")

        $prompt = [Message]::Submit().content

        Write-Host "Imagining...`r" -NoNewline

        $body = @{
            model = $script:ImageModel; 
            prompt = $prompt;
            n = 1;
            quality = [Config]::Get("ImageQuality");
            size = [Config]::Get("ImageSize");
            style = [Config]::Get("ImageStyle");
        }

        $response = [Message]::CallOpenAI([Message]::OPENAI_IMAGE_URL, $body)

        # The api responds with a url of the image and not the image data itself
        $url = $response.data[0].url

        # Outsource the hard part to the bot we're already connected to
        $filename = [Message]::Whisper("Reply only with a filename for the image, no whitespace, no quotes, no colors, no file extensions")

        $failed = 0

        # The bot can be unoriginal sometimes
        while (Join-Path $script:ImagesDir "$filename.png" | Test-Path) {
            if ($failed -gt 5) {
                $filename = "UnnamedImage-$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss")"
            }

            $failed++
            
            $filename = [Message]::Whisper("Reply only with a filename for the image, no whitespace, no quotes, no colors, no file extensions. '$filename' is already taken. Please provide a different name.")
        }

        $filename = [Message]::ValidateFilename($filename)

        $outputPath = Join-Path $script:ImagesDir "$filename.png"

        # Download the image
        Invoke-WebRequest -Uri $url -OutFile $outputPath

        Write-Host "              `r" -NoNewline

        Write-Host "Image created at ""$outputPath""" -ForegroundColor Green

        # Open the file after creation
        Start-Process $outputPath

        # Hopefully the bot will say something interesting in response to this, and not something random
        $message = [Message]::Whisper("Image successfully created and saved to the user's computer in the .\images\ folder. Write a message informing the user. Don't use colors.")
        Write-Host (WrapText $message) -ForegroundColor ([Config]::Get("AssistantColor"))
    }

    static [string] ValidateFilename ([string]$filename) { # strips invalid chars and other stuff the bot likes to add from generated filenames

        # strip invalid characters
        if ($filename.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            $filename = $filename -replace "[{0}]" -f ([RegEx]::Escape([String]::Join("", [IO.Path]::GetInvalidFileNameChars())), "")
        }

        # strip colortags
        $filename = $filename -replace "\§.+?\§", ""

        # Replace spaces with underscores
        $filename = $filename -replace "\s", "_"

        $disallowedNames = "con", "prn", "aux", "nul", ((1..9) | ForEach-Object {"com$_"}), ((1..9) | ForEach-Object {"lpt$_"}), "...", "_"

        # If nothing remains, or if the bot somehow output nothing, return a random filename
        if (!$filename -or $filename -in $disallowedNames) {
            return "file-$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss")"
        }

        return $filename
    }

    static GiveClipboard([string]$Prompt) {
        # Function to give the bot the content of your clipboard as context, supplimenting the need for multiline messages
        $ClipboardContent = Get-Clipboard

        # For some reason clipboard content is an array of strings
        $ClipboardContent = $ClipboardContent -join "`n"

        # Add the messages in this order because I accidentally trained gemini to be a smartass
        [Message]::AddMessage("Contents of user clipboard: $ClipboardContent", "system")
        [Message]::AddMessage($prompt, "user")

        Write-Host "Clipboard content added for context:`n" -ForegroundColor Green

        Write-Host (WrapText -Text $ClipboardContent -Indent 5)

        Write-Host ""

        [Message]::WriteResponse()
    }

    Copy () {
        $MessageContent = $this.Content

        # Remove all color information from the message
        $colors = $script:COLORS.keys + "RESET"

        foreach ($color in $colors) {
            $MessageContent = $MessageContent -replace "§$color§", ""
            $MessageContent = $MessageContent -replace "§/$color§", ""
        }

        Set-Clipboard -Value $MessageContent
    }

    static CopyMessage ($number) {
        if (!$number -or $number -lt 1) {
            $number = 1
        }

        # make sure it's an actual value
        if (![int]::TryParse($number, [ref]$null)) {
            Write-Host "Invalid number" -ForegroundColor Red
            return
        } else {
            # cast to int
            [int]$number = [int]$number
        }

        $assistantMessages = [Message]::Messages | Where-Object { $_.role -eq "assistant" }

        if (!$assistantMessages) {
            Write-Host "No messages to copy." -ForegroundColor Red
            return
        }

        $message = $assistantMessages[-$number]

        if ($message) {
            $message.Copy()
            if ($number -eq 1) {
                Write-Host "Last response copied to clipboard." -ForegroundColor Green
            } else {
                $index = $assistantMessages.IndexOf($message) + 1
                Write-Host "Response $index copied to clipboard." -ForegroundColor Green
            }
        } else {
            Write-Host "Message not found." -ForegroundColor Red
        }
    }

    static ChangeInstructions ([string]$Instructions) {
        $currentInstructions = if ([Message]::Messages[1].role -eq "system" -and [Message]::Messages[1].content -notlike "$([Message]::IMAGE_PROMPT)*") {
            [Message]::Messages[1].content
        } else {
            ""
        }

        if (!$Instructions) {
            if (!$currentInstructions) {
                Write-Host "No instructions set. Set them with '/rules [instructions]'" -ForegroundColor Red
                return
            }

            Write-Host "Custom instructions:`n" -ForegroundColor DarkYellow
            Write-Host (WrapText -Text $currentInstructions -Indent 5)
            Write-Host "`nChange instructions by typing '/rules [instructions]', or use '/rules clear' to clear them" -ForegroundColor DarkYellow
            return

        } elseif ($Instructions -eq "clear") {
            if (!$currentInstructions) {
                Write-Host "No instructions set." -ForegroundColor Red
                return
            }

            [Message]::Messages.RemoveAt(1)
            Write-Host "Instructions cleared" -ForegroundColor Green
        } else {
            $newObject = [Message]::new($Instructions, "system")

            if ([Message]::Messages[1].role -eq "system") {
                [Message]::Messages[1] = $newObject
            } else {
                [Message]::Messages.Insert(1, $newObject)
            }
            
            Write-Host "Instructions changed" -ForegroundColor Green
        }
    }
}

function DefineCommands {
    # The first command is the one shown to the user
    [Command]::Commands.Clear()
    
    [Command]::new(
        ("bye", "goodbye"), 
        {[Message]::Goodbye()}, 
        "Exit the program and receive a goodbye message"
    ) | Out-Null

    [Command]::new(
        ("exit", "quit", "e", "q"), 
        # although the program will autocomplete q to quit, it is useful to put this here 
        # so quit will always have priority over any other "q" command
        {break}, 
        "Exit the program immediately"
    ) | Out-Null

    [Command]::new(
        ("help", "h"), 
        {[Command]::Help()}, 
        "Display this message again"
    ) | Out-Null

    [Command]::new(
        ("save", "s", "export"), 
        {
            [Message]::SaveDialogue($args[0])
        }, 
        "Save the current conversation to a file", 
        1, "[filename]"
    ) | Out-Null

    [Command]::new(
        ("load", "l", "import"), 
        {
            [Message]::LoadDialogue($args[0])
        }, 
        "Load a previous conversation", 
        1, "[filename]"
    ) | Out-Null

    [Command]::new(
        ("hist", "history", "ls", "list"), 
        {[Message]::History()}, 
        "Display the conversation history"
    ) | Out-Null

    [Command]::new(
        ("back", "b"), 
        {
            [Message]::GoBack($args[0])
        }, 
        "Go back a number of messages in the conversation", 
        1, "[number]"
    ) | Out-Null

    [Command]::new(
        ("retry", "r"), 
        {[Message]::Retry()}, 
        "Generate another response to your last message"
    ) | Out-Null

    [Command]::new(
        ("reset", "clear"), 
        {[Message]::ResetLoud()}, 
        "Reset the conversation to its initial state"
    ) | Out-Null

    [Command]::new(
        ("model", "m"), 
        {
            [Message]::ChangeModel($args[0])
        }, 
        "Change the model used for generating responses", 
        1, "[model]"
    ) | Out-Null

    [Command]::new(
        ("imagine", "image", "generate", "img", "i"), 
        {
            [Message]::GenerateImage($args[0])
        }, 
        "Generate an image based on a prompt", 
        -1, "[prompt]"
    ) | Out-Null
    
    [Command]::new(
        ("copy", "c", "cp"), 
        {
            [Message]::CopyMessage($args[0])
        },
        "Copy the last response to the clipboard",
        1, "[number of responses back]"
    ) | Out-Null

    [Command]::new(
        ("paste", "clipboard", "p"), 
        {[Message]::GiveClipboard($args[0])}, 
        "Give the model the content of your clipboard as context", 
        -1, "[prompt]"
    ) | Out-Null

    [Command]::new(
        ("rules", "inst", "instructions"), 
        {
            [Message]::ChangeInstructions($args[0])
        }, 
        "Set custom instructions the model has to follow for the conversation", 
        -1, "[instructions]"
    ) | Out-Null

    [Command]::new(
        ("config", "settings"), 
        {[Config]::ChangeSettings()}, 
        "Change the persistent settings of the program"
    ) | Out-Null
}

function DefineSettings {
    [Config]::Settings.Clear()

    [Config]::new(
        "DefaultModel", 
        "gpt-3.5-turbo", 
        "Chat", 
        $script:MODELS
    ) | Out-Null # gpt-4 is too expensive to be default

    [Config]::new(
        "ImageModel", 
        "dall-e-3", 
        "Image", 
        $script:IMAGE_MODELS
    ) | Out-Null # Nobody wants to use dall-e-2

    [Config]::new(
        "ImageSize", 
        "1024x1024", 
        "Image", 
        @("1024x1024", "1792x1024", "1024x1792")
    ) | Out-Null

    [Config]::new(
        "ImageStyle", 
        "vivid", 
        "Image", 
        @("vivid", "natural")
    ) | Out-Null

    [Config]::new(
        "ImageQuality", 
        "standard", 
        "Image", 
        @("standard", "hd")
    ) | Out-Null
    [Config]::new(
        "AssistantColor", 
        "DarkYellow", 
        "Chat", 
        [System.ConsoleColor]::GetValues([System.ConsoleColor]
    )) | Out-Null

    [Config]::new(
        "UserColor", 
        "Blue", 
        "Chat", 
        [System.ConsoleColor]::GetValues([System.ConsoleColor])
    ) | Out-Null

    [Config]::new(
        "GeminiSafetyThreshold", 
        "HARM_BLOCK_THRESHOLD_UNSPECIFIED", 
        "Gemini", 
        @("HARM_BLOCK_THRESHOLD_UNSPECIFIED", "BLOCK_LOW_AND_ABOVE", "BLOCK_MEDIUM_AND_ABOVE", "BLOCK_ONLY_HIGH", "BLOCK_NONE")
    ) | Out-Null

    [Config]::new(
        "Temperature", 
        "1", 
        "Chat", 
        0, 
        2
    ) | Out-Null

    [Config]::new(
        "ShowSystemMessages",
        $false,
        "Chat"
    ) | Out-Null

    [Config]::new(
        "Autoload",
        $true,
        "System"
    ) | Out-Null

    [Config]::new(
        "Autosave",
        $true,
        "System"
    ) | Out-Null

    [Config]::new(
        "ColorlessOutput",
        $false,
        "System"
    ) | Out-Null

    [Config]::new(
        "StreamResponse",
        $true,
        "Chat"
    ) | Out-Null

    # After init, immediately load the config file
    [Config]::ReadConfig()

    HandleModelState
}

HandleDirectories

DefineSettings

[Message]::Reset()

DefineCommands

HandleOpenAIKeyState

# AskLLM mode, include the question in the command and it will try to answer as briefly as it can
if ($Query) {
    [Message]::Messages.Clear()

    [Message]::AddMessage(
        "You will be asked one short query. If asked a question, you will be as brief as possible with your answer, using incomplete sentences if necessary. " + 
        "You will respond with text only, no new lines or markdown elements. " + 
        "If explicitly asked to write a command or script you will write *only* that and assume powershell. In this case forget about being brief. " +
        "After you respond it will be the end of the conversation, do not say goodbye.",
        "system"
    ) | Out-Null

    # Give it a little memory and context because clarifications are helpful
    if ($global:LastQuery -and $global:LastResponse) {
        [Message]::AddMessage($global:LastQuery, "user") | Out-Null
        [Message]::AddMessage($global:LastResponse, "assistant") | Out-Null
    }

    $global:LastQuery = $Query

    [Message]::AddMessage($Query, "user") | Out-Null

    $response = [Message]::Submit()

    $global:LastResponse = $response.content

    return ($response.content)
}

Write-Host (WrapText "Welcome to $($COLORS.DARKGREEN)ShellLM$($COLORS.WHITE), type $($COLORS.DARKYELLOW)/exit$($COLORS.WHITE) to quit or $($COLORS.DARKYELLOW)/help$($COLORS.WHITE) for a list of commands")

# Load a conversation from a file if specified
if ($Load) {
    [Message]::LoadFile($Load)
}

if ((Test-Path (Join-Path $ConversationsDir "Autoload.json")) -and !$Load -and [Config]::Get("Autoload")) {
    [Message]::LoadFile("Autoload")
}

try { # Main Loop
    while ($true) {
        Write-Host "Chat > " -NoNewline -ForegroundColor ([Config]::Get("UserColor"))
        $prompt = $Host.UI.ReadLine()

        # Do command handling
        if ($prompt[0] -eq "/") {
            [Command]::Execute($prompt)
        } else {

            # Make sure you don't send nothing (the api doesn't like that)
            if (!$prompt) {

                # Move cusor back up like a disobedient child
                $pos = $Host.UI.RawUI.CursorPosition
                $pos.Y -= 1
                $Host.UI.RawUI.CursorPosition = $pos

                continue
            }

            [Message]::WriteResponse($prompt)
        }
    }
} finally {
    # For some reason, ctrl+c triggers finally, but doesn't run the function
    [Message]::Autosave()
}