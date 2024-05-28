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
            content = "write a short story using all your colors"
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

function GetLine {
    $response = $streamReader.ReadLine()

    if (!$response) {
        return $null
    }

    return ConvertFrom-Json ($response -split ": ")[1]
}

function DetermineColor {
    param (
        [string]$tagStart
    )

    $colorTag = $tagStart

    while ($true) {
        $line = GetLine

        if (!$line) {
            continue
        }

        $token = $line.choices.delta.content

        if ($token -contains "§") {
            $colorTag += ($token -split "§")[0]

            $color = $COLORS.ContainsKey($colorTag) ? $COLORS[$colorTag] : $AssistantColor

            return ($color)
        }

        $colorTag += $token
    }
}

$color = $AssistantColor

while ($true) {
    $line = GetLine

    if (!$line) {
        continue
    }

    if ($line.choices.finish_reason -eq "stop") {
        break
    }

    $token = $line.choices.delta.content

    foreach ($char in $token.ToCharArray()) {
        if ($char -eq "§") {
            $color = DetermineColor ($token -split "§")[1]
            break
        }

        Write-Host $color$char -NoNewline
    }
}