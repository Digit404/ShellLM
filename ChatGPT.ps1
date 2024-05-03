<#
.SYNOPSIS
    This script is a PowerShell implementation of a chatbot using OpenAI's GPT models.

.DESCRIPTION
    The script allows users to interact with the chatbot by sending messages and receiving responses from the GPT model. It supports multiple commands and provides a conversational interface.

.PARAMETER Query
    Specifies the user's message/query to be sent to the chatbot.

.PARAMETER Model
    Specifies the GPT model to use for generating responses. The available options are "gpt-4-turbo", and "gpt-3.5-turbo". The default value is "gpt-3.5-turbo".

.PARAMETER ImageModel
    Specifies the DALL-E model to use for generating images. The available options are "dall-e-2" and "dall-e-3". The default value is "dall-e-2".

.PARAMETER Load
    Specifies a file containing a conversation to load. This can be used to continue a previous conversation.

.PARAMETER Key
    Specifies the OpenAI API key to use for making API calls to the OpenAI chat/completions endpoint.
    If not provided, the script will prompt the user to enter the API key. It will also automatically set the API key as an environment variable.

.NOTES
    Version 2.3
    - This script requires an OpenAI API key to make API calls to the OpenAI chat/completions endpoint.
    - The script uses ANSI escape codes for color formatting in the terminal.
    - The script supports various commands that can be used to interact with the chatbot.
    - The script provides a conversational history and allows exporting the conversation to a JSON file.

.EXAMPLE
    PS C:\> .\ChatGPT.ps1 -Model "gpt-4" -Query "What is the capital of ecuador?"

    This example runs the script using the "gpt-4" model and asks the question "What is the capital of ecuador?".

.EXAMPLE
    PS C:\> .\ChatGPT.ps1 -Load conversation

    This example loads a conversation from the "conversation.json" file within the conversations dir and continues the conversation.
#>

[CmdletBinding(PositionalBinding=$false)] # Important as it make it so you can throw the model param anywhere
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet(
        "gpt-3",
        "gpt-3.5",
        "gpt-3.5-turbo",
        "gpt-4",
        "gpt-4-turbo",
        "gemini"
    )]
    [string] $Model = "gpt-3.5-turbo", # gpt-4 is too expensive to be default

    [Parameter(Mandatory=$false)]
    [ValidateSet(
        "dall-e-2",
        "dall-e-3"
    )]
    [string] $ImageModel = "dall-e-3", # Nobody wants to use dall-e-2

    [Parameter(ValueFromRemainingArguments)]
    [string] $Query,

    [Parameter(Mandatory=$false)]
    [Alias("l", "Import", "File", "Conversation")]
    [string] $Load,

    [Parameter(Mandatory=$false)]
    [string] $Key,

    [Parameter(Mandatory=$false)]
    [string] $GeminiKey,

    [Parameter(Mandatory=$false)]
    [switch] $Clear,

    [Parameter(Mandatory=$false)]
    [System.ConsoleColor] $AssistantColor = "DarkYellow",

    [Parameter(Mandatory=$false)]
    [System.ConsoleColor] $UserColor = "Blue"
)

$ESC = [char]27 # Escape char for colors

# Consider making this a parameter
$CONVERSATIONS_DIR = Join-Path $PSScriptRoot .\conversations\

# Added this part because the bot will always remember the last interaction and sometimes this is undesirable if you want a different output
if ($Clear) {
    $global:LastQuery = ""
    $global:LastResponse = ""
    Write-Host "AskGPT context cleared" -ForegroundColor Yellow
    if (!$Query) {
        exit
    }
}

if (!(Test-Path $CONVERSATIONS_DIR)) {
    New-Item -ItemType Directory -Path $CONVERSATIONS_DIR | Out-Null
}

$CONVERSATIONS_DIR = Resolve-Path ($CONVERSATIONS_DIR)

$IMAGES_DIR = Join-Path $PSScriptRoot .\images\

if (!(Test-Path $IMAGES_DIR)) {
    New-Item -ItemType Directory -Path $IMAGES_DIR | Out-Null
}

$IMAGES_DIR = Resolve-Path ($IMAGES_DIR)

# Handle key state

