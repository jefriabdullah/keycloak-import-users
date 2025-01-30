# Keycloak Import Users

## [import-users.sh](./import-users.sh) - Administer Keycloak accounts from the command-line
See [users.csv](./users.csv) for example format.
### Prerequisites in the Keycloak realm:
1. Create client (eg. keycloak_acct_admin) for this script. Access Type: public.
1. Add the realm admin user (eg. realm_admin) to the realm
1. In the realm admin user's settings > Client Role > "realm-management", assign it all available roles
1. In realm, enable Direct Grant API at Settings > Login

### Env File
Example of .env_prod. You should find the correct .env_prod on the documentation handed to you.
```sh
base_url="https://url.of.keycloak"
realm="ph-celcom"
client_id="kc_user_import_script"
client_secret="redacted"
ph_celcom_uuid="redacted"
```

### Import users found in csv
```sh
$ ./import-users.sh --import users.csv
```

### Delete users found in csv
```sh
$ ./import-users.sh --import users.csv
```
