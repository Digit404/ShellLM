$ESC = [char]27

$global:COLORS = @{
    BLACK         = "$ESC[30m"
    RED           = "$ESC[31m"
    GREEN         = "$ESC[32m"
    YELLOW        = "$ESC[33m"
    BLUE          = "$ESC[34m"
    MAGENTA       = "$ESC[35m"
    CYAN          = "$ESC[36m"
    WHITE         = "$ESC[37m"
    BRIGHTBLACK   = "$ESC[90m"
    BRIGHTRED     = "$ESC[91m"
    BRIGHTGREEN   = "$ESC[92m"
    BRIGHTYELLOW  = "$ESC[93m"
    BRIGHTBLUE    = "$ESC[94m"
    BRIGHTMAGENTA = "$ESC[95m"
    BRIGHTCYAN    = "$ESC[96m"
    BRIGHTWHITE   = "$ESC[97m"
}

$MODEL = "gpt-4"

$CONVERSATIONS_DIR = Join-Path $PSScriptRoot .\conversations\

if (!(Test-Path $CONVERSATIONS_DIR)) {
    New-Item -ItemType Directory -Path $CONVERSATIONS_DIR
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
    [string]$Content;
    [string]$Role;

    static [System.Collections.ArrayList]$Messages = @()

    Message([string]$Content, [string]$Role) {
        $this.Content = $Content
        $this.Role = $Role ? $Role : "user"

        [Message]::Messages.Add($this)
    }

    [psobject] Get() {
        return [PSCustomObject]@{
            content = $this.Content
            role = $this.Role
        }
    }

    static [psobject] GetMessages() {
        return @([Message]::Messages | ForEach-Object { $_.Get() })
    }

    static Send([string]$Content) {
        if ($Content) {
            [Message]::new($Content, "user")
        }
        Write-Host "Thinking...`r" -NoNewline

        try {
            $response = (Invoke-WebRequest `
            -Uri https://api.openai.com/v1/chat/completions `
            -Method Post `
            -Headers @{
                "Authorization" = "Bearer $($env:OPENAI_API_KEY)"; 
                "Content-Type" = "application/json"
            } `
            -Body (@{
                model = "gpt-3.5-turbo"; 
                messages = [Message]::GetMessages()} | ConvertTo-Json -Compress)) | ConvertFrom-Json

            $responseMessage = $response.choices[0].message

            [Message]::new($responseMessage.content, $responseMessage.role)
            
        } catch {
            Write-Host "An error occurred: $_" -ForegroundColor Red
        }
    }
}

[Command]::new(@("exit", "quit", "e"), {exit}, "Exit the program")
[Command]::new(@("help"), {[Command]::Help() }, "Show this help message")

