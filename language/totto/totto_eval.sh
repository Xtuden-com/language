# coding=utf-8
# Copyright 2018 The Google AI Language Team Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#!/bin/bash

# Prepare the needed variables.
PREDICTION_PATH=unset
TARGET_PATH=unset
OUTPUT_DIR="temp/"
MODE="test"

# Function to report
usage()
{
  echo "Usage: totto_eval.sh [ -p | --prediction_path PREDICTION/PATH.txt ]
                     [ -t | --target_path TARGET/PATH.jsonl ]
                     [ -o | --output_dir ./dev/ ]
                     [ -m | --mode   dev/test   ]"
  exit 2
}

# Parse the arguments and check for validity.
PARSED_ARGUMENTS=$(getopt -a -n totto_eval -o p:t:o:m: --long prediction_path:,target_path:,output_dir:,mode: -- "$@")
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
  usage
fi

# echo "PARSED_ARGUMENTS is $PARSED_ARGUMENTS"
# Sort the arguments into their respective variables.
while :
do
  case "$1" in
    -p | --prediction_path) PREDICTION_PATH="$2"  ; shift 2  ;;
    -t | --target_path)     TARGET_PATH="$2"      ; shift 2  ;;
    -o | --output_dir)      OUTPUT_DIR="$2"       ; shift 2 ;;
    -m | --mode)            MODE="$2"             ; shift 2 ;;
    # -- denotes the end of arguments; break out of the while loop
    --) shift; break ;;
    *) shift; break ;
  esac
done

# Check the validity of the arguments (e.g., files exist and mode is valid).
if [[ $PREDICTION_PATH == unset || $TARGET_PATH == unset ]]
then
  echo "Prediction path and target path are required arguments."
  usage
  exit 2
elif [[ !($MODE == "dev" || $MODE == "test") ]]
then
  echo "Mode has to be dev or test."
  usage
  exit 2
elif [[ !(-f $PREDICTION_PATH) ]]
then
  echo "Your prediction path \"${PREDICTION_PATH}\" does not exist on your filesystem."
  usage
  exit 2
elif [[ !(-f $TARGET_PATH) ]]
then
  echo "Your target path \"${TARGET_PATH}\" does not exist on your filesystem."
  usage
  exit 2
fi

# Trim trailing slash (for concatenation ease later).
OUTPUT_DIR=$(echo $OUTPUT_DIR | sed 's:/*$::')

# All checks passed. Report the variables.
echo "Running with the following variables:"
echo "PREDICTION_PATH   : $PREDICTION_PATH"
echo "TARGET_PATH       : $TARGET_PATH "
echo "OUTPUT_DIR        : $OUTPUT_DIR"
echo "MODE              : $MODE"

if [ ! -d "${OUTPUT_DIR}" ]; then
  echo "Creating Output directory."
  mkdir "${OUTPUT_DIR}"
fi

if [ ! -d "${OUTPUT_DIR}/mosesdecoder" ]; then
  echo "Cloning moses for BLEU script."
  git clone https://github.com/moses-smt/mosesdecoder.git "${OUTPUT_DIR}/mosesdecoder"
  ret=$?
  if [ $ret -ne 0 ]; then
    echo "Failed to git clone. Make sure that git is installed and that github is reacheable."
    exit 1
  fi
fi

# echo "Preparing references."
python -m language.totto.prepare_references_for_eval \
  --input_path="${TARGET_PATH}" \
  --output_dir="${OUTPUT_DIR}" \
  --mode="${MODE}"
ret=$?
if [ $ret -ne 0 ]; then
  echo "Failed to run python script. Please ensure that all libraries are installed and that files are formatted correctly."
  exit 1
fi

echo "Preparing predictions."
python -m language.totto.prepare_predictions_for_eval \
  --input_prediction_path="${PREDICTION_PATH}" \
  --input_target_path="${TARGET_PATH}" \
  --output_dir="${OUTPUT_DIR}"
