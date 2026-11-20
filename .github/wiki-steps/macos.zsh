# The gswiki "Lich:Software/Installation/macOS" steps, verbatim, as typed in
# Terminal (zsh). Ruby = {{Lich version|ruby}} = 4.0.9.
setopt ERR_EXIT PIPE_FAIL
step() { print -r -- ""; print -r -- "======== $* ========"; }

step "Step 1: brew doctor"
brew doctor || print "(brew doctor reported warnings; CI images always have some)"

step "Step 2: required packages"
brew install gtk+3
brew install gobject-introspection
brew install rbenv
brew install adwaita-icon-theme
brew install openssl@3
brew upgrade ca-certificates

step "Step 3: shell setup"
echo $SHELL
echo 'eval "$(rbenv init -)"' >> ~/.zshrc
echo 'if [ -z $DISPLAY ]; then export DISPLAY=:0.0; fi' >> ~/.zshrc
source ~/.zshrc
rbenv versions

step "Step 4: Ruby 4.0.9"
rbenv install 4.0.9
rbenv global 4.0.9
ruby -v

step "Step 5: download Lich"
mkdir -p ~/Downloads ~/Desktop
cd ~/Downloads
curl -fsSL -o lich-5.zip https://github.com/elanthia-online/lich-5/releases/latest/download/lich-5.zip
unzip -q lich-5.zip
mv Lich5 ~/Desktop/

step "Step 6: gems"
cd ~/Desktop/Lich5
bundle config set --local without 'development vscode'
bundle install
ruby -e "require 'sqlite3'; p true"
ruby -e "require 'gtk3'; p true"

step "Check: Lich GemCheck"
ruby -I lib -e 'require "gemcheck"; m = Lich::GemCheck.missing_gems([:default, :profanity, :gtk]); abort("missing: #{m.join(", ")}") unless m.empty?; puts "Lich GemCheck: all gems present"'
ruby lich.rbw --version | head -n 1
