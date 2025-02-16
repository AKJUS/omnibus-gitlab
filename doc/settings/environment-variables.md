---
stage: Systems
group: Distribution
info: To determine the technical writer assigned to the Stage/Group associated with this page, see https://handbook.gitlab.com/handbook/product/ux/technical-writing/#assignments
title: Setting custom environment variables
---

{{< details >}}

- Tier: Free, Premium, Ultimate
- Offering: GitLab Self-Managed

{{< /details >}}

If necessary you can set custom environment variables to be used by Puma,
Sidekiq, Rails and Rake via `/etc/gitlab/gitlab.rb`. This can be useful in
situations where you need to use a proxy to access the internet and need to
clone externally hosted repositories directly into GitLab. In
`/etc/gitlab/gitlab.rb` supply a `gitlab_rails['env']` with a hash value. For
example:

```ruby
gitlab_rails['env'] = {
    "http_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080",
    "https_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080"
#    "no_proxy" => ".yourdomain.com"  # Wildcard syntax if you need your internal domain to bypass proxy
}
```

You can also override environment variables from other GitLab components which
might be required if you are behind a proxy:

```ruby
# Needed for proxying Git clones
gitaly['env'] = {
    "http_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080",
    "https_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080"
}

gitlab_workhorse['env'] = {
    "http_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080",
    "https_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080"
}

gitlab_pages['env'] = {
    "http_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080",
    "https_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080"
}

# If you use the docker registry
registry['env'] = {
    "http_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080",
    "https_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080"
}
```

GitLab will attempt to use HTTP Basic Authentication when a username and password is included in the proxy URL.

Proxy settings use the `.` syntax for globing.

Proxy URL values should generally be `http://` only, unless
your proxy has its own SSL certificate and SSL enabled. This means, even for
the `https_proxy` value, you should usually specify a value as
`http://<USERNAME>:<PASSWORD>@example.com:8080`.

{{< alert type="note" >}}

DNS rebind protection is disabled when either the HTTP_PROXY or the HTTPS_PROXY environment variable is set,
and the domain DNS can't be resolved.

{{< /alert >}}

## Applying the changes

Any change made to the environment variables requires a reconfigure for it
to take effect.

Perform a reconfigure:

```shell
sudo gitlab-ctl reconfigure
```

## Troubleshooting

### An environment variable is not being set

Check that you don't have multiple entries for the same `['env']`. The last one will override
previous entries. In this example, `NTP_HOST` will not be set:

```ruby
gitlab_rails['env'] = { 'NTP_HOST' => "<DOMAIN_OF_NTP_SERVICE>" }

gitlab_rails['env'] = {
    "http_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080",
    "https_proxy" => "http://<USERNAME>:<PASSWORD>@example.com:8080"
}
```

### Error: `Connection reset by peer` when mirroring repositories

If the `no_proxy` value includes port numbers in the URLs, it may cause DNS resolution failures. Remove any port numbers from the `no_proxy` URLs to resolve this issue.