ret=$?
if [ $ret -ne 0 ]; then
  echo "Failed to run python script. Please ensure that all libraries are installed and that files are formatted correctly."
  exit 1
fi

# Define all required files and detokenize.
echo "Running detokenizers."
declare -a StringArray=("predictions" "overlap_predictions" "nonoverlap_predictions"
            "references" "overlap_references" "nonoverlap_references"
            "references-multi0" "references-multi1" "references-multi2"
            "overlap_references-multi0" "overlap_references-multi1" "overlap_references-multi2"
            "nonoverlap_references-multi0" "nonoverlap_references-multi1" "nonoverlap_references-multi2"
            "tables_parent_precision_format" "tables_parent_recall_format"
            "overlap_tables_parent_precision_format" "overlap_tables_parent_recall_format"
            "nonoverlap_tables_parent_precision_format" "nonoverlap_tables_parent_recall_format"
            )

for filename in "${StringArray[@]}";
do
  ${OUTPUT_DIR}/mosesdecoder/scripts/tokenizer/detokenizer.perl -q -l en -threads 8 < "${OUTPUT_DIR}/${filename}" > "${OUTPUT_DIR}/detok_${filename}"
done

echo "======== EVALUATE OVERALL ========"

# Compute BLEU scores using sacrebleu (https://github.com/mjpost/sacrebleu)
echo "Computing BLEU (overall)"
cat ${OUTPUT_DIR}/detok_predictions | sacrebleu ${OUTPUT_DIR}/detok_references-multi0 ${OUTPUT_DIR}/detok_references-multi1 ${OUTPUT_DIR}/detok_references-multi2
ret=$?
if [ $ret -ne 0 ]; then
  echo "Failed to run eval script. You may have to install PERL packages using cpanm."
  exit 1
fi

echo "Computing PARENT (overall)"
python -m language.totto.totto_parent_eval \
  --reference_path="${OUTPUT_DIR}/detok_references-multi" \
  --generation_path="${OUTPUT_DIR}/detok_predictions" \
  --precision_table_path="${OUTPUT_DIR}/detok_tables_parent_precision_format" \
  --recall_table_path="${OUTPUT_DIR}/detok_tables_parent_recall_format"

echo "======== EVALUATE OVERLAP SUBSET ========"

echo "Computing BLEU (overlap subset)"
cat ${OUTPUT_DIR}/detok_overlap_predictions | sacrebleu ${OUTPUT_DIR}/detok_overlap_references-multi0 ${OUTPUT_DIR}/detok_overlap_references-multi1 ${OUTPUT_DIR}/detok_overlap_references-multi2

echo "Computing PARENT (overlap subset)"
python -m language.totto.totto_parent_eval \
  --reference_path="${OUTPUT_DIR}/detok_overlap_references-multi" \
  --generation_path="${OUTPUT_DIR}/detok_overlap_predictions" \
  --precision_table_path="${OUTPUT_DIR}/detok_overlap_tables_parent_precision_format" \
  --recall_table_path="${OUTPUT_DIR}/detok_overlap_tables_parent_recall_format"

echo "======== EVALUATE NON-OVERLAP SUBSET ========"

echo "Computing BLEU (non-overlap subset)"
cat ${OUTPUT_DIR}/detok_nonoverlap_predictions | sacrebleu ${OUTPUT_DIR}/detok_nonoverlap_references-multi0 ${OUTPUT_DIR}/detok_nonoverlap_references-multi1 ${OUTPUT_DIR}/detok_nonoverlap_references-multi2

echo "Computing PARENT (non-overlap subset)"
python -m language.totto.totto_parent_eval \
  --reference_path="${OUTPUT_DIR}/detok_nonoverlap_references-multi" \
  --generation_path="${OUTPUT_DIR}/detok_nonoverlap_predictions" \
  --precision_table_path="${OUTPUT_DIR}/detok_nonoverlap_tables_parent_precision_format" \
  --recall_table_path="${OUTPUT_DIR}/detok_nonoverlap_tables_parent_recall_format"
