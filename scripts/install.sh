#!/bin/bash

set -euo pipefail

if [ "$(uname)" != "Darwin" ] ; then
	echo "Not macOS!"
	exit 1
fi

PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH

brew install git
brew install zsh-autosuggestions
brew install zsh-completions
brew install mise
brew install jq
brew install rectangle
brew install visual-studio-code
brew install orbstack

if [ ! -e ~/.zsh ]; then
	mkdir ~/.zsh
fi
curl -o ~/.zsh/git-prompt.zsh https://raw.githubusercontent.com/woefe/zsh-git-prompt/master/git-prompt.zsh

# if [ ! -e $(pwd)/zsh-completions-chmod-done.tmp ]; then
# 	chmod -R go-w '/opt/homebrew/share' # error point of github actions
# 	touch $(pwd)/zsh-completions-chmod-done.tmp
# fi
