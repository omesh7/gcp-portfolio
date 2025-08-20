#!bin/bash
# Lab 1: Create Project & Assign Viewer Role
export PROJECT_ID="devops-iam-demo-$(date +%s)"

gcloud projects create $PROJECT_ID
gcloud config set project $PROJECT_ID

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:devops.engineer@example.com" \
  --role="roles/viewer"

#Lab 2: Create a Service Account & Grant Role
gcloud iam service-accounts create devops-bot \
  --display-name="DevOps Pipeline Bot"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:devops-bot@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.editor"

  #TASKS Your Cloud Build pipeline should deploy to GKE but NOT delete clusters.

gcloud iam service-accounts create task-3-role \
   --display-name="Task 3 Role"

gcloud projects add-iam-policy-binding $PROJECT_ID \
   --member="serviceAccount:task-3-role@$PROJECT_ID.iam.gserviceaccount.com" \
   --role="roles/container.developer"
  #roles/container.developer role allows deploying to GKE clusters but doesn't include cluster deletion permissions


  #-------------------CLEAN_RESOURCES-------------

gcloud projects delete $PROJECT_ID --quiet
unset PROJECT_ID
