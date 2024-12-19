#!/bin/bash

inputFile="$2"

if [[ ! -f "$inputFile" ]]; then
    echo "Error: File '$inputFile' not found."
    exit 1
fi

mapfile input < "$inputFile"

archive_status="${input[0]}"
allowed_format="${input[1]}"
allowed_language="${input[2]}"
mark="${input[3]}"
penalty_for_unmatched="${input[4]}"
working_directory="${input[5]}"
student_id_range="${input[6]}"
expected_out_location="${input[7]}"
penalty_for_violation="${input[8]}"
plagiarism_ids="${input[9]}"
penalty_for_plagiarism="${input[10]}"

IFS=' ' read -r startID endID <<< "$student_id_range"
IFS=' ' read -r archive_status <<< "$archive_status"

working_directory="$(realpath "$working_directory")"
expected_out_location="$(realpath "$expected_out_location")"
plagiarism_ids="$(realpath "$plagiarism_ids")"

expected_lines=11

if [[ ${#input[@]} -ne $expected_lines ]]; then
    echo "Error: The input file does not have the correct number of lines."
    exit 1
fi

if [[ "$archive_status" != "true" && "$archive_status" != "false" ]]; then
    echo "Error: Line 1 must be 'true' or 'false'."
    exit 1
fi

for format in $allowed_format; do
    if [[ "$format" != "zip" && "$format" != "rar" && "$format" != "tar" ]]; then
        echo "Error: Line 2 must specify allowed archive formats like 'zip rar tar'."
        exit 1
    fi
done

for format in $allowed_language; do
    if [[ "$format" != "c" && "$format" != "cpp" && "$format" != "python" && "$format" != "sh" ]]; then
        echo "Error: Line 3 must specify allowed programming languages like 'c cpp python sh'."
        exit 1
    fi
done

if ! echo "$mark" | grep -qE '^[0-9]+$'; then
    echo "Error: Line 4 must be a number representing total marks."
    exit 1
fi

if ! echo "$penalty_for_unmatched" | grep -qE '^[0-9]+$'; then
    echo "Error: Line 5 must be a number representing penalty for unmatched output."
    exit 1
fi

if [[ ! -d "$working_directory" ]]; then
    echo "Error: Line 6 must be a valid directory path."
    exit 1
fi

if ! echo "$student_id_range" | grep -qE '^[0-9]+\ [0-9]+$'; then
    echo "Error: Line 7 must specify a valid student ID range like '2005001 2005121'."
    exit 1
fi

if [[ ! -f "$expected_out_location" ]]; then
    echo "Error: Line 8 must be a valid file path for the expected output."
    exit 1
fi

if ! echo "$penalty_for_violation" | grep -qE '^[0-9]+$'; then
    echo "Error: Line 9 must be a number representing penalty for submission guideline violations."
    exit 1
fi

if [[ ! -f "$plagiarism_ids" ]]; then
    echo "Error: Line 10 must be a valid file path for the plagiarism analysis file."
    exit 1
fi

if ! echo "$penalty_for_plagiarism" | grep -qE '^[0-9]+$'; then
    echo "Error: Line 11 must be a percentage representing plagiarism penalty like '100%'."
    exit 1
fi

if [ -d /home/issues ]; then
    rm -rf /home/issues/*
else
    mkdir -p /home/issues
fi

if [ -d /home/checked ]; then
    rm -rf /home/checked/*
else
    mkdir -p /home/checked
fi

declare -A marks
declare -A deductions
declare -A remarks
declare -A final_marks

compare_output() {
    local student_output="$1"
    local expected_output="$2"

    mapfile -t expected_lines < <(awk '{$1=$1};1' "$expected_output" | tr -d '\r')
    mapfile -t student_lines < <(awk '{$1=$1};1' "$student_output" | tr -d '\r')

    missing_count=0

    for expected_line in "${expected_lines[@]}"; do
        if ! printf '%s\n' "${student_lines[@]}" | grep -Fxq "$expected_line"; then
            missing_count=$((missing_count + 1))
        fi
    done

    echo "$missing_count"
}

unarchive_file() {
    local file="$1"
    local extension="$2"
    local destination="$working_directory"

    case "$extension" in
        "zip") unzip "$file" -d "$destination" ;;
        "rar") unrar x "$file" "$destination" ;;
        "tar") tar -xf "$file" -C "$destination" ;; 
    esac

    local extracted_folder_path=$(find "$destination" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    echo "$extracted_folder_path"
}


is_allowed_language() {
    local extension="$1"
    local allowed_languages="$2"
    local al=false
    for format in $allowed_languages; do
        if [[ "$format" == "python" ]]; then
            format="py"
        fi
        if [[ "$extension" == "$format" ]]; then
            al=true
            break
        fi
    done

    echo "$al"
}

is_plagiarized() {
    local studentID="$1"
    local plagiarism_file="$2"
    
    mapfile -t lines < <(awk '{$1=$1};1' "$plagiarism_file" | tr -d '\r')
    num_lines=${#lines[@]}

    status=false
    for ((i = 0; i < num_lines; i++)); do
        line=$(echo "${lines[i]}" | awk '{$1=$1};1')  
        if [[ "$line" == "$studentID" ]]; then
            status=true
            break
        fi
    done

    echo "$status"
}

create_marks_report() {
    local marks_csv="/home/marks.csv"
    echo "id,marks,marks_deducted,total_marks,remarks" > "$marks_csv"
    for ((id = startID; id <= endID; id++)); do
        echo "$id,${marks["$id"]},${deductions["$id"]},${final_marks["$id"]},${remarks["$id"]}" >> "$marks_csv"
    done
}


run_student_program() {
    local studentID="$1"
    local file_path="$2"
    local fl="${file_path##*.}"
    local output_file="$working_directory/$studentID/${studentID}_output.txt"

    touch "$output_file"

    if [[ "$fl" == "sh" ]]; then
        # sudo apt-get install dos2unix
        dos2unix "$file_path"
    fi

    case "$fl" in
        py)  python3 "$file_path" >> "$output_file" 2>&1 ;;
        c)   
            gcc "$file_path" -o "$working_directory/$studentID/program" &&
            "$working_directory/$studentID/program" >> "$output_file" 2>&1 ;;
        cpp) 
            g++ "$file_path" -o "$working_directory/$studentID/program" &&
            "$working_directory/$studentID/program" >> "$output_file" 2>&1 ;;
        sh)  
            bash "$file_path" >> "$output_file" 2>&1 ;;
        *)  
            echo "Unknown file extension."
            ;;
    esac
}

for ((id = startID; id <= endID; id++)); do

    marks["$id"]="$mark"
    deductions["$id"]=0
    remarks["$id"]=""
    final_marks["$id"]=0

    folder=$(find "$working_directory" -maxdepth 1 \( -type f -o -type d \) \( -name "$id.*" -o -name "$id" \) | head -n 1)
    folderName=""

    if [[ -n "$folder" ]]; then
        folderName=$(basename "$folder") 
    fi

    studentID="${folderName%%.*}"
    extension="${folderName##*.}"

    if [[ "$studentID" == "" ]]; then
        marks["$id"]=0
        deductions["$id"]=0
        remarks["$id"]="missing submission"
        final_marks["$id"]=0
        continue
    fi

    if [[ "$archive_status" == "true" ]]; then
        if [[ "$extension" == "zip" || "$extension" == "rar" || "$extension" == "tar" ]]; then

            extracted_folder_path=$(unarchive_file "$folder" "$extension")
            extracted_folder_name=$(basename "$extracted_folder_path")

            allowed=false
            for format in $allowed_format; do
                if [[ "$extension" == "$format" ]]; then
                    allowed=true
                    break
                fi
            done
            if [[ "$allowed" == false ]]; then
                deductions["$studentID"]=$((deductions["$studentID"] + penalty_for_violation))
                marks["$studentID"]=0
                final_marks["$studentID"]=$((-deductions["$studentID"]))
                remarks["$studentID"]="${remarks["$studentID"]} issue case #2;"
                mv "$extracted_folder_path" "/home/issues"
                continue
            fi
            
            if [[ "$extracted_folder_name" != "$studentID" ]]; then
                deductions["$studentID"]=$((deductions["$studentID"] + penalty_for_violation))
                remarks["$studentID"]="${remarks["$studentID"]} issue case #4;"
            fi

        elif [[ "$folderName" != "$studentID" ]]; then
            mkdir -p "$working_directory/$studentID"
            mv "$folder" "$working_directory/$studentID"
        else
            deductions["$studentID"]=$((deductions["$studentID"] + penalty_for_violation))
            remarks["$studentID"]="${remarks["$studentID"]} issue case #1;"
        fi
    else
        if [[ "$extension" == "zip" || "$extension" == "rar" || "$extension" == "tar" ]]; then
            marks["$id"]=0
            deductions["$id"]=0
            remarks["$id"]="missing submission"
            final_marks["$id"]=0
            continue
        fi
        if [[ "$folderName" != "$studentID" ]]; then
            mkdir -p "$working_directory/$studentID"
            mv "$folder" "$working_directory/$studentID"
        fi
    fi

    file_name=$(find "$working_directory/$studentID" -maxdepth 1 -type f -print -quit | xargs basename)
    bName="${file_name%%.*}"
    ext="${file_name##*.}"

    if ((bName < startID || bName > endID)); then
        continue
    fi

    allowed_lan=$(is_allowed_language "$ext" "$allowed_language")
    if [[ "$allowed_lan" == true ]]; then
        run_student_program "$studentID" "$working_directory/$studentID/$file_name"
    else 
        deductions["$studentID"]=$((deductions["$studentID"] + penalty_for_violation))
        marks["$studentID"]=0
        final_marks["$studentID"]=$((-deductions["$studentID"]))
        remarks["$studentID"]="${remarks["$studentID"]} issue case #3;"
        mv "$working_directory/$studentID" "/home/issues"
        continue
    fi

    error_count=$(compare_output "$working_directory/$studentID/${studentID}_output.txt" "$expected_out_location")
    penalty=$((error_count * penalty_for_unmatched))
    # deductions["$studentID"]=$((deductions["$studentID"] + penalty))
    # remarks["$studentID"]="${remarks["$studentID"]} unmatched output;"  

    evaluated_mark=$(($mark - penalty))
    marks["$studentID"]="$evaluated_mark"
    final_marks["$studentID"]=$(($evaluated_mark - deductions["$studentID"]))

    p_status=$(is_plagiarized "$studentID" "$plagiarism_ids")

    if [[ "$p_status" == true ]]; then
        # deductions["$studentID"]=$((deductions["$studentID"] + penalty_for_plagiarism))
        final_marks["$studentID"]=$((-penalty_for_plagiarism))
        remarks["$studentID"]="${remarks["$studentID"]} plagiarism detected;"
    fi
    
    mv "$working_directory/$studentID" "/home/checked"
    
done

create_marks_report