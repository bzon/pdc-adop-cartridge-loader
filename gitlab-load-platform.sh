#!/bin/bash -e

# If Infra is Swarm Cluster
if [[ $(docker network ls | grep $CUSTOM_NETWORK_NAME | grep overlay | wc -l) -gt 0 ]]
then
  export DOCKER_HOST=tcp://10.10.2.100:2375
fi

export INITIAL_WORKSPACE_NAME=${1}
export INITIAL_PROJECT_NAME={$1}Project

if [[ $1 == 'None' ]] || [[ -z $1 ]]; then
 echo "Nothing to do.."
 echo "Usage: ./gitlab-load-platform.sh ProjectName"
 exit 0
fi

# export ADMIN credentials
export $(docker exec jenkins env | grep ADMIN)

# Wait for Jenkins to be up and running       
until [[ $(docker exec jenkins curl -I -s ${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@localhost:8080/jenkins/|head -n 1|cut -d$' ' -f2) == 200 ]]; do echo "Jenkins unavailable, sleeping for 5s"; sleep 5; done

# Wait for Gerrit  SSH key to be available
until [[ $(docker exec jenkins curl -L ${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@gerrit:8080/gerrit/a/accounts/jenkins/sshkeys | grep jenkins@adop-core | wc -l) -gt 0 ]]; do echo "Gerrit's jenkins ssh key unavailable, sleeping for 5s"; sleep 5; done

# Wait for Gitlab to be up and running       
until [[ $(docker exec jenkins curl -I -s ${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@gitlab/gitlab/users/sign_in|head -n 1|cut -d$' ' -f2) == 200 ]]; do echo "Gitlab unavailable, sleeping for 5s"; sleep 5; done

# Wait for Gitlab Token to be available
until [[ $(docker exec jenkins curl --silent -X POST "http://gitlab/gitlab/api/v3/session?login=root&password=${PASSWORD_GITLAB}" | python -c 'import json,sys;obj=json.load(sys.stdin);print obj['\''private_token'\''];' | wc -l) -gt 0 ]]; do echo "Gitlab Token unavailable, sleeping for 5s"; sleep 5; done

# Create Gitlab_Load_Platform job
docker exec jenkins curl -X POST "${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@localhost:8080/jenkins/job/Load_Platform/buildWithParameters?GIT_URL=https://github.com/bzon/adop-b-framework-gitlab-load-platform.git&GENERATE_EXAMPLE_WORKSPACE=false" --data token=gAsuE35s

# Wait for Gitlab_Load_Platform job
until [[ $(docker exec jenkins curl -I -s ${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@localhost:8080/jenkins/job/Gitlab_Load_Platform/api/json|head -n 1|cut -d$' ' -f2) == 200 ]]; do echo "Load Platform job not finished, sleeping for 5s"; sleep 5; done

# Create Generate_Workspace job
docker exec jenkins curl -X POST "${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@localhost:8080/jenkins/job/Gitlab_Load_Platform/buildWithParameters?GIT_URL=https://github.com/bzon/adop-b-framework-gitlab-platform-management.git" --data token=UKdjguOElrnS

# Wait for Workspace_Managment to be created
until [[ $(docker exec jenkins curl -I -s ${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@localhost:8080/jenkins/job/Workspace_Management/job/Generate_Workspace/api/json|head -n 1|cut -d$' ' -f2) == 200 ]]; do echo "Gitlab Load Platform job not finished, sleeping for 5s"; sleep 5; done

# Run Workspace_Management
docker exec jenkins curl -X POST "${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@localhost:8080/jenkins/job/Workspace_Management/job/Generate_Workspace/buildWithParameters?WORKSPACE_NAME=${INITIAL_WORKSPACE_NAME}"

# Wait for Generate_Project to be created
until [[ $(docker exec jenkins curl -I -s ${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@localhost:8080/jenkins/job/${INITIAL_WORKSPACE_NAME}/job/Project_Management/job/Generate_Project/api/json|head -n 1|cut -d$' ' -f2) == 200 ]]; do echo "Generate Workspace job not finished, sleeping for 5s"; sleep 5; done

# Create Project                
docker exec jenkins curl -X POST ${INITIAL_ADMIN_USER}:${INITIAL_ADMIN_PASSWORD}@localhost:8080/jenkins/job/${INITIAL_WORKSPACE_NAME}/job/Project_Management/job/Generate_Project/buildWithParameters?PROJECT_NAME=${INITIAL_PROJECT_NAME}
