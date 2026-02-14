vcl 4.1;

backend default {
    .host = "edge-cache-api";
    .port = "3000";
    .connect_timeout = 5s;
    .first_byte_timeout = 10s;
    .between_bytes_timeout = 2s;
}

sub vcl_recv {
    # Handle PURGE requests (invalidation)
    if (req.method == "PURGE") {
        # Validate purge token
        # NOTE: test-purge-token is a deployment-time placeholder; replace via env/templating with a strong secret for each environment.
        if (req.http.X-Purge-Token != "test-purge-token") {
            return (synth(401, "Unauthorized"));
        }
        
        # BAN by product ID from URL if present
        if (req.url ~ "^/product/") {
            ban(req.url ~ "^/product/");
            return (synth(200, "Purged"));
        }
        
        # BAN all cacheable content if no specific URL
        ban("obj.http.url ~ ^/");
        return (synth(200, "Purged"));
    }

    # Bypass cache for non-cacheable endpoints
    if (req.url ~ "^/(cart|account)") {
        set req.http.X-Pass = "true";
        return (pass);
    }

    # Bypass cache if session cookie is present
    if (req.http.Cookie ~ "session") {
        set req.http.X-Pass = "true";
        return (pass);
    }

    # Only cache GET and HEAD requests
    if (req.method != "GET" && req.method != "HEAD") {
        set req.http.X-Pass = "true";
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
    if (req.http.X-Pass) {
        set resp.http.X-Cache = "PASS";
    } elsif (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }

    # Add hit count for debugging
    set resp.http.X-Cache-Hits = obj.hits;
}
