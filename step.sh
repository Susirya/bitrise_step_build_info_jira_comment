#!/usr/bin/env bash

set -e
# debug log
if [ "${show_debug_logs}" == "yes" ]; then
  set -x
fi

red=$'\e[31m'
green=$'\e[32m'
blue=$'\e[34m'
magenta=$'\e[35m'
cyan=$'\e[36m'
reset=$'\e[0m'

#if [ -z "$jira_project_name" ]; then
#    echo "Jira Project Name is required."
#    usage
#fi
#
#if [ -z "$jira_url" ]; then
#    echo "Jira Url is required."
#    usage
#fi
#
#if [ -z "$jira_token" ]; then
#    echo "Jira token is required."
#    usage
#fi
#
#if [ -z "$jira_from_status" ]; then
#    echo "Status of tasks for deployment is required."
#    usage
#fi

MERGES=$(git log --pretty=format:%B $(git merge-base --octopus $(git log -1 --merges --pretty=format:%P))..$(git log -1 --merges --pretty=format:%H))

SAVEDIFS=$IFS
IFS=$'\n'

MERGES=($MERGES)

IFS=$SAVEDIFS

SAVEDIFS=$IFS
IFS=$'|'

PROJECT_PREFIXES=($jira_project_prefixes)

IFS=$SAVEDIFS

LAST_COMMIT=$(git log -1 --pretty=format:%B)
LAST_COMMIT_SUBJECT=$(git log -1 --pretty=format:%s)

TASKS=()

echo "${green}⚙  PROJECT_PREFIXES:${reset}"
printf '%s\n' "${PROJECT_PREFIXES[@]}"
echo "${reset}"

echo "${blue}⚡ ️Last commit:${cyan}"
echo $'\t'"📜 "$LAST_COMMIT
echo "${reset}"

