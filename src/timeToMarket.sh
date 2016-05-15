#!/bin/bash

JIRA_REST_API_URL="https://somaiah.atlassian.net/rest/api/2"
JIRA_USER="admin"
JIRA_PASSWORD="secret"

CONFLUENCE_REST_API_PAGE_URL="https://somfluence.atlassian.net/wiki/rest/api/content"
CONFLUENCE_SPACE="MRLI"
CONFLUENCE_USER="admin"
CONFLUENCE_PASSWORD="secret"
CONFLUENCE_PAGE_ID=1179659

SPACE="<div style='line-height:50px;'><br/></div>"
declare -a JIRA_FIX_VERSION_ARRAY
declare -a DAYS_BETWEEN_ARRAY
JSON=""

###################################################################################################################
# echo message and exit
###################################################################################################################
function exitOnFailure() {
	echo $1;
	exit -1;
}

###################################################################################################################
# get some confluence page info, specified by CONFLUENCE_PAGE_ID
# This is needed to update the page later
###################################################################################################################
function getPageInfo() {
	local url="${CONFLUENCE_REST_API_PAGE_URL}?expand=version"
	local response=`curl --globoff --insecure --silent -u ${CONFLUENCE_USER}:${CONFLUENCE_PASSWORD} -X GET -H 'Content-Type: application/json' ${url}`
	NEXT_PAGE_VERSION=`echo ${response} | jq -r --arg PAGE_ID "${CONFLUENCE_PAGE_ID}" '.results | .[] | select(.id==$PAGE_ID) |.version.number + 1'`
	PAGE_NAME=`echo ${response} | jq -r --arg PAGE_ID "${CONFLUENCE_PAGE_ID}" '.results | .[] | select(.id==$PAGE_ID) |.title'`
}

###################################################################################################################
# Update a Confluence page, specified by CONFLUENCE_PAGE_ID
###################################################################################################################
function updateConfluencePage() {
	declare NEXT_PAGE_VERSION=""
	declare PAGE_NAME=""

	getPageInfo

	#  Had to redirect to a file to create input to get this work properly. Otherwise the variable replacement choked
	rm -f body.json
	echo '{"id":"'${CONFLUENCE_PAGE_ID}'","type":"page","title":"'${PAGE_NAME}'","space":{"key":"'${CONFLUENCE_SPACE}'"},"body":{"storage":{"value":"'${CONTENT}'","representation":"storage"}},"version":{"number":'${NEXT_PAGE_VERSION}'}}' > body.json

	RESPONSE=`curl --globoff --insecure --silent -u ${CONFLUENCE_USER}:${CONFLUENCE_PASSWORD} -X PUT -H 'Content-Type: application/json' --data @body.json ${CONFLUENCE_REST_API_PAGE_URL}/${CONFLUENCE_PAGE_ID}`
echo ${RESPONSE}
	UPDATED_PAGE_ID=`echo ${RESPONSE} | jq '.id | select(. != null)'`

	if [ -z "$UPDATED_PAGE_ID" ]; then
		echo "Could not create a page on confluence. Response was: $RESPONSE"
		exitOnFailure "Exiting."
	fi

	echo "Page with ID: $UPDATED_PAGE_ID and Title: $PAGE_NAME successfully updated."
}


###################################################################################################################
# Generate HTML for a confluence line chart macro
###################################################################################################################
function generateLineChartMacro() {
	BAR_CONTENT="<ac:macro ac:name='chart'>
  <ac:parameter ac:name='type'>line</ac:parameter>
  <ac:parameter ac:name='width'>400</ac:parameter>
  <ac:parameter ac:name='height'>600</ac:parameter>
    <ac:parameter ac:name='forgive'>true</ac:parameter>
  <ac:parameter ac:name='xLabel'>Release</ac:parameter>
  <ac:parameter ac:name='yLabel'>Days</ac:parameter>
  <ac:parameter ac:name='categoryLabelPosition'>down90</ac:parameter>
  <ac:rich-text-body>
    <table>
      <tbody>
		<tr>
          <th><p>&nbsp;</p></th>"

	# Print out x-axis
	for i in "${JIRA_FIX_VERSION_ARRAY[@]}"; do
		BAR_CONTENT="${BAR_CONTENT}
		<th><p>$i</p></th>"
	done

	BAR_CONTENT="${BAR_CONTENT}
	</tr>
	<tr>
		<td><p>Average days used per release</p></td>"

	for i in "${DAYS_BETWEEN_ARRAY[@]}"; do
		BAR_CONTENT="${BAR_CONTENT}
		<td><p>$i</p></td>"
	done

	BAR_CONTENT="${BAR_CONTENT}
	</tr>
	</tbody>
	</table>
  </ac:rich-text-body>
  </ac:macro>"

	echo "The macro generated is:"
	echo "${BAR_CONTENT}"

	CONTENT="${CONTENT} ${BAR_CONTENT} ${SPACE}"
}

