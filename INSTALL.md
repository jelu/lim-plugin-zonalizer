# Install

## Packages for Ubuntu

Packages for Ubuntu can be installed from a PPA on LaunchPad.

```
sudo add-apt-repository ppa:jelu/zonalizer
sudo apt-get update
sudo apt-get install zonalizer-backend
```

If you wish to use CouchDB as database then also install the package
`liblim-plugin-zonalizer-db-couchdb-perl`.

# Configure

Configure Lim to listen on a port by using one of the examples below in
`/etc/lim/agent.yaml`. Consider fronting the application with either Apache or
Nginx.

```yaml
---
agent:
  uri:
    - http+rest://localhost:8080
```

```yaml
---
agent:
  uri:
    - uri: http+rest://localhost:8080
      plugin: Zonalizer
```

Restart the Lim Agent Daemon to get the changes in effect, following example is
for Debian/Ubuntu.

```
sudo service lim-agentd restart
```

# Test the API

For the following examples it is recommended that you turn on pretty printing
JSON in Lim otherwise it's going to be hard to read the JSON objects.

Edit `/etc/lim/agent.yaml` and add the following:

```yaml
rpc:
  json:
    pretty: 1
```

The restart Lim.

```
sudo service lim-agentd restart
```

You can now use `curl` to talk to the API and check that it's working.

```
curl 'http://localhost:8080/zonalizer/1/version'
```

The above gives you an JSON object back with the version of Zonalizer,
Zonemaster and all of Zonemaster's tests.

Now let's execute a test of `example.com`.

```
curl -g -X POST 'http://localhost:8080/zonalizer/1/analysis?fqdn=example.com'
```

You will get a JSON object with the `id` of the test like this
`{"id":"Dbce5VacQBubM76Imyg42A"}`, we can use the `id` to check the status of
the analysis. In the below examples replace `Dbce5VacQBubM76Imyg42A` with the
`id` you got.

```
curl -g 'http://localhost:8080/zonalizer/1/analysis/Dbce5VacQBubM76Imyg42A/status'
```

If `progress` is 100 in the returned JSON object the test is done and the
results can be looked at.

```
curl -g 'http://localhost:8080/zonalizer/1/analysis/Dbce5VacQBubM76Imyg42A?results=1'
```

# Database setup

If you installed without a database driver the `Memory` driver will be used and
no setup is needed (but all results are lost on restart).

## CouchDB

Install CouchDB, following example is for Debian/Ubuntu. CouchDB does not have
to be installed on the same server, you can also create multiple nodes and
replication. See CouchDB documentation for more information.

```
sudo apt-get install couchdb
```

Initialize the CouchDB database, the `URI` to the database should be in the
format of `http://localhost:5984/zonalizer` and must be the same used in the
configuration below.

```
zonalizer-couchdb-database --create URI
```

Configure Zonalizer to use CouchDB, for example in
`/etc/lim/agent.d/zonalizer.yaml` (create if not existing).

```yaml
---
zonalizer:
  db_driver: CouchDB
  db_conf:
    uri: http://localhost:5984/zonalizer
```

# Exposing the API

If you are planning to expose the API for a web application please consider
using nginx or others to front the requests, here is a nginx example config to
do just that.

Note that this config include limiting of requests and blocking `DELETE`, this
is important since the API has calls to delete an analysis or the entire
database.

```
upstream backend {
        server localhost:8080;
        keepalive 16;
}

limit_req_zone $binary_remote_addr zone=one:10m rate=1r/s;

server {
        listen 80 default_server;
        listen [::]:80 default_server;

        location /search/ {
                limit_req zone=one burst=5;
        }

        root <some root directory>;
        index index.html;

        server_name _;

        location / {
                try_files $uri $uri/ =404;
        }

        location /zonalizer/ {
                if ($request_method = DELETE) {
                        return 403;
                }

                proxy_pass http://backend;
                proxy_http_version 1.1;
                proxy_set_header Connection "";
                proxy_buffering off;
        }
}
```
