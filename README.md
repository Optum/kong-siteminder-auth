# Kong Siteminder Auth
Siteminder authentication integration with the Kong Gateway

## Configuration
You can add the plugin with the following request:

```bash
$ curl -X POST http://kong:8001/apis/{api}/plugins \
    --data "name=kong-siteminder-auth" \
    --data "config.siteminder_endpoint=https://siteminder-webservice.company.com/auth/something" \
    --data "config.method=POST" \
    --data "config.content_type=application/xml" \
    --data "config.timeout=10000" \
    --data "config.keepalive=60000" \
    --data "config.authenticated_group=by_route_id" \
```

The ```config.authenticated_group``` helps set the context of the group defined on the tx for native Kong ACL plugin integration so you have the capability to run this auth pattern alongside other Kong auth patterns.

You will also need to configure these shm cache dicts in your Kong template for this plugin to leverage:
```
# exclusive siteminder shm caches
lua_shared_dict kong_sm_cache       5m;
lua_shared_dict kong_sm_cache_miss  2m;
lua_shared_dict kong_sm_cache_locks 1m;
```

<ins>NOTE:</ins>

A client can call the proxy by passing the siteminder session into 1 of two sections of the request:

Option 1: SiteminderToken header, ex:

SiteminderToken: eRJBOMWgghIUuLP5iuBezXaKjIqG3kssOWfiRf……

Option 2: As a SMSESSION Cookie header, ex:

Cookie: SMSESSION=eRJBOMWgghIUuLP5iuBezXaKjIqG3kssOWfiRf……;

Also, Kong will populate `X-UserInfo` header with the successful response body received from Siteminder to send to the API provider.

## Supported Kong Releases
Kong >= 2.X.X

## Installation
Recommended:
```
$ luarocks install kong-siteminder-auth
```
Other:
```
$ git clone https://github.com/Optum/kong-siteminder-auth.git /path/to/kong/plugins/kong-siteminder-auth
$ cd /path/to/kong/plugins/kong-siteminder-auth
$ luarocks make *.rockspec
```

## Maintainers
[jeremyjpj0916](https://github.com/jeremyjpj0916)<br />
[vino10](https://github.com/vino10)

Feel free to open issues, or refer to our [Contribution Guidelines](https://github.com/Optum/kong-siteminder-auth/blob/master/CONTRIBUTING.md) if you have any questions.
