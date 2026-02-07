#!/bin/bash

set -e
declare -A defaults
declare -A config_file
declare -A args
declare -A config
declare -A users
declare -A path
declare -A service
declare -A md5
declare -A regex
declare -A image

config_path="/opt/reality-ezpz"
compose_project='reality-ezpz'
BACKTITLE=RealityEZPZ
MENU="Select an option:"
HEIGHT=30
WIDTH=60
CHOICE_HEIGHT=20

image[sing-box]="ghcr.io/sagernet/sing-box:v1.12.12"
image[nginx]="nginx:1.24.0"
image[certbot]="certbot/certbot:v2.6.0"
image[haproxy]="haproxy:2.8.0"

defaults[transport]=tcp
defaults[domain]=apple.com
defaults[port]=443
defaults[safenet]=OFF
defaults[core]=sing-box
readonly CORE=sing-box
defaults[security]=reality
defaults[server]=$(curl -fsSL --ipv4 https://cloudflare.com/cdn-cgi/trace | grep ip | cut -d '=' -f2)

config_items=(
  "core"
  "security"
  "service_path"
  "public_key"
  "private_key"
  "short_id"
  "transport"
  "domain"
  "server"
  "port"
  "safenet"
)

regex[domain]="^[a-zA-Z0-9]+([-.][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}$"
regex[port]="^[1-9][0-9]*$"
regex[username]="^[a-zA-Z0-9]+$"
regex[ip]="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
regex[domain_port]="^[a-zA-Z0-9]+([-.][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}(:[1-9][0-9]*)?$"
regex[file_path]="^[a-zA-Z0-9_/.-]+$"
regex[url]="^(http|https)://([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|[0-9]{1,3}(\.[0-9]{1,3}){3})(:[0-9]{1,5})?(/.*)?$"

function show_help {
  echo ""
  echo "Usage: singbox.sh [-t|--transport=tcp|http|grpc|ws|tuic|hysteria2|shadowtls] [-d|--domain=<domain>] [--server=<server>]
  [--regenerate] [--default] [-r|--restart] [--enable-safenet=true|false] [--port=<port>]
  [--security=reality|letsencrypt|selfsigned] [-m|--menu] [--show-server-config] [--add-user=<username>] [--list-users]
  [--show-user=<username>] [--delete-user=<username>] [--backup] [--restore=<url|file>] [--backup-password=<password>] [-u|--uninstall]"
  echo ""
  echo "  -t, --transport <tcp|http|grpc|ws|tuic|hysteria2|shadowtls> Transport protocol (tcp, http, grpc, ws, tuic, hysteria2, shadowtls, default: ${defaults[transport]})"
  echo "  -d, --domain <domain>     Domain to use as SNI (default: ${defaults[domain]})"
  echo "      --server <server>     IP address or domain name of server (Must be a valid domain if using letsencrypt security)"
  echo "      --regenerate          Regenerate public and private keys"
  echo "      --default             Restore default configuration"
  echo "  -r  --restart             Restart services"
  echo "  -u, --uninstall           Uninstall reality"
  echo "      --enable-safenet <true|false> Enable or disable safenet (blocking malware and adult content)"
  echo "      --port <port>         Server port (default: ${defaults[port]})"
  echo "      --security <reality|letsencrypt|selfsigned> Select type of TLS encryption (reality, letsencrypt, selfsigned, default: ${defaults[security]})"
  echo "  -m  --menu                Show menu"
  echo "      --show-server-config  Print server configuration"
  echo "      --add-user <username> Add new user"
  echo "      --list-users          List all users"
  echo "      --show-user <username> Shows the config and QR code of the user"
  echo "      --delete-user <username> Delete the user"
  echo "      --backup              Backup users and configuration and upload it to temp.sh"
  echo "      --restore <url|file>  Restore backup from URL or file"
  echo "      --backup-password <password> Create/Restore password protected backup file"
  echo "  -h, --help                Display this help message"
  return 1
}

function parse_args {
  local opts
  opts=$(getopt -o t:d:rumh --long transport:,domain:,server:,regenerate,default,restart,uninstall,enable-safenet:,port:,security:,menu,show-server-config,add-user:,list-users,show-user:,delete-user:,backup,restore:,backup-password:,help -- "$@")
  if [[ $? -ne 0 ]]; then
    return 1
  fi
  eval set -- "$opts"
  while true; do
    case $1 in
      -t|--transport)
        args[transport]="$2"
        case ${args[transport]} in
          tcp|http|grpc|ws|tuic|hysteria2|shadowtls)
            shift 2
            ;;
          *)
            echo "Invalid transport protocol: ${args[transport]}"
            return 1
            ;;
        esac
        ;;
      -d|--domain)
        args[domain]="$2"
        if ! [[ ${args[domain]} =~ ${regex[domain_port]} ]]; then
          echo "Invalid domain: ${args[domain]}"
          return 1
        fi
        shift 2
        ;;
      --server)
        args[server]="$2"
        if ! [[ ${args[server]} =~ ${regex[domain]} || ${args[server]} =~ ${regex[ip]} ]]; then
          echo "Invalid server: ${args[domain]}"
          return 1
        fi
        shift 2
        ;;
      --regenerate)
        args[regenerate]=true
        shift
        ;;
      --default)
        args[default]=true
        shift
        ;;
      -r|--restart)
        args[restart]=true
        shift
        ;;
      -u|--uninstall)
        args[uninstall]=true
        shift
        ;;
      --enable-safenet)
        case "$2" in
          true|false)
            $2 && args[safenet]=ON || args[safenet]=OFF
            shift 2
            ;;
          *)
            echo "Invalid safenet option: $2"
            return 1
            ;;
        esac
        ;;
      --port)
        args[port]="$2"
        if ! [[ ${args[port]} =~ ${regex[port]} ]]; then
          echo "Invalid port number: ${args[port]}"
          return 1
        elif ((args[port] < 1 || args[port] > 65535)); then
          echo "Port number out of range: ${args[port]}"
          return 1
        fi
        shift 2
        ;;
      --security)
        args[security]="$2"
        case ${args[security]} in
          reality|letsencrypt|selfsigned)
            shift 2
            ;;
          *)
            echo "Invalid TLS security option: ${args[security]}"
            return 1
            ;;
        esac
        ;;
      -m|--menu)
        args[menu]=true
        shift
        ;;
      --show-server-config)
        args[server-config]=true
        shift
        ;;
      --add-user)
        args[add_user]="$2"
        if ! [[ ${args[add_user]} =~ ${regex[username]} ]]; then
          echo "Invalid username: ${args[add_user]}\nUsername can only contains A-Z, a-z and 0-9"
          return 1
        fi
        shift 2
        ;;
      --list-users)
        args[list_users]=true
        shift
        ;;
      --show-user)
        args[show_config]="$2"
        shift 2
        ;;
      --delete-user)
        args[delete_user]="$2"
        shift 2
        ;;
      --backup)
        args[backup]=true
        shift
        ;;
      --restore)
        args[restore]="$2"
        if [[ ! ${args[restore]} =~ ${regex[file_path]} ]] && [[ ! ${args[restore]} =~ ${regex[url]} ]]; then
          echo "Invalid: Backup file path or URL is not valid."
          return 1
        fi
        shift 2
        ;;
      --backup-password)
        args[backup_password]="$2"
        shift 2
        ;;
      -h|--help)
        return 1
        ;;
      --)
        shift
        break
        ;;
      *)
        echo "Unknown option: $1"
        return 1
        ;;
    esac
  done

  if [[ ${args[uninstall]} == true ]]; then
    uninstall
  fi
}

function backup {
  local backup_name
  local backup_password="$1"
  local backup_file_url
  local exit_code
  backup_name="reality-ezpz-backup-$(date +%Y-%m-%d_%H-%M-%S).zip"
  cd "${config_path}"
  if [ -z "${backup_password}" ]; then
    zip -r "/tmp/${backup_name}" . > /dev/null
  else
    zip -P "${backup_password}" -r "/tmp/${backup_name}" . > /dev/null
  fi
  if ! backup_file_url=$(curl -fsS -m 30 -F "file=@/tmp/${backup_name}" "https://temp.sh/upload"); then
    rm -f "/tmp/${backup_name}"
    echo "Error in uploading backup file" >&2
    return 1
  fi
  rm -f "/tmp/${backup_name}"
  echo "${backup_file_url}"
}

