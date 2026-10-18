#!/bin/bash

INVENTORY_FILE="inventory.ini"
SSH_USER="ubuntu"
KEY_FILE="~/.ssh/DEV-PEM-KP.pem"

set -o errexit
set -o nounset
set -o pipefail

# Query the Name tag and public IP for every running instance.
INSTANCE_DATA=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value | [0], PublicIpAddress]" \
  --output text)

declare -a DEV_IPS=()
declare -a PRD_IPS=()

while IFS=$'\t' read -r INSTANCE_NAME PUBLIC_IP; do
  [[ -z "${INSTANCE_NAME}" || "${INSTANCE_NAME}" == "None" ]] && continue
  [[ -z "${PUBLIC_IP}" || "${PUBLIC_IP}" == "None" ]] && continue

  case "${INSTANCE_NAME}" in
    DEV*)
      DEV_IPS+=("${PUBLIC_IP}")
      ;;
    PROD*)
      PRD_IPS+=("${PUBLIC_IP}")
      ;;
    *)
      echo "Skipping instance with unsupported Name tag: ${INSTANCE_NAME}" >&2
      ;;
  esac
done <<< "${INSTANCE_DATA}"

if (( ${#DEV_IPS[@]} == 0 && ${#PRD_IPS[@]} == 0 )); then
  echo "Error: No running DEV or PROD instances with public IPs were found." >&2
  exit 1
fi

{
  echo "[dev-webservers]"
  printf '%s\n' "${DEV_IPS[@]}"
  echo

  echo "[prd-webservers]"
  printf '%s\n' "${PRD_IPS[@]}"
  echo

  echo "[dev:children]"
  echo "dev-webservers"
  echo

  echo "[prd:children]"
  echo "prd-webservers"
  echo

  echo "[dev:vars]"
  echo "ansible_user=${SSH_USER}"
  echo "ansible_ssh_private_key_file=${KEY_FILE}"
  echo

  echo "[prd:vars]"
  echo "ansible_user=${SSH_USER}"
  echo "ansible_ssh_private_key_file=${KEY_FILE}"
} > "${INVENTORY_FILE}"

echo "Successfully written to ${INVENTORY_FILE}:"
cat "${INVENTORY_FILE}"