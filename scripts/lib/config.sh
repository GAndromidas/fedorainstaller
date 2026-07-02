#!/bin/bash
set -uo pipefail

has_yq() {
    command -v yq &>/dev/null
}

read_yaml_packages() {
    local yaml_file="$1"
    local yaml_path="$2"
    local array_name="$3"

    if ! has_yq; then
        log_error "yq is required for YAML parsing"
        eval "$array_name=()"
        return 1
    fi

    if [ ! -f "$yaml_file" ]; then
        log_error "YAML file not found: $yaml_file"
        eval "$array_name=()"
        return 1
    fi

    local yq_output
    yq_output=$(yq -r "$yaml_path[].name" "$yaml_file" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$yq_output" ]; then
        eval "$array_name=()"
        while IFS= read -r package; do
            [ -z "$package" ] && continue
            eval "$array_name+=(\"$package\")"
        done <<< "$yq_output"
    else
        eval "$array_name=()"
    fi
}

read_yaml_packages_with_desc() {
    local yaml_file="$1"
    local yaml_path="$2"
    local array_name="$3"

    if ! has_yq; then
        log_error "yq is required for YAML parsing"
        eval "$array_name=()"
        return 1
    fi

    if [ ! -f "$yaml_file" ]; then
        log_error "YAML file not found: $yaml_file"
        eval "$array_name=()"
        return 1
    fi

    local yq_output
    yq_output=$(yq -r "$yaml_path[] | [.name, .description] | @tsv" "$yaml_file" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$yq_output" ]; then
        eval "$array_name=()"
        while IFS=$'\t' read -r name desc; do
            [ -z "$name" ] && continue
            eval "$array_name+=(\"$name|$desc\")"
        done <<< "$yq_output"
    else
        eval "$array_name=()"
    fi
}

read_yaml_value() {
    local yaml_file="$1"
    local yaml_path="$2"

    if ! has_yq; then
        log_error "yq is required for YAML parsing"
        return 1
    fi

    if [ ! -f "$yaml_file" ]; then
        log_error "YAML file not found: $yaml_file"
        return 1
    fi

    yq -r "$yaml_path" "$yaml_file" 2>/dev/null
}

yaml_key_exists() {
    local yaml_file="$1"
    local yaml_path="$2"

    if ! has_yq; then
        return 1
    fi

    if [ ! -f "$yaml_file" ]; then
        return 1
    fi

    yq eval "$yaml_path" "$yaml_file" &>/dev/null
}

get_yaml_keys() {
    local yaml_file="$1"
    local yaml_path="$2"

    if ! has_yq; then
        log_error "yq is required for YAML parsing"
        return 1
    fi

    if [ ! -f "$yaml_file" ]; then
        log_error "YAML file not found: $yaml_file"
        return 1
    fi

    yq eval "$yaml_path | keys | .[]" "$yaml_file" 2>/dev/null
}
