#!/bin/bash

# Purpose: Commandline interface of Cloudflare API
# Author : Anh K. Huynh
# Date   : 2015 July 27th
# License: MIT

#
# Method 1:
#       _cf_zone_dns_get_entries --zone_id foobar
#
# Method 2:
#       export CF_ZONE_ID="$(_cf_zone_get_entry_id --name "domain")" || return 1
#       _cf_zone_dns_get_entries ...
#
__cf_detect_arg() {
  while (( $# )); do
    case "${1:0:2}" in
    "--")
      var="${1:2}"; shift;
      val="${1:-}"; shift;
      if [[ -n "${var}" ]]; then
        CF_ARGS["$var"]="${val}"
        CF_ARG_FLAGS["$var"]=1
      fi
      ;;
    *)
      shift
      ;;
    esac
  done

  if [[ -n "${CF_ZONE_ID:-}" ]] && ! __cf_has_arg zone_id; then
    CF_ARG_FLAGS["zone_id"]=1
    CF_ARGS["zone_id"]="${CF_ZONE_ID}"
  fi

  if [[ -n "${CF_EMAIL:-}" ]] && ! __cf_has_arg email; then
    CF_ARG_FLAGS["email"]=1
    CF_ARGS["email"]="${CF_EMAIL}"
  fi

  if [[ -n "${CF_DEBUG:-}" ]] && ! __cf_has_arg debug; then
    CF_ARG_FLAGS["debug"]=1
    CF_ARGS["debug"]="${CF_DEBUG}"
  fi

  export CF_EMAIL="$(__cf_get_arg email)"
  export CF_DEBUG="$(__ensure_boolean $(__cf_get_arg debug))"
}

__cf_error() {
  echo "{\"success\":false,\"message\":\"$@\",\"result\":[]}"
  echo "{\"success\":false,\"message\":\"$@\",\"result\":[]}" 1>&2
  return 1
}

__cf_get_arg() {
  local _var="${1:-}"
  echo "${CF_ARGS[$_var]:-}"
}

__cf_has_arg() {
  local _var="${1:-}"
  [[ "${CF_ARG_FLAGS[$_var]:-}" == "1" ]]
}

# Cloudflare strictly requires "true" or "false"
__ensure_boolean() {
  case "${1,,}" in
  "0"|"false"|"") echo "false";;
               *) echo "true";;
  esac
}

# Cloudflare strictly requires "on" or "off"
__ensure_on_off() {
  case "${1,,}" in
  "on"|"1"|"true") echo "on";;
                *) echo "off";;
  esac
}

__my_json_pp() {
  perl -e '
    use JSON;
    my $stream = do { local $/; <STDIN> };
    my $json = decode_json($stream);
    my $ret = $json->{"success"};
    if ($ENV{"CF_ENTRY"}) {
      printf("%s\n", eval(sprintf("\$json->%s", $ENV{"CF_ENTRY"})));
    }
    else {
      print $stream;
    }

    exit($ret);
  '
}

__cf_request() {
  local _uri="$1"; shift

  [[ "${CF_DEBUG:-}" == ""true ]] \
  && echo >&2 ":: $FUNCNAME: $_uri, data -> $@"

  {
    if [[ -n "${CF_BEARER_TOKEN:-}" ]]; then
      curl -sSLo- --connect-timeout "${CURL_TIMEOUT:-4}" \
        "https://api.cloudflare.com/client/v4$_uri" \
        -H "Authorization: Bearer $CF_BEARER_TOKEN" \
        -H "Content-Type: application/json" \
        "$@"
    else
      curl -sSLo- --connect-timeout "${CURL_TIMEOUT:-4}" \
        "https://api.cloudflare.com/client/v4$_uri" \
        -H "X-Auth-Email: $CF_EMAIL" \
        -H "X-Auth-Key: $CF_KEY" \
        -H "Content-Type: application/json" \
        "$@"
    fi
  } \
  | __my_json_pp
}

_cf_zone_get_entries() { #public: List all zones
  local _name=

  if __cf_has_arg name; then
    _name="&name=$(__cf_get_arg name)"
  fi

  __cf_request "/zones$_name"
}

_cf_zone_get_entry() {
  local _name="$(__cf_get_arg name)"
  local _total=

  local _response

  _response="$(__cf_request "/zones/?name=$_name&match=all")"
  _total="$( \
    echo "$_response" \
    | CF_ENTRY='{"result_info"}->{"total_count"}' __my_json_pp)"

  if [[ "$_total" != "1" ]]; then
    __cf_error "$FUNCNAME: Zero or more than 1 matches found."
    return 1
  fi

  echo "$_response"
}

