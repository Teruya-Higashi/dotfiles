#!/bin/bash

set -euxo pipefail

if [ "$(uname)" != "Darwin" ] ; then
	echo "Not macOS!"
	exit 1
fi

if [ -e ~/.zshrc ]; then
    mv ~/.zshrc ~/.zshrc_bk_$(date +"%Y%m%d%I%M%S")
fi
ln -s $(pwd)/.zshrc ~/.zshrc

if [ -e ~/.vimrc ]; then
    mv ~/.vimrc ~/.vimrc_bk_$(date +"%Y%m%d%I%M%S")
fi
ln -s $(pwd)/.vimrc ~/.vimrc
