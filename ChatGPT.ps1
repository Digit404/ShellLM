<#
.SYNOPSIS
    This script is a PowerShell implementation of a chatbot using OpenAI's GPT models.

.DESCRIPTION
    The script allows users to interact with the chatbot by sending messages and receiving responses from the GPT model. It supports multiple commands and provides a conversational interface.

.PARAMETER Model
    Specifies the GPT model to use for generating responses. The available options are "gpt-4", "gpt-4-turbo-preview", and "gpt-3.5-turbo". The default value is "gpt-3.5-turbo".

.PARAMETER Query
    Specifies the user's message/query to be sent to the chatbot.

.PARAMETER Load
    Specifies a file containing a conversation to load. This can be used to continue a previous conversation.

.PARAMETER Key
    Specifies the OpenAI API key to use for making API calls to the OpenAI chat/completions endpoint.
    If not provided, the script will prompt the user to enter the API key.

.NOTES
    - This script requires an OpenAI API key to make API calls to the OpenAI chat/completions endpoint.
    - The script uses ANSI escape codes for color formatting in the terminal.
    - The script supports various commands that can be used to interact with the chatbot.
    - The script provides a conversational history and allows exporting the conversation to a JSON file.

.EXAMPLE
    PS C:\> .\ChatGPT-PS.ps1 -Model "gpt-4" -Query "What is the capital of ecuador?"

    This example runs the script using the "gpt-4" model and asks the question "What is the capital of ecuador?".

.EXAMPLE
    PS C:\> .\ChatGPT-PS.ps1 -Load conversation

    This example loads a conversation from the "conversation.json" file within the conversations dir and continues the conversation.
#>

[CmdletBinding(PositionalBinding=$false)] # Important as it make it so you can throw the model param anywhere
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet(
        "gpt-4",
        "gpt-4-turbo-preview",
        "gpt-3.5-turbo"
    )]
    [string] $Model = "gpt-3.5-turbo",

    [Parameter(ValueFromRemainingArguments)]
    [string] $Query,

    [Parameter(Mandatory=$false)]
    [Alias("l", "Import", "File", "Conversation")]
    [string] $Load,

    [Parameter(Mandatory=$false)]
    [string] $Key
)

$ESC = [char]27 # Escape char for colors

# Consider making this a parameter
$CONVERSATIONS_DIR = Resolve-Path (Join-Path $PSScriptRoot .\conversations\)

# Handle key state
if (!$env:OPENAI_API_KEY -and !$Key) {
    Write-Host "OPEN AI API KEY NOT FOUND. GET ONE HERE: https://platform.openai.com/api-keys" -ForegroundColor Red
    Write-Host "Please input API key, or set it as an environment variable."
    Write-Host "> " -NoNewline
    $Key = $Host.UI.ReadLine()
}

if (!$Key) {
    $Key = $env:OPENAI_API_KEY
}

# This is just to confirm the key is valid, does not actually use the list of models.
$response = Invoke-WebRequest `
    -Uri https://api.openai.com/v1/models `
    -Headers @{
        "Authorization" = "Bearer $($Key)"
    }

if ($response.StatusCode -ne 200) {
    Write-Host "Invalid API key. Please try again." -ForegroundColor Red
    exit
}

if ($Key -ne $env:OPENAI_API_KEY) {
    [System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $Key, "User")
}

# Colors for the terminal
$COLORS = @{
    RED = "$ESC[31m"
    GREEN = "$ESC[32m"
    YELLOW = "$ESC[33m"
    BLUE = "$ESC[34m"
    MAGENTA = "$ESC[35m"
    CYAN = "$ESC[36m"
    WHITE = "$ESC[37m"
    BRIGHTBLACK = "$ESC[90m"
    BRIGHTRED = "$ESC[91m"
    BRIGHTGREEN = "$ESC[92m"
    BRIGHTYELLOW = "$ESC[93m"
    BRIGHTBLUE = "$ESC[94m"
    BRIGHTMAGENTA = "$ESC[95m"
    BRIGHTCYAN = "$ESC[96m"
    BRIGHTWHITE = "$ESC[97m"
    RESET = "$ESC[33m"
}