if (( ${#MERGES[*]} > 0 ))
then
	echo "${blue}⚡ Last merge commits:${cyan}"

	for (( i=0 ; i<${#MERGES[*]} ; ++i ))
	do
		echo $'\t'"📜 "${MERGES[$i]}
	done

	echo "${reset}"

	if [ "$LAST_COMMIT_SUBJECT" = "${MERGES[0]}" ];
	then
		echo "${green}✅ Merge commit detected. Searching for tasks in merge commits messages...${cyan}"
		for (( i=0 ; i<${#MERGES[*]} ; ++i ))
		do
			echo $'\t'"📜 "${MERGES[$i]}
		done
    for (( i=0 ; i<${#PROJECT_PREFIXES[*]} ; ++i ))
    do
      for task in $(echo ${MERGES[*]} | grep "${PROJECT_PREFIXES[$i]}[0-9]{1,5}" -E -o || true | sort -u -r --version-sort)
      do
        TASKS+=($task)
      done
    done

	else
		echo "${magenta}☑️  Not a merge commit. Searching for tasks in current commit message...${cyan}"
		echo
		echo $'\t'"📜 "$LAST_COMMIT "${reset}"

    for (( i=0 ; i<${#PROJECT_PREFIXES[*]} ; ++i ))
    do
      for task in $(echo $LAST_COMMIT | grep "${PROJECT_PREFIXES[$i]}[0-9]{1,5}" -E -o || true | sort -u -r --version-sort)
      do
        TASKS+=($task)
      done
    done
	fi
fi

if [ "${show_debug_logs}" == "yes" ]; then
    echo "${reset}"
    echo "${blue}📙  Tasks:${reset}"
    echo "${TASKS[*]}"
    echo "${green}⚙  Removing duplicates:${reset}"
fi

TASKS=($(printf '%s\n' "${TASKS[@]}" | sort -u ))

if [ "${show_debug_logs}" == "yes" ]; then
    echo "${TASKS[*]}"
    echo "${reset}"

    echo "${blue}✉️  Comment:${cyan}"
    echo "$jira_comment"
    echo "${reset}"
fi

escaped_jira_comment=$(echo "$jira_comment" | perl -pe 's/\n/\\n/g' | sed 's/"/'\''/g' | sed 's/.\{2\}$//')

if [ "${show_debug_logs}" == "yes" ]; then
    echo "${blue}✉️ Escaped comment:${cyan}"
    echo "$escaped_jira_comment"
    echo "${reset}"
fi

create_comment_data()
{
cat<<EOF
{
"body": "${escaped_jira_comment}"
}
EOF
}

comment_data="$(create_comment_data)"

echo "${blue}⚡ Posting comment to:"
if [  -n "$TASKS" ]; then
    echo $'\t'$'\t'"${red}❗️No issues to comment found!"
fi
for (( i=0 ; i<${#TASKS[*]} ; ++i ))
do
    echo $'\t'"${magenta}⚙️  "${TASKS[$i]}

    res="$(curl -w %{response_code} -s -o /dev/null -u $jira_user:$jira_token -X POST -H "Content-Type: application/json" \
            --data-binary "${comment_data}" --url https://${jira_domain}/rest/api/2/issue/${TASKS[$i]}/comment)"

    if test "$res" == "201"
    then
        echo $'\t'$'\t'"${green}✅ Success!${reset}"
    else
        echo $'\t'$'\t'"${red}❗️ Failed${reset}"
        echo $res
    fi
done
echo "${reset}" 


create_set_data()
{
cat<<EOF
{"fields": {"${jira_issue_field_name}":{"value":"${jira_issue_field_value}"}}}
EOF
}

set_field_data="$(create_set_data)"

echo "${blue}⚡ Setting field value ${set_field_data} to:"
if [  -n "$TASKS" ]; then
    echo $'\t'$'\t'"${red}❗️No issues to set value found!"
fi
for (( i=0 ; i<${#TASKS[*]} ; ++i ))
do
    echo $'\t'"${magenta}⚙️  "${TASKS[$i]}

    res="$(curl -w %{response_code} -s -o /dev/null -u $jira_user:$jira_token -X PUT -H 'Content-Type: application/json' \
            --data-binary "${set_field_data}" https://${jira_domain}/rest/api/2/issue/${TASKS[$i]})"

    if test "$res" == "204"
    then
        echo $'\t'$'\t'"${green}✅ Success!${reset}"
    else
        echo $'\t'$'\t'"${red}❗️ Failed${reset}"
        echo $res
    fi
done

echo "${blue}⚡ Changing statuses '$jira_from_status' -> '$jira_to_status' for:"

query=$(jq -n --arg jql "project = $jira_project_name AND status = '$jira_from_status'" \
    '{ jql: $jql, startAt: 0, maxResults: 200, fields: [ "id" ], fieldsByKeys: false }');

if [ "${show_debug_logs}" == "yes" ]; then
    echo "${blue}✉️ Query to be executed in Jira:${cyan}"
    echo "$query"
    echo "${reset}"
fi

tasks_to_close=$(curl -s -u $jira_user:$jira_token -X POST -H 'Content-Type: application/json' \
    --data "$query" --url  https://$jira_domain/rest/api/2/search | jq -r '.issues[].key')

if [ "${show_debug_logs}" == "yes" ]; then
    echo "${blue}✉️ Tasks potentially ready for transition found in Jira:${cyan}"
    echo "$tasks_to_close"
    echo "${reset}"
fi

if [  -n "$tasks_to_close" ]; then
    echo $'\t'$'\t'"${red}❗️No issues with '$jira_from_status' status found!"
fi

for task in ${tasks_to_close}
do
    case "$TASKS" in
        *"$task"*)
            echo $'\t'"${magenta}⚙️  "$task

            if [ -n "$jira_to_status" ]; then
                transition_id=$(curl -s -u $jira_user:$jira_token -H 'Accept: application/json'\
                    --url  https://$jira_domain/rest/api/2/issue/$task/transitions | \
                    jq -r ".transitions[] | select( .to.name == \"$jira_to_status\" ) | .id")

                if [ -n "$transition_id" ]; then
                    query=$(jq -n \
                        --arg transition_id $transition_id \
                        '{ transition: { id: $transition_id } }'
                    );

                    res="$(curl -w %{response_code} -s -u $jira_user:$jira_token \
                        -H 'Content-Type: application/json' --request POST \
                        --data "$query" --url  https://$jira_domain/rest/api/2/issue/$task/transitions)"

                    if test "$res" == "204"
                    then
                        echo $'\t'$'\t'"${green}✅ Success!${reset}"
                    else
                        echo $'\t'$'\t'"${red}❗️ Failed${reset}"
                        echo $res
                    fi
                else
                    echo $'\t'$'\t'"${red}❗️No matching transitions from status '$jira_from_status' to '$jira_to_status' for $task"
                fi
            fi
            ;;
    esac
done
