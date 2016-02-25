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

```
---
agent:
  uri:
    - http+rest://localhost:8080
```

```
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

```
---
zonalizer:
  db_driver: CouchDB
  db_conf:
    uri: http://localhost:5984/zonalizer
```
