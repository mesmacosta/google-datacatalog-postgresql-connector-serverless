#!/usr/bin/env bash
dir=$(pwd)

function finish {
    cd $dir
}
trap finish EXIT

cd cloud-function

function enable_apis() {
    gcloud services enable secretmanager.googleapis.com cloudfunctions.googleapis.com
}

function create_pubsub_topic() {
    local topic_name=$1
    gcloud pubsub topics create $topic_name
}

function create_service_account() {
    local service_account_name=$1
    local project_id=$2
    # Create Service Account
    gcloud iam service-accounts create $service_account_name \
    --display-name  "Service Account for PostgreSQL connector serverless" \
    --project $project_id

    # Add Data Catalog Admin role
    gcloud projects add-iam-policy-binding $project_id \
    --member "serviceAccount:$service_account_name@$project_id.iam.gserviceaccount.com" \
    --project $project_id \
    --quiet \
    --role "roles/datacatalog.admin"

    # Add Secrets manager acessor role
    gcloud projects add-iam-policy-binding $project_id \
    --member "serviceAccount:$service_account_name@$project_id.iam.gserviceaccount.com" \
    --project $project_id \
    --quiet \
    --role "roles/secretmanager.secretAccessor"
}

function create_cloud_scheduler() {
    local topic_name=$1

    gcloud scheduler jobs create pubsub gcs-run-postgresql-connector \
    --schedule "$CRON_SCHEDULE" \
    --topic $topic_name \
    --message-body "sync"
}

function upsert_cloud_function() {
    local topic_name=$1
    local project_id=$2
    local service_account_name=$3


    local project_number=$(gcloud projects list \
    --filter="project_id:$project_id" \
    --format='value(project_number)')

  cat <<EOF >.env.yaml
DATACATALOG_PROJECT_ID: $DATACATALOG_PROJECT_ID
DATACATALOG_PROJECT_NUMBER: $project_number
DATACATALOG_LOCATION_ID: $DATACATALOG_LOCATION_ID
DB_CREDENTIALS_USER_SECRET: $DB_CREDENTIALS_USER_SECRET
DB_CREDENTIALS_PASS_SECRET: $DB_CREDENTIALS_PASS_SECRET
POSTGRESQL_SERVER: $POSTGRESQL_SERVER
POSTGRES_DB: $POSTGRES_DB  
EOF

    gcloud functions deploy gcf-run-postgresql-connector \
    --runtime python37 \
    --trigger-topic $topic_name \
    --project $project_id \
    --entry-point sync \
    --service-account $service_account_name@$project_id.iam.gserviceaccount.com \
    --env-vars-file .env.yaml
}

function main() {
    readonly update_function=$UPDATE_FUNCTION

    gcloud config set project $DATACATALOG_PROJECT_ID

    # Skip infrastructure creation if we are updating the cloud function.
    if [[ -z ${update_function} ]]; then
        echo -e "\033[1;42m [STEP 1] Enable required APIs \033[0m"
        enable_apis

        echo -e "\033[1;42m [STEP 2] Create PubSub topic \033[0m"
        create_pubsub_topic $TOPIC_NAME

        echo -e "\033[1;42m [STEP 3] Create Cloud Scheduler \033[0m"
        # CRON_SCHEDULE format: "30 * * * *"
        # https://cloud.google.com/scheduler/docs/configuring/cron-job-schedules
        create_cloud_scheduler $TOPIC_NAME

        echo -e "\033[1;42m [STEP 4] Create Cloud Function Service Account \033[0m"
        create_service_account $SA_NAME $DATACATALOG_PROJECT_ID
    fi

    echo -e "\033[1;42m [LAST STEP] Upsert Cloud Function \033[0m"

    # Update requirements.txt
    python3 -m pip install pip-tools
    python3 -m piptools compile --output-file=requirements.txt requirements.in

    upsert_cloud_function $TOPIC_NAME $DATACATALOG_PROJECT_ID $SA_NAME
}

main