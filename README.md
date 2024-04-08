# ChatGPT PS

This project is a terminal-based interface for interacting with OpenAI's ChatGPT model. It allows users to have text-based conversations with the AI, ask questions, and receive responses.

## Features

- Simple and intuitive command-based interface
- Colorful and formatted messages for easy readability
- Conversation history and navigation
- Saving and loading conversations from JSON files
- Retry option to generate alternative responses
- AskGPT mode for brief answers to questions
- Supports GPT-3.5, GPT-4, and GPT-4-turbo-preview
- Image generation: Generate images using the DALL-E API. The generated images are saved in the `.\images` folder.

## Installation

1. Get an [Open AI API key](https://platform.openai.com/account/api-keys)
	- Sign in to your OpenAI account on [OpenAI Platform](https://platform.openai.com/).
	- Navigate to your account settings and select "API Keys".
	- Create a new API key if you don't already have one.

2. Set API key as OPENAI_API_KEY environment variable. This can optionally be done within the script itself.

	**Windows:**
	- To set an environment variable on Windows, you can use the following command in Command Prompt:

		```powershell
		[System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "sk-...", "User")
		```

	- Make sure to replace `"sk-..."` with your actual API key.

	**Mac/Linux:**
	- To set an environment variable on Mac or Linux, you can use the following command in the terminal:

		```powershell
		export OPENAI_API_KEY='sk-...'
		```

	- Again, replace `'sk-...'` with your actual API key.

	- Please note that the above instructions assume that you have the necessary permissions to set environment variables on your system.

3. Clone the repository, or download and run the script:

	```powershell
	git clone https://github.com/Digit404/ChatGPT-PS.git
	```

4. Works best when added to PATH, so it can be used from anywhere!

## Usage

1. Enable running scripts on your machine

	```powershell
	Set-ExecutionPolicy Bypass -Scope User
	```

1. Start the ChatGPT terminal interface:

	```powershell
	.\ChatGPT.ps1
	```

2. Or add the prompt after the file to get a brief answer to your question

	```powershell
	.\ChatGPT.ps1 "What is the capital of Ecuador?"
	```

## Commands

The following commands are available within the terminal interface:

- `/bye` (`/goodbye`): Exit and receive a goodbye message.
- `/help` (`/h`): Display a list of available commands and their descriptions.
- `/exit` (`/e`, `/quit`, `/q`): Exit the program immediately.
- `/save [filename]` (`/s`, `/export`): Save the current conversation to a JSON file.
- `/load [filename]` (`/l`, `/import`): Load a previous conversation from a JSON file.
- `/hist` (`/list`, `/ls`, `/history`): Display the conversation history.
- `/back [number]` (`/b`): Go back a number of messages in the conversation.
- `/retry` (`/r`): Generate another response to your last message.
- `/reset` (`/clear`): Reset the conversation to its initial state.
- `/model [model]` (`/m`): Change the model used for generating responses.
- `/imagine {prompt}` (`/generate`, `/image`, `/img`, `/i`): Generate an image based on a given prompt.
- `/copy [number of messages back]` (`/c`, `/cp`): Copy the last response to the clipboard (without formatting).
- `/paste [prompt]` (`/p`, `/clipboard`): Give the model the content of your clipboard as context.

## Troubleshooting

If you encounter any issues during the installation or usage of the script, double-check that you have set the `OPENAI_API_KEY` environment variable correctly.

If the problem persists, feel free to open an issue on the [GitHub repository](https://github.com/Digit404/ChatGPT-PS/issues) for further assistance.