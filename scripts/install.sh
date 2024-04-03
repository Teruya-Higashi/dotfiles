#!/bin/bash

set -euo pipefail

if [ "$(uname)" != "Darwin" ] ; then
	echo "Not macOS!"
	exit 1
fi

eval $(/opt/homebrew/bin/brew shellenv)

brew bundle

if [ ! -e ~/.zsh ]; then
	mkdir ~/.zsh
fi
curl -o ~/.zsh/git-prompt.zsh https://raw.githubusercontent.com/woefe/zsh-git-prompt/master/git-prompt.zsh

# if [ ! -e $(pwd)/zsh-completions-chmod-done.tmp ]; then
# 	chmod -R go-w '/opt/homebrew/share' # error point of github actions
# 	touch $(pwd)/zsh-completions-chmod-done.tmp
# fi
