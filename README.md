# API v1

This describes the API version 1 for Zonalizer.  The URLs in this description
assumes that Lim operates without any prefixes and all structure examples are
in JSON.

## Data Model Overview

The data model is structured with a top level object called `analyze` which
contains information about the DNS tests that has been performed for a fully
qualified domain name (FQDN).

## Data Types

The following data types are used:

* `uuid`: A version 4 UUID.
* `string`: An UTF8 string.
* `integer`: A signed big integer.
* `float`: A float.
* `href`: An URL pointing to another object or objects as according to HATEOAS.
* `datetime`: An UTC Unix Timestamp integer.

## HATEOAS

By default all URLs are HATEOAS but it can be disable via configuration or by
setting `base_url` to false (0) in the request for any call that returns objects
with URLs.

Example:

```
GET /zonalizer/1/analysis?base_url=0
```

## Pagination

All calls returning a list of objects will have the capabilities to return
paginated result using cursors.

The following URI query string options can be used:

* `limit`: This is the number of individual objects that are returned in each
  page, default and max limit is configurable.
* `before`: This is the cursor that points to the start of the page of data that
  has been returned.
* `after`: This is the cursor that points to the end of the page of data that
  has been returned.
* `sort`: The field name in the corresponding objects being returned that the
  result should be sorted on.
* `direction`: The direction of the result in conjunction with `sort`, can be
  `ascending` or `descending`.  Default is ascending.

Example:

```
GET /zonalizer/1/analysis?limit=100&after=cursor
GET /zonalizer/1/analysis?limit=10&sort=created&direction=descending
```

For each paginated result the following object is also included:

```
{
  ...
  "paging": {
    "cursors": {
      "after": "string",
      "before": "string"
    },
    "previous": "href",
    "next": "href"
  }
}
```

* `before`: This is the cursor that points to the start of the page of data that
  has been returned.
* `after`: This is the cursor that points to the end of the page of data that
  has been returned.
* `next`: The full API query that will return the next page of data.  If not
  included, this is the last page of data.
* `previous`: The full API query that will return the previous page of data.
  If not included, this is the first page of data.

## Configuration

Following configuration parameters exists and can be configured via Lim's YAML
config files.

### zonalizer

The following paramters can be configured below the root entry `zonalizer`.

#### base_url

A bool that controls if the base URL is included in the HATEOAS output.

#### custom_base_url

A string with a custom base URL that will be used if `base_url` is true, this
is helpful if Zonalizer is run behind load balancer or session divider.

#### db_driver

A string with the database driver to use.

#### db_conf

A hash this the database driver configuration, see Database Configuration.

#### default_limit

An integer with the default number of objects to return for calls that return
a list of objects.

#### max_limit

An integer with the maximum number of objects to return for calls that return
a list of objects, the given `limit` may not be larger then this and if it is
then the limit will be `max_limit`.

### Configuration example with defaults

```
---
zonalizer:
  base_url: 1
  db_driver: Memory
  default_limit: 10
  max_limit: 10
```

## Calls

### GET /zonalizer/1/version

Get the version of Zonalizer.

```
{
  "version": "string"
}
```

### GET /zonalizer/1/status

Get status about API and analysis.

```
{
   "api" : {
      "requests" : 501,
      "errors" : 0
   },
   "analysis" : {
      "ongoing" : 0,
      "completed" : 5,
      "failed" : 0
   }
}
```

* `api.requests`: The number of API requests processed, this includes any kind
  of API call.
* `api.errors`: The number of API errors.
* `analysis.ongoing`: Number of currently ongoing analysis.
* `analysis.completed`: Number of completed analysis.
* `analysis.failed`: Number of failed analysis.

### GET /zonalizer/1/analysis[?results=bool&lang=string]

Get a list of all analysis that exists in the database for Zonalizer.
See `analyze` under Objects for description of the analyze object.

```
{
  "analysis": [
    analyze,
    analyze,
    ...
  ],
  "paging": ...
}
```

* `results`: If true (1), include `results` in the `analyze` objects in the
  response. Default false (0).
* `lang`: Specify the language to use when generating the `message` in the
  `result` object and in the `error` object, default en_US.UTF-8.

### DELETE /zonalizer/1/analysis

Delete all analysis.  Returns HTTP Status 2xx on success and 4xx/5xx on error.

### GET /zonalizer/1/analysis?search=string[&results=bool&lang=string]

Search for analysis which FQDN matches the given string.  If prefixed with a dot
then all subdomains are returned.  For example `.com` will return all analysis
ending with `.com` but `example.com` will only return analysis for that FQDN.
See `analyze` under Objects for description of the analyze object.

```
{
  "analysis": [
    analyze,
    analyze,
    ...
  ],
  "paging": ...
}
```

* `search`: A string with the domainname to search for.  If prefixed with a dot,
  matches all ending with the string.
* `results`: If true (1), include `results` in the `analyze` objects in the
  response. Default false (0).
* `lang`: Specify the language to use when generating the `message` in the
  `result` object and in the `error` object, default en_US.UTF-8.

### POST /zonalizer/1/analysis?fqdn=string

