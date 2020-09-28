 #!/bin/bash

cleanExit() {
  echo "🚀 Exiting..."
  rm -f changes.txt*
  rm -f deleted.txt*
  rm -f temp* 
  exit
}

echo "🚀 Salesforce deployment job started!"

SILENT=false
OPEN_ORG=false
REMOVE_ONLY=false
DEPLOY_ONLY=false
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

while [[ $# -gt 0 ]]; do
    case "$1" in
    -s)
        SILENT=true
        shift
        ;;
    -o)
        OPEN_ORG=true
        shift
        ;;
    -r)
        REMOVE_ONLY=true
        DEPLOY_ONLY=false
        shift
        ;;
    -d)
        DEPLOY_ONLY=true
        REMOVE_ONLY=false
        shift
        ;;
    --)
        shift
        break
        ;;
    *)
        echo "Invalid option: $1"
        exit 1  ## Could be optional.
        ;;
    esac
  shift
done

## Get changes


if [ $SILENT != 'true' ]
then
  ## Get revision ID
  echo "🚀 Please provide the GIT revision ID, this will be used to diff against your current HEAD (i.e. release/1.39 or HEAD~1)"
  read -p "🚀 GIT Revision ID: " GIT_REV
  echo
else
  GIT_REV=HEAD
  DEFAULT_ORG="$(sfdx force:config:get defaultusername --json | grep -Eo '"value":.*?[^\\]",' | sed -e 's/[\"\,\: ]*//g' | sed -e 's/value//g')"
  echo "🚀 Default org:" $DEFAULT_ORG
fi

## Get changes
git diff $GIT_REV --diff-filter=ACMTUXB --name-only --no-renames -- force-app/ > temp
## Get deleted
git diff $GIT_REV --diff-filter=D --name-only --no-renames -- force-app/ > tempd

if [ $SILENT != 'true' ]
then
  ## Confirm manifest is correct
  if [ $REMOVE_ONLY != 'true' ]
  then
    echo
    echo "🚀 Deployment manifest:"
    echo "   ===================="
    cat temp
  fi
  if [ $DEPLOY_ONLY != 'true' ]
  then
    echo
    echo "🚀 Deleted manifest:"
    echo "   ================="
    cat tempd
  fi

  echo
  read -p "🚀 Confirm the manifest above is correct (y/N): " ANSWER
  case ${ANSWER:0:1} in
      y|Y )
      ;;
      * )
          echo "🚀 Try a different GIT revision ID."
          cleanExit
      ;;
  esac
fi

# ** Convert manifest to SFDX format
# Convert newlines to commas
tr '\n' ',' < temp > changes.txt
rm temp
# Add escaped double quotes around each filename
sed -i -e 's/\,/\"\"\,\"\"/g' changes.txt 
# Put double quotes at the beginning of the file
echo -e "\"\"$(cat changes.txt)" > changes.txt
# Remove trailing comma
sed -i -e 's/\,\"\"$//g' changes.txt

# ** Convert manifest SFDX format
# Convert newlines to commas
tr '\n' ',' < tempd > deleted.txt
rm tempd
# Add escaped double quotes around each filename
sed -i -e 's/\,/\"\"\,\"\"/g' deleted.txt 
# Put double quotes at the beginning of the file
echo -e "\"\"$(cat deleted.txt)" > deleted.txt
# Remove trailing comma
sed -i -e 's/\,\"\"$//g' deleted.txt

if [ $SILENT != 'true' ]
then
  echo
  read -p "🚀 Target org to deploy to (i.e. evctpkg): " ORG
  if [ -z "$ORG" ]
  then
    echo "No org provided."
    cleanExit
  fi

  echo
  echo "🚀 Deployment command:"
  echo "   ====================="
  if [ $REMOVE_ONLY != 'true' ]
  then
    echo
    echo "sfdx force:source:deploy -u $ORG -p $(<changes.txt)" 
  fi
  if [ $DEPLOY_ONLY != 'true' ]
  then
    echo
    echo "🚀 sfdx force:source:delete -r -u $ORG -p $(<deleted.txt)"
  fi

  echo
  read -p "🚀 Type D to deploy execute the deployment commands above (D): " ANSWER
  case ${ANSWER:0:1} in
      d|D )
      ;;
      * )
          echo "🚀 No deployment performed."
          cleanExit
      ;;
  esac
fi

if [ $SILENT != 'true' ]
then
  if [ $REMOVE_ONLY != 'true' ]
  then
    echo
    sfdx force:source:deploy -u $ORG -p $(<changes.txt)
  fi
  if [ $DEPLOY_ONLY != 'true' ]
  then
    echo
    git stash push &> /dev/null
    git checkout $GIT_REV -- force-app/ &> /dev/null
    sfdx force:source:delete -r -u $ORG -p $(<deleted.txt)
    # git checkout $BRANCH -- force-app/ &> /dev/null
    git reset $BRANCH --hard &> /dev/null
    git stash pop &> /dev/null
  fi
  
  echo
  read -p "🚀 Deployment complete.  Open SFDX org? (Y/n): "
  case ${ANSWER:0:1} in
      y|Y )
      echo
      sfdx force:org:open -u $ORG
      ;;
      * )
      ;;
  esac
  echo
else
  if [[ -s changes.txt ]]
  then
    echo "🚀 Deploying changes and deletions against default org:" $DEFAULT_ORG
    if [ $REMOVE_ONLY != 'true' ]
    then
      echo
      sfdx force:source:deploy -p $(<changes.txt)
    fi
    if [ $DEPLOY_ONLY != 'true' ]
    then
      echo
      sfdx force:source:delete -p $(<deleted.txt)
    fi
  else
    echo "🚀 No changes to deploy!"
  fi
  if [ $OPEN_ORG == true ]
    then
      echo "🚀 Opening default org..."
      echo
      sfdx force:org:open
      echo
  fi
fi
cleanExit