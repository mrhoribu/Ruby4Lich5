# The gswiki "Lich:Software/Installation/Linux" steps, verbatim, as typed in an
# interactive bash terminal. Ruby = {{Lich version|ruby}} = 4.0.9.
# Run as: bash -i linux.sh <debian|arch|fedora>
# Only CI-forced change: --noconfirm on the two pacman commands (no one to
# answer their prompts).
set -eo pipefail
step() { printf '\n======== %s ========\n' "$*"; }
cd ~

step "Step 1: required packages ($1)"
case "$1" in
  debian)
    sudo apt-get -y update
    sudo apt-get -y install autoconf bison build-essential curl libssl-dev libyaml-dev libreadline-dev zlib1g-dev libncurses-dev libffi-dev libgdbm-dev libsqlite3-dev git unzip libcairo2-dev libgirepository1.0-dev libgtk-3-dev gobject-introspection
    ;;
  arch)
    sudo pacman -Syu --noconfirm
    sudo pacman -S --needed --noconfirm base-devel openssl libyaml readline zlib ncurses libffi gdbm sqlite git unzip curl gtk3 gobject-introspection
    ;;
  fedora)
    sudo dnf -y update
    sudo dnf -y install git autoconf bison cairo-devel curl gcc gdbm gdbm-devel gdk-pixbuf2-devel glib2-devel gobject-introspection-devel gtk3-devel libyaml-devel libffi-devel make ncurses-devel openssl-devel readline-devel redhat-rpm-config sqlite-devel unzip zlib-devel
    ;;
esac

step "Step 2: rbenv"
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc || true   # a distro .bashrc line may return non-zero; rbenv below proves it loaded

step "Step 3: Ruby 4.0.9"
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
rbenv install 4.0.9
rbenv global 4.0.9
ruby -v

step "Step 4: download Lich"
cd ~
curl -L "https://github.com/elanthia-online/lich-5/releases/latest/download/lich-5.zip" -o temp.zip && unzip temp.zip -d ./ && rm temp.zip

step "Step 5: gems"
echo "gem: --no-document" > ~/.gemrc
cd ~/Lich5
bundle config set --local without 'development vscode'
bundle install

step "Check: gems load, Lich GemCheck"
ruby -e "require 'sqlite3'; require 'gtk3'; puts 'sqlite3 and gtk3 load'"
ruby -I lib -e 'require "gemcheck"; m = Lich::GemCheck.missing_gems([:default, :profanity, :gtk]); abort("missing: #{m.join(", ")}") unless m.empty?; puts "Lich GemCheck: all gems present"'
ruby lich.rbw --version | head -n 1