Initiate a new test for a given zone.  See `analyze` under Objects for
description of the analyze object.

* `fqdn`: A string with the FQDN to analyze.

### GET /zonalizer/1/analysis/:id[?results=bool&lang=string]

Get information about an analyze.  See `analyze` under Objects for description
of the analyze object.

* `results`: If true (1), include `results` in the `analyze` objects in the
  response. Default true (1).
* `lang`: Specify the language to use when generating the `message` in the
  `result` object and in the `error` object, default en_US.UTF-8.

### GET /zonalizer/1/analysis/:id/status

Only get status information about an analyze, this call is optimal for polling.

```
{
  "status": "string",
  "progress": integer,
}
```

* `status`: The status of the check, see Check Statuses.
* `progress`: The progress of the check as an integer with the percent of
  completion.

### DELETE /zonalizer/1/analysis/:id

Delete an analyze.  Returns HTTP Status 2xx on success and 4xx/5xx on error.

## Objects

### analyze

The main analyze object which may include all results from Zonemaster.

```
{
  "id": "uuid",
  "fqdn": "string",
  "status": "string",
  "error": error,
  "progress": integer,
  "created": datetime,
  "updated": datetime,
  "results": [
    result,
    result,
    ...
  ]
}
```

* `id`: The UUID of the analyze.
* `fqdn`: The FQDN of the analyze.
* `status`: The status of the check, see Check Statuses.
* `error`: An object describing an error, see `error` under Objects.  (optional)
* `progress`: The progress of the check as an integer with the percent of
  completion.
* `created`: The date and time of when the object was created.
* `updated`: The date and time of when the object was last updated.
* `results`: An array containing `result` objects.  (optional)

### error

An object describing an error.

```
{
  "code": "string",
  "message": "string"
}
```

* `code`: A string with the error code, see Analyze Errors.
* `message`: A textual description of the error.

### result

A result object which is taken unprocessed from Zonemaster, description here may
vary depending on the version of Zonemaster you are running.

This documentation corresponds to version 1.0.7 of Zonemaster.

```
{
  "_id": integer,
  "args": {
    ...
  },
  "level": "string",
  "module": "string",
  "tag": "string",
  "timestamp": float,
  "message": "string"
}
```

* `_id`: A basic counter for each result object in the set, starts at zero (0).
  This is an additional paramter which is added by Zonalizer.
* `args`: An object with the arguments used for the specific result.
* `level`: The serverity of the result, see Result Levels.
* `module`: The Zonemaster module that produced the result.
* `tag`: A describing tag of the result, this is used by Zonemaster to generate
  the message.
* `timestamp`: A timestamp for when the result was generated, this is a float
  value of the number of seconds since the start of the analysis.
* `message`: A describing message of the result.

## Analyze Statuses

* `queued`: indicates that the analyze has been queued and waiting on a worker
  to start processing it.
* `analyzing`: indicates that the analyze has been taken up by a worker and its
  processing it.
* `done`: indicates that the analyze is done and results are available.
* `failed`: indicates that the analyze failed, check `error` and `results` for
  an `error` why it failed.
* `stopped`: indicates that the analyze was stopped, check `error` and `results`
  for an `error` why it was stopped.

## Result Levels

The following result levels can be given by Zonemaster, please see Zonemaster
documentation for more details.

- DEBUG3
- DEBUG2
- DEBUG
- INFO
- NOTICE
- WARNING
- ERROR
- CRITICAL

## Errors

Errors that are related to the communication with the API are returned as JSON
in a `Lim::Error` format and other errors which are related to the processing
of analysis are set in the `error` object.

For example this is a internal server error (500):

```
{
  "Lim::Error" : {
    "module" : "Lim::Plugin::Zonalizer::Server",
    "code" : 500,
    "message" : null
  }
}
```

### API Errors

These errors are returned as a string in the `message` value or in logs.

#### duplicate_id_found

A duplicated id was found.

#### id_not_found

The requested id was not found.

#### revision_missmatch

The revision of the object missmatched, the object was most likely updated
out of scope.

#### invalid_limit

An invalid limit was supplied, limit may not be less then 0 and more the
`max_limit`.

#### invalid_sort_field

An invalid field was supplied in the `sort` parameter.

#### internal_database_error

An internal database error, see logs for more information.

#### invalid_after

An invalid `after` parameter was supplied.

#### invalid_before

An invalid `before` parameter was supplied.

### HTTP Errors

These are the HTTP status errors returned, additional errors may be returned
from the framework.

#### 400 BAD REQUEST

Indicates that the requested limit, sort field or URL (for a new check) is
invalid.  See `message` for the corresponding API error.

#### 404 NOT FOUND

Indicates that the requested id was not found, see `message` for the
corresponding API error.

#### 500 INTERNAL SERVER ERROR

Indicates that an internal error occurred, more detailed information can be
found in the logs.

This error also occurs when the framework's input and output data validation
checks fail, see logs for detailed information.

### Analyze Errors

TODO

# LICENSE AND COPYRIGHT

Copyright 2015 Jerry Lundström

Copyright 2015 IIS (The Internet Foundation in Sweden)

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
