#!/bin/bash

#########################################################
# Description:
#  This script automates the installation of this VM as an ansible VM. Specifically it:
#     installs ansible on all the nodes
#     configures ssh keys
# Parameters :
#  1 - i: IP Pattern
#  2 - n: Number of nodes
# Note :
# This script has only been tested on Ubuntu 14.04 LTS
#########################################################

#---BEGIN VARIABLES---
IP_ADDRESS_SPACE=''
NUMBER_OF_NODES=''
NODE_LIST_IPS=()
USER_NAME=''
USER_PASSWORD=''
TEMPLATE_ROLE='ansible'
START_IP_INDEX=0
SSH_AZ_ACCOUNT_NAME=''
SSH_AZ_ACCOUNT_KEY=''

function usage()
{
    echo "INFO:"
    echo "Usage: configure-ansible.sh [-i IP_ADDRESS_SPACE ] [-n NUMBER_OF_NODES ]"
    echo "The -i (ipAddressSpace) parameters specifies the starting IP space for the vms.For instance if you specify 10.0.2.2, and 3 nodes, the script will find for the VMS 10.0.2.20, 10.0.2.21,10.0.2.22.Plase note that Azure reserves the first 4 IPs, so you will have to specify an IP space in which IP x.x.x0 is available"
    echo "The -n (numberOfNodes) parameter specifies the number of VMs"
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
if [ $# -ne 12 ]; then
    log "ERROR:Wrong number of arguments specified. Parameters received $#. Terminating the script."
    usage
    exit 1
fi

while getopts :i:n:r:f:a:k: optname; do
    log "INFO:Option $optname set with value ${OPTARG}"
  case $optname in
    i) # IP address space
      IP_ADDRESS_SPACE=${OPTARG}
      ;;
    n) # Number of VMS
      NUMBER_OF_NODES=${OPTARG}
      IDX=${START_IP_INDEX}
      while [ "${IDX}" -lt "${NUMBER_OF_NODES}" ];
      do
        NODE_LIST_IPS[$IDX]="${IP_ADDRESS_SPACE}${IDX}"
        IDX=$((${IDX} + 1))
      done
      ;;
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

function install_ansible_ubuntu()
{
    sudo apt-get --yes --force-yes install software-properties-common
    sudo apt-add-repository ppa:ansible/ansible -y
    sudo apt-get --yes --force-yes update
    sudo apt-get --yes --force-yes install ansible
    # install sshpass
    sudo apt-get --yes --force-yes install sshpass
    # install Git
    sudo apt-get --yes --force-yes install git
    # install python
    sudo apt-get --yes --force-yes install python-pip
}


function get_sshkeys()
{
    log "INFO:Retrieving ssh keys from Azure Storage"
	sudo apt-get --yes --force-yes install build-essential libssl-dev libffi-dev python-dev

	sudo pip install cryptography
    sudo pip install azure-storage

    # Download both Private and Public Key
    python GetSSHFromPrivateStorageAccount.py ${SSH_AZ_ACCOUNT_NAME} ${SSH_AZ_ACCOUNT_KEY} id_rsa
    python GetSSHFromPrivateStorageAccount.py ${SSH_AZ_ACCOUNT_NAME} ${SSH_AZ_ACCOUNT_KEY} id_rsa.pub
}


function configure_ssh()
{
    # copy ssh private key
    mkdir -p ~/.ssh
    mv id_rsa ~/.ssh

    # set permissions
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_rsa

    # copy root ssh key
    cat id_rsa.pub  >> ~/.ssh/authorized_keys
    rm id_rsa.pub

    # set permissions
    chmod 600 ~/.ssh/authorized_keys

    #restart sshd service - Ubuntu
    service ssh restart
}


function configure_ansible()
{
    # Copy ansible hosts file
    ANSIBLE_HOST_FILE=/etc/ansible/hosts
    ANSIBLE_CONFIG_FILE=/etc/ansible/ansible.cfg

    cp ${ANSIBLE_HOST_FILE} ${ANSIBLE_HOST_FILE}.backup
    cp ${ANSIBLE_CONFIG_FILE} ${ANSIBLE_CONFIG_FILE}.backup

    # Accept ssh keys by default
    printf  "[defaults]\nhost_key_checking = False\n\n" >> "${ANSIBLE_CONFIG_FILE}"
    # Shorten the ControlPath to avoid errors with long host names , long user names or deeply nested home directories
    echo  $'[ssh_connection]\ncontrol_path = ~/.ssh/ansible-%%h-%%r' >> "${ANSIBLE_CONFIG_FILE}"
    echo "\nscp_if_ssh=True" >> "${ANSIBLE_CONFIG_FILE}"
    # Generate a new ansible host file
    # printf  "[master]\n${IP_ADDRESS_SPACE}.${NUMBER_OF_NODES}\n\n" >> "${ANSIBLE_HOST_FILE}"
    printf  "[${TEMPLATE_ROLE}]\n${IP_ADDRESS_SPACE}[0:$(($NUMBER_OF_NODES - 1))]" >> "${ANSIBLE_HOST_FILE}"

    # Validate ansible configuration
    ansible ${TEMPLATE_ROLE} -m ping -v
}

function configure_storage()
{
	log "INFO: Configuring Storage "
	log "WARNING: This process is not incremental, don't use it if you don't want to lose your existing storage configuration"

	# Run ansible template to configure Storage : Create RAID and Configure Filesystem
	ansible-playbook InitStorage_RAID.yml  --extra-vars "target=${TEMPLATE_ROLE} file_system=${FILE_SYSTEM}"
}

install_ansible_ubuntu
get_sshkeys
configure_ssh
configure_ansible
