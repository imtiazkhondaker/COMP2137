#!/usr/bin/env bash
set -euo pipefail

# ----- config -----
declare -A GROUP_USERS=(
  [brews]="coors stella michelob guiness"
  [trees]="oak pine cherry willow maple walnut ash apple"
  [cars]="chrysler toyota dodge chevrolet pontiac ford suzuki pontiac hyundai cadillac jaguar"
  [staff]="bill tim marilyn kevin george"
  [admins]="bob rob brian dennis dennis"
)

SHARE_BASES=(brews trees cars staff admins)
PASSWORD_LOG="/root/new_user_passwords.tsv"

# Password generator (matches your instructor’s suggestion)
genpw() { dd if=/dev/random count=1 status=none | base64 | dd bs=16 count=1 status=none; }

# Require root
if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo: sudo bash $0" >&2
  exit 1
fi

echo "Writing passwords to $PASSWORD_LOG"
: > "$PASSWORD_LOG"
chmod 600 "$PASSWORD_LOG"

# 1) Groups
echo "==> Creating groups"
for g in "${!GROUP_USERS[@]}"; do
  if ! getent group "$g" >/dev/null; then
    groupadd "$g"
    echo "  created group: $g"
  else
    echo "  group exists: $g"
  fi
done

# 2) Shared directories (owned by root:<group>, perms 2770)
echo "==> Creating shared directories"
for d in "${SHARE_BASES[@]}"; do
  dir="/$d"
  mkdir -p "$dir"
  chown root:"$d" "$dir"
  chmod 2770 "$dir"   # rwx for owner+group, SGID bit keeps group inheritance
  echo "  ensured $dir (root:$d, mode 2770)"
done

# 3) Users per group
echo "==> Creating users"
for g in "${!GROUP_USERS[@]}"; do
  for u in ${GROUP_USERS[$g]}; do
    if id -u "$u" >/dev/null 2>&1; then
      echo "  user exists: $u (group $g) - skipping create"
      # still ensure home perms are tight
      [[ -d /home/$u ]] && chmod 700 "/home/$u" || true
      continue
    fi
    pw="$(genpw)"
    useradd -m -s /bin/bash -g "$g" "$u"
    echo "$u:$pw" | chpasswd
    # owner-only perms on home
    chmod 700 "/home/$u"
    printf "%-15s  %s\n" "$u" "$pw" >> "$PASSWORD_LOG"
    echo "  created user: $u  (primary group: $g)"
  done
done

# 4) Dennis: sudo + member of all groups
echo "==> Ensuring 'dennis' is in sudo and all groups"
# Create dennis if missing (rare if above created him)
if ! id -u dennis >/dev/null 2>&1; then
  pw="$(genpw)"
  useradd -m -s /bin/bash -g admins dennis
  echo "dennis:$pw" | chpasswd
  chmod 700 /home/dennis
  printf "%-15s  %s\n" "dennis" "$pw" >> "$PASSWORD_LOG"
  echo "  created user: dennis"
fi
# Collect all group names:
all_groups=$(printf "%s " "${!GROUP_USERS[@]}")
# Add dennis to sudo and all those groups
usermod -aG sudo,$(echo "$all_groups" | tr ' ' ',') dennis
echo "  added dennis to: sudo and ${all_groups}"

echo "==> Done."
echo "Passwords saved to: $PASSWORD_LOG  (keep this file safe!)"