###################################################################################################################
# Calculates the days between two given dates
###################################################################################################################
function calculateDaysBetween() {
	local date1=`echo $1 | sed 's/T.*//' | sed 's/-//g'`
	local date2=`echo $2 | sed 's/T.*//' | sed 's/-//g'`
	echo $(( ($(date --date=$date2 +%s) - $(date --date=$date1 +%s) )/(60*60*24) ))
}

###################################################################################################################
# Gets the number of days between the created and resolution dates
###################################################################################################################
function getDaysBetweenArray() {
	local fixVersionIndex=0
	local averageDaysForRelease

    for i in "${JIRA_FIX_VERSION_ARRAY[@]}"; do
		#strip leading and trailing spaces
		version="$(echo -e "${i}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

		local resolutionDates_csv=`echo ${JSON} | jq -r --arg FIX_VERSION "${version}" '.[] | select (.version==$FIX_VERSION)  | .resolutionDate'`
		resolutionDates_csv=`echo ${resolutionDates_csv} | sed 's/\[//' | sed 's/\]//' | sed 's/\"//g'`
		echo "getDaysBetweenArray(): local resolutionDates_csv is: $resolutionDates_csv"
		local createdDates_csv=`echo ${JSON} | jq -r --arg FIX_VERSION "${version}" '.[] | select (.version==$FIX_VERSION)  | .createdDate'`
		createdDates_csv=`echo ${createdDates_csv} | sed 's/\[//' | sed 's/\]//' | sed 's/\"//g'`
		echo "getDaysBetweenArray(): local createdDates_csv is: $createdDates_csv"

		local resolutionDates_array=( ${resolutionDates_csv} )
		local createdDates_array=( ${createdDates_csv} )

		( IFS=$', '; echo "getDaysBetweenArray(): local resolutionDates_array is: [${resolutionDates_array[*]}]" )
		( IFS=$', '; echo "getDaysBetweenArray(): local createdDates_array is: [${createdDates_array[*]}]" )

		local index=0
		local daysBetween=0
		for j in "${resolutionDates_array[@]}"; do
			let daysBetween+=$(calculateDaysBetween "${createdDates_array[index]}" "${resolutionDates_array[index]}")
			let index++
		done

		let averageDaysForRelease=${daysBetween}/${index}
		DAYS_BETWEEN_ARRAY[fixVersionIndex]=${averageDaysForRelease}
		let fixVersionIndex++
	done

	( IFS=$', '; echo "getDaysBetweenArray(): DAYS_BETWEEN_ARRAY is: [${DAYS_BETWEEN_ARRAY[*]}]" )

}


###################################################################################################################
# Returns an array of all unique fix versions
###################################################################################################################
function getFixVersionsArray() {
	local version_array_csv=`echo ${JSON} | jq -r 'sort_by(.resolutionDate) | map(.version) | unique'`
	version_array_csv=`echo ${version_array_csv} | sed 's/\[//' | sed 's/\]//' | sed 's/\"//g'`

	oldIFS="$IFS"
	IFS=','
	IFS=${IFS:0:1} # this is useful to format your code with tabs
	JIRA_FIX_VERSION_ARRAY=( ${version_array_csv} )
	IFS="$oldIFS"

	( IFS=$', '; echo "getFixVersionsArray(): Jira fix version array is: [${JIRA_FIX_VERSION_ARRAY[*]}]" )
}


JIRA_SEARCH_URL="${JIRA_REST_API_URL}/search?jql=project=%22MRL%22%20AND%20issuetype%20in%20(Bug,%20Story,%20Task)%20AND%20fixVersion%20in%20releasedVersions()"

JIRA_FILTER_INFO=`curl --globoff --insecure --silent -u ${JIRA_USER}:${JIRA_PASSWORD} -X GET -H 'Content-Type: application/json' "${JIRA_SEARCH_URL}"`

JSON=`echo ${JIRA_FILTER_INFO} | jq -r '.issues | map(.fields | (.fixVersions[] | { version: .name }) + { resolutionDate: .resolutiondate} + {createdDate: .created})'`

getFixVersionsArray
getDaysBetweenArray

CONTENT="<h2>Average time to market per release </h2><table><tbody><tr>
		<td> <h2>Project: Moon Rocket Launch</h2> ${SPACE}"

generateLineChartMacro

CONTENT="${CONTENT} </td></tr></tbody></table>"

echo $CONTENT > ttm.txt
updateConfluencePage


