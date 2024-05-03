# ShellLM
A Versatile PowerShell-based LLM Interface

## Overview

ShellLM is a feature-rich and flexible terminal application that allows users to have text-based conversations with large language models (LLMs), including GPT-4 and Gemini. It provides an intuitive command-based interface, enabling users to easily interact with the models and explore their capabilities.

## Features

- Seamless communication with LLM APIs such as GPT-4 and Gemini
- Colorful formatted messages for easy readability
- Comprehensive conversation history and navigation
- Conversation saving and loading to/from JSON files
- Retry option to generate alternative responses
- AskLLM mode for concise answers to specific questions
- Supports `GPT-3.5-turbo`, `GPT-4`,` GPT-4-turbo`, and `gemini-pro`
- Image generation: Generate images using the DALL-E API (requires an OpenAI API key)
- Custom instructions: Set specific guidelines for the model to follow during conversations
- Automatically loads conversation 'autoload.json' on startup, automatically saves last conversation

## Installation

1. **Obtain an OpenAI API key:**
   - Sign in to your OpenAI account and navigate to your account settings.
   - Select "API Keys" and create a new API key if you don't already have one.

2. **Set the API key as an environment variable:**
   - Open a Command Prompt and enter the following command:
     ```
     [System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "sk-...", "User")
     ```
   - Replace `"sk-..."` with your actual API key.

3. **Clone or download the repository:**
   ```
   git clone https://github.com/Digit404/ChatGPT-PS.git
   ```

## Usage

1. **Start the ShellLM terminal interface**
   ```
   .\ShellLM.ps1
   ```

2. **Interact with the model**
   - Type your messages and press Enter to send them to the model.
   - Use the available commands (listed below) to manage conversations, generate images, and customize the experience.

- Alternatively, you can append your prompt after the file name to get a quick response without entering the interactive shell:
     ```
     .\ShellLM.ps1 "What is the capital of Ecuador?"
     ```

### Commands

- `/bye` (`/goodbye`): Exit the program with a farewell message.
- `/help`: Display a list of available commands and their descriptions.
- `/exit` (`/quit`): Exit the program immediately.
- `/save [filename]` (`/export`): Save the current conversation to a JSON file.
- `/load [filename]` (`/import`): Load a previous conversation from a JSON file.
- `/hist` (`/list`, `/ls`, `/history`): Display the conversation history.
- `/back [number]`: Go back a number of messages in the conversation.
- `/retry`: Generate another response to your last message.
- `/reset` (`/clear`): Reset the conversation to its initial state.
- `/model [model]`: Change the model used for generating responses.
- `/imagine {prompt}` (`/generate`, `/image`, `/img`): Generate an image based on a given prompt.
- `/copy [number of messages back]` (`/cp`): Copy the last response to the clipboard (without formatting).
- `/paste [prompt]` (`/clipboard`): Provide the model with the content of your clipboard as context.
- `/rules [instructions]` (`/instructions`): Set custom instructions for the model to follow during the conversation.

### Troubleshooting

If you encounter an issue initially running the program, make sure you have enabled running scripts on your system by running this command
	```powershell
	Set-ExecutionPolicy Bypass -Scope User
	```

If you encounter any further issues, please double-check that you have correctly set the `OPENAI_API_KEY` environment variable. If the problem persists, please open an issue on the GitHub repository for further assistance.

**Note:** This script is still under development and may undergo further changes in the future.