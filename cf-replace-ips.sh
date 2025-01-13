#!/bin/bash

# Set default values for Cloudflare credentials
DEFAULT_EMAIL=""
DEFAULT_ZONE_ID=""
DEFAULT_API_KEY=""

# Set default values for A record modification
DEFAULT_SUBDOMAIN=""
DEFAULT_CSV_PATH=""

# Set default configuration file path
CFG_PATH="./config.cfg"
LOG_FILE="./cf-replace-ips.log"

# Load configuration file if it exists
if [ -f "$CFG_PATH" ]; then
  source "$CFG_PATH"
fi

# Function to log messages
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Prompt user for Cloudflare credentials
read -p "Cloudflare email [${DEFAULT_EMAIL}]: " EMAIL
read -p "Cloudflare zone ID [${DEFAULT_ZONE_ID}]: " ZONE_ID
read -p "Cloudflare API key [${DEFAULT_API_KEY}]: " API_KEY

# Use default values if user input is empty
EMAIL="${EMAIL:-$DEFAULT_EMAIL}"
ZONE_ID="${ZONE_ID:-$DEFAULT_ZONE_ID}"
API_KEY="${API_KEY:-$DEFAULT_API_KEY}"

# Validate Cloudflare credentials
if [[ -z "$EMAIL" || -z "$ZONE_ID" || -z "$API_KEY" ]]; then
  echo "Error: Cloudflare credentials are required."
  exit 1
fi

# Prompt user for A record modification details
read -p "Subdomain to modify [${DEFAULT_SUBDOMAIN}]: " SUBDOMAIN
read -p "Path to CSV file containing new IPs [${DEFAULT_CSV_PATH}]: " CSV_PATH

# Use default values if user input is empty
SUBDOMAIN="${SUBDOMAIN:-$DEFAULT_SUBDOMAIN}"
CSV_PATH="${CSV_PATH:-$DEFAULT_CSV_PATH}"

# Validate CSV file path
if [[ ! -f "$CSV_PATH" ]]; then
  echo "Error: CSV file not found at $CSV_PATH"
  exit 1
fi

# Get existing A records for subdomain
RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${SUBDOMAIN}" \
              -H "X-Auth-Email: ${EMAIL}" \
              -H "X-Auth-Key: ${API_KEY}" \
              -H "Content-Type: application/json")

# Check for API errors
if echo "$RECORDS" | jq -e '.success == false' > /dev/null; then
  echo "Error: Failed to retrieve DNS records. $(echo "$RECORDS" | jq -r '.errors[].message')"
  exit 1
fi

# Extract existing record IDs
IDS=$(echo "$RECORDS" | jq -r '.result[].id')

# Backup existing records
echo "$RECORDS" > "${SUBDOMAIN}_backup_$(date +%F).json"
log_message "Backup of existing records saved to ${SUBDOMAIN}_backup_$(date +%F).json"

# Delete existing A records for subdomain
echo -e "\n\nDeleting existing records...\n"
for ID in $IDS; do
  RESPONSE=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${ID}" \
       -H "X-Auth-Email: ${EMAIL}" \
       -H "X-Auth-Key: ${API_KEY}" \
       -H "Content-Type: application/json")
  if echo "$RESPONSE" | jq -e '.success == false' > /dev/null; then
    echo "Error: Failed to delete record $ID. $(echo "$RESPONSE" | jq -r '.errors[].message')"
    log_message "Failed to delete record $ID. $(echo "$RESPONSE" | jq -r '.errors[].message')"
  else
    echo "Deleted record $ID"
    log_message "Deleted record $ID"
  fi
done

# Add new A records for each IP address listed in CSV file
echo -e "\n\nAdding new A Records for listed IPs...\n"
while read -r IP; do
  RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
       -H "X-Auth-Email: ${EMAIL}" \
       -H "X-Auth-Key: ${API_KEY}" \
       -H "Content-Type: application/json" \
       --data "{\"type\":\"A\",\"name\":\"${SUBDOMAIN}\",\"content\":\"${IP}\",\"ttl\":1,\"proxied\":false}")
  if echo "$RESPONSE" | jq -e '.success == false' > /dev/null; then
    echo "Error: Failed to add record for IP $IP. $(echo "$RESPONSE" | jq -r '.errors[].message')"
    log_message "Failed to add record for IP $IP. $(echo "$RESPONSE" | jq -r '.errors[].message')"
  else
    echo "Added record for IP $IP"
    log_message "Added record for IP $IP"
  fi
done < "$CSV_PATH"

# Save user input as default values in configuration file
echo "DEFAULT_EMAIL='${EMAIL}'" > "$CFG_PATH"
echo "DEFAULT_ZONE_ID='${ZONE_ID}'" >> "$CFG_PATH"
echo "DEFAULT_API_KEY='${API_KEY}'" >> "$CFG_PATH"
echo "DEFAULT_SUBDOMAIN='${SUBDOMAIN}'" >> "$CFG_PATH"
echo "DEFAULT_CSV_PATH='${CSV_PATH}'" >> "$CFG_PATH"

log_message "Script execution completed successfully."
echo -e "\nScript execution completed successfully. Logs saved to $LOG_FILE"