function WrapText {
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$Text,

        [string]$FirstIndent,
        [int]$Indent
    )

    $Width = $Host.UI.RawUI.BufferSize.Width - ($Indent)

    # First indent should be the same as the indent when not specified
    $wrappedText = $FirstIndent ? $FirstIndent : (" " * $Indent)

    $words = $Text -split '\s+|\r?\n'

    $lineLength = 0

    while ($words) {
        $word = $words[0]

        if ($lineLength + $word.Length + 1 -gt $Width) {
            $wrappedText += "`n" + (" " * $Indent)
            $lineLength = 0
        }

        $wrappedText += "$word "
        $lineLength += $word.Length + 1

        $words = $words[1..$words.Length]
    }

    return $wrappedText
}

class Command {
    [string[]]$Keywords; # The different keywords that can be used to trigger the command, the first one is the one shown to user
    [string]$Description; # Short description of the command when /help is called
    [scriptblock]$Action; # The action to be executed when the command is called
    [int]$ArgsNum; # Number of arguments the command expects
    [string]$Usage; # Usage example for the command without the command itself

    static [System.Collections.ArrayList]$Commands = @()

    Command([string[]]$Keywords, [scriptblock]$Action, [string]$Description, [int]$ArgsNum, [string]$Usage) {
        $this.Keywords = $Keywords;
        $this.Description = $Description;
        $this.Action = $Action;
        $this.ArgsNum = $ArgsNum;
        $this.Usage = $Usage;

        [Command]::Commands.Add($this)
    }