# PATCH /zones/:zone_identifier/settings/development_mode
_cf_zone_settings_update() {
  local _zone_id="$(__cf_get_arg zone_id)"
  local _name="$(__cf_get_arg name)"
  local _devel="$(__cf_get_arg devel)"
  local _response=

  if __cf_has_arg "devel"; then
    _devel="$(__ensure_on_off $_devel)"

    __cf_request \
      "/zones/$_zone_id/settings/development_mode" \
      -X PATCH \
      --data "{\"value\":\"$_devel\"}"
  else
    __cf_error "$FUNCNAME: Feature not yet implemented. Your input: $@"
  fi
}

_cf_zone_get_entry_id() {
 _cf_zone_get_entry "$@" \
 | CF_ENTRY='{"result"}[0]->{"id"}' __my_json_pp

 [[ "${PIPESTATUS[0]}" -eq 0 ]]
}

# --zone_id  ID         : The identity of a zone
# --name     DNS_NAME   : The dns entry
# --per_page NUM        : Number of results per request
_cf_zone_dns_get_entries() {
  local _zone_id="$(__cf_get_arg zone_id)"
  local _name="$(__cf_get_arg name)"
  local _per_page="$(__cf_get_arg per_page)"

  _per_page="${_per_page:-100}"

  local _page="1"
  local _total_pages=""

  if [[ -n "$_name" ]]; then
    _name="&name=$_name&match=all"
  fi

  _response="$(__cf_request "/zones/$_zone_id/dns_records?per_page=$_per_page$_name")"
  _total_page="$( \
    echo "$_response" \
    | CF_ENTRY='{"result_info"}->{"total_pages"}' __my_json_pp)"

  # echo >&2 ":: $FUNCNAME: total page => $_total_page"
  if [[ -z "$_total_page" ]]; then
    echo "$_response"
    return 1
  elif [[ "$_total_page" == "0" ]]; then
    echo "$_response"
    return 1
  fi

  {
    echo "["
    echo "  $_response,"

    _page=2 # next_page
    while [[ "$_page" -le "$_total_page" ]]; do
      __cf_request "/zones/$_zone_id/dns_records?page=$_page&per_page=$_per_page$_name"
      echo ","
      (( _page ++ ))
    done

    echo '{"result":[], "success":true}'
    echo "]"
  } \
  | perl -e '
      use JSON;
      my $stream = do { local $/; <>; };
      my $json = decode_json $stream;
      my $ret = {
                  "success" => true,
                  "result" => [],
                  "result_info" => {
                    "total_pages" => 0,
                    "merged" => true
                  }
                };
      my $success = true;
      my $total_page = 0;
      foreach (keys @{$json}) {
        $total_page = $_;
        my $item = @{$json}[$_];

        $success = ($success && $item->{"success"});
        push(@{$ret->{"result"}}, @{$item->{"result"}});
      }

      $ret->{"result_info"}->{"total_page"} = $total_page;
      $ret->{"success"} = $success;

      print(encode_json($ret));

      if ($success eq false) {
        exit(1);
      }
    '
}

# --zone_id  ID           : The identify of the zone
# --name     DNS_NAME     : The entry to create
# --type     A|CNAME      : Record type (Must be: A or CNAME)
# --value    IP|DNS_NAME  : The value of dns record
_cf_zone_dns_create_entry() { #public: Create new dns entry
  local _zone_id="$(__cf_get_arg zone_id)"
  local _name="$(__cf_get_arg name)"
  local _type="$(__cf_get_arg type)"
  local _content="$(__cf_get_arg value)"
  local _ttl="$(__cf_get_arg ttl)"

  _ttl="${_ttl:-120}"

  __cf_request "/zones/$_zone_id/dns_records" \
    -X POST \
    --data "{\"type\":\"$_type\",\"name\":\"$_name\",\"content\":\"$_content\",\"ttl\":$_ttl}"
}

# This is to make sure there is only ONE match
# FIXME: support --entry_id filter
_cf_zone_dns_get_entry() {
  local _zone_id="$(__cf_get_arg zone_id)"
  local _name="$(__cf_get_arg name)"
  local _total=
  local _type="$(__cf_get_arg type)"

  local _response="$(__cf_request "/zones/$_zone_id/dns_records?name=$_name&match=all")"

  if __cf_has_arg type; then
    _response="$(
      echo "$_response" \
      | CF_TYPE="$_type" \
        perl -e '
          use JSON;
          my $stream = do { local $/; <STDIN> };
          my $json = decode_json($stream);
          my $items = $json->{"result"};
          my %ret = {
            "result" => [],
            "result_info" => {"total_count" => 0 }
            };

          foreach(keys @$items) {
            my $item = @$items[$_];
            if ($item->{"type"} eq $ENV{"CF_TYPE"}) {
              push(@{$ret->{"result"}}, $item);
            }
          };

          $ret->{"result_info"}->{"total_count"} = scalar(@{$ret->{"result"}});
          $ret->{"success"} => true;

          print encode_json($ret);
        '
    )"

    if [[ $? -ge 1 ]]; then
      __cf_error "$FUNCNAME: Error happened when filtering items for type = '$_type'."
      return 1
    fi
  fi

  _total="$( \
      echo "$_response" \
      | CF_ENTRY='{"result_info"}->{"total_count"}' \
        __my_json_pp \
    )"

  if [[ "$_total" != "1" ]]; then
    __cf_error "$FUNCNAME: Zero or more than 1 matches found."
    return 1
  fi

  echo "$_response"
}

