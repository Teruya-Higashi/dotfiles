#!/bin/bash

set -euo pipefail

if [ "$(uname)" != "Darwin" ] ; then
	echo "Not macOS!"
	exit 1
fi

PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH

brew install git
brew install gh
brew install zsh-autosuggestions
brew install zsh-completions
brew install mise
brew install rectangle
brew install visual-studio-code
brew install orbstack
brew install claude-code
brew install claude
brew install chatgpt
brew install codex
brew install dbeaver-community
brew install google-japanese-ime

if [ ! -e ~/.zsh ]; then
	mkdir ~/.zsh
fi
curl -o ~/.zsh/git-prompt.zsh https://raw.githubusercontent.com/woefe/zsh-git-prompt/master/git-prompt.zsh

# if [ ! -e $(pwd)/zsh-completions-chmod-done.tmp ]; then
# 	chmod -R go-w '/opt/homebrew/share' # error point of github actions
# 	touch $(pwd)/zsh-completions-chmod-done.tmp
# fi

mise use -g gcloud@latest
mise use -g aws@latest
mise use -g jq@latest
mise use -g yq@latest
mise use -g uv@latest
mise use -g npm:takt@latest

claude mcp add serena -s user -- mise x -- uvx --from "git+https://github.com/oraios/serena" serena start-mcp-server --enable-web-dashboard false --context ide-assistant
claude mcp add codex codex mcp-server
