#!/bin/bash

#Please run azure-cli version 2.0.79 as minimum

# Change for your subscription
AZ_SUBSCRIPTION=SWAP YOURS HERE
AZ_RESOURCE_GROUP=liq_poc
AZ_LOCATION=westeurope
AZ_MANAGED_IDENTITY=liq_identity
AZ_TOPIC_NAME=JuniperOut
AZ_STORAGE_NAME=emfstor546
AZ_QUEUE_NAME=emfin
AZ_CONTAINER_NAME=from-juniper
AZ_EVENT_SUBSCRIPTION_NAME=juniper-subscription

az login
az account set -s ${AZ_SUBSCRIPTION} 

# Check EventGrid is enabled!
eventgridregistered=$(az provider show --namespace Microsoft.EventGrid --query "registrationState")
if [ $eventgridregistered == "NotRegistered" ]; then
    az provider register --namespace Microsoft.EventGrid
    eventgridregistered=$(az provider show --namespace Microsoft.EventGrid --query "registrationState")
fi

# Create resource group
az group create --name ${AZ_RESOURCE_GROUP} --location ${AZ_LOCATION}

#Create a user assigned managed identity for use on our storage and cluster.
#This means this identity will exist even if the resources it is granted access
#to are deleted
spID=$(az identity create -n ${AZ_MANAGED_IDENTITY} -g ${AZ_RESOURCE_GROUP} --query principalId --out tsv)
echo "Service Principal created: ${spID}"

# Create Storage Queue - HAS TO BE V2
#Create Storage with HDFS Support - (notice local redundancy)
storageID=$(az storage account create \
    --name ${AZ_STORAGE_NAME} \
    --resource-group ${AZ_RESOURCE_GROUP} \
    --location ${AZ_LOCATION} \
    --sku Standard_RAGRS \
    --kind StorageV2 \
    --https-only true \
    --enable-hierarchical-namespace true \
    --query id --out tsv)
echo "Storage account created: ${storageID}"

# Grant Role assignment to the storage
az role assignment create --assignee ${spID} --role 'Storage Blob Data Owner' --scope ${storageID}

az storage queue create --name ${AZ_QUEUE_NAME} --account-name ${AZ_STORAGE_NAME}
az storage container create --name ${AZ_CONTAINER_NAME} --account-name ${AZ_STORAGE_NAME}

# Get the id for queue
queueid="$storageID/queueservices/default/queues/${AZ_QUEUE_NAME}"
expiryDate=$(date -d "+1 days" +"%Y-%m-%d")

az eventgrid event-subscription create \
  --source-resource-id $storageID \
  --subject-begins-with "/blobServices/default/containers/${AZ_CONTAINER_NAME}/" \
  --name ${AZ_EVENT_SUBSCRIPTION_NAME} \
  --endpoint-type storagequeue \
  --endpoint $queueid \
  --expiration-date $expiryDate

# Test it!
touch testfile.txt
az storage blob upload --file testfile.txt --name testfile.txt --container-name ${AZ_CONTAINER_NAME} --account-name ${AZ_STORAGE_NAME}