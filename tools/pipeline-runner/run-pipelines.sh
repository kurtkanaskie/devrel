#!/bin/sh
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DIRS="$1"
PIPELINE_REPORT=""
DEVREL_ROOT="$PWD"

PATH=$PATH:"$DEVREL_ROOT/tools/another-apigee-client"
PATH=$PATH:"$DEVREL_ROOT/tools/organization-cleanup/organization-cleanup.sh"
PATH=$PATH:"$DEVREL_ROOT/tools/apigee-sackmesser/bin"

run_single_pipeline() {
  DIR=$1
  echo "[INFO] DevRel Pipeline: $DIR"
  (cd "$DIR" && ./pipeline.sh;)
}

if [ -z "$APIGEE_USER" ] && [ -z "$APIGEE_PASS" ]; then
  echo "[WARN] NO CREDENTIALS - SKIPPING PIPELINES"
  exit 0
fi

echo "[INFO] cleaning up organizations"
APIGEE_TOKEN=$(gcloud auth print-access-token)
sackmesser clean all --googleapi -t "$APIGEE_TOKEN" -o "$APIGEE_X_ORG" --quiet
sackmesser clean all --apigeeapi -u "$APIGEE_USER" -p "$APIGEE_PASS" -o "$APIGEE_ORG" --quiet

if [ -z "$DIRS" ]; then
  for TYPE in references labs tools; do
    for D in "$DEVREL_ROOT"/"$TYPE"/*; do
      DIRS="$DIRS,$D"
    done
  done
  DIRS=$(echo "$DIRS" | cut -c 2-)
fi

for DIR in $(echo "$DIRS" | sed "s/,/ /g")
do
  if ! test -f  "$DIR/pipeline.sh"; then
    echo "[WARN] $DIR/pipeline.sh NOT FOUND"
    PIPELINE_REPORT="$PIPELINE_REPORT;[N/A] $DIR,0,0s"
  else
    STARTTIME=$(date +%s)
    run_single_pipeline "$DIR"
    PIPELINE_EXIT=$?
    ENDTIME=$(date +%s)
    PIPELINE_REPORT="$PIPELINE_REPORT;$DIR,$PIPELINE_EXIT,$((ENDTIME-STARTTIME))s"
  fi
done

# print report
echo "$PIPELINE_REPORT" | tr ";" "\n" | awk 'NF' | awk -F"," '$2 = ($2 > 0 ? "fail" : "pass")' OFS=";" > pipeline-result.txt
echo
echo "FINAL RESULT"
column -s ";" -t ./pipeline-result.txt
echo

# set exit code
! echo "$PIPELINE_REPORT" | tr ";" "\n" | awk -F"," '{ print $2 }' | grep -v -q "0"
