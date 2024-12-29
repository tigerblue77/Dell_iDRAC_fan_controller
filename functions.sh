# Define global functions
# This function applies Dell's default dynamic fan control profile
function apply_Dell_fan_control_profile() {
  # Use ipmitool to send the raw command to set fan control to Dell default
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x01 0x01 > /dev/null
  CURRENT_FAN_CONTROL_PROFILE="Dell default dynamic fan control profile"
}

# Apply user-defined fan control settings
#
# This function applies user-defined fan control settings based on the specified mode and fan speed.
# It handles both decimal and hexadecimal fan speed inputs, converting between them as needed.
# The function then applies the fan control and updates the current fan control profile.
#
# Parameters:
#   $1 (FAN_CONTROL_PROFILE): The fan control mode.
#                             1 for static fan speed, 2 for dynamic (interpolated) fan control.
#   $2 (LOCAL_FAN_SPEED): The desired fan speed. Can be in decimal (0-100) or hexadecimal (0x00-0x64) format.
#
# Global variables used:
#   CURRENT_FAN_CONTROL_PROFILE: Updated with the current fan control profile description.
#
# Returns:
#   None. In case of an invalid mode, it calls graceful_exit().
function apply_user_fan_control_profile() {
  local FAN_CONTROL_PROFILE=$1
  local LOCAL_FAN_SPEED=$2
  # TODO Tigerblue77 : change in apply_fan_control_profile and include Dell default fan control profile as case 3 ?
  # TODO Tigerblue77 : add column % and set comment on profile change (store current_applied_profile as 1 / 2 / 3)
  # TODO Tigerblue77 : check and improve startup graph + show it even if not in interpolated mode
  if [[ $LOCAL_FAN_SPEED == 0x* ]]; then
    local LOCAL_DECIMAL_FAN_SPEED=$(convert_hexadecimal_value_to_decimal "$LOCAL_FAN_SPEED")
    local LOCAL_HEXADECIMAL_FAN_SPEED=$LOCAL_FAN_SPEED
  else
    local LOCAL_DECIMAL_FAN_SPEED=$LOCAL_FAN_SPEED
    local LOCAL_HEXADECIMAL_FAN_SPEED=$(convert_decimal_value_to_hexadecimal "$LOCAL_FAN_SPEED")
  fi

  case $FAN_CONTROL_PROFILE in
    1)
      set_fans_speed "$LOCAL_HEXADECIMAL_FAN_SPEED"
      CURRENT_FAN_CONTROL_PROFILE="User static fan control profile ($LOCAL_DECIMAL_FAN_SPEED%)"
      ;;
    2)
      set_fans_speed "$LOCAL_HEXADECIMAL_FAN_SPEED"
      CURRENT_FAN_CONTROL_PROFILE="Interpolated fan control profile ($LOCAL_DECIMAL_FAN_SPEED%)"
      ;;
    *)
      echo "Invalid mode selected. Please use 1 for static fan speed or 2 for dynamic fan control."
      graceful_exit
      ;;
  esac
}

# Set fans speed to a specified value
#
# This function sets the fan speed to a user-specified value using ipmitool.
# It first checks if the input value is in hexadecimal format, and converts it
# if necessary. Then it sends raw commands to iDRAC to set the fan control.
#
# Parameters:
#   $1 (VALUE): The desired fan speed value. Can be in decimal or hexadecimal format.
#               If in decimal, it will be converted to hexadecimal.
#
# Returns:
#   None
#
# Note:
#   This function uses the global variable $IDRAC_LOGIN_STRING for iDRAC login.
function set_fans_speed() {
  local FAN_SPEED_TO_APPLY=$1

  # Check if the input value is a hexadecimal number, if not, convert it to hexadecimal
  if [[ $FAN_SPEED_TO_APPLY != 0x* ]]; then
      FAN_SPEED_TO_APPLY=$(convert_decimal_value_to_hexadecimal "$FAN_SPEED_TO_APPLY")
  fi

  # Use ipmitool to send the raw command to set fan control to user-specified value
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x01 0x00 > /dev/null
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x02 0xff "$FAN_SPEED_TO_APPLY" > /dev/null
}

# Convert first parameter given ($DECIMAL_NUMBER) to hexadecimal
# Usage : convert_decimal_value_to_hexadecimal "$DECIMAL_NUMBER"
# Returns : hexadecimal value of DECIMAL_NUMBER
function convert_decimal_value_to_hexadecimal() {
  local DECIMAL_NUMBER=$1
  local HEXADECIMAL_NUMBER=$(printf '0x%02x' $DECIMAL_NUMBER)
  echo $HEXADECIMAL_NUMBER
}

