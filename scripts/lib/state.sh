#!/bin/bash
set -uo pipefail

# ============================================================================
# State library: installation progress tracking, resume, error handling and
# reboot prompts. Writes to $STATE_FILE (~/.fedorainstaller.state).
# ============================================================================

# Validate state file integrity
validate_state_file() {
    if [ ! -f "$STATE_FILE" ]; then
        return 0  # No file is valid
    fi

    # Check if file is readable and not empty
    if [ ! -r "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
        log_warning "State file is corrupted or empty. Starting fresh installation."
        rm -f "$STATE_FILE" 2>/dev/null || true
        return 1
    fi

    return 0
}

# Mark step as completed with atomic write
mark_step_complete() {
    local step_name="$1"

    # Validate step name
    if [ -z "$step_name" ]; then
        log_error "mark_step_complete: step_name cannot be empty"
        return 1
    fi

    # Atomic write with file locking to prevent corruption
    local temp_state_file="$STATE_FILE.tmp.$$"
    (
        flock -x 200
        echo "$step_name" >> "$temp_state_file"
    ) 200>"$temp_state_file" && mv "$temp_state_file" "$STATE_FILE" 2>/dev/null || {
        log_error "Failed to update state file for step: $step_name"
        return 1
    }
}

# Mark step with status (completed/failed)
mark_step_complete_with_progress() {
    local step_name="$1"
    local status="${2:-completed}"

    # Validate step name
    if [ -z "$step_name" ]; then
        log_error "mark_step_complete_with_progress: step_name cannot be empty"
        return 1
    fi

    # Write status to state file with consistent format for parsing
    if [ "$status" = "completed" ]; then
        echo "COMPLETED: $step_name" >> "$STATE_FILE"
    else
        echo "FAILED: $step_name" >> "$STATE_FILE"
    fi
}

# Check if step was completed (checks for "COMPLETED: stepname" format)
is_step_complete() {
    [ -f "$STATE_FILE" ] && grep -q "^COMPLETED: $1$" "$STATE_FILE"
}

# ===== Error handling =====

# Enhanced error handling and cleanup on failure/exit
cleanup_on_error() {
    local exit_code=${1:-$?}
    local error_line=${2:-$LINENO}

    if [ $exit_code -ne 0 ]; then
        # Mark installation as failed
        INSTALLATION_SUCCESS=false

        log_error "Installation failed with exit code $exit_code at line $error_line"
        log_error "Check the log file for details: $INSTALL_LOG"

        # Kill sudo keep-alive if running
        if [ -n "${SUDO_KEEPALIVE_PID+x}" ]; then
            kill $SUDO_KEEPALIVE_PID 2>/dev/null || true
        fi

        # Offer recovery options
        echo ""
        ui_error "Installation encountered an error!"
        ui_info "Options:"
        ui_info "1. Run the script again to resume from where it left off"
        ui_info "2. Check the log file: $INSTALL_LOG"
        ui_info "3. Start fresh installation: rm -f $STATE_FILE"

        # Save error state
        echo "FAILED: Installation failed at line $error_line (exit code: $exit_code)" >> "$STATE_FILE"
    fi
}

# Function to save log on exit
save_log_on_exit() {
    # Kill sudo keep-alive if running
    if [ -n "${SUDO_KEEPALIVE_PID+x}" ]; then
        kill $SUDO_KEEPALIVE_PID 2>/dev/null || true
    fi

    {
        echo ""
        echo "=========================================="
        echo "Installation ended: $(date)"
        echo "=========================================="

        # Add summary if installation completed successfully
        if [ "$INSTALLATION_SUCCESS" = "true" ]; then
            echo "Installation completed successfully!"
            echo "Total installation time: $(($(date +%s) - INSTALLATION_START_TIME)) seconds"
        else
            echo "Installation completed with errors!"
            echo "Check the log above for details."
        fi
    } >> "$INSTALL_LOG"
}

# Delete installer files
delete_fedorainstaller_files() {
    print_info "Cleaning up installer files..."
    [ -d "$HOME/.fedorainstaller" ] && rm -rf "$HOME/.fedorainstaller"
    [ -f "$INSTALL_LOG" ] && rm -f "$INSTALL_LOG"
    [ -f "$STATE_FILE" ] && rm -f "$STATE_FILE"
    print_success "Installer files cleaned up."
}

# Prompt for reboot
prompt_reboot() {
    local errors_present="${1:-0}"
    if [ "$errors_present" = "0" ]; then
        echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${CYAN}🔄 SYSTEM REBOOT${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"

        if command -v figlet >/dev/null; then
            echo -e "${CYAN}"
            figlet "System Reboot"
            echo -e "${RESET}"
        else
            echo -e "${CYAN}========== System Reboot ==========${RESET}"
        fi

        echo -e "${CYAN}Installation completed successfully!${RESET}"
        echo -e "${YELLOW}It's strongly recommended to reboot your system now.\n${RESET}"

        if supports_gum; then
            if gum confirm "Reboot now?" --default=true; then
                reboot_now=true
            else
                reboot_now=false
            fi
        else
            echo -n -e "${YELLOW}Reboot now? [Y/n]: ${RESET}"
            read -r reboot_ans
            reboot_ans=${reboot_ans,,}
            case "$reboot_ans" in
                ""|y|yes) reboot_now=true ;;
                *)        reboot_now=false ;;
            esac
        fi

        if [ "$reboot_now" = true ]; then
            echo -e "\n${CYAN}Rebooting...${RESET}\n"
            delete_fedorainstaller_files
            if command -v figlet >/dev/null; then
                sudo $DNF_CMD remove -y figlet >/dev/null 2>&1
            fi
            sudo reboot
        else
            echo -e "\n${YELLOW}Reboot skipped. You can reboot manually at any time using \`sudo reboot\`.${RESET}\n"
        fi
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
    else
        echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${RED}⚠️  INSTALLATION COMPLETED WITH ERRORS${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        print_warning "Some steps failed. Review the log at $INSTALL_LOG"
        if [ ${#ERRORS[@]} -gt 0 ]; then
            for err in "${ERRORS[@]}"; do
                print_error "$err"
            done
        fi
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
    fi
}

# ===== Resume functionality =====

# Show resume menu with options
show_resume_menu() {
    # Validate state file first
    if ! validate_state_file; then
        return 0
    fi

    if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
        echo ""
        ui_info "Previous installation detected. Checking installation status..."

        local completed_steps=()
        local step_status=()
        local has_failures=false
        local last_completed_step=""

        # Read and parse state file
        while IFS= read -r step; do
            if [[ "$step" =~ ^COMPLETED:\ (.+)$ ]]; then
                local step_name="${BASH_REMATCH[1]}"
                completed_steps+=("$step")
                step_status+=("completed")
                last_completed_step="$step_name"
            elif [[ "$step" =~ ^FAILED:\ (.+)$ ]]; then
                local step_name="${BASH_REMATCH[1]}"
                completed_steps+=("$step")
                step_status+=("failed")
                has_failures=true
            elif [[ "$step" =~ ^FAILED: ]]; then
                # Legacy format
                completed_steps+=("$step")
                step_status+=("failed")
                has_failures=true
            else
                # Legacy format - assume completed
                completed_steps+=("$step")
                step_status+=("completed")
                last_completed_step="$step"
            fi
        done < "$STATE_FILE"

        if [ ${#completed_steps[@]} -eq 0 ]; then
            ui_info "No completed steps found in state file"
            return 0
        fi

        echo ""
        echo -e "${YELLOW}Installation Progress Summary${RESET}"
        echo ""
        for i in "${!completed_steps[@]}"; do
            local step="${completed_steps[$i]}"
            local status="${step_status[$i]}"
            local display_step="${step#*: }"

            case "$status" in
                "completed")
                    echo -e "${GREEN}  [COMPLETED] $display_step${RESET}"
                    ;;
                "failed")
                    echo -e "${RED}  [FAILED] $display_step${RESET}"
                    ;;
            esac
        done
        echo ""

        if supports_gum; then
            if [ "$has_failures" = true ]; then
                if gum confirm --default=true "Found failed steps. Retry failed steps first?"; then
                    ui_info "Will retry failed steps during installation"
                    return 0
                elif gum confirm --default=false "Resume from last completed step?"; then
                    ui_success "Resuming installation from last completed step..."
                    return 0
                else
                    if gum confirm --default=false "Start fresh installation (this will clear previous progress)?"; then
                        rm -f "$STATE_FILE" 2>/dev/null || true
                        ui_info "Starting fresh installation..."
                        return 0
                    else
                        ui_info "Installation cancelled by user"
                        exit 0
                    fi
                fi
            else
                if gum confirm --default=true "Resume installation from where you left off?"; then
                    ui_success "Resuming installation..."
                    return 0
                else
                    if gum confirm --default=false "Start fresh installation (this will clear previous progress)?"; then
                        rm -f "$STATE_FILE" 2>/dev/null || true
                        ui_info "Starting fresh installation..."
                        return 0
                    else
                        ui_info "Installation cancelled by user"
                        exit 0
                    fi
                fi
            fi
        else
            if [ "$has_failures" = true ]; then
                echo "Found failed steps. Options:"
                echo "1. Retry failed steps first"
                echo "2. Resume from last completed step"
                echo "3. Start fresh installation"
                echo "4. Cancel"
                echo ""
                read -r -p "Choose an option (1-4): " choice
                case "$choice" in
                    1)
                        ui_info "Will retry failed steps during installation"
                        return 0
                        ;;
                    2)
                        ui_success "Resuming installation from last completed step..."
                        return 0
                        ;;
                    3)
                        rm -f "$STATE_FILE" 2>/dev/null || true
                        ui_info "Starting fresh installation..."
                        return 0
                        ;;
                    4)
                        ui_info "Installation cancelled by user"
                        exit 0
                        ;;
                    *)
                        ui_warn "Invalid option. Resuming installation..."
                        return 0
                        ;;
                esac
            else
                echo "Resume installation from where you left off? (y/n)"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    ui_success "Resuming installation..."
                    return 0
                else
                    echo "Start fresh installation? (y/n)"
                    read -r fresh_response
                    if [[ "$fresh_response" =~ ^[Yy]$ ]]; then
                        rm -f "$STATE_FILE" 2>/dev/null || true
                        ui_info "Starting fresh installation..."
                        return 0
                    else
                        ui_info "Installation cancelled by user"
                        exit 0
                    fi
                fi
            fi
        fi
    fi
}
