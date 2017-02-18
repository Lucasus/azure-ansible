#!/bin/bash

#########################################################
# Description:
#  This script configures root login over ssh using keys.
#  The .pub key must file on the same folder
#########################################################

#---BEGIN VARIABLES---
SSH_AZ_ACCOUNT_NAME=''
SSH_AZ_ACCOUNT_KEY=''


function usage()
{
    echo "INFO:"
    echo "Usage: configure_ssh_root [-a] [-k]"
    echo "The -a (azureStorageAccountName) parameter specifies the name of the storage account that contains the private keys"
    echo "The -k (azureStorageAccountKey) parameter specifies the key of the private storage account that contains the private keys"
}

function log()
{
    # If you want to enable this logging add a un-comment the line below and add your account id
    #curl -X POST -H "content-type:text/plain" --data-binary "${HOSTNAME} - $1" https://logs-01.loggly.com/inputs/<key>/tag/es-extension,${HOSTNAME}
    echo "$1"
}

#---PARSE AND VALIDATE PARAMETERS---
if [ $# -ne 4 ]; then
    log "ERROR:Wrong number of arguments specified. Parameters received $#. Terminating the script."
    usage
    exit 1
fi

while getopts :a:k: optname; do
    log "INFO:Option $optname set with value ${OPTARG}"
  case $optname in
    a) # Azure Private Storage Account Name- SSH Keys
      SSH_AZ_ACCOUNT_NAME=${OPTARG}
      ;;
    k) # Azure Private Storage Account Key - SSH Keys
      SSH_AZ_ACCOUNT_KEY=${OPTARG}
      ;;

    \?) #Invalid option - show help
      log "ERROR:Option -${BOLD}$OPTARG${NORM} not allowed."
      usage
      exit 1
      ;;
  esac
done

function get_sshkeys()
{
    # install python
    log "INFO:Installing Python and Azure Storage Python SDK"

    apt-get --yes --force-yes update
    apt-get --yes --force-yes install python-pip

    # Install Python Azure Storage SDK
	apt-get --yes --force-yes install build-essential libssl-dev libffi-dev python-dev

	pip install cryptography
    pip install azure-storage

    # Download Public Key
    python GetSSHFromPrivateStorageAccount.py  ${SSH_AZ_ACCOUNT_NAME} ${SSH_AZ_ACCOUNT_KEY} id_rsa.pub
}

function configure_ssh()
{
    # copy root ssh key
    mkdir -p ~/.ssh
    cat id_rsa.pub >> ~/.ssh/authorized_keys
    # rm id_rsa.pub

    # set permissions
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys

    #restart sshd service - Ubuntu
    service ssh restart
}

get_sshkeys
configure_ssh
