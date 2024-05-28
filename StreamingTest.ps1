$URI = "https://api.openai.com/v1/chat/completions"

$ESC = [char]27 # Escape char for colors

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

$SYSTEM_MESSAGE = (
    'You are a helpful assistant communicating through the terminal. Do not use markdown syntax. Give detailed responses. ' +
    'You can use `§COLOR§` to change the color of your text for emphasis or whatever you want, and §RESET§ to go back. ' +
    'If you write code, do not use "```". Use colors for syntax highlighting instead. ' +
    'Colors available are RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE, GRAY, RESET. ' +
    'You can also use DARK colors using §DARKCOLOR§. (E.g. §DARKRED§Hello§RESET§).' 
)

$body = @{
    model    = "gpt-3.5-turbo"
    messages = @(
        @{
            role    = "system"
            content = $SYSTEM_MESSAGE
        },
        @{
            role    = "user"
            content = "write a short story using all of your colors"
        }
    )
    stream   = $true
} | ConvertTo-Json

$AssistantColor = $COLORS["DARKYELLOW"]

# Beginning of the actual logic

$webrequest = [System.Net.HttpWebRequest]::Create($URI)

$webrequest.Method = "POST"
$webrequest.Headers.Add("Authorization", "Bearer " + $env:OPENAI_API_KEY)
$webrequest.ContentType = "application/json"

$RequestBody = [System.Text.Encoding]::UTF8.GetBytes($body)

$RequestStream = $webrequest.GetRequestStream()
$RequestStream.Write($RequestBody, 0, $RequestBody.Length)

$responseStream = $webrequest.GetResponse().GetResponseStream()
$streamReader = [System.IO.StreamReader]::new($responseStream)

function GetChunk {
    $response = $streamReader.ReadLine()

    if (!$response) {
        return $null
    }

    $Global:chunks += ($response -split ": ")[1]

    return ConvertFrom-Json ($response -split ": ")[1]
}

function FindColor {
    param (
        [string]$colorTag
    )

    # Clean color tag
    $colorTag = ($colorTag.ToUpper() -replace "§", "") -replace "/", ""

    if ($COLORS.ContainsKey($colorTag)) {
        return $COLORS[$colorTag]
    }

    return $AssistantColor
}

function PrintWord {
    param (
        [string]$word,
        [string]$color
    )

    $maxLineLength = $host.ui.rawui.BufferSize.Width - 1
    $currentLineLength = [Console]::CursorLeft
    if ($currentLineLength + $word.Length -gt $maxLineLength) {
        Write-Host ""
        $currentLineLength = 0
        if ($word -eq " ") {
            return
        }
    }
    Write-Host "$color$word" -NoNewline
}

$buffer = ""
$color = $AssistantColor

$global:message = ""
$global:chunks = @()

do {
    $chunk = GetChunk
    if (!$chunk) {
        continue
    }

    $stop = $chunk.choices.finish_reason -eq "stop"

    if ($stop) {
        Write-Host Stopping! -ForegroundColor Red
    }

    $token = $chunk.choices.delta.content
    $global:message += $token
    $buffer += $token

    while ($true) {
        $split = $buffer -split "(\s+)"

        $words = $split | Select-Object -SkipLast 1 | Where-Object { $_ -ne "" }

        if (!$words) {
            break
        }

        $word = $words[0]

        if ($word -eq "`n`n") {
            Write-Host Hello -ForegroundColor Green
        }

        $buffer = ($split | Where-Object { $_ -ne "" } | Select-Object -Skip 1) -join ""

        if ($word -like "*§*§*") {
            $parts = $word -split "§"

            # write each even part and change the color to each odd part
            for ($i = 0; $i -lt $parts.Length; $i++) {
                if ($i % 2 -eq 0) {
                    PrintWord -word $parts[$i] -color $color
                } else {
                    $color = FindColor $parts[$i]
                }
            }
        } else {
            PrintWord -word $word -color $color
        }
    }
} while (!$stop)