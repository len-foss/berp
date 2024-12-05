#!/bin/bash

FOLDER="custom"
[[ "${FOLDER}" != */ ]] && FOLDER="${FOLDER}/"

VERSION=$(git rev-parse --abbrev-ref HEAD | sed 's/-.*//')
STAGING=${VERSION}-staging
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# checkout ticket branch
function _ch {
    git checkout ${VERSION}-ticket-$2
}
function _chs {
    git checkout ${STAGING}-ticket-$2
}

# branch
function _b {
  _check_ticket
  BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD)-ticket-$TICKET"
  git checkout -b $BRANCH_NAME
}

function _chm {
  git checkout ${VERSION}
}
function _chms {
  git checkout ${STAGING}
}

function _check_ticket {
  if [ -z "$TICKET" ]; then
    BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
    if [[ $BRANCH_NAME =~ .*-([0-9]+)-.* ]]; then
      TICKET=${BASH_REMATCH[1]}
      echo "Branch ticket: $TICKET"
    elif [[ $BRANCH_NAME =~ -([0-9]+)$ ]]; then
      TICKET=${BASH_REMATCH[1]}
      echo "Branch \$ ticket: $TICKET"
    else
      read -p "Please enter the ticket: " TICKET
    fi
    export TICKET
  else
    echo "Current ticket: $TICKET"
  fi
}

function _check_clean_status {
  if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Working directory is not clean"
    exit 1
  fi
}

function _check_feature_branch {
  if [[ ! $CURRENT_BRANCH =~ $TICKET ]]; then
    echo "Error: Not on a feature branch"
    exit 1
  fi
}

function _f {
  _check_clean_status
  git fetch --all
  git checkout ${STAGING}
  git merge
  git checkout ${VERSION}
  git merge
  git checkout ${CURRENT_BRANCH}
}

# check merge
function _cm {
    _check_clean_status
    _check_feature_branch

    diff_output=$(git merge-tree $(git merge-base ${VERSION} ${STAGING}) ${VERSION} ${STAGING})
    if [[ -n "$diff_output" ]]; then
        echo "Error: Staging is out of sync with master, use ccp to get a new feature-staging branch"
        exit 1
    fi

    git checkout ${STAGING}  > /dev/null 2>&1
    # Check if the feature branch can be merged into staging without conflict
    MERGE_TEST=$(git merge --no-commit --no-ff ${CURRENT_BRANCH} 2>&1)
        if [[ $MERGE_TEST =~ "conflict" ]]; then
        echo "Error: Cannot merge feature branch into staging without conflict"
        git merge --abort
        git checkout ${CURRENT_BRANCH}  > /dev/null 2>&1
        exit 1
    fi

    echo "Feature branch can be merged into staging without conflict and only brings its own commits"
}

function _ccp {
  _check_clean_status
  _check_feature_branch
  _check_ticket
  _chms  # switch to staging
  _b 0 $TICKET  # switch to a new staging branch 
  commits=$(git log --format="%H" ${VERSION}..${CURRENT_BRANCH}) # Cherry-pick the commits onto the VERSION branch 
  echo $commits
  for commit in $commits; do
    git cherry-pick -x $commit
    if [ $? -ne 0 ]; then
      echo "Error: cherry-pick failed at commit $commit"
      exit 1
    fi
  done
}

# show all branches containing ticket
function _ls {
    git branch --list "*-ticket-$2"
}

# commit
function _c {
  _check_ticket
  local MSG="${2}"
  COMMIT_NAME="[ticket-$TICKET]"
  PREFIX_LEN=${#FOLDER}
  FOLDERS=$(git -C "$folder" diff --cached --name-only --diff-filter=ACM | xargs -I {} dirname {} | \
    awk -v folder="$FOLDER" -v flen="$PREFIX_LEN" '{sub("^" folder, ""); sub("/.*", ""); print}' | \
    sort -u | sed ':a;N;$!ba;s/\n/, /g' | sed 's/, $//'
  )
  COMMIT_NAME="${COMMIT_NAME} ${FOLDERS}"
  if [ -n "$MSG" ]; then
    COMMIT_NAME="${COMMIT_NAME}: ${MSG}"
  fi
  git commit -m "$COMMIT_NAME"
}


_$1 "$@"