function HandleOpenAIKeyState { # Just to group it together, this is the only place it's used
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

HandleOpenAIKeyState

if ($Model -eq "gemini") {
    HandleGeminiKeyState
}

# the turbo models are better than the base models and are less expensive
if ($model -eq "gpt-3" -or $model -eq "gpt-3.5") {
    $model = "gpt-3.5-turbo"
}

if ($model -eq "gpt-4") {
    $model = "gpt-4-turbo"
}

$SYSTEM_MESSAGE = (
    'You are communicating through the terminal. Do not use markdown syntax. ' +
    'You can use `{COLOR}` to change the color of your text for emphasis or whatever you want, and {RESET} to go back. ' +
    'If you write code, do not use "```". Use colors for syntax highlighting instead. ' +
    'Colors available are RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE, GRAY, RESET. ' +
    'You can also use DARK colors using {DARKCOLOR}. (E.g. {DARKRED}Hello{RESET}).' 
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

$COLORS.RESET = $COLORS.$($AssistantColor.ToString())

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

class Command {
    [string[]]$Keywords; # The different keywords that can be used to trigger the command, the first one is the one shown to user
    [string]$Description; # Short description of the command when /help is called
    [scriptblock]$Action; # The action to be executed when the command is called
    [int]$ArgsNum; # Number of arguments the command expects
    [string]$Usage; # Usage example for the command without the command itself

    # I don't think argsNum is doing anything anymore, but I'm afraid to remove it...

    static [System.Collections.ArrayList]$Commands = @()

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
    [string]$content;
    [string]$role;

    static [string] $AI_COLOR = $script:COLORS.$($script:AssistantColor.ToString())
    static [string] $USER_COLOR = $script:COLORS.$($script:UserColor.ToString())

    static [string] $CHAT_URL = "https://api.openai.com/v1/chat/completions"
    static [string] $IMAGE_URL = "https://api.openai.com/v1/images/generations"

    static [System.Collections.ArrayList]$Messages = @()

    Message([string]$content, [string]$role) {
        $this.content = $content
        $this.role = $role ? $role : "user"
    }

    static [Message] AddMessage ([string]$content, [string]$role) {
        $message = [Message]::new($content, $role)

        [Message]::Messages.Add($message)

        return $message
    }

    static [Message] Query([string]$MessageContent) { # Wrapper for submit to add a message from the user first

        # It doesn't exist if it's not added to the list
        if ($MessageContent) {
            [Message]::AddMessage($MessageContent, "user")
        }

        return [Message]::Submit()
    }

    static [Message] Submit() { # Submit messages to the GPT model and receive a response
        # Print thinking message
        Write-Host "Thinking...`r" -NoNewline
        
        if ($script:MODEL -eq "gemini") {

            $body = @{
                contents = [Message]::ConvertToGemini()
            }

            $response = [Message]::CallGemini($body)

            if (!$response) {
                return $null
            }

            $responseMessage = $response.candidates[0].content.parts[0].text

            $assistantMessage = [Message]::AddMessage($responseMessage, "assistant")
            
        } else {
            # Define body for API call
            $body = @{
                model = $script:MODEL; 
                messages = [Message]::Messages
            }

            # Main API call to OpenAI
            $response = [Message]::CallOpenAI([Message]::CHAT_URL, $body)

            if (!$response) {
                return $null
            }

            $assistantMessage = [Message]::AddMessage($response.choices[0].message.content, $response.choices[0].message.role)
        }

        # Clear the thinking message on the event that the message is very short.
        Write-Host "              `r" -NoNewline

        # Returning the MESSAGE object, not a string
        return $assistantMessage
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
                -Body $bodyJSON | ConvertFrom-Json

            return $response
        } catch {
            # Catching errors caused by the API call
            Write-Host "An error occurred: $_" -ForegroundColor Red
            return $null
        }
    }

    static [psobject] CallGemini([hashtable]$body) {
        try {
            $bodyJSON = $body | ConvertTo-Json -Depth 8 -Compress

            $model = "gemini-pro" # Used for if google takes 1.5 out of preview, currently 1.5 is rate limited to 2 requests per minute. Not useful

            # Assemble the URL because google has never heard of a header
            $url = "https://generativelanguage.googleapis.com/v1beta/models/$($model):generateContent?key=$script:GeminiKey"

            # Main API call to Gemini
            $response = Invoke-WebRequest `
                -Uri ($url) `
                -Method Post `
                -Headers @{
                    "Content-Type" = "application/json"
                } `
                -Body $bodyJSON | ConvertFrom-Json

            return $response
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
            $messageRole = if ($message.role -eq "user") {
                "user"
            } elseif ($message.role -eq "assistant") {
                "model"
            } else {
                "system"
            }

            $messageContent = $message.content

            # turn system message to user message
            if ($messageRole -eq "system") {
                $messageRole = "user"
                $messageContent = "SYSTEM MESSAGE: $($message.content)."
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

        # Insert fake messages to work around gemini's limitations

        if ($contents[0].role -ne "user") {
            $contents.Insert(0, @{
                role = "user"
                parts = @(
                    @{
                        text = "..."
                    }
                )
            })
        }

        if ($contents[-1].role -ne "user") {
            $contents.Add(@{
                role = "user"
                parts = @(
                    @{
                        text = "..."
                    }
                )
            })
        }

        for ($i = 1; $i -lt $contents.Count; $i++) {
            if ($contents[$i].role -eq $contents[$i - 1].role) {

                $messageRole = $contents[$i].role -eq "user" ? "model" : "user"

                $contents.Insert($i, @{
                    role = $messageRole
                    parts = @(
                        @{
                            text = "..."
                        }
                    )
                })
            }
        }

        # For testing purposes
        Write-Debug ($contents | ConvertTo-Json -Depth 8)

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
        $messageContent = $this.content

        # If the message is not a system message, apply color formatting
        if (!($this.role -eq "system")) {
            foreach ($Item in $script:COLORS.GetEnumerator()) {
                $messageContent = $messageContent -replace "{$($Item.Key)}", $Item.Value
            }
        }

        $color = if ($this.role -eq "assistant") {
            [Message]::AI_COLOR
        } elseif ($this.role -eq "user") {
            [Message]::USER_COLOR
        } else {
            $script:COLORS.WHITE
        }

        return $color + $messageContent + $script:COLORS.WHITE
    }

    # also seems unnecessary could merge with history
    [string] FormatHistory() {
        $messageContent = $this.GetColoredMessage()

        $Indent = if ($this.role -eq "assistant") {
            ([Message]::AI_COLOR + "GPT: ")
        } elseif ($this.role -eq "user") {
            ([Message]::USER_COLOR + "You: ")
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

        if (Test-Path (Join-Path $script:CONVERSATIONS_DIR "Autoload.json")) {
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
        [Message]::Reset()

        Write-Host "Conversation reset" -ForegroundColor Green
    }

    static Retry() {
        if ([Message]::Messages.Count -lt 2) {
            Write-Host "There are no messages in history." -ForegroundColor Red
            return
        }
        [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
        Write-Host ([Message]::Submit().FormatMessage())
    }

    static ExportJson([string]$filename) {
        $filepath = ""
        while ($true) {
            if (!$filename) {
                Write-Host (WrapText "What would you like to name the file? (Press enter to generate a name, enter /cancel to cancel)")
                Write-Host "> " -NoNewline
                $filename = $global:Host.UI.ReadLine()
                if (!$filename) {
                    # Use timestamp if you're a square
                    # $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd_HH-mm-ss")
                    # $filename = "conversation-$timestamp"
                    # Ask chatgpt for a name for the conversation

                    $filename = [Message]::Whisper("Reply only with a good very short name that summarizes this conversation in a filesystem compatible string, no quotes, no colors, no file extensions")

                    while (Join-Path $script:CONVERSATIONS_DIR "$filename.json" | Test-Path) {
                        $filename = [Message]::Whisper("That name is already taken. Please provide a different name.")
                    }
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

            $filepath = Join-Path $script:CONVERSATIONS_DIR $filename

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
    }

    static SaveFile ([string]$filepath) {
        $json = [Message]::Messages | ConvertTo-Json -Depth 5

        $json | Set-Content -Path $filepath

        if ((Split-Path $filepath -Leaf) -ne "autosave.json") { # Silent autosave
            Write-Host "Conversation saved to $($filepath)" -ForegroundColor Green
        }
    }

    static ImportJson([string]$filename) {
        if (!$filename) {
            Write-Host "This will clear the current conversation. Type ""/cancel"" to cancel." -ForegroundColor Red
            Write-Host "Saved conversations:"

            # Sort items by most recent
            $conversations = Get-ChildItem -Path $script:CONVERSATIONS_DIR -Filter *.json | Sort-Object LastWriteTime -Descending

            # display each item
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
            Write-Host "This will clear the current conversation. Continue?" -NoNewline
            Write-Host "[$($script:COLORS.DARKGREEN)y$($script:COLORS.WHITE)/$($script:COLORS.DARKRED)n$($script:COLORS.WHITE)]" -ForegroundColor Red

            # Make sure they have a chance to turn back
            Write-Host "> " -NoNewline
            if ($global:Host.UI.ReadLine() -ne "y") {
                return
            }
        }

        [Message]::LoadFile($filename)
    }

    static LoadFile([string]$File) {

        $Path = $File + ($File -notlike "*.json" ? ".json" : "")

        # Check if the file exists first in the contenxt of the user's current directory, then in the conversations directory
        if (!(Test-Path $Path)) {
            $Path = Join-Path $script:CONVERSATIONS_DIR $Path
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

        if ($file -ne "autoload") { # Silent autoload
            Write-Host "Conversation ""$File"" loaded" -ForegroundColor Green
        }
    }

    static History () {
        # Get all non-system messages
        $nonSystemMessages = [Message]::Messages | Where-Object { $_.role -ne "system" }

        if (!$nonSystemMessages) {
            Write-Host "There are no messages in history" -ForegroundColor Red
            return
        }

        foreach ($message in $nonSystemMessages) {
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
        $Models = "gpt-3.5-turbo", "gpt-4", "gpt-4-turbo", "gemini"
        $ImageModels = "dall-e-2", "dall-e-3"

        # Just print all model information if no model is provided
        if (!$Model) {
            Write-Host "`nAvailable models:"
            Write-Host "`nText Models:" -ForegroundColor DarkYellow

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
                WrapText "Please note that pricing varies drastically between the models, and that GPT-4 is not recommended for use as it is more expensive and less powerful than the turbo model."
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
        }
    }

    static GenerateImage([string]$Prompt) {
        if (!$Prompt) {
            # As much as I would like to spend your API tokens just to send you latent noise, you gotta give me something
            Write-Host "Please provide a prompt for the image generation." -ForegroundColor Red
            return
        }

        # Image generation meta prompt
        $Message = "Create a detailed image generation prompt for DALL-E based on the following request, include nothing other than the description in plain text: $Prompt"
        [Message]::AddMessage($Message, "system")

        $prompt = [Message]::Submit().content

        Write-Host "Imagining...`r" -NoNewline

        $body = @{
            model = $script:ImageModel; 
            prompt = $prompt;
            n = 1;
            size = "1024x1024" # Default size
        }

        $response = [Message]::CallOpenAI([Message]::IMAGE_URL, $body)

        # The api responds with a url of the image and not the image data itself
        $url = $response.data[0].url

        # Outsource the hard part to the bot we're already connected to
        $filename = [Message]::Whisper("Reply only with a filename for the image, no whitespace, no quotes, no file extensions")

        # The bot can be unoriginal sometimes
        while (Join-Path $script:IMAGES_DIR "$filename.png" | Test-Path) {
            $filename = [Message]::Whisper("That name is already taken. Please provide a different name.")
        }

        $outputPath = Join-Path $script:IMAGES_DIR "$filename.png"

        # Download the image
        Invoke-WebRequest -Uri $url -OutFile $outputPath

        Write-Host "              `r" -NoNewline

        Write-Host "Image created at ""$outputPath""" -ForegroundColor Green

        # Open the file after creation
        Start-Process $outputPath

        # Hopefully the bot will say something interesting in response to this, and not something random
        [Message]::AddMessage("Image created.", "system")
        Write-Host ([Message]::Submit().FormatMessage())
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

        Write-Host ([Message]::Submit().FormatMessage())
    }

    Copy () {
        $MessageContent = $this.content

        # Remove all color information from the message
        foreach ($Item in $script:COLORS.GetEnumerator()) {
            $MessageContent = $MessageContent -replace "{$($Item.Key)}", ""
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
        $currentInstructions = if ([Message]::Messages[1].role -eq "system") {
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
            [Message]::ExportJson($args[0])
        }, 
        "Save the current conversation to a file", 
        1, "[filename]"
    ) | Out-Null

    [Command]::new(
        ("load", "l", "import"), 
        {
            [Message]::ImportJson($args[0])
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
}

[Message]::Reset()

DefineCommands

# AskGPT mode, include the question in the command and it will try to answer as briefly as it can
if ($Query) {
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

    $response = [Message]::Query($Query)

    $global:LastResponse = $response.content

    return ($response.content)
}

Write-Host (WrapText "Welcome to $($COLORS.DARKGREEN)ChatGPT$($COLORS.WHITE), type $($COLORS.DARKYELLOW)/exit$($COLORS.WHITE) to quit or $($COLORS.DARKYELLOW)/help$($COLORS.WHITE) for a list of commands")

# Load a conversation from a file if specified
if ($Load) {
    [Message]::LoadFile($Load)
}

if (Test-Path (Join-Path $CONVERSATIONS_DIR "Autoload.json")) {
    [Message]::LoadFile("Autoload")
}

try {
    while ($true) {
        Write-Host "Chat > " -NoNewline -ForegroundColor $UserColor
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

            Write-Host ([Message]::Query($prompt).FormatMessage())
        }
    }
} finally {
    # For some reason, ctrl+c triggers finally, but doesn't run the function
    # Save the conversation to autosave
    [Message]::SaveFile((Join-Path $CONVERSATIONS_DIR "autosave.json"))
}