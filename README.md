## Table of contents

1. [Description](#description)
1. [Author](#author)
1. [License](#license)
1. [Examples](#examples)
1. [Tips](#tips)
1. [FIXME](#fixme)

## Description

A `Bash` binding of Cloudflare API https://api.cloudflare.com/.
Require `Bash4`, `perl-json`.

## Author

Anh K. Huynh.

## License

The work is released under a MIT license.

## Examples

````
# Without Bearer token, you need to set up two variables
$ export CF_KEY_FILE=./my_api_key.private
$ export CF_EMAIL=john@example.net

# Alternatively, you can use CF_BEARER_TOKEN instead of those two variables
$ export CF_BEARER_TOKEN=....

# List all of my domains
$ ./cloudflare_api.sh _cf_zone_get_entries | json_pp

# Get information of a domain
$ ./cloudflare_api.sh _cf_zone_get_entry example.net | json_pp

# Return the identify of a domain
$ ./cloudflare_api.sh _cf_zone_get_entry_id example.net

$ export CF_ZONE_ID=foobar # result return from the above step

$ ./cloudflare_api.sh _cf_zone_dns_get_simple_list
# Or equivalently
# ./cloudflare_api.sh _cf_zone_dns_get_simple_list --zone_id $CF_ZONE_ID

# Create an dns entry
$ ./cloudflare_api.sh _cf_zone_dns_create_entry \
    --zone_id $CF_ZONE_ID \
    --name "foo.example.net" \
    --ttl 1 \
    --type CNAME \
    --value "bar.example.net"

$ ./cloudflare_api.sh _cf_zone_dns_get_entry \
    --zone_id $CF_ZONE_ID \
    --name "foo.example.net"

# Enable proxying
$ ./cloudflare_api.sh _cf_zone_dns_update_entry \
    --zone_id $CF_ZONE_ID \
    --name "foo.example.net" \
    --proxied true

# Purging cache
$ ./cloudflare_api.sh _cf_cache_purge_all \
    --zone_id $CF_ZONE_ID

# Purge some URIs
$ ./cloudflare_api.sh _cf_purge_uri \
    --zone_id $CF_ZONE_ID \
    http://example.net/foo \
    http://example.net/bar \
    ...
````

## Tips

1. Use `--debug true` option to see how `curl` sends request(s) to Cloudflare.
1. If `--zone_id` option is not specified, the `CF_ZONE_ID` environment is used.
1. Sourcing and noop would help to set up some variables like `CF_ZONE_ID`.
   For example,

        source cloudflare_api.sh : "$@"
        # Now CF_ZONE_ID is exported.
        # See details in `_cf_check` and `__cf_detect_arg`

## FIXME

1. Ability to specify `--entry_id` when updating / listing
1. Not work with entry that has multiple DNS properties (`A`, `MX`, ...)