# Convert first parameter given ($HEXADECIMAL_NUMBER) to decimal
# Usage : convert_hexadecimal_value_to_decimal "$HEXADECIMAL_NUMBER"
# Returns : decimal value of HEXADECIMAL_NUMBER
function convert_hexadecimal_value_to_decimal() {
  local HEXADECIMAL_NUMBER=$1
  local DECIMAL_NUMBER=$(printf '%d' $HEXADECIMAL_NUMBER)
  echo $DECIMAL_NUMBER
}

# Retrieve temperature sensors data using ipmitool
# Usage : retrieve_temperatures "$IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT" "$IS_CPU2_TEMPERATURE_SENSOR_PRESENT"
function retrieve_temperatures() {
  if (( $# != 2 )); then
    printf "Illegal number of parameters.\nUsage: retrieve_temperatures \$IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT \$IS_CPU2_TEMPERATURE_SENSOR_PRESENT" >&2
    return 1
  fi
  local IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=$1
  local IS_CPU2_TEMPERATURE_SENSOR_PRESENT=$2

  local DATA=$(ipmitool -I $IDRAC_LOGIN_STRING sdr type temperature | grep degrees)

  # Parse CPU data
  local CPU_DATA=$(echo "$DATA" | grep "3\." | grep -Po '\d{2}')
  CPU1_TEMPERATURE=$(echo $CPU_DATA | awk "{print \$$CPU1_TEMPERATURE_INDEX;}")
  if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT; then
    CPU2_TEMPERATURE=$(echo $CPU_DATA | awk "{print \$$CPU2_TEMPERATURE_INDEX;}")
  else
    CPU2_TEMPERATURE="-"
  fi

  # Parse inlet temperature data
  INLET_TEMPERATURE=$(echo "$DATA" | grep Inlet | grep -Po '\d{2}' | tail -1)

  # If exhaust temperature sensor is present, parse its temperature data
  if $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT; then
    EXHAUST_TEMPERATURE=$(echo "$DATA" | grep Exhaust | grep -Po '\d{2}' | tail -1)
  else
    EXHAUST_TEMPERATURE="-"
  fi
}

# /!\ Use this function only for Gen 13 and older generation servers /!\
function enable_third_party_PCIe_card_Dell_default_cooling_response() {
  # We could check the current cooling response before applying but it's not very useful so let's skip the test and apply directly
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x00 0x00 0x00 > /dev/null
}

# /!\ Use this function only for Gen 13 and older generation servers /!\
function disable_third_party_PCIe_card_Dell_default_cooling_response() {
  # We could check the current cooling response before applying but it's not very useful so let's skip the test and apply directly
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x01 0x00 0x00 > /dev/null
}

# Returns :
# - 0 if third-party PCIe card Dell default cooling response is currently DISABLED
# - 1 if third-party PCIe card Dell default cooling response is currently ENABLED
# - 2 if the current status returned by ipmitool command output is unexpected
# function is_third_party_PCIe_card_Dell_default_cooling_response_disabled() {
#   THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE=$(ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x01 0x16 0x05 0x00 0x00 0x00)

#   if [ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 01 00 00" ]; then
#     return 0
#   elif [ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 00 00 00" ]; then
#     return 1
#   else
#     echo "Unexpected output: $THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" >&2
#     return 2
#   fi
# }

# Prepare traps in case of container exit
function graceful_exit() {
  echo "Gracefully exiting as requested..."
  apply_Dell_fan_control_profile

  # Reset third-party PCIe card cooling response to Dell default depending on the user's choice at startup
  if ! $KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT; then
    enable_third_party_PCIe_card_Dell_default_cooling_response
  fi

  echo "/!\ WARNING /!\ Container stopped, Dell default dynamic fan control profile applied for safety."
  exit 0
}

# Helps debugging when people are posting their output
function get_Dell_server_model() {
  IPMI_FRU_content=$(ipmitool -I $IDRAC_LOGIN_STRING fru 2>/dev/null) # FRU stands for "Field Replaceable Unit"

  SERVER_MANUFACTURER=$(echo "$IPMI_FRU_content" | grep "Product Manufacturer" | awk -F ': ' '{print $2}')
  SERVER_MODEL=$(echo "$IPMI_FRU_content" | grep "Product Name" | awk -F ': ' '{print $2}')

  # Check if SERVER_MANUFACTURER is empty, if yes, assign value based on "Board Mfg"
  if [ -z "$SERVER_MANUFACTURER" ]; then
    SERVER_MANUFACTURER=$(echo "$IPMI_FRU_content" | tr -s ' ' | grep "Board Mfg :" | awk -F ': ' '{print $2}')
  fi

  # Check if SERVER_MODEL is empty, if yes, assign value based on "Board Product"
  if [ -z "$SERVER_MODEL" ]; then
    SERVER_MODEL=$(echo "$IPMI_FRU_content" | tr -s ' ' | grep "Board Product :" | awk -F ': ' '{print $2}')
  fi
}

# Print interpolated fan speeds for a range of CPU temperatures
#
# This function generates 10 CPU temperatures between the lower and upper thresholds,
# calculates the corresponding fan speeds using the calculate_interpolated_fan_speed function,
# and displays the results.
#
# Parameters:
#   $1 (CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION): The lower temperature threshold
#   $2 (CPU_TEMPERATURE_THRESHOLD): The upper temperature threshold
#   $3 (LOCAL_DECIMAL_FAN_SPEED): The base fan speed (as a decimal percentage)
#   $4 (LOCAL_DECIMAL_HIGH_FAN_SPEED): The maximum fan speed (as a decimal percentage)
#
# Returns:
#   None (prints the results to stdout)
print_interpolated_fan_speeds() {
  local CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION=$1
  local CPU_TEMPERATURE_THRESHOLD=$2
  local LOCAL_DECIMAL_FAN_SPEED=$3
  local LOCAL_DECIMAL_HIGH_FAN_SPEED=$4

  echo -e "\e[1mInterpolated Fan Speeds Chart\e[0m"
  echo "=================================================================="

  local temperature_range=$((CPU_TEMPERATURE_THRESHOLD - CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION))
  local step=$((temperature_range / 9))
  local chart_width=50

  # Calculate color thresholds
  local green_threshold=$((CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION + temperature_range * 80 / 100))
  local yellow_threshold=$((CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION + temperature_range * 90 / 100))

  # Print column names
  printf " Temp | Fan  | %-${chart_width}s\n" "Speed"
  printf "======+======+"
  printf '%0.s=' $(seq 1 $((chart_width + 2)))
  printf "\n"

  # Print the chart
  for i in {0..9}; do
    local temp
    if [ $i -eq 9 ]; then
      temp=$CPU_TEMPERATURE_THRESHOLD
    else
      temp=$((CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION + i * step))
    fi
    local fan_speed
    fan_speed=$(calculate_interpolated_fan_speed "$temp" "$CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION" "$CPU_TEMPERATURE_THRESHOLD" "$LOCAL_DECIMAL_FAN_SPEED" "$LOCAL_DECIMAL_HIGH_FAN_SPEED")
    local bar_length=$((fan_speed * chart_width / 100))
    local empty_length=$((chart_width - bar_length))

    # Calculate color based on temperature
    if [ "$temp" -lt "$green_threshold" ]; then
      color="\e[32m"  # Green
    elif [ "$temp" -lt "$yellow_threshold" ]; then
      color="\e[33m"  # Yellow
    else
      color="\e[31m"  # Red
    fi

    printf "%3d°C | %3d%% | ${color}%-${bar_length}s%-${empty_length}s\e[0m|\n" "$temp" "$fan_speed" "$(printf '%0.s█' $(seq 1 "$bar_length"))" "$(printf '%0.s ' $(seq 1 "$empty_length"))"
  done

  echo
  echo -e "\e[1mLower Threshold:\e[0m ${CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION}°C"
  echo -e "\e[1mUpper Threshold:\e[0m ${CPU_TEMPERATURE_THRESHOLD}°C"
  echo -e "\e[1mBase Fan Speed:\e[0m ${LOCAL_DECIMAL_FAN_SPEED}%"
  echo -e "\e[1mMax Fan Speed:\e[0m ${LOCAL_DECIMAL_HIGH_FAN_SPEED}%"
  echo -e "\e[1mColor Thresholds:\e[0m"
  echo -e "  \e[32mGreen:\e[0m  < ${green_threshold}°C"
  echo -e "  \e[33mYellow:\e[0m ${green_threshold}°C - ${yellow_threshold}°C"
  echo -e "  \e[31mRed:\e[0m    > ${yellow_threshold}°C"
}

# Returns the maximum value among the given integer arguments.
# Usage: max <integer1> <integer2> ... <integerN>
function max() {
  local highest_temp=$1
  shift # Moves the arguments, the first one is now deleted

  for temp in "$@"; do # Iterates over the remaining arguments
    if [ "$temp" -gt "$highest_temp" ]; then
      highest_temp="$temp"
    fi
  done
  echo $highest_temp
}

# Define functions to check if CPU 1 and CPU 2 temperatures are above the threshold
function CPU1_HEATING() { [ $CPU1_TEMPERATURE -gt $CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION ]; }
function CPU1_OVERHEATING() { [ $CPU1_TEMPERATURE -gt $CPU_TEMPERATURE_THRESHOLD ]; }
function CPU2_HEATING() { [ $CPU2_TEMPERATURE -gt $CPU_TEMPERATURE_THRESHOLD_FOR_FAN_SPEED_INTERPOLATION ]; }
function CPU2_OVERHEATING() { [ $CPU2_TEMPERATURE -gt $CPU_TEMPERATURE_THRESHOLD ]; }
