#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/envs/dev"
INVENTORY_PATH="${ROOT_DIR}/ansible/inventory/dev.ini"

cd "${TF_DIR}"

BASTION_IP="$(terraform output -raw bastion_public_ip)"

cat > "${INVENTORY_PATH}" <<INI
[ops]
bastion ansible_host=${BASTION_IP} ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/olivesafety-dev-bastion ansible_python_interpreter=/usr/bin/python3
INI

echo "Inventory generated: ${INVENTORY_PATH}"
cat "${INVENTORY_PATH}"
