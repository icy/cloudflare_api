## Description

A minimalist `Bash` binding of Cloudflare API https://api.cloudflare.com/.

## Author

Anh K. Huynh.

## License

The work is released under a MIT license.

## Examples

````
$ export CF_KEY_FILE=./my_api_key.private
$ export CF_EMAIL=john@example.net

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

````
