$ESC = [char]27

$MODEL = "gpt-4"

$CONVERSATIONS_DIR = Join-Path $PSScriptRoot .\conversations\

if (!(Test-Path $CONVERSATIONS_DIR)) {
    New-Item -ItemType Directory -Path $CONVERSATIONS_DIR | Out-Null
}

function WrapText {
    param (
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
    [string[]]$Keywords;
    [string]$Description;
    [scriptblock]$Action;
    [int]$ArgsNum;
    [string]$Usage;

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

    static Help() {
        foreach ($command in [Command]::Commands) {
            Write-Host "/$(@($command.Keywords)[0])`t$($command.Description)" -ForegroundColor Yellow
            if ($command.Usage) {
                Write-Host "`tUSAGE: /$(@($command.Keywords)[0]) $($command.Usage)" -ForegroundColor Black
            }
        }
    }

    static Execute($prompt) {
        # Split up prompt into command name and the rest as arguments
        $commandName, $argumentsString = $prompt -split '\s+', 2

        # Find the matching command
        $command = [Command]::Commands | Where-Object { $_.Keywords -contains $commandName.TrimStart('/') }

        if ($command) {
            # Split arguments string, if any
            $arguments = $argumentsString -split '\s+'
            
            # Ensure we only pass the number of arguments the command expects
            $arguments = $arguments[0..($command.ArgsNum - 1)]

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

    static [hashtable]$COLORS = @{
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

    static [string] $AI_COLOR = [Message]::COLORS.YELLOW
    static [string] $USER_COLOR = [Message]::COLORS.BLUE

    static [System.Collections.ArrayList]$Messages = @()

    Message([string]$content, [string]$role) {
        $this.content = $content
        $this.role = $role ? $role : "user"

        [Message]::Messages.Add($this)
    }

    static [Message] Submit([string]$MessageContent) {

        # It doesn't exist if it's not added to the list
        if ($MessageContent) {
            [Message]::new($MessageContent, "user")
        }

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
                "Authorization" = "Bearer $($env:OPENAI_API_KEY)"; 
                "Content-Type" = "application/json"
            } `
            -Body $body | ConvertFrom-Json

            $assistantMessage = [Message]::new(
                $response.choices[0].message.content, 
                $response.choices[0].message.role
            )

            # Clear the thinking message on the event that the message is very short.
            Write-Host "              `r" -NoNewline

            return $assistantMessage
            
        } catch {
            Write-Host "An error occurred: $_" -ForegroundColor Red
            return $null
        }
    }
    
    static [string] FormatMessage([Message]$Message) {
        if (!$Message) {
            return ""
        }

        $messageContent = $Message.content

        # If the message is not a system message, apply color formatting
        if (!($Message.role -eq "system")) {
            foreach ($Item in [Message]::COLORS.GetEnumerator()) {
                $messageContent = $messageContent -replace "{$($Item.Key)}", $Item.Value
            }
        }

        $Indent = if ($Message.role -eq "assistant") {
            ([Message]::AI_COLOR + "GPT: ")
        } elseif ($Message.role -eq "user") {
            ([Message]::USER_COLOR + "You: ")
        } else {
            ([Message]::COLORS.WHITE + "Sys: ")
        }

        $messageContent = WrapText -Text $messageContent -FirstIndent $Indent -Indent 5

        return $messageContent
    }
    
    static Reset([bool]$silent = $false) {
        [Message]::Messages.Clear()

        [Message]::new(
            'You are communicating through the terminal. ' +
            'You can use `{COLOR}` to change the color of your text for emphasis or whatever you want. ' +
            'Do not use markdown. If you write code, do not use "```". Use colors for syntax highlighting instead. ' +
            'Colors available are RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE, RESET. ' +
            'You can also use BRIGHT colors using {BRIGHTCOLOR}. (E.g. {BRIGHTRED}Hello{RESET})',
            "system"
        )

        if (!$silent) {
            Write-Host "Conversation reset" -ForegroundColor Green
        }
    }

    static ExportJson($filename) {
        while ($true) {
            if (!$filename) {
                Write-Host (WrapText "What would you like to name the file? (Press enter for autogenerated name)")
                $filename = Read-Host "> "
                if (!$filename) {
                    # Use timestamp if you're a square
                    # $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd_HH-mm-ss")
                    # $filename = "conversation-$timestamp"
                    # Ask chatgpt for a name for the conversation

                    $filename = [Message]::Submit("Reply only with a good name that summarizes this conversation in a filesystem compatible string, no quotes, no colors, no file extensions")
                    # Remove last message and response from conversation history
                    [Message]::Messages.RemoveAt([Message]::Messages.Count - 1)
                }
                elseif ($filename -eq "/cancel") {
                    Write-Host "Export canceled" -ForegroundColor Red
                    return
                }
            }
            if ($filename.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
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
    }
}

[Command]::new(@("exit", "quit", "e"), {exit}, "Exit the program")
[Command]::new(@("help"), {[Command]::Help() }, "Show this help message")

[Message]::Messages