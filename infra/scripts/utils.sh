command_exists() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ $1 not found"
    exit 1
  fi
}

nc_check() {
  local host="$1"
  local port="$2"

  # Detect platform and use appropriate nc syntax
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: use -G flag for 2-second timeout
    nc -z -G2 -w2 "$host" "$port"
    return $?
  else
    # Linux: use timeout command if available, otherwise basic nc
    if command -v timeout >/dev/null 2>&1; then
      timeout 2 nc -z -w2 "$host" "$port"
      return $?
    fi
    # Fallback: basic nc (may hang on some systems)
    nc -z -w2 "$host" "$port"
    return $?
  fi
}
