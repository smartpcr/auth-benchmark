#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
sudo echo "APT::Get::Assume-Yes \"true\";" > /etc/apt/apt.conf.d/90assumeyes
sudo apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    openssl \
    apt-utils \
    apt-transport-https \
    git \
    iputils-ping \
    libcurl3 \
    libicu55 \
    libunwind8 \
    lsb-release \
    gnupg2 \
    software-properties-common \
    netcat \
    wget \
    unzip \
    openssh-server \
    sshfs


# Install jq-1.6 (beta)
sudo wget -q https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 \
    && sudo chmod +x jq-linux64 \
    && sudo mv jq-linux64 /usr/bin/jq

# install node
curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
sudo apt install nodejs
sudo chown -R $(id -u):$(id -g) /usr/lib/node_modules

# Install docker, requires docker run args: `-v /var/run/docker.sock:/var/run/docker.sock`
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" && \
    sudo apt-get update && \
    sudo apt-get -y install docker-ce

# Install docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    sudo chmod +x /usr/local/bin/docker-compose

# Install terraform
sudo wget -q https://releases.hashicorp.com/terraform/0.12.6/terraform_0.12.6_linux_amd64.zip \
    && unzip terraform_0.12.6_linux_amd64.zip \
    && chmod +x terraform \
    && sudo mv terraform /usr/local/bin/ \
    && rm terraform_0.12.6_linux_amd64.zip -f

# Install kubectl
sudo curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
    && chmod +x kubectl \
    && sudo mv ./kubectl /usr/local/bin/kubectl

# Install helm
sudo curl -LO https://get.helm.sh/helm-v2.14.3-linux-amd64.tar.gz \
    && tar -zxvf helm-v2.14.3-linux-amd64.tar.gz \
    && chmod +x ./linux-amd64/helm \
    && sudo mv ./linux-amd64/helm /usr/local/bin/helm \
    && rm helm-v2.14.3-linux-amd64.tar.gz -f \
    && rm -rf linux-amd64 -f

# Install fab
sudo curl -LO 'https://github.com/microsoft/fabrikate/releases/download/0.15.0/fab-v0.15.0-linux-amd64.zip' \
    && unzip fab-v0.15.0-linux-amd64.zip \
    && rm fab-v0.15.0-linux-amd64.zip -f \
    && chmod +x fab \
    && sudo mv ./fab /usr/local/bin/fab

# Install AZ CLI
sudo curl -sL https://aka.ms/InstallAzureCLIDeb | bash
sudo echo "AZURE_EXTENSION_DIR=/usr/local/lib/azureExtensionDir" | tee -a /etc/environment \
    && mkdir -p /usr/local/lib/azureExtensionDir
sudo chown -R $(id -u):$(id -g) /home/$USER/.azure

# Install az extensions
sudo az extension add --name application-insights

# Install powershell core
sudo wget -q https://packages.microsoft.com/config/ubuntu/16.04/packages-microsoft-prod.deb \
    && sudo dpkg -i packages-microsoft-prod.deb \
    && sudo apt-get update \
    && sudo apt-get install -y powershell \
    && rm packages-microsoft-prod.deb -f

# Install dotnet core sdk, this fix powershell core handling of cert trust chain problem
sudo apt-get install -y dotnet-sdk-3.1

# add basic git config
sudo git config --global user.email "xiaodoli@microsoft.com" && \
    sudo git config --global user.name "Xiaodong Li" && \
    sudo git config --global push.default matching && \
    sudo git config --global credential.helper store

# setup azure function tools
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-$(lsb_release -cs)-prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/dotnetdev.list'
sudo apt-get update
sudo apt-get install -y azure-functions-core-tools