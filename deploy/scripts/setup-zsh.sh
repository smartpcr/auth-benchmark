sudo apt-get install git-core zsh
sudo curl -OL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh
sudo chmod +x ./install.sh
sh ./install.sh
sudo rm ./install.sh
sudo chsh -s $(which zsh)
cd ~/.oh-my-zsh/plugins
sudo git clone https://github.com/zsh-users/zsh-syntax-highlighting
sudo git clone https://github.com/zsh-users/zsh-autosuggestions
compaudit | xargs chmod g-w,o-w ~/.oh-my-zsh/plugins

echo "ZSH_THEME=\"random\""
echo "plugins=(git colored-man-pages zsh-autosuggestions zsh-syntax-highlighting)"

echo "" >> ~/.zshrc
echo "alias k=\"kubectl\"" >> ~/.zshrc
echo "alias kc=\"kubectl config current-context\"" >> ~/.zshrc
echo "alias kw=\"kubectl config use-context $1\"" >> ~/.zshrc

source ~/.zshrc
