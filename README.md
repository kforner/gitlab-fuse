Gitlab virtual filesystem
=========================


## setup

install libfuse-dev
```
sudo apt install libfuse-dev
# depending on the system
sudo adduser karl fuse
# then logout/login

# maybe
sudo apt install libhttp-headers-fast-perl
```

install those perl modules:

  - Test::Pod
  - GitLab::API::v3
  - Smart::Comments
  - Fuse
  - Memoize

```
sudo cpanm Cookie::Baker
sudo cpanm GitLab::API::v3
sudo cpanm Role::REST::Client
sudo cpanm HTTP::Entity::Parser
sudo cpanm GitLab::API::v3

```

## authentication

### using a gitlab access token

in gitlab UI, go to your profile settings, then Access Tokens.
  - Enter a name
  - check "access your API"
  - then click "Create Personal Acess Token"

## usage

The easiest way is to define the following env vars:

  - GITLAB_API_V3_URL: your GitLab API v3 API base. Typically this will be something like http://git.example.com/api/v3.
  - GITLAB_API_V3_TOKEN: The API token to access the API with.





