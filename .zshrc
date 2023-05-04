typeset -U path PATH
path=(
  /opt/homebrew/bin(N-/)
  /opt/homebrew/sbin(N-/)
  /usr/bin
  /usr/sbin
  /bin
  /sbin
  /usr/local/bin(N-/)
  /usr/local/sbin(N-/)
  /Library/Apple/usr/bin
)

# colors
export LSCOLORS=gxfxcxdxcxegedabagacad
alias ls="ls -GF"
autoload -Uz colors && colors

# activate zsh-completions and zsh-autosuggestions
if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  autoload -Uz compinit && compinit
fi

# activate zsh-git-prompt
if ! type python &>/dev/null; then
  if type python3 &>/dev/null; then
    alias python="python3"
  else
    echo "python3 not found. can not activate zsh-git-prompt"
  fi
fi
source "$(brew --prefix)/opt/zsh-git-prompt/zshrc.sh"

# customize git-prompt
# ref. https://github.com/olivierverdier/zsh-git-prompt/blob/0a6c8b610e799040b612db8888945f502a2ddd9d/zshrc.sh#L95-L106
ZSH_THEME_GIT_PROMPT_PREFIX="[ "
ZSH_THEME_GIT_PROMPT_SUFFIX=" ]"
ZSH_THEME_GIT_PROMPT_SEPARATOR=" | "
ZSH_THEME_GIT_PROMPT_BRANCH="%{$fg[magenta]%}"
ZSH_THEME_GIT_PROMPT_STAGED="%{$fg[blue]%}%{#%G%}"
ZSH_THEME_GIT_PROMPT_CONFLICTS="%{$fg[red]%}%{x%G%}"
ZSH_THEME_GIT_PROMPT_CHANGED="%{$fg[red]%}%{+%G%}"
ZSH_THEME_GIT_PROMPT_BEHIND="%{↑%G%}"
ZSH_THEME_GIT_PROMPT_AHEAD="%{↑%G%}"
ZSH_THEME_GIT_PROMPT_UNTRACKED="%{..%G%}"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[green]%}%{--%G%}"

# for prompt variables
local user="%{$fg[yellow]%}%n%{$reset_color%}"
local host="%{$fg[cyan]%}@%m%{$reset_color%}"
local pwd="%{$fg[cyan]%}%~%{$reset_color%}"
local head="%{$fg[white]%}%(!.#.$)%"

prompt_with_git_status() {
  if [ "$(git rev-parse --is-inside-work-tree 2> /dev/null)" = true ]; then
    PROMPT="${user} : ${pwd} $(git_super_status)"$'\n'"${head}  "
  else
    PROMPT="${user} : ${pwd}"$'\n'"${head}  "
  fi
}

precmd() {
  prompt_with_git_status
}