    # Overloaded constructor for mandatory parameters only
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
            Write-Host "/$(@($command.Keywords)[0])" -ForegroundColor DarkYellow -NoNewline
            Write-Host "`t$($command.Description)" 
            if ($command.Usage) {
                Write-Host "`tUSAGE: /$(@($command.Keywords)[0]) $($command.Usage)" -ForegroundColor Black
            }
        }
    }

    static Execute($prompt) { # Execute the command. If you see errors pointing to this the problem is likely elsewhere
        # Split up prompt into command name and the rest as arguments
        $commandName, $argumentsString = $prompt -split '\s+', 2

        # Find the matching command
        $command = [Command]::Commands | Where-Object { $_.Keywords -contains $commandName.TrimStart('/') }

        if ($command) {
            if (!$argumentsString) {
                $command.Action.Invoke()
                return
            }
            # Split arguments string, if any
            [string]$arguments = $argumentsString -split '\s+'
            
            # Ensure we only pass the number of arguments the command expects
            $arguments = @($arguments)[0..($command.ArgsNum - 1)]

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

    static [string] $AI_COLOR = $script:COLORS.YELLOW
    static [string] $USER_COLOR = $script:COLORS.BLUE

    static [System.Collections.ArrayList]$Messages = @()

    Message([string]$content, [string]$role) {
        $this.content = $content
        $this.role = $role ? $role : "user"

        [Message]::Messages.Add($this)
    }

    static [Message] Submit([string]$MessageContent) { # Overload for submit to add a message from the user first

        # It doesn't exist if it's not added to the list
        if ($MessageContent) {
            [Message]::new($MessageContent, "user")
        }

        return [Message]::Submit()
    }

    static [Message] Submit() { # Submit messages to the GPT model and receive a response
        # Print thinking message
        Write-Host "Thinking...`r" -NoNewline

        try {
            # Define body for API call
            $body = @{
                model = $script:MODEL; 
                messages = [Message]::Messages
            } | ConvertTo-Json -Compress

            # Main API call to OpenAI
            $response = Invoke-WebRequest `
            -Uri https://api.openai.com/v1/chat/completions `
            -Method Post `
            -Headers @{
                "Authorization" = "Bearer $script:Key"; 
                "Content-Type" = "application/json"
            } `
            -Body $body | ConvertFrom-Json

            $assistantMessage = [Message]::new(
                $response.choices[0].message.content, 
                $response.choices[0].message.role
            )

            # Clear the thinking message on the event that the message is very short.
            Write-Host "              `r" -NoNewline

            # Returning the MESSAGE object, not a string
            return $assistantMessage
            
        } catch {
            # Catching errors caused by the API call
            Write-Host "An error occurred: $_" -ForegroundColor Red
            return $null
        }
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

        return $color + $messageContent
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

        # Default message to start the conversation and inform the bot on how to use the colors
        [Message]::new(
            'You are communicating through the terminal. ' +
            'You can use `{COLOR}` to change the color of your text for emphasis or whatever you want, and {RESET} to go back. ' +
            'Do not use markdown. If you write code, do not use "```". Use colors for syntax highlighting instead. ' +
            'Colors available are RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE, RESET. ' +
            'You can also use BRIGHT colors using {BRIGHTCOLOR}. (E.g. {BRIGHTRED}Hello{RESET})',
            "system"
        )
    }

    static ResetLoud() { # Reset the conversation and inform the user
        [Message]::Reset()

        Write-Host "Conversation reset" -ForegroundColor Green
    }

    static Retry() {
        [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
        Write-Host ([Message]::Submit().FormatMessage())
    }

    static ExportJson($filename) {
        while ($true) {
            if (!$filename) {
                Write-Host (WrapText "What would you like to name the file? (Press enter to generate a name)")
                Write-Host "> " -NoNewline
                $filename = $global:Host.UI.ReadLine()
                if (!$filename) {
                    # Use timestamp if you're a square
                    # $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd_HH-mm-ss")
                    # $filename = "conversation-$timestamp"
                    # Ask chatgpt for a name for the conversation

                    $filename = [Message]::Submit("Reply only with a good very short name that summarizes this conversation in a filesystem compatible string, no quotes, no colors, no file extensions").content
                    # Remove last two messages from conversation history
                    [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
                    [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
                }
                elseif ($filename -eq "/cancel") {
                    Write-Host "Export canceled" -ForegroundColor Red
                    return
                }
            }
            if ($filename.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
                # Don't allow invalid characters in the filename
                Write-Host "Invalid name." -ForegroundColor Red
                $filename = ""
            } else {
                break
            }
        }

        # Ensure it ends in .json
        $filename += $filename -notlike "*.json" ? ".json" : ""

        $filepath = Join-Path $script:CONVERSATIONS_DIR $filename

        $json = [Message]::Messages | ConvertTo-Json -Depth 5

        $json | Set-Content -Path $filepath

        Write-Host "Conversation saved to $($filepath)" -ForegroundColor Green
    }

    static ImportJson($filename) {
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

            if ($filename -eq "/cancel") {
                Write-Host "Import canceled" -ForegroundColor Red
                return
            }

            # If the input is a number, use it to select the conversation
            if ([int]::TryParse($filename, [ref]$null)) {
                if ($filename -gt 0 -and $filename -lt $conversations.Count + 1) {
                    $filename = $conversations[[int]$filename - 1].BaseName
                } else {
                    Write-Host "Invalid number" -ForegroundColor Red
                    return
                }
            }
        } else {
            # If the user provided a comversation name
            Write-Host "This will clear the current conversation. Continue?"`
            "$($script:COLORS.BRIGHTWHITE)[$($script:COLORS.GREEN)y$($script:COLORS.BRIGHTWHITE)/$($script:COLORS.RED)n$($script:COLORS.BRIGHTWHITE)]" -ForegroundColor Red

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
            [Message]::new($message.content, $message.role)
        }

        Write-Host "Conversation ""$File"" loaded" -ForegroundColor Green
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
        }
    }

    static GoBack ([int]$NumBack) {
        if ($NumBack -lt 1) {
            $NumBack = 1
        }

        # Don't remove the system message
        $nonSystemMessages = [Message]::Messages | Where-Object { $_.role -ne "system" }

        if ($NumBack -gt $nonSystemMessages.Count) {
            Write-Host "Reached the beginning of the conversation" -ForegroundColor Red
            return
        }

        # Go back 2 messages (1 user and one assistant message)
        for ($i = 0; $i -lt $NumBack * 2; $i++) {
            [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
        }

        Write-Host "Went back $NumBack message(s)" -ForegroundColor Green
    }

    static Goodbye() {
        Write-Host ([Message]::Submit("Goodbye!").FormatMessage())
        exit
    }

    static ChangeModel ([string]$Model) {
        $Models = "gpt-4-turbo-preview", "gpt-4", "gpt-3.5-turbo"

        if (!$Model) {
            Write-Host "Current model: $script:MODEL" -ForegroundColor Blue
            Write-Host "Available models:" -ForegroundColor DarkYellow

            foreach ($model in $Models) {
                $index = $Models.IndexOf($model) + 1
                Write-Host "  [$index]`t$model" -ForegroundColor DarkYellow
            }

            return
        }

        if ([int]::TryParse($Model, [ref]$null)) {
            $Model = $Models[[int]$Model - 1]
        }
        
        if ($Models -notcontains $Model) {
            Write-Host "Invalid model. Available models are $($Models -join ", ")" -ForegroundColor Red
            return
        }

        $script:MODEL = $Model
        Write-Host "Model changed to $Model" -ForegroundColor Green
    }
}
function DefineCommands {
    [Command]::Commands.Clear()
    [Command]::new(
        @("bye", "goodbye"), 
        {[Message]::Goodbye()}, 
        "Exit the program and receive a goodbye message"
    ) | Out-Null

    [Command]::new(
        @("exit", "quit", "e", "q"), 
        {exit}, 
        "Exit the program immediately"
    ) | Out-Null

    [Command]::new(
        @("help", "h"), 
        {[Command]::Help()}, 
        "Display this message again"
    ) | Out-Null

    [Command]::new(
        @("save", "s", "export"), 
        {
            [Message]::ExportJson($args[0])
        }, 
        "Save the current conversation to a file", 
        1, "[filename]"
    ) | Out-Null

    [Command]::new(
        @("load", "l", "import"), 
        {
            [Message]::ImportJson($args[0])
        }, 
        "Load a previous conversation", 
        1, "[filename]"
    ) | Out-Null

    [Command]::new(
        @("hist", "history", "ls", "list"), 
        {[Message]::History()}, 
        "Display the conversation history"
    ) | Out-Null

    [Command]::new(
        @("back", "b"), 
        {
            [Message]::GoBack($args[0])
        }, 
        "Go back a number of messages in the conversation", 
        1, "[number]"
    ) | Out-Null

    [Command]::new(
        @("retry", "r"), 
        {[Message]::Retry()}, 
        "Generate another response to your last message"
    ) | Out-Null

    [Command]::new(
        @("reset", "clear"), 
        {[Message]::ResetLoud()}, 
        "Reset the conversation to its initial state"
    ) | Out-Null

    [Command]::new(
        @("model", "m"), 
        {
            [Message]::ChangeModel($args[0])
        }, 
        "Change the model used for generating responses", 
        1, "[model]"
    ) | Out-Null
}

if (!(Test-Path $CONVERSATIONS_DIR)) {
    New-Item -ItemType Directory -Path $CONVERSATIONS_DIR | Out-Null
}

[Message]::Reset()

DefineCommands

# AskGPT mode, include the question in the command and it will try to answer as briefly as it can
if ($Query) {
    [Message]::new(
        "You will be asked one short question. You will be as brief as possible with your response, using incomplete sentences if necessary. " + 
        "You will respond with text only, no new lines or markdown elements.  " + 
        "After you respond it will be the end of the conversation, do not say goodbye.",
        "system"
    ) | Out-Null

    Write-Host ([Message]::Submit($Query).FormatMessage())
    exit
}

Write-Host (WrapText "Welcome to $($COLORS.GREEN)ChatGPT$($COLORS.BRIGHTWHITE), type $($COLORS.YELLOW)/exit$($COLORS.BRIGHTWHITE) to quit or $($COLORS.YELLOW)/help$($COLORS.BRIGHTWHITE) for a list of commands")

# Load a conversation from a file if specified
if ($Load) {
    [Message]::LoadFile($Load)
}

while ($true) {
    Write-Host "$($COLORS.BLUE)Chat > " -NoNewline
    $prompt = $Host.UI.ReadLine()

    # Do command handling
    if ($prompt[0] -eq "/") {
        [Command]::Execute($prompt)
    } else {
        Write-Host ([Message]::Submit($prompt).FormatMessage())
    }
}