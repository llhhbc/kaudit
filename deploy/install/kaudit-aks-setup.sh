#!/bin/bash

######################################################
#       AKS Audit Log Setup for Alcide kAudit        #
######################################################

# mandatory user-defined script parameters
# may be provided in the command line: -c <AKS-cluster-name> -g <resource-group> -l <location>
# Resource Group of AKS cluster
RESOURCE_GROUP=""
# Location of AKS cluster, for example: eastus
LOCATION=""
# AKS cluster name
AKS_CLUSTER_NAME=""

echo "AKS Audit Log Setup for Alcide kAudit"

if [[ $# -eq 0 && $RESOURCE_GROUP == "" && $LOCATION == "" && $AKS_CLUSTER_NAME == "" ]]; then
  echo "Command line options:  -g <resource-group> -c <AKS-cluster-name> -l <location>"
  exit 0
fi

# Given command line args - parse them:
if (($# != 0)); then
  while getopts ":c:g:l:h" opt; do
    case $opt in
      c)
        AKS_CLUSTER_NAME="${OPTARG}"
        ;;
      g)
        RESOURCE_GROUP="${OPTARG}"
        ;;
      l)
        LOCATION="${OPTARG}"
        ;;
      h)
        echo "Command line options:  -g <resource-group> -c <AKS-cluster-name> -l <location>"
        exit 0
        ;;
      \?)
        echo "Invalid option: -$OPTARG" >&2
        exit 1
        ;;
      :)
        echo "Option -$OPTARG requires an argument." >&2
        exit 1
        ;;
    esac
  done
fi

# 0. validate user-provided parameters
if [ -z ${RESOURCE_GROUP} ]; then
  echo Resource group is not configured
  exit
fi
if [ -z ${LOCATION} ]; then
  echo Location is not configured
  exit
fi
if [ -z ${AKS_CLUSTER_NAME} ]; then
  echo AKS cluster name is not configured
  exit
fi


# optional script parameters, can leave default values
# EventHubs Namespace name
EVENT_HUBS_NAMESPACE="kaudit-eh-${AKS_CLUSTER_NAME}"
# EventHub name
EVENT_HUB="kaudit-eh-k8saudit-${AKS_CLUSTER_NAME}"
# EventHub manage Authorization Rule name
EVENT_HUBS_NAMESPACE_MANAGE_AUTH_RULE="k8s-audit-manage-${AKS_CLUSTER_NAME}"
# EventHub listen Authorization Rule name
EVENT_HUB_LISTEN_AUTH_RULE="k8s-audit-listen-${AKS_CLUSTER_NAME}"
# Diagnostics Settings name
DIAGNOSTICS_SETTINGS="k8s-audit-${AKS_CLUSTER_NAME}"

echo "Preparing EventHub ${EVENT_HUBS_NAMESPACE}/${EVENT_HUB} for AKS cluster ${AKS_CLUSTER_NAME} in resource group ${RESOURCE_GROUP}, location ${LOCATION}"


# 1. create EventHubs Namespace
az eventhubs namespace create \
   -n ${EVENT_HUBS_NAMESPACE} \
   -g ${RESOURCE_GROUP} \
   -l ${LOCATION} \
   --enable-kafka false \
   --sku Basic

# 2. Create EventHub
az eventhubs eventhub create \
   -n ${EVENT_HUB} \
   --namespace-name ${EVENT_HUBS_NAMESPACE} \
   -g ${RESOURCE_GROUP} \
   --message-retention 1 \
   --partition-count 2

# 3. Create Authorization Rule with Manage,Send,Listen rights on EventHub Namespace
MANAGE_RULE_ID=$(az eventhubs namespace authorization-rule create \
   -n ${EVENT_HUBS_NAMESPACE_MANAGE_AUTH_RULE} \
   --namespace-name ${EVENT_HUBS_NAMESPACE} \
   -g ${RESOURCE_GROUP} \
   --rights Manage Send Listen \
   --query id \
   -o tsv)

# 4. Create Authorization Rule with Listen rights on EventHub
az eventhubs eventhub authorization-rule create \
   -n ${EVENT_HUB_LISTEN_AUTH_RULE} \
   --eventhub-name ${EVENT_HUB} \
   --namespace-name ${EVENT_HUBS_NAMESPACE} \
   -g ${RESOURCE_GROUP} \
   --rights Listen

# 5. Send k8s audit log from the AKS cluster, using the configured Authorization Rule, to created EventHub
az monitor diagnostic-settings create \
   -n ${DIAGNOSTICS_SETTINGS} \
   --resource ${AKS_CLUSTER_NAME} \
   --resource-type microsoft.containerservice/managedclusters \
   -g ${RESOURCE_GROUP} \
   --event-hub ${EVENT_HUB} \
   --event-hub-rule ${MANAGE_RULE_ID} \
   --logs "[ { \"category\": \"kube-audit\", \"enabled\": true } ]"

# 6. Get credential keys for EventHub

echo Parameters for kAudit setup
echo ---------------------------
echo "EventHub name: ${EVENT_HUB}"
echo "EventHub connection string:"
az eventhubs eventhub authorization-rule keys list \
   -n ${EVENT_HUB_LISTEN_AUTH_RULE} \
   -g ${RESOURCE_GROUP} \
   --namespace-name ${EVENT_HUBS_NAMESPACE} \
   --eventhub-name ${EVENT_HUB} \
   --query primaryConnectionString \
   -o tsv

echo "AKS Audit Log Setup for Alcide kAudit complete!"
echo "Please follow Alcide kAudit installation guide to verify the AKS setup and integrate with kAudit."