_cf_zone_dns_get_entry_id() {
 _cf_zone_dns_get_entry "$@" \
 | CF_ENTRY='{"result"}[0]->{"id"}' __my_json_pp

 [[ "${PIPESTATUS[0]}" -eq 0 ]]
}

# Update A/CNAME value
# Update proxied value
_cf_zone_dns_update_entry() { #public: Update dns entry
  local _zone_id="$(__cf_get_arg zone_id)"
  local _name="$(__cf_get_arg name)"

  local _type
  local _content
  local _proxied

  local _entry_ttl
  local _entry_id=
  local _entry_props=""

  if ! __cf_has_arg name; then
    __cf_error "$FUNCNAME: please specify --name."
    return 1
  fi

  if ! __cf_has_arg value && ! __cf_has_arg proxied; then
    __cf_error "$FUNCNAME: please specify --proxied and/or --value."
    return 1
  fi

  _entry_props="$(_cf_zone_dns_get_entry --zone_id "$_zone_id" --name "$_name")" \
  || return 1

  _entry_id="$(echo "$_entry_props" | CF_ENTRY='{"result"}[0]->{"id"}' __my_json_pp)"

  if __cf_has_arg type; then
    _entry_type="$(__cf_get_arg type)"
  else
    _entry_type="$(echo "$_entry_props" | CF_ENTRY='{"result"}[0]->{"type"}' __my_json_pp)"
  fi

  if __cf_has_arg proxied; then
    _entry_proxied="$(__cf_get_arg proxied)"
  else
    _entry_proxied="$(echo "$_entry_props" | CF_ENTRY='{"result"}[0]->{"proxied"}' __my_json_pp)"
  fi

  if __cf_has_arg value; then
    _entry_content="$(__cf_get_arg value)"
  else
    _entry_content="$(echo "$_entry_props" | CF_ENTRY='{"result"}[0]->{"content"}' __my_json_pp)"
  fi

  _entry_proxied="$(__ensure_boolean $_entry_proxied)"

  local _entry_ttl
  if [[ "$_entry_proxied" == "true" ]]; then
    _entry_ttl="1"
  else
    _entry_ttl="$(__cf_get_arg ttl)"
    if [[ -z "$_entry_ttl" ]]; then
      _entry_ttl="$(echo "$_entry_props" | CF_ENTRY='{"result"}[0]->{"ttl"}' __my_json_pp)"
    fi
  fi

  __cf_request "/zones/$_zone_id/dns_records/$_entry_id" \
    -X PUT \
    --data "{\"type\":\"$_entry_type\",\"name\":\"$_name\",\"content\":\"$_entry_content\",\"ttl\":$_entry_ttl,\"proxied\":$_entry_proxied}"
}

_cf_cache_purge_all() {
  local _zone_id="$(__cf_get_arg zone_id)"

  echo >&2 ":: $FUNCNAME: purge all caches under the zone $_zone_id..."

  __cf_request "/zones/$_zone_id/purge_cache" \
    -X DELETE \
    --data '{"purge_everything":true}'
}

