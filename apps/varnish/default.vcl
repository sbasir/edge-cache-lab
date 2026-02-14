vcl 4.1;

backend default {
    .host = "api";
    .port = "3000";
}

sub vcl_recv {
    # Bypass cache for non-cacheable endpoints
    if (req.url ~ "^/(cart|account)") {
        return (pass);
    }

    # Bypass cache if session cookie is present
    if (req.http.Cookie ~ "session") {
        return (pass);
    }

    # Only cache GET and HEAD requests
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    return (hash);
}

sub vcl_backend_response {
    # Set TTL for cacheable responses
    if (beresp.status == 200) {
        set beresp.ttl = 2m;
    }
}

sub vcl_deliver {
    # Add X-Cache header to indicate cache status
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }

    # Add hit count for debugging
    set resp.http.X-Cache-Hits = obj.hits;
}