function restore {
  local backup_file="$1"
  local backup_password="$2"
  local temp_file
  local unzip_output
  local unzip_exit_code
  local current_state
  if [[ ! -r ${backup_file} ]]; then
    temp_file=$(mktemp -u)
    if [[ "${backup_file}" =~ ^https?://temp\.sh/ ]]; then
      if ! curl -fSsL -m 30 -X POST "${backup_file}" -o "${temp_file}"; then
        echo "Cannot download or find backup file" >&2
        return 1
      fi
    else
      if ! curl -fSsL -m 30 "${backup_file}" -o "${temp_file}"; then
        echo "Cannot download or find backup file" >&2
        return 1
      fi
    fi
    backup_file="${temp_file}"
  fi
  current_state=$(set +o)
  set +e
  if [[ -z "${backup_password}" ]]; then
    unzip_output=$(unzip -P "" -t "${backup_file}" 2>&1)
  else
    unzip_output=$(unzip -P "${backup_password}" -t "${backup_file}" 2>&1)
  fi
  unzip_exit_code=$?
  eval "$current_state"
  if [[ ${unzip_exit_code} -eq 0 ]]; then
    if ! echo "${unzip_output}" | grep -q 'config'; then
      echo "The provided file is not a reality-ezpz backup file." >&2
      rm -f "${temp_file}"
      return 1
    fi
  else
    if echo "${unzip_output}" | grep -q 'incorrect password'; then
      echo "The provided password for backup file is incorrect." >&2
    else
      echo "An error occurred during zip file verification: ${unzip_output}" >&2
    fi
    rm -f "${temp_file}"
    return 1
  fi
  rm -rf "${config_path}"
  mkdir -p "${config_path}"
  set +e
  if [[ -z "${backup_password}" ]]; then
    unzip_output=$(unzip -d "${config_path}" "${backup_file}" 2>&1)
  else
    unzip_output=$(unzip -P "${backup_password}" -d "${config_path}" "${backup_file}" 2>&1)
  fi
  unzip_exit_code=$?
  eval "$current_state"
  if [[ ${unzip_exit_code} -ne 0 ]]; then
    echo "Error in backup restore: ${unzip_output}" >&2
    rm -f "${temp_file}"
    return 1
  fi
  rm -f "${temp_file}"
  return
}

function dict_expander {
  local -n dict=$1
  for key in "${!dict[@]}"; do
    echo "${key} ${dict[$key]}"
  done
}

function parse_config_file {
  if [[ ! -r "${path[config]}" ]]; then
    generate_keys
    return 0
  fi
  while IFS= read -r line; do
    if [[ "${line}" =~ ^\s*# ]] || [[ "${line}" =~ ^\s*$ ]]; then
      continue
    fi
    key=$(echo "$line" | cut -d "=" -f 1)
    value=$(echo "$line" | cut -d "=" -f 2-)
    config_file["${key}"]="${value}"
  done < "${path[config]}"
  if [[ -z "${config_file[public_key]}" || \
        -z "${config_file[private_key]}" || \
        -z "${config_file[short_id]}" || \
        -z "${config_file[service_path]}" ]]; then
    generate_keys
  fi
  return 0
}

function parse_users_file {
  mkdir -p "$config_path"
  touch "${path[users]}"
  while read -r line; do
    if [[ "${line}" =~ ^\s*# ]] || [[ "${line}" =~ ^\s*$ ]]; then
      continue
    fi
    IFS="=" read -r key value <<< "${line}"
    users["${key}"]="${value}"
  done < "${path[users]}"
  if [[ -n ${args[add_user]} ]]; then
    if [[ -z "${users["${args[add_user]}"]}" ]]; then
      users["${args[add_user]}"]=$(cat /proc/sys/kernel/random/uuid)
    else
      echo 'User "'"${args[add_user]}"'" already exists.'
    fi
  fi
  if [[ -n ${args[delete_user]} ]]; then
    if [[ -n "${users["${args[delete_user]}"]}" ]]; then
      if [[ ${#users[@]} -eq 1 ]]; then
        echo -e "You cannot delete the only user.\nAt least one user is needed.\nCreate a new user, then delete this one."
        exit 1
      fi
      unset users["${args[delete_user]}"]
    else
      echo "User "${args[delete_user]}" does not exists."
      exit 1
    fi
  fi
  if [[ ${#users[@]} -eq 0 ]]; then
    users[RealityEZPZ]=$(cat /proc/sys/kernel/random/uuid)
    echo "RealityEZPZ=${users[RealityEZPZ]}" >> "${path[users]}"
    return 0
  fi
  return 0
}

function restore_defaults {
  local defaults_items=("${!defaults[@]}")
  for item in "${defaults_items[@]}"; do
    config["${item}"]="${defaults[${item}]}"
  done
}

function build_config {
  local free_80=true
  if [[ ${args[regenerate]} == true ]]; then
    generate_keys
  fi
  for item in "${config_items[@]}"; do
    if [[ -n ${args["${item}"]} ]]; then
      config["${item}"]="${args[${item}]}"
    elif [[ -n ${config_file["${item}"]} ]]; then
      config["${item}"]="${config_file[${item}]}"
    else
      config["${item}"]="${defaults[${item}]}"
    fi
  done
  if [[ ${args[default]} == true ]]; then
    restore_defaults
    return 0
  fi
  if [[ ! ${config[server]} =~ ${regex[domain]} && ${config[security]} == 'letsencrypt' ]]; then
    echo 'You have to assign a domain to server with "--server <domain>" option if you want to use "letsencrypt" as TLS certifcate.'
    exit 1
  fi
  if [[ ${config[transport]} == 'ws' && ${config[security]} == 'reality' ]]; then
    echo 'You cannot use "ws" transport with "reality" TLS certificate. Use other transports or change TLS certifcate to letsencrypt or selfsigned'
    exit 1
  fi
  if [[ ${config[transport]} == 'tuic' && ${config[security]} == 'reality' ]]; then
    echo 'You cannot use "tuic" transport with "reality" TLS certificate. Use other transports or change TLS certifcate to letsencrypt or selfsigned'
    exit 1
  fi

  if [[ ${config[transport]} == 'hysteria2' && ${config[security]} == 'reality' ]]; then
    echo 'You cannot use "hysteria2" transport with "reality" TLS certificate. Use other transports or change TLS certifcate to letsencrypt or selfsigned'
    exit 1
  fi


  if [[ ${config[security]} == 'letsencrypt' && ${config[port]} -ne 443 ]]; then
    if lsof -i :80 >/dev/null 2>&1; then
      free_80=false
      for container in $(${docker_cmd} -p ${compose_project} ps -q); do
        if docker port "${container}"| grep '0.0.0.0:80' >/dev/null 2>&1; then
          free_80=true
          break
        fi
      done
    fi
    if [[ ${free_80} != 'true' ]]; then
      echo 'Port 80 must be free if you want to use "letsencrypt" as the security option.'
      exit 1
    fi
  fi

  if [[ -n "${args[security]}" && "${args[security]}" == 'reality' && "${config_file[security]}" != 'reality' && "${config_file[transport]}" != 'shadowtls' ]]; then
    config[domain]="${defaults[domain]}"
  fi
  if [[ -n "${args[security]}" && "${args[security]}" != 'reality' && "${config_file[security]}" == 'reality' && "${config_file[transport]}" != 'shadowtls' ]]; then
    config[domain]="${config[server]}"
  fi
  
  if [[ -n "${args[transport]}" && "${args[transport]}" == 'shadowtls' && "${config_file[transport]}" != 'shadowtls' && "${config_file[security]}" != 'reality' ]]; then
    config[domain]="${defaults[domain]}"
  fi
  if [[ -n "${args[transport]}" && "${args[transport]}" != 'shadowtls' && "${config_file[transport]}" == 'shadowtls' && "${config_file[security]}" != 'reality' ]]; then
    config[domain]="${config[server]}"
  fi

  if [[ -n "${args[server]}" && "${config[security]}" != 'reality' && "${config[transport]}" != 'shadowtls' ]]; then
    config[domain]="${config[server]}"
  fi
}

function update_config_file {
  mkdir -p "${config_path}"
  touch "${path[config]}"
  for item in "${config_items[@]}"; do
    if grep -q "^${item}=" "${path[config]}"; then
      sed -i "s|^${item}=.*|${item}=${config[${item}]}|" "${path[config]}"
    else
      echo "${item}=${config[${item}]}" >> "${path[config]}"
    fi
  done
  check_reload
}

function update_users_file {
  rm -f "${path[users]}"
  for user in "${!users[@]}"; do
    echo "${user}=${users[${user}]}" >> "${path[users]}"
  done
  check_reload
}

function generate_keys {
  local key_pair
  key_pair=$(docker run --rm ${image[sing-box]} generate reality-keypair)
  config_file[public_key]=$(echo "${key_pair}" | grep 'PublicKey' | awk '{print $2}')
  config_file[private_key]=$(echo "${key_pair}" | grep 'PrivateKey' | awk '{print $2}')
  config_file[short_id]=$(openssl rand -hex 8)
  config_file[service_path]=$(openssl rand -hex 4)
}

function uninstall {
  if docker compose >/dev/null 2>&1; then
    docker compose --project-directory "${config_path}" down --timeout 2 || true
    docker compose --project-directory "${config_path}" -p ${compose_project} down --timeout 2 || true
  elif which docker-compose >/dev/null 2>&1; then
    docker-compose --project-directory "${config_path}" down --timeout 2 || true
    docker-compose --project-directory "${config_path}" -p ${compose_project} down --timeout 2 || true
  fi
  rm -rf "${config_path}"
  echo "Reality-EZPZ uninstalled successfully."
  exit 0
}

function install_packages {
  if ! which qrencode whiptail jq xxd zip unzip >/dev/null 2>&1; then
    if which apt >/dev/null 2>&1; then
      apt update
      DEBIAN_FRONTEND=noninteractive apt install qrencode whiptail jq xxd zip unzip -y
      return 0
    fi
    if which yum >/dev/null 2>&1; then
      yum makecache
      yum install epel-release -y || true
      yum install qrencode newt jq vim-common zip unzip -y
      return 0
    fi
    echo "OS is not supported!"
    return 1
  fi
}

function install_docker {
  if ! which docker >/dev/null 2>&1; then
    curl -fsSL -m 5 https://get.docker.com | bash
    systemctl enable --now docker
    docker_cmd="docker compose"
    return 0
  fi
  if docker compose >/dev/null 2>&1; then
    docker_cmd="docker compose"
    return 0
  fi
  if which docker-compose >/dev/null 2>&1; then
    docker_cmd="docker-compose"
    return 0
  fi
  curl -fsSL -m 30 https://github.com/docker/compose/releases/download/v2.28.0/docker-compose-linux-$(uname -m) -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  docker_cmd="docker-compose"
  return 0
}

function generate_docker_compose {
  cat >"${path[compose]}" <<EOF
networks:
  reality:
    driver: bridge
    enable_ipv6: true
    ipam:
      config:
      - subnet: fc11::1:0/112
services:
  engine:
    image: ${image[${config[core]}]}
    $([[ ${config[security]} == 'reality' || ${config[transport]} == 'shadowtls' ]] && echo "ports:" || true)
    $([[ (${config[security]} == 'reality' || ${config[transport]} == 'shadowtls') && ${config[port]} -eq 443 ]] && echo '- 80:8080' || true)
    $([[ ${config[security]} == 'reality' || ${config[transport]} == 'shadowtls' ]] && echo "- ${config[port]}:8443" || true)
    $([[ ${config[transport]} == 'tuic' || ${config[transport]} == 'hysteria2' ]] && echo "ports:" || true)
    $([[ ${config[transport]} == 'tuic' || ${config[transport]} == 'hysteria2' ]] && echo "- ${config[port]}:8443/udp" || true)
    $([[ ${config[security]} != 'reality' && ${config[transport]} != 'shadowtls' ]] && echo "expose:" || true)
    $([[ ${config[security]} != 'reality' && ${config[transport]} != 'shadowtls' ]] && echo "- 8443" || true)
    restart: always
    environment:
      TZ: Etc/UTC
    volumes:
    - ./${path[engine]#${config_path}/}:/etc/${config[core]}/config.json
    $([[ ${config[security]} != 'reality' ]] && { [[ ${config[transport]} == 'http' ]] || [[ ${config[transport]} == 'tcp' ]] || [[ ${config[transport]} == 'tuic' ]] || [[ ${config[transport]} == 'hysteria2' ]]; } && echo "- ./${path[server_crt]#${config_path}/}:/etc/${config[core]}/server.crt" || true)
    $([[ ${config[security]} != 'reality' ]] && { [[ ${config[transport]} == 'http' ]] || [[ ${config[transport]} == 'tcp' ]] || [[ ${config[transport]} == 'tuic' ]] || [[ ${config[transport]} == 'hysteria2' ]]; } && echo "- ./${path[server_key]#${config_path}/}:/etc/${config[core]}/server.key" || true)
    networks:
    - reality
$(if [[ ${config[security]} != 'reality' && ${config[transport]} != 'shadowtls' ]]; then
echo "
  nginx:
    image: ${image[nginx]}
    expose:
    - 80
    restart: always
    volumes:
    - ./website:/usr/share/nginx/html
    networks:
    - reality
  haproxy:
    image: ${image[haproxy]}
    ports:
    $([[ ${config[security]} == 'letsencrypt' || ${config[port]} -eq 443 ]] && echo '- 80:8080' || true)
    - ${config[port]}:8443
    restart: always
    volumes:
    - ./${path[haproxy]#${config_path}/}:/usr/local/etc/haproxy/haproxy.cfg
    - ./${path[server_pem]#${config_path}/}:/usr/local/etc/haproxy/server.pem
    networks:
    - reality"
fi)
$(if [[ ${config[security]} == 'letsencrypt' && ${config[transport]} != 'shadowtls' ]]; then
echo "
  certbot:
    build:
      context: ./certbot
    expose:
    - 80
    restart: always
    volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - ./certbot/data:/etc/letsencrypt
    - ./$(dirname "${path[server_pem]#${config_path}/}"):/certificate
    - ./${path[certbot_deployhook]#${config_path}/}:/deployhook.sh
    - ./${path[certbot_startup]#${config_path}/}:/startup.sh
    - ./website:/website
    networks:
    - reality
    entrypoint: /bin/sh
    command: /startup.sh"
fi)
EOF
}

function generate_haproxy_config {
echo "
global
  ssl-default-bind-options ssl-min-ver TLSv1.2
defaults
  option http-server-close
  timeout connect 5s
  timeout client 300s
  timeout client-fin 1s
  timeout server-fin 1s
  timeout server 300s
  timeout tunnel 3600s
  timeout http-keep-alive 1s
  timeout queue 15s
frontend http
  mode http
  bind :::8080 v4v6
$(if [[ ${config[security]} == 'letsencrypt' ]]; then echo "
  use_backend certbot if { path_beg /.well-known/acme-challenge }
  acl letsencrypt-acl path_beg /.well-known/acme-challenge
  redirect scheme https if !letsencrypt-acl
"; fi)
  use_backend default
frontend tls
$(if [[ ${config[transport]} != 'tcp' ]]; then echo "
  bind :::8443 v4v6 ssl crt /usr/local/etc/haproxy/server.pem alpn h2,http/1.1
  mode http
  http-request set-header Host ${config[server]}
$(if [[ ${config[security]} == 'letsencrypt' ]]; then echo "
  use_backend certbot if { path_beg /.well-known/acme-challenge }
"; fi)
$(if [[ ${config[transport]} != 'tuic' && ${config[transport]} != 'hysteria2' ]]; then echo "
  use_backend engine if { path_beg /${config[service_path]} }
"; fi)
  use_backend default
"; else echo "
  bind :::8443 v4v6
  mode tcp
  use_backend engine
"; fi)
$(if [[ ${config[transport]} != 'tuic' && ${config[transport]} != 'hysteria2' ]]; then echo "
backend engine
  retry-on conn-failure empty-response response-timeout
$(if [[ ${config[transport]} != 'tcp' ]]; then echo "
  mode http
"; else echo "
  mode tcp
"; fi)
$(if [[ ${config[transport]} == 'grpc' ]]; then echo "
  server engine engine:8443 check tfo proto h2
"; elif [[ ${config[transport]} == 'http' && ${config[core]} == 'sing-box' ]]; then echo "
  server engine engine:8443 check tfo proto h2 ssl verify none
"; elif [[ ${config[transport]} == 'http' && ${config[core]} != 'sing-box' ]]; then echo "
  server engine engine:8443 check tfo ssl verify none
"; else echo "
  server engine engine:8443 check tfo
"; fi)
"; fi)
$(if [[ ${config[security]} == 'letsencrypt' ]]; then echo "
backend certbot
  mode http
  server certbot certbot:80
"; fi)
backend default
  mode http
  server nginx nginx:80
" | grep -vE '^\s*$' > "${path[haproxy]}"
}

function generate_certbot_script {
  cat >"${path[certbot_startup]}" << EOF
#!/bin/sh
trap exit TERM
fullchain_path=/etc/letsencrypt/live/${config[server]}/fullchain.pem
if [[ -r "\${fullchain_path}" ]]; then
  fullchain_fingerprint=\$(openssl x509 -noout -fingerprint -sha256 -in "\${fullchain_path}" 2>/dev/null |\
awk -F= '{print \$2}' | tr -d : | tr '[:upper:]' '[:lower:]')
  installed_fingerprint=\$(openssl x509 -noout -fingerprint -sha256 -in /certificate/server.pem 2>/dev/null |\
awk -F= '{print \$2}' | tr -d : | tr '[:upper:]' '[:lower:]')
  if [[ \$fullchain_fingerprint != \$installed_fingerprint ]]; then
    /deployhook.sh /certificate ${compose_project} ${config[server]} ${service[server_crt]} $([[ ${config[transport]} != 'tcp' ]] && echo "${service[server_pem]}" || true)
  fi
fi
while true; do
  ls -d /website/* | grep -E '^/website/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$'|xargs rm -f
  uuid=\$(uuidgen)
  echo "\$uuid" > "/website/\$uuid"
  response=\$(curl -skL --max-time 3 http://${config[server]}/\$uuid)
  if echo "\$response" | grep \$uuid >/dev/null; then
    break
  fi
  echo "Domain ${config[server]} is not pointing to the server"
  sleep 5
done
ls -d /website/* | grep -E '^/website/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$'|xargs rm -f
while true; do
  certbot certonly -n \\
    --standalone \\
    --key-type ecdsa \\
    --elliptic-curve secp256r1 \\
    --agree-tos \\
    --register-unsafely-without-email \\
    -d ${config[server]} \\
    --deploy-hook "/deployhook.sh /certificate ${compose_project} ${config[server]} ${service[server_crt]} $([[ ${config[transport]} != 'tcp' ]] && echo "${service[server_pem]}" || true)"
  sleep 1h &
  wait \${!}
done
EOF
}

function generate_certbot_deployhook {
  cat >"${path[certbot_deployhook]}" << EOF
#!/bin/sh
cert_path=\$1
compose_project=\$2
domain=\$3
renewed_path=/etc/letsencrypt/live/\$domain
cat "\$renewed_path/fullchain.pem" > "\$cert_path/server.crt"
cat "\$renewed_path/privkey.pem" > "\$cert_path/server.key"
cat "\$renewed_path/fullchain.pem" "\$renewed_path/privkey.pem" > "\$cert_path/server.pem"
i=4
while [ \$i -le \$# ]; do
  eval service=\\\${\$i}
  docker compose -p "${compose_project}" restart --timeout 2 "\$service"
  i=\$((i+1))
done
EOF
  chmod +x "${path[certbot_deployhook]}"
}

function generate_certbot_dockerfile {
  cat >"${path[certbot_dockerfile]}" << EOF
FROM ${image[certbot]}
RUN apk add --no-cache docker-cli-compose curl uuidgen
EOF
}

function generate_selfsigned_certificate {
  openssl ecparam -name prime256v1 -genkey -out "${path[server_key]}"
  openssl req -new -key "${path[server_key]}" -out /tmp/server.csr -subj "/CN=${config[server]}"
  openssl x509 -req -days 365 -in /tmp/server.csr -signkey "${path[server_key]}" -out "${path[server_crt]}"
  cat "${path[server_key]}" "${path[server_crt]}" > "${path[server_pem]}"
  rm -f /tmp/server.csr
}

function generate_engine_config {
  local type
  local users_object=""
  local reality_object=""
  local tls_object=""
  local reality_port=443
  local temp_file
  
  case ${config[transport]} in
    tuic) type='tuic' ;;
    hysteria2) type='hysteria2' ;;
    shadowtls) type='shadowtls' ;;
    *) type='vless' ;;
  esac
  if [[ (${config[security]} == 'reality' || ${config[transport]} == 'shadowtls') && ${config[domain]} =~ ":" ]]; then
    reality_port="${config[domain]#*:}"
  fi
  reality_object='"tls": {
    "enabled": true,
    "server_name": "'"${config[domain]%%:*}"'",
    "alpn": [],
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "'"${config[domain]%%:*}"'",
        "server_port": '"${reality_port}"',
        "tcp_fast_open": true,
        "connect_timeout": "5s"
      },
      "private_key": "'"${config[private_key]}"'",
      "short_id": ["'"${config[short_id]}"'"],
      "max_time_difference": "1m"
    }
  }'
  tls_object='"tls": {
    "enabled": true,
    "certificate_path": "/etc/sing-box/server.crt",
    "key_path": "/etc/sing-box/server.key",
    "alpn": ["h2", "http/1.1"],
    "min_version": "1.2",
    "max_version": "1.3",
    "cipher_suites": [
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
      "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
    ]
  }'
    for user in "${!users[@]}"; do
      if [ -n "$users_object" ]; then
        users_object="${users_object},"$'\n'
      fi
      if [[ ${config[transport]} == 'tuic' ]]; then
        users_object=${users_object}'{"uuid": "'"${users[${user}]}"'", "password": "'"$(echo -n "${user}${users[${user}]}" | sha256sum | cut -d ' ' -f 1 | head -c 16)"'", "name": "'"${user}"'"}'
      elif [[ ${config[transport]} == 'hysteria2' ]]; then
        users_object=${users_object}'{"password": "'"$(echo -n "${user}${users[${user}]}" | sha256sum | cut -d ' ' -f 1 | head -c 16)"'", "name": "'"${user}"'"}'
      elif [[ ${config[transport]} == 'shadowtls' ]]; then
        users_object=${users_object}'{"password": "'"${users[${user}]}"'", "name": "'"${user}"'"}'
      else
        users_object=${users_object}'{"uuid": "'"${users[${user}]}"'", "flow": "'"$([[ ${config[transport]} == 'tcp' ]] && echo 'xtls-rprx-vision' || true)"'", "name": "'"${user}"'"}'
      fi
    done
    cat >"${path[engine]}" <<EOF
{
  "log": {
    "level": "error",
    "timestamp": true
  },
  "ntp": {
    "enabled": true,
    "server": "time.google.com",
    "server_port": 123,
    "interval": "30m"
  },
  "dns": {
    "servers": [
      $([[ ${config[safenet]} == ON ]] && echo '{"type": "tcp", "tag": "dns-main", "server": "1.1.1.3"}' || echo '{"type": "tcp", "tag": "dns-main", "server": "1.1.1.1"}'),
      $([[ ${config[safenet]} == ON ]] && echo '{"type": "tcp", "tag": "dns-fallback", "server": "1.0.0.3"}' || echo '{"type": "tcp", "tag": "dns-fallback", "server": "8.8.8.8"}')
    ],
    "strategy": "prefer_ipv4",
    "independent_cache": true,
    "reverse_mapping": true,
    "cache_capacity": 4096
  },
  "inbounds": [
    {
      "type": "direct",
      "listen": "::",
      "listen_port": 8080,
      "network": "tcp",
      "override_address": "${config[domain]%%:*}",
      "override_port": 80,
      "tcp_fast_open": true,
      "tcp_multi_path": false,
      "udp_fragment": true,
      "udp_timeout": "5m"
    },
    {
      "type": "${type}",
      "tag": "in",
      "listen": "::",
      "listen_port": 8443,
      "tcp_fast_open": true,
      "tcp_multi_path": false,
      "udp_fragment": true,
      "udp_timeout": "5m",
      "users": [${users_object}],
      $(if [[ ${config[security]} == 'reality' && ${config[transport]} != 'shadowtls' ]]; then
        echo "${reality_object}"
      elif [[ ${config[transport]} == 'http' || ${config[transport]} == 'tcp' || ${config[transport]} == 'tuic' || ${config[transport]} == 'hysteria2' ]]; then
        echo "${tls_object}"
      elif [[ ${config[transport]} == 'shadowtls' ]]; then
        :
      else
        echo '"tls":{"enabled": false}'
      fi)
      $(if [[ ${config[transport]} == http ]]; then
      echo ',"multiplex": {"enabled": true, "padding": true}'
      echo ',"transport": {"type": "http", "host": ["'"${config[server]}"'"], "path": "/'"${config[service_path]}"'", "idle_timeout": "30s", "ping_timeout": "15s"}'
      fi
      if [[ ${config[transport]} == grpc ]]; then
      echo ',"multiplex": {"enabled": true, "padding": true}'
      echo ',"transport": {"type": "grpc", "service_name": "'"${config[service_path]}"'", "idle_timeout": "30s", "ping_timeout": "15s"}'
      fi 
      if [[ ${config[transport]} == ws ]]; then
      echo ',"multiplex": {"enabled": true, "padding": true}'
      echo ',"transport": {"type": "ws", "headers": {"Host": "'"${config[server]}"'"}, "path": "/'"${config[service_path]}"'"}'
      fi
      if [[ ${config[transport]} == tuic ]]; then
      echo ',"congestion_control": "bbr", "auth_timeout": "3s", "zero_rtt_handshake": false, "heartbeat": "10s"'
      fi
      if [[ ${config[transport]} == hysteria2 ]]; then
      echo ',"obfs": {"type": "salamander", "password": "'"${config[service_path]}"'"}, "ignore_client_bandwidth": true, "masquerade": "https://'"${config[server]}:${config[port]}"'"'
      fi
      if [[ ${config[transport]} == shadowtls ]]; then
      echo '"version": 3, "strict_mode": true, "detour": "shadowsocks", "handshake": {"server": "'"${config[domain]%%:*}"'", "server_port": '"${reality_port}"'}'
      fi
      )
    }
    $(if [[ ${config[transport]} == 'shadowtls' ]]; then
    echo ', {
      "type": "shadowsocks",
      "tag": "shadowsocks",
      "listen": "127.0.0.1",
      "listen_port": 8444,
      "method": "chacha20-ietf-poly1305",
      "password": "'"${config[private_key]}"'",
      "multiplex": {"enabled": true, "padding": true},
      "users": ['"${users_object}"']
    }'
    fi )
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "internet",
      "tcp_fast_open": true,
      "tcp_multi_path": false,
      "udp_fragment": true,
      "connect_timeout": "5s",
      "domain_resolver": "dns-main"
    }
  ],
  "route": {
    "final": "internet",
    "auto_detect_interface": true,
    "default_domain_resolver": "dns-main",
    "rule_set": [
      {
        "tag": "block",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/aleskxyz/sing-box-rules/refs/heads/rule-set/block.srs",
        "download_detour": "internet"
      },
      {
        "tag": "nsfw",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/aleskxyz/sing-box-rules/refs/heads/rule-set/geosite-nsfw.srs",
        "download_detour": "internet"
      },
      {
        "tag": "geoip-private",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/aleskxyz/sing-box-rules/refs/heads/rule-set/geoip-private.srs",
        "download_detour": "internet"
      },
      {
        "tag": "geosite-private",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/aleskxyz/sing-box-rules/refs/heads/rule-set/geosite-private.srs",
        "download_detour": "internet"
      },
      {
        "tag": "bypass",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/aleskxyz/sing-box-rules/refs/heads/rule-set/bypass.srs",
        "download_detour": "internet"
      }
    ],
    "rules": [
      {
        "inbound": "in",
        "action": "resolve",
        "strategy": "prefer_ipv4"
      },
      {
        "inbound": "in",
        "action": "sniff",
        "timeout": "100ms"
      },
    $(if [[ ${config[transport]} == 'shadowtls' ]]; then
    echo '{
        "inbound": "shadowsocks",
        "action": "resolve",
        "strategy": "prefer_ipv4"
      },
      {
        "inbound": "shadowsocks",
        "action": "sniff",
        "timeout": "300ms"
      },'
    fi )
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "rule_set": [
          "block",
          "geoip-private",
          "geosite-private"
          $([[ ${config[safenet]} == ON ]] && echo ',"nsfw"' || true)
          ,"bypass"
        ],
        "action": "reject"
      },
      {
        "network": "tcp",
        "port": [
          25,
          587,
          465,
          2525
        ],
        "action": "reject"
      },
      {
        "port": 853,
        "action": "reject"
      },
      {
        "network": "udp",
        "port": [
          443,
          3478
        ],
        "action": "reject"
      },
      {
        "protocol": ["bittorrent", "stun"],
        "action": "reject"
      }
    ]
  },
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/etc/sing-box/cache.db",
      "store_fakeip": false,
      "store_rdrc": true,
      "rdrc_timeout": "168h"
    }
  }
}
EOF
  
  if [[ -r ${config_path}/sing-box.patch ]]; then
    if ! jq empty ${config_path}/sing-box.patch; then
      echo "sing-box.patch is not a valid json file. Fix it or remove it!"
      exit 1
    fi
    temp_file=$(mktemp)
    jq -s add ${path[engine]} ${config_path}/sing-box.patch > ${temp_file}
    mv ${temp_file} ${path[engine]}
  fi
}

function generate_config {
  generate_docker_compose
  generate_engine_config
  if [[ ${config[security]} != "reality" && ${config[transport]} != 'shadowtls' ]]; then
    mkdir -p "${config_path}/certificate"
    generate_haproxy_config
    if [[ ! -r "${path[server_pem]}" || ! -r "${path[server_crt]}" || ! -r "${path[server_key]}" ]]; then
      generate_selfsigned_certificate
    fi
  fi
  if [[ ${config[security]} == "letsencrypt" && ${config[transport]} != 'shadowtls' ]]; then
    mkdir -p "${config_path}/certbot"
    generate_certbot_deployhook
    generate_certbot_dockerfile
    generate_certbot_script
  fi
}

function get_ipv6 {
  curl -fsSL -m 3 --ipv6 https://cloudflare.com/cdn-cgi/trace 2> /dev/null | grep ip | cut -d '=' -f2
}

function print_client_configuration {
  local username=$1
  local client_config
  local ipv6
  local client_config_ipv6
  if [[ ${config[transport]} == 'tuic' ]]; then
    client_config="tuic://"
    client_config="${client_config}${users[${username}]}"
    client_config="${client_config}:$(echo -n "${username}${users[${username}]}" | sha256sum | cut -d ' ' -f 1 | head -c 16)"
    client_config="${client_config}@${config[server]}"
    client_config="${client_config}:${config[port]}"
    client_config="${client_config}/?congestion_control=bbr&udp_relay_mode=quic"
    client_config="${client_config}$([[ ${config[security]} == 'selfsigned' ]] && echo "&allow_insecure=1" || true)"
    client_config="${client_config}#${username}"
  elif [[ ${config[transport]} == 'hysteria2' ]]; then
    client_config="hy2://"
    client_config="${client_config}$(echo -n "${username}${users[${username}]}" | sha256sum | cut -d ' ' -f 1 | head -c 16)"
    client_config="${client_config}@${config[server]}"
    client_config="${client_config}:${config[port]}"
    client_config="${client_config}/?obfs=salamander&obfs-password=${config[service_path]}"
    client_config="${client_config}$([[ ${config[security]} == 'selfsigned' ]] && echo "&insecure=1" || true)"
    client_config="${client_config}#${username}"
  elif [[ ${config[transport]} == 'shadowtls' ]]; then
    client_config='{"dns":{"independent_cache":true,"rules":[{"domain":["dns.google"],"server":"dns-direct"}],"servers":[{"address":"https://dns.google/dns-query","address_resolver":"dns-direct","strategy":"ipv4_only","tag":"dns-remote"},{"address":"local","address_resolver":"dns-local","detour":"direct","strategy":"ipv4_only","tag":"dns-direct"},{"address":"local","detour":"direct","tag":"dns-local"},{"address":"rcode://success","tag":"dns-block"}]},"inbounds":[{"listen":"127.0.0.1","listen_port":6450,"override_address":"8.8.8.8","override_port":53,"tag":"dns-in","type":"direct"},{"domain_strategy":"","endpoint_independent_nat":true,"inet4_address":["172.19.0.1/28"],"mtu":9000,"sniff":true,"sniff_override_destination":false,"stack":"mixed","tag":"tun-in","auto_route":true,"type":"tun"},{"domain_strategy":"","listen":"127.0.0.1","listen_port":2080,"sniff":true,"sniff_override_destination":false,"tag":"mixed-in","type":"mixed"}],"log":{"level":"warning"},"outbounds":[{"method":"chacha20-ietf-poly1305","password":"'"${users[${username}]}"'","server":"127.0.0.1","server_port":1080,"type":"shadowsocks","udp_over_tcp":true,"domain_strategy":"","tag":"proxy","detour":"shadowtls"},{"password":"'"${users[${username}]}"'","server":"'"${config[server]}"'","server_port":'"${config[port]}"',"tls":{"enabled":true,"insecure":false,"server_name":"'"${config[domain]%%:*}"'","utls":{"enabled":true,"fingerprint":"chrome"}},"version":3,"type":"shadowtls","domain_strategy":"","tag":"shadowtls"},{"tag":"direct","type":"direct"},{"tag":"bypass","type":"direct"},{"tag":"block","type":"block"},{"tag":"dns-out","type":"dns"}],"route":{"auto_detect_interface":true,"rule_set":[],"rules":[{"outbound":"dns-out","port":[53]},{"inbound":["dns-in"],"outbound":"dns-out"},{"ip_cidr":["224.0.0.0/3","ff00::/8"],"outbound":"block","source_ip_cidr":["224.0.0.0/3","ff00::/8"]}]}}'
  else
    client_config="vless://"
    client_config="${client_config}${users[${username}]}"
    client_config="${client_config}@${config[server]}"
    client_config="${client_config}:${config[port]}"
    client_config="${client_config}?security=$([[ ${config[security]} == 'reality' ]] && echo reality || echo tls)"
    client_config="${client_config}&encryption=none"
    client_config="${client_config}&alpn=$([[ ${config[transport]} == 'ws' ]] && echo 'http/1.1' || echo 'h2,http/1.1')"
    client_config="${client_config}&headerType=none"
    client_config="${client_config}&fp=chrome"
    client_config="${client_config}&type=${config[transport]}"
    client_config="${client_config}&flow=$([[ ${config[transport]} == 'tcp' ]] && echo 'xtls-rprx-vision' || true)"
    client_config="${client_config}&sni=${config[domain]%%:*}"
    client_config="${client_config}$([[ ${config[transport]} == 'ws' || ${config[transport]} == 'http' ]] && echo "&host=${config[server]}" || true)"
    client_config="${client_config}$([[ ${config[security]} == 'reality' ]] && echo "&pbk=${config[public_key]}" || true)"
    client_config="${client_config}$([[ ${config[security]} == 'reality' ]] && echo "&sid=${config[short_id]}" || true)"
    client_config="${client_config}$([[ ${config[transport]} == 'ws' || ${config[transport]} == 'http' ]] && echo "&path=%2F${config[service_path]}" || true)"
    client_config="${client_config}$([[ ${config[transport]} == 'grpc' ]] && echo '&mode=gun' || true)"
    client_config="${client_config}$([[ ${config[transport]} == 'grpc' ]] && echo "&serviceName=${config[service_path]}" || true)"
    client_config="${client_config}#${username}"
  fi
  echo ""
  echo "=================================================="
  echo "Client configuration:"
  echo ""
  echo "$client_config"
  echo ""
  echo "Or you can scan the QR code:"
  echo ""
  qrencode -t ansiutf8 "${client_config}"
  ipv6=$(get_ipv6)
  if [[ -n $ipv6 ]]; then
    if [[ ${config[transport]} != 'shadowtls' ]]; then
      client_config_ipv6=$(echo "$client_config" | sed "s/@${config[server]}:/@[${ipv6}]:/" | sed "s/#${username}/#${username}-ipv6/")
    else
      client_config_ipv6=$(echo "$client_config" | sed "s/\"server\":\"${config[server]}\"/\"server\":\"${ipv6}\"/")
    fi
    echo ""
    echo "==================IPv6 Config======================"
    echo "Client configuration:"
    echo ""
    echo "$client_config_ipv6"
    echo ""
    echo "Or you can scan the QR code:"
    echo ""
    qrencode -t ansiutf8 "${client_config_ipv6}"
  fi
}

function upgrade {
  local uuid
  if [[ -e "${HOME}/reality/config" ]]; then
    ${docker_cmd} --project-directory "${HOME}/reality" down --remove-orphans --timeout 2
    mv -f "${HOME}/reality" ${config_path}
  fi
  uuid=$(grep '^uuid=' "${path[config]}" 2>/dev/null | cut -d= -f2 || true)
  if [[ -n $uuid ]]; then
    sed -i '/^uuid=/d' "${path[users]}"
    echo "RealityEZPZ=${uuid}" >> "${path[users]}"
    sed -i 's|=true|=ON|g; s|=false|=OFF|g' "${path[users]}"
  fi
  rm -f "${config_path}/singbox.conf"
  if ! ${docker_cmd} ls | grep ${compose_project} >/dev/null && [[ -r ${path[compose]} ]]; then
    ${docker_cmd} --project-directory ${config_path} down --remove-orphans --timeout 2
  fi
  if [[ -r ${path[config]} ]]; then
    sed -i 's|transport=h2|transport=http|g' "${path[config]}"
    sed -i 's|core=singbox|core=sing-box|g' "${path[config]}"
    sed -i 's|security=tls-invalid|security=selfsigned|g' "${path[config]}"
    sed -i 's|security=tls-valid|security=letsencrypt|g' "${path[config]}"
  fi
  for key in "${!path[@]}"; do
    if [[ -d "${path[$key]}" ]]; then
      rm -rf "${path[$key]}"
    fi
  done
}

function main_menu {
  local selection
  while true; do
    selection=$(whiptail --clear --backtitle "$BACKTITLE" --title "Server Management" \
      --menu "$MENU" $HEIGHT $WIDTH $CHOICE_HEIGHT \
      --ok-button "Select" \
      --cancel-button "Exit" \
      "1" "Add New User" \
      "2" "Delete User" \
      "3" "View User" \
      "4" "View Server Config" \
      "5" "Configuration" \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      break
    fi
    case $selection in
      1 )
        add_user_menu
        ;;
      2 )
        delete_user_menu
        ;;
      3 )
        view_user_menu
        ;;
      4 )
        view_config_menu
        ;;
      5 )
        configuration_menu
        ;;
    esac
  done
}

function add_user_menu {
  local username
  local message
  while true; do
    username=$(whiptail \
      --clear \
      --backtitle "$BACKTITLE" \
      --title "Add New User" \
      --inputbox "Enter username:" \
      $HEIGHT $WIDTH \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      break
    fi
    if [[ ! $username =~ ${regex[username]} ]]; then
      message_box "Invalid Username" "Username can only contains A-Z, a-z and 0-9"
      continue
    fi
    if [[ -n ${users[$username]} ]]; then
      message_box "Invalid Username" '"'"${username}"'" already exists.'
      continue
    fi
    users[$username]=$(cat /proc/sys/kernel/random/uuid)
    update_users_file
    whiptail \
      --clear \
      --backtitle "$BACKTITLE" \
      --title "Add New User" \
      --yes-button "View User" \
      --no-button "Return" \
      --yesno 'User "'"${username}"'" has been created.' \
      $HEIGHT $WIDTH \
      3>&1 1>&2 2>&3
    if [[ $? -ne 0 ]]; then
      break
    fi
    view_user_menu "${username}"
  done
}

function delete_user_menu {
  local username
  while true; do
    username=$(list_users_menu "Delete User")
    if [[ $? -ne 0 ]]; then
      return 0
    fi
    if [[ ${#users[@]} -eq 1 ]]; then
      message_box "Delete User" "You cannot delete the only user.\nAt least one user is needed.\nCreate a new user, then delete this one."
      continue
    fi
    whiptail \
      --clear \
      --backtitle "$BACKTITLE" \
      --title "Delete User" \
      --yesno "Are you sure you want to delete $username?" \
      $HEIGHT $WIDTH \
      3>&1 1>&2 2>&3
    if [[ $? -ne 0 ]]; then
      continue
    fi
    unset users["${username}"]
    update_users_file
    message_box "Delete User" 'User "'"${username}"'" has been deleted.'
  done
}

function view_user_menu {
  local username
  local user_config
  while true; do
    if [[ $# -gt 0 ]]; then
      username=$1
    else
      username=$(list_users_menu "View User")
      if [[ $? -ne 0 ]]; then
        return 0
      fi
    fi
    if [[ ${config[transport]} == 'tuic' ]]; then
      user_config=$(echo "
Protocol: tuic
Remarks: ${username}
Address: ${config[server]}
Port: ${config[port]}
UUID: ${users[$username]}
Password: $(echo -n "${username}${users[${username}]}" | sha256sum | cut -d ' ' -f 1 | head -c 16)
UDP Relay Mode: quic
Congestion Control: bbr
      " | tr -s '\n')
    elif [[ ${config[transport]} == 'hysteria2' ]]; then
      user_config=$(echo "
Protocol: hysteria2
Remarks: ${username}
Address: ${config[server]}
Port: ${config[port]}
Password: $(echo -n "${username}${users[${username}]}" | sha256sum | cut -d ' ' -f 1 | head -c 16)
OBFS Type: salamander
OBFS Password: ${config[service_path]}
      " | tr -s '\n')
    elif [[ ${config[transport]} == 'shadowtls' ]]; then
      user_config=$(echo "
=== First item of the chain proxy ===
Protocol: shadowtls
Remarks: ${username}-shadowtls
Address: ${config[server]}
Port: ${config[port]}
Password: ${users[$username]}
Protocol Version: 3
SNI: ${config[domain]%%:*}
Fingerprint: chrome
=== Second item of the chain proxy ===
Protocol: shadowsocks
Remarks: ${username}-shadowsocks
Address: 127.0.0.1
Port: 1080
Password: ${users[$username]}
Encryption Method: chacha20-ietf-poly1305
UDP over TCP: true

      " | tr -s '\n')
    else
      user_config=$(echo "
Protocol: vless
Remarks: ${username}
Address: ${config[server]}
Port: ${config[port]}
ID: ${users[$username]}
Flow: $([[ ${config[transport]} == 'tcp' ]] && echo 'xtls-rprx-vision' || true)
Network: ${config[transport]}
$([[ ${config[transport]} == 'ws' || ${config[transport]} == 'http' ]] && echo "Host Header: ${config[server]}" || true)
$([[ ${config[transport]} == 'ws' || ${config[transport]} == 'http' ]] && echo "Path: /${config[service_path]}" || true)
$([[ ${config[transport]} == 'grpc' ]] && echo 'gRPC mode: gun' || true)
$([[ ${config[transport]} == 'grpc' ]] && echo 'gRPC serviceName: '"${config[service_path]}" || true)
TLS: $([[ ${config[security]} == 'reality' ]] && echo 'reality' || echo 'tls')
SNI: ${config[domain]%%:*}
ALPN: $([[ ${config[transport]} == 'ws' ]] && echo 'http/1.1' || echo 'h2,http/1.1')
Fingerprint: chrome
$([[ ${config[security]} == 'reality' ]] && echo "PublicKey: ${config[public_key]}" || true)
$([[ ${config[security]} == 'reality' ]] && echo "ShortId: ${config[short_id]}" || true)
      " | tr -s '\n')
    fi
    whiptail \
      --clear \
      --backtitle "$BACKTITLE" \
      --title "${username} details" \
      --yes-button "View QR" \
      --no-button "Return" \
      --yesno "${user_config}" \
      $HEIGHT $WIDTH \
      3>&1 1>&2 2>&3
    if [[ $? -eq 0 ]]; then
      clear
      print_client_configuration "${username}"
      echo
      echo "Press Enter to return ..."
      read
      clear
    fi
    if [[ $# -gt 0 ]]; then
      return 0
    fi
  done
}

function list_users_menu {
  local title=$1
  local options
  local selection
  options=$(dict_expander users)
  selection=$(whiptail --clear --noitem --backtitle "$BACKTITLE" --title "$title" \
    --menu "Select the user" $HEIGHT $WIDTH $CHOICE_HEIGHT $options \
    3>&1 1>&2 2>&3)
  if [[ $? -ne 0 ]]; then
    return 1
  fi
  echo "${selection}"
}

function show_server_config {
  local server_config
  server_config="Server Address: ${config[server]}"
  server_config=$server_config$'\n'"Server Address: ${config[server]}"
  server_config=$server_config$'\n'"Domain SNI: ${config[domain]}"
  server_config=$server_config$'\n'"Port: ${config[port]}"
  server_config=$server_config$'\n'"Transport: ${config[transport]}"
  server_config=$server_config$'\n'"Security: ${config[security]}"
  server_config=$server_config$'\n'"Safenet: ${config[safenet]}"
  echo "${server_config}"
}

function view_config_menu {
  local server_config
  server_config=$(show_server_config)
  message_box "Server Configuration" "${server_config}"
}

function restart_menu {
  whiptail \
    --clear \
    --backtitle "$BACKTITLE" \
    --title "Restart Services" \
    --yesno "Are you sure to restart services?" \
    $HEIGHT $WIDTH \
    3>&1 1>&2 2>&3
  if [[ $? -ne 0 ]]; then
    return
  fi
  restart_docker_compose
}

function regenerate_menu {
  whiptail \
    --clear \
    --backtitle "$BACKTITLE" \
    --title "Regenrate keys" \
    --yesno "Are you sure to regenerate keys?" \
    $HEIGHT $WIDTH \
    3>&1 1>&2 2>&3
  if [[ $? -ne 0 ]]; then
    return
  fi
  generate_keys
  config[public_key]=${config_file[public_key]}
  config[private_key]=${config_file[private_key]}
  config[short_id]=${config_file[short_id]}
  update_config_file
  message_box "Regenerate keys" "All keys has been regenerated."
}

function restore_defaults_menu {
  whiptail \
    --clear \
    --backtitle "$BACKTITLE" \
    --title "Restore Default Config" \
    --yesno "Are you sure to restore default configuration?" \
    $HEIGHT $WIDTH \
    3>&1 1>&2 2>&3
  if [[ $? -ne 0 ]]; then
    return
  fi
  restore_defaults
  update_config_file
  message_box "Restore Default Config" "All configurations has been restored to their defaults."
}

function configuration_menu {
  local selection
  while true; do
    selection=$(whiptail --clear --backtitle "$BACKTITLE" --title "Configuration" \
      --menu "Select an option:" $HEIGHT $WIDTH $CHOICE_HEIGHT \
      "1" "Server Address" \
      "2" "Transport" \
      "3" "SNI Domain" \
      "4" "Security" \
      "5" "Port" \
      "6" "Safe Internet" \
      "7" "Restart Services" \
      "8" "Regenerate Keys" \
      "9" "Restore Defaults" \
      "10" "Create Backup" \
      "11" "Restore Backup" \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      break
    fi
    case $selection in
      1 )
        config_server_menu
        ;;
      2 )
        config_transport_menu
        ;;
      3 )
        config_sni_domain_menu
        ;;
      4 )
        config_security_menu
        ;;
      5 )
        config_port_menu
        ;;
      6 )
        config_safenet_menu
        ;;
      7 )
        restart_menu
        ;;
      8 )
        regenerate_menu
        ;;
      9 )
        restore_defaults_menu
        ;;
      10 )
        backup_menu
        ;;
      11 )
        restore_backup_menu
        ;;
    esac
  done
}

function config_server_menu {
  local server
  while true; do
    server=$(whiptail --clear --backtitle "$BACKTITLE" --title "Server Address" \
      --inputbox "Enter Server IP or Domain:" $HEIGHT $WIDTH "${config["server"]}" \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      break
    fi
    if [[ ! ${server} =~ ${regex[domain]} && ${config[security]} == 'letsencrypt' ]]; then
      message_box 'Invalid Configuration' 'You have to assign a valid domain to server if you want to use "letsencrypt" certificate.'
      continue
    fi
    if [[ -z ${server} ]]; then
      server="${defaults[server]}"
    fi
    config[server]="${server}"
    if [[ ${config[security]} != 'reality' && ${config[transport]} != 'shadowtls' ]]; then
      config[domain]="${server}"
    fi
    update_config_file
    break
  done
}

function config_transport_menu {
  local transport
  while true; do
    transport=$(whiptail --clear --backtitle "$BACKTITLE" --title "Transport" \
      --radiolist --noitem "Select a transport protocol:" $HEIGHT $WIDTH $CHOICE_HEIGHT \
      "tcp" "$([[ "${config[transport]}" == 'tcp' ]] && echo 'on' || echo 'off')" \
      "http" "$([[ "${config[transport]}" == 'http' ]] && echo 'on' || echo 'off')" \
      "grpc" "$([[ "${config[transport]}" == 'grpc' ]] && echo 'on' || echo 'off')" \
      "ws" "$([[ "${config[transport]}" == 'ws' ]] && echo 'on' || echo 'off')" \
      "tuic" "$([[ "${config[transport]}" == 'tuic' ]] && echo 'on' || echo 'off')" \
      "hysteria2" "$([[ "${config[transport]}" == 'hysteria2' ]] && echo 'on' || echo 'off')" \
      "shadowtls" "$([[ "${config[transport]}" == 'shadowtls' ]] && echo 'on' || echo 'off')" \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      break
    fi
    if [[ ${transport} == 'ws' && ${config[security]} == 'reality' ]]; then
      message_box 'Invalid Configuration' 'You cannot use "ws" transport with "reality" TLS certificate. Use other transports or change TLS certifcate to "letsencrypt" or "selfsigned"'
      continue
    fi
    if [[ ${transport} == 'tuic' && ${config[security]} == 'reality' ]]; then
      message_box 'Invalid Configuration' 'You cannot use "tuic" transport with "reality" TLS certificate. Use other transports or change TLS certifcate to "letsencrypt" or "selfsigned"'
      continue
    fi
    if [[ ${transport} == 'hysteria2' && ${config[security]} == 'reality' ]]; then
      message_box 'Invalid Configuration' 'You cannot use "hysteria2" transport with "reality" TLS certificate. Use other transports or change TLS certifcate to "letsencrypt" or "selfsigned"'
      continue
    fi
    if [[ ${config[transport]} != 'shadowtls' && ${transport} == 'shadowtls' && ${config[security]} != 'reality' ]]; then
      config[domain]="${defaults[domain]}"
    fi
    config[transport]=$transport
    update_config_file
    break
  done
}

function config_sni_domain_menu {
  local sni_domain
  while true; do
    sni_domain=$(whiptail --clear --backtitle "$BACKTITLE" --title "SNI Domain" \
      --inputbox "Enter SNI domain:" $HEIGHT $WIDTH "${config[domain]}" \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      break
    fi
    if [[ ! $sni_domain =~ ${regex[domain_port]} ]]; then
      message_box "Invalid Domain" '"'"${sni_domain}"'" in not a valid domain.'
      continue
    fi
    config[domain]=$sni_domain
    update_config_file
    break
  done
}

function config_security_menu {
  local security
  local free_80=true
  while true; do
    security=$(whiptail --clear --backtitle "$BACKTITLE" --title "Security Type" \
      --radiolist --noitem "Select a security type:" $HEIGHT $WIDTH $CHOICE_HEIGHT \
      "reality" "$([[ "${config[security]}" == 'reality' ]] && echo 'on' || echo 'off')" \
      "letsencrypt" "$([[ "${config[security]}" == 'letsencrypt' ]] && echo 'on' || echo 'off')" \
      "selfsigned" "$([[ "${config[security]}" == 'selfsigned' ]] && echo 'on' || echo 'off')" \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      break
    fi
    if [[ ! ${config[server]} =~ ${regex[domain]} && ${security} == 'letsencrypt' ]]; then
      message_box 'Invalid Configuration' 'You have to assign a valid domain to server if you want to use "letsencrypt" as security type'
      continue
    fi
    if [[ ${config[transport]} == 'ws' && ${security} == 'reality' ]]; then
      message_box 'Invalid Configuration' 'You cannot use "reality" TLS certificate with "ws" transport protocol. Change TLS certifcate to "letsencrypt" or "selfsigned" or use other transport protocols'
      continue
    fi
    if [[ ${config[transport]} == 'tuic' && ${security} == 'reality' ]]; then
      message_box 'Invalid Configuration' 'You cannot use "reality" TLS certificate with "tuic" transport. Change TLS certifcate to "letsencrypt" or "selfsigned" or use other transports'
      continue
    fi
    if [[ ${config[transport]} == 'hysteria2' && ${security} == 'reality' ]]; then
      message_box 'Invalid Configuration' 'You cannot use "reality" TLS certificate with "hysteria2" transport. Change TLS certifcate to "letsencrypt" or "selfsigned" or use other transports'
      continue
    fi
    if [[ ${security} == 'letsencrypt' && ${config[port]} -ne 443 ]]; then
      if lsof -i :80 >/dev/null 2>&1; then
        free_80=false
        for container in $(${docker_cmd} -p ${compose_project} ps -q); do
          if docker port "${container}" | grep '0.0.0.0:80' >/dev/null 2>&1; then
            free_80=true
            break
          fi
        done
      fi
      if [[ ${free_80} != 'true' ]]; then
        message_box 'Port 80 must be free if you want to use "letsencrypt" as the security option.'
        continue
      fi
    fi
    if [[ ${security} != 'reality' && ${config[transport]} != 'shadowtls' ]]; then
      config[domain]="${config[server]}"
    fi
    if [[ ${config[security]} != 'reality' && ${security} == 'reality' && ${config[transport]} != 'shadowtls' ]]; then
      config[domain]="${defaults[domain]}"
    fi
    config[security]="${security}"
    update_config_file
    break
  done
}

function config_port_menu {
  local port
  while true; do
    port=$(whiptail --clear --backtitle "$BACKTITLE" --title "Port" \
      --inputbox "Enter port number:" $HEIGHT $WIDTH "${config[port]}" \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      break
    fi
    if [[ ! $port =~ ${regex[port]} ]]; then
      message_box "Invalid Port" "Port must be an integer"
      continue
    fi
    if ((port < 1 || port > 65535)); then
      message_box "Invalid Port" "Port must be between 1 to 65535"
      continue
    fi
    config[port]=$port
    update_config_file
    break
  done
}

function config_safenet_menu {
  local safenet
  safenet=$(whiptail --clear --backtitle "$BACKTITLE" --title "Safe Internet" \
    --radiolist --noitem "Enable blocking malware and adult content" $HEIGHT $WIDTH $CHOICE_HEIGHT \
    "Enable" "$([[ "${config[safenet]}" == 'ON' ]] && echo 'on' || echo 'off')" \
    "Disable" "$([[ "${config[safenet]}" == 'OFF' ]] && echo 'on' || echo 'off')" \
    3>&1 1>&2 2>&3)
  if [[ $? -ne 0 ]]; then
    return
  fi
  config[safenet]=$([[ $safenet == 'Enable' ]] && echo ON || echo OFF)
  update_config_file
}

function backup_menu {
  local backup_password
  local result
  backup_password=$(whiptail \
    --clear \
    --backtitle "$BACKTITLE" \
    --title "Backup" \
    --inputbox "Choose a password for the backup file.\nLeave blank if you do not wish to set a password for the backup file." \
    $HEIGHT $WIDTH \
    3>&1 1>&2 2>&3)
  if [[ $? -ne 0 ]]; then
    return
  fi
  if result=$(backup "${backup_password}" 2>&1); then
    clear
    echo "Backup has been create and uploaded successfully."
    echo "You can download the backup file from here:"
    echo ""
    echo "${result}"
    echo ""
    echo "The URL is valid for 3 days."
    echo
    echo "Press Enter to return ..."
    read
    clear
  else
    message_box "Backup Failed" "${result}"
  fi
}

function restore_backup_menu {
  local backup_file
  local backup_password
  local result
  while true; do
    backup_file=$(whiptail \
      --clear \
      --backtitle "$BACKTITLE" \
      --title "Restore Backup" \
      --inputbox "Enter backup file path or URL" \
      $HEIGHT $WIDTH \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      break
    fi
    if [[ ! $backup_file =~ ${regex[file_path]} ]] && [[ ! $backup_file =~ ${regex[url]} ]]; then
      message_box "Invalid Backup path of URL" "Backup file path or URL is not valid."
      continue
    fi
    backup_password=$(whiptail \
      --clear \
      --backtitle "$BACKTITLE" \
      --title "Restore Backup" \
      --inputbox "Enter backup file password.\nLeave blank if there is no password." \
      $HEIGHT $WIDTH \
      3>&1 1>&2 2>&3)
    if [[ $? -ne 0 ]]; then
      continue
    fi
    if result=$(restore "${backup_file}" "${backup_password}" 2>&1); then
      parse_config_file
      parse_users_file
      build_config
      update_config_file
      update_users_file
      message_box "Backup Restore Successful" "Backup has been restored successfully."
      args[restart]=true
      break
    else
      message_box "Backup Restore Failed" "${result}"
    fi
  done
}

function restart_docker_compose {
  ${docker_cmd} --project-directory ${config_path} -p ${compose_project} down --remove-orphans --timeout 2 || true
  ${docker_cmd} --project-directory ${config_path} -p ${compose_project} up --build -d --remove-orphans --build
}

function restart_container {
  if [[ -z "$(${docker_cmd} ls | grep "${path[compose]}" | grep running || true)" ]]; then
    restart_docker_compose
    return
  fi
  if ${docker_cmd} --project-directory ${config_path} -p ${compose_project} ps --services "$1" | grep "$1"; then
    ${docker_cmd} --project-directory ${config_path} -p ${compose_project} restart --timeout 2 "$1"
  fi
}

function check_reload {
  declare -A restart
  generate_config
  for key in "${!path[@]}"; do
    if [[ "${md5["$key"]}" != $(get_md5 "${path[$key]}") ]]; then
      restart["${service["$key"]}"]='true'
      md5["$key"]=$(get_md5 "${path[$key]}")
    fi
  done
  if [[ "${restart[compose]}" == 'true' ]]; then
    restart_docker_compose
    return
  fi
  for key in "${!restart[@]}"; do
    if [[ $key != 'none' ]]; then
      restart_container "${key}"
    fi
  done
}

function message_box {
  local title=$1
  local message=$2
  whiptail \
    --clear \
    --backtitle "$BACKTITLE" \
    --title "$title" \
    --msgbox "$message" \
    $HEIGHT $WIDTH \
    3>&1 1>&2 2>&3
}

function get_md5 {
  local file_path
  file_path=$1
  md5sum "${file_path}" 2>/dev/null | cut -f1 -d' ' || true
}

function generate_file_list {
  path[config]="${config_path}/config"
  path[users]="${config_path}/users"
  path[compose]="${config_path}/docker-compose.yml"
  path[engine]="${config_path}/engine.conf"
  path[haproxy]="${config_path}/haproxy.cfg"
  path[certbot_deployhook]="${config_path}/certbot/deployhook.sh"
  path[certbot_dockerfile]="${config_path}/certbot/Dockerfile"
  path[certbot_startup]="${config_path}/certbot/startup.sh"
  path[server_pem]="${config_path}/certificate/server.pem"
  path[server_key]="${config_path}/certificate/server.key"
  path[server_crt]="${config_path}/certificate/server.crt"

  service[config]='none'
  service[users]='none'
  service[compose]='compose'
  service[engine]='engine'
  service[haproxy]='haproxy'
  service[certbot_deployhook]='certbot'
  service[certbot_dockerfile]='compose'
  service[certbot_startup]='certbot'
  service[server_pem]='haproxy'
  service[server_key]='engine'
  service[server_crt]='engine'

  for key in "${!path[@]}"; do
    md5["$key"]=$(get_md5 "${path[$key]}")
  done
}

function tune_kernel {
  cat >/etc/sysctl.d/99-reality-ezpz.conf <<EOF
# File system limits
fs.file-max = 1000000

# Network core settings - optimized for high throughput
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.core.netdev_max_backlog = 500000
net.core.somaxconn = 8192

# TCP settings - optimized for Reality/VLESS
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 10000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1

# TCP memory tuning - increased for better performance
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.tcp_rmem = 8192 87380 134217728
net.ipv4.tcp_wmem = 8192 65536 134217728

# TCP optimization
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_ecn = 0

# BBR congestion control - best for Reality
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Connection tracking
net.netfilter.nf_conntrack_max = 2000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30

# IPv6 optimization
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# UDP optimization
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
EOF
  sysctl -qp /etc/sysctl.d/99-reality-ezpz.conf >/dev/null 2>&1 || true
}

function configure_docker {
  local docker_config="/etc/docker/daemon.json"
  local config_modified=false
  local temp_file
  temp_file=$(mktemp)
  if [[ ! -f "${docker_config}" ]] || [[ ! -s "${docker_config}" ]]; then
    echo '{"experimental": true, "ip6tables": true}' | jq . > "${docker_config}"
    config_modified=true
  else
    if ! jq . "${docker_config}" &> /dev/null; then
      echo '{"experimental": true, "ip6tables": true}' | jq . > "${docker_config}"
      config_modified=true
    else
      if jq 'if .experimental != true or .ip6tables != true then .experimental = true | .ip6tables = true else . end' "${docker_config}" | jq . > "${temp_file}"; then
        if ! cmp --silent "${docker_config}" "${temp_file}"; then
          mv "${temp_file}" "${docker_config}"
          config_modified=true
        fi
      fi
    fi
  fi
  rm -f "${temp_file}"
  if [[ "${config_modified}" = true ]] || ! systemctl is-active --quiet docker; then
    sudo systemctl restart docker || true
  fi
}

parse_args "$@" || show_help
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi
if [[ ${args[backup]} == true ]]; then
  if [[ -n ${args[backup_password]} ]]; then
    backup_url=$(backup "${args[backup_password]}")
  else
    backup_url=$(backup)
  fi
  if [[ $? -eq 0 ]]; then
    echo "Backup created successfully. You can download the backup file from this address:"
    echo "${backup_url}"
    echo "The URL is valid for 3 days."
    exit 0
  fi
fi
if [[ -n ${args[restore]} ]]; then
  if [[ -n ${args[backup_password]} ]]; then
    restore "${args[restore]}" "${args[backup_password]}"
  else
    restore "${args[restore]}"
  fi
  if [[ $? -eq 0 ]]; then
    args[restart]=true
    echo "Backup has been restored successfully."
  fi
  echo "Press Enter to continue ..."
  read
  clear
fi
generate_file_list
install_packages
install_docker
configure_docker
upgrade
parse_config_file
parse_users_file
build_config
update_config_file
update_users_file
tune_kernel

if [[ ${args[menu]} == 'true' ]]; then
  set +e
  main_menu
  set -e
fi
if [[ ${args[restart]} == 'true' ]]; then
  restart_docker_compose
fi
if [[ -z "$(${docker_cmd} ls | grep "${path[compose]}" | grep running || true)" ]]; then
  restart_docker_compose
fi
if [[ ${args[server-config]} == true ]]; then
  show_server_config
  exit 0
fi
if [[ -n ${args[list_users]} ]]; then
  for user in "${!users[@]}"; do
    echo "${user}"
  done
  exit 0
fi
if [[ ${#users[@]} -eq 1 ]]; then
  username="${!users[@]}"
fi
if [[ -n ${args[show_config]} ]]; then
  username="${args[show_config]}"
  if [[ -z "${users["${username}"]}" ]]; then
    echo 'User "'"$username"'" does not exists.'
    exit 1
  fi
fi
if [[ -n ${args[add_user]} ]]; then
  username="${args[add_user]}"
fi
if [[ -n $username ]]; then
  print_client_configuration "${username}"
fi
echo "Command has been executed successfully!"
exit 0