# $0 --zone_id foobar file1 file2 file3
_cf_cache_purge_uri() {
  local _zone_id="$(__cf_get_arg zone_id)"

  local _files=""

  echo >&2 ":: $FUNCNAME: purge cache for $@"

  while (( $# )); do
    _files="\"$1\",$_files"
    shift
  done

  _files="${_files%,*}"

  __cf_request "/zones/$_zone_id/purge_cache" \
    -X DELETE \
    --data "{\"files\":[$_files]}"
}

_cf_check() {
  if [[ -n "${CF_BEARER_TOKEN:-}" ]]; then
    export CF_BEARER_TOKEN
    return 0
  fi

  local _f_key="${CF_KEY_FILE:-etc/cloudflare.$CF_EMAIL.key}"

  if [[ ! -f "$_f_key" ]]; then
    __cf_error "$FUNCNAME: File '$_f_key' not found, or CF_BEARER_TOKEN is not set."
    return 1
  fi

  export CF_KEY="$(head -1 "$_f_key" 2>/dev/null)"
}

_cf_zone_dns_get_simple_list() { #public: Print a simple list of dns entries
  _cf_zone_dns_get_entries "$@" \
  | perl -e '
      use JSON;
      my $stream = do { local $/; <STDIN> };
      my $json = decode_json($stream);
      my $ret = $json->{"success"};

      printf("# Non-Proxied entries\n");
      foreach ( keys @{$json->{"result"}} ) {
        my $entry = $json->{"result"}[$_];
        if (! $entry->{"proxied"}) {
          printf("%40s %5s %s\n", $entry->{"name"}, $entry->{"type"}, $entry->{"content"});
        }
      }

      printf("# Proxied entries\n");
      foreach ( keys @{$json->{"result"}} ) {
        my $entry = $json->{"result"}[$_];
        if ($entry->{"proxied"}) {
          printf("%40s %5s %s\n", $entry->{"name"}, $entry->{"type"}, $entry->{"content"});
        }
      }

      exit($ret);
    '
}

_cf_zone_custom_pages_get() {
  local _zone_id="$(__cf_get_arg zone_id)"
  local _name="$(__cf_get_arg name)"
  local _devel="$(__cf_get_arg devel)"
  local _response=

  if __cf_has_arg "devel"; then
    _devel="$(__ensure_on_off $_devel)"

    __cf_request \
      "/zones/$_zone_id/settings/development_mode" \
      -X PATCH \
      --data "{\"value\":\"$_devel\"}"
  else
    __cf_error "$FUNCNAME: Feature not yet implemented. Your input: $@"
  fi
}

_cf_zone_custom_pages_get_entry() {
  local _zone_id="$(__cf_get_arg zone_id)"
  local _page_id="$(__cf_get_arg page_id)"
  local _response=

  if ! __cf_has_arg page_id; then
    __cf_error "$FUNCNAME: --page_id must be provided. Valid values: basic_challenge, waf_challenge, country_challenge, ip_block, under_attack, 500_errors, 1000_errors, always_online"

    return
  fi

  __cf_request \
    "/zones/$_zone_id/custom_pages/$_page_id" \
    -X GET \
  | perl -e '
      use JSON;
      my $stream = do { local $/; <STDIN> };
      my $json = decode_json($stream);
      my $ret = $json->{"success"};

      if ($json->{"result"}->{"url"}) {
        $json->{"result"}->{"preview_url"} = sprintf("http://cloudflarepreview.com/preview-cpage?act=preview&target=%s&url=%s", $json->{"result"}->{"preview_target"}, $json->{"result"}->{"url"})
      }
      print encode_json($json);

      exit($ret);
    '
}

_cf_zone_custom_pages_update_entry() {
  local _zone_id="$(__cf_get_arg zone_id)"
  local _page_id="$(__cf_get_arg page_id)"
  local _url="$(__cf_get_arg url)"
  local _state="$(__cf_get_arg state)"

  local _response=

  if ! __cf_has_arg page_id; then
    __cf_error "$FUNCNAME: --page_id must be provided. Valid values: basic_challenge, waf_challenge, country_challenge, ip_block, under_attack, 500_errors, 1000_errors, always_online"
    return
  fi

  if ! __cf_has_arg url; then
    __cf_error "$FUNCNAME: --url must be specified."
    return
  fi

  if ! __cf_has_arg state; then
    __cf_error "$FUNCNAME: --state must be specified. Valid values: default, customized."
    return
  fi

  __cf_request \
    "/zones/$_zone_id/custom_pages/$_page_id" \
    -X PUT \
    --data "{\"url\":\"$_url\",\"state\":\"$_state\"}"
}

_cf_zone_custom_pages_get_entries() {
  local _zone_id="$(__cf_get_arg zone_id)"
  local _response=

  __cf_request \
    "/zones/$_zone_id/custom_pages" \
    -X GET
}

_cf_zone_custom_pages_simple_list() {
  _cf_zone_custom_pages_get_entries "$@" \
  | perl -e '
      use JSON;
      my $stream = do { local $/; <STDIN> };
      my $json = decode_json($stream);
      my $ret = $json->{"success"};

      foreach ( keys @{$json->{"result"}} ) {
        my $entry = $json->{"result"}[$_];
        my $desc = $entry->{"description"};
        $desc =~ s/ +/_/g;
        printf("%s %s url=%s %s\n", $entry->{"id"}, $entry->{"state"}, $entry->{"url"}, $desc);
      }

      exit($ret);
    ' \
  | column -t
}

_help() {
  grep -Ee "^_cf_.*#public" "${BASH_SOURCE[0]:-$0}" \
  | column -s '()' -t
}

#######################################################################
# Main program
########################################################################

if [[ -z "${@:-}" || "${1:-}" == "help" ]]; then
  _help
  exit
fi

declare -A CF_ARGS=()
declare -A CF_ARG_FLAGS=()
unset CF_ENTRY || exit 1

__cf_detect_arg "$@"
_cf_check || exit 1

"${@:-_help}"
