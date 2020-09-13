#!/usr/bin/env bash

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--name) name="$2"; shift ;;
        -n|--value) value="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z ${name} ]] || [[ -z ${value} ]]; then
    echo "Must supply --name and --value."
    exit 1 # terminate and indicate error
fi

gcloud config set project $PROJECT_ID

echo -e "\033[1;42m [STEP 1] Enable required APIs \033[0m"

gcloud services enable secretmanager.googleapis.com

echo -e "\033[1;42m [STEP 2] Creating secret \033[0m"

echo -n $value | \
    gcloud beta secrets create $name \
      --data-file=- \
      --replication-policy automatic