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

MERGES=$(git log --pretty=format:%B $(git merge-base --octopus $(git log -1 --merges --pretty=format:%P))..$(git log -1 --merges --pretty=format:%H))

SAVEDIFS=$IFS
IFS=$'\n'

MERGES=($MERGES)

IFS=$SAVEDIFS

SAVEDIFS=$IFS
IFS=$'|'

PROJECT_PREFIXES=($project_prefix)

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

echo "${reset}"
echo "${blue}📙  Tasks:${reset}"
echo "${TASKS[*]}"
echo "${green}⚙  Removing duplicates:${reset}"
TASKS=($(printf '%s\n' "${TASKS[@]}" | sort -u ))
echo "${TASKS[*]}"
echo "${reset}"

echo "${blue}✉️  Comment:${cyan}"
echo "$jira_comment"
echo "${reset}"

escaped_jira_comment=$(echo "$jira_comment" | perl -pe 's/\n/\\n/g' | sed 's/"/'\''/g' | sed 's/.\{2\}$//')


echo "${blue}✉️ Escaped comment:${cyan}"
echo "$escaped_jira_comment"
echo "${reset}"

create_comment_data()
{
cat<<EOF
{
"body": "${escaped_jira_comment}"
}
EOF
}

comment_data="$(create_comment_data)"

echo "${blue}⚡ Posting to:"
for (( i=0 ; i<${#TASKS[*]} ; ++i ))
do
echo $'\t'"${magenta}⚙️  "${TASKS[$i]}

res="$(curl --write-out %{response_code} --silent --output /dev/null --user $jira_user:$jira_token --request POST --header "Content-Type: application/json" --data-binary "${comment_data}" --url https://${backlog_default_url}/rest/api/2/issue/${TASKS[$i]}/comment)"

if test "$res" == "201"
then
echo $'\t'$'\t'"${green}✅ Success!${reset}"
else
echo $'\t'$'\t'"${red}❗️ Failed${reset}"
echo $res
fi
done
echo "${reset}" 
