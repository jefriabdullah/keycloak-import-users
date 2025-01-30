#!/bin/bash

### Env
#source .staging_env
source .prod_env

#### Globals

access_token=""
refresh_token=""
userid=""
client_role_name="AUTH_CONTEXT_CCTOOL"


#### Helpers
process_result() {
  expected_status="$1"
  result="$2"
  msg="$3"
  out_result="$4"

  #err_msg=${result% *}
  err_msg=$(echo ${out_result} | grep -Eo '"errorMessage":.*?[^\\]"')
  actual_status=${result##* }

  printf "[HTTP $actual_status] $msg "
  if [ "$actual_status" == "$expected_status" ]; then
    echo "successful"
    return 0
  else
    echo "failed " ${err_msg}
    #echo -e "\t$err_msg"
    return 1
  fi
}

kc_login() {

  result=$(curl --write-out " %{http_code}" -s -k -X POST \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${client_id}" \
    --data-urlencode "client_secret=${client_secret}" \
    --data-urlencode "grant_type=client_credentials" \
    "${base_url}/realms/${realm}/protocol/openid-connect/token")

  msg="Login"
  process_result "200" "$result" "$msg"
  if [ $? -ne 0 ]; then
    echo "Please correct error before retrying. Exiting."
    exit 1  #no point continuing if login fails
  fi

  # Extract access_token
  access_token=$(sed -E -n 's/.*"access_token":"([^"]+)".*/\1/p' <<< "$result")
  #echo ${access_token}
  refresh_token=$(sed -E -n 's/.*"refresh_token":"([^"]+)".*/\1/p' <<< "$result")

  cc_tool_role=$(curl -s -k -X GET $base_url/admin/realms/$realm/clients/${ph_celcom_uuid}/roles/${client_role_name} \
  --header "Authorization: Bearer $access_token")
  if [ $? -ne 0 ]; then
    exit 1;
  fi

}

kc_create_user() {
  firstname="$1"
  lastname="$2"
  username="$3"
  email="$3"
  password="$4"

  result=$(curl --write-out " %{http_code}" -i -s -k --request POST \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $access_token" \
  --data '{
    "enabled": "true",
    "username": "'"$username"'",
    "email": "'"$email"'",
    "firstName": "'"$firstname"'",
    "lastName": "'"$lastname"'",
    "credentials": [{ 
      "type": "password", 
      "value": "'"$password"'", 
      "temporary": "false" 
      }] 
  }' "$base_url/admin/realms/$realm/users")

  # userid=$(echo "$result" | grep -o "Location: .*" | egrep -o '[a-zA-Z0-9]+(-[a-zA-Z0-9]+)+') #parse userid
  # userid=`echo $userid | awk '{ print $2 }'`
  http_code=$(sed -E -n 's,HTTP[^ ]+ ([0-9]{3}) .*,\1,p' <<< "$result") #parse HTTP coded
  output=$(echo ${result} | grep -Eo '"errorMessage":.*?[^\\]"')

  # printf "\n"
  # echo $result
  # printf "\n"
  # echo $http_code
  # printf "\n"

  kc_lookup_username $username
  msg="$username: insert ($userid)"
  process_result "201" "$http_code" "$msg" "${output}" | tee -a import-$(date +'%Y%m%d').log 
  return $? #return status from process_result
}

kc_delete_user() {
  userid="$1"

  result=$(curl --write-out " %{http_code}" -s -k --request DELETE \
  --header "Authorization: Bearer $access_token" \
  "$base_url/admin/realms/$realm/users/$userid")

  msg="$username: delete"
  process_result "204" "$result" "$msg"
  return $? #return status from process_result
}

# Convert name to uuid  setting  global userid ( This should really return etc. )
kc_lookup_username() {
  username="$1"

  result=$(curl --write-out " %{http_code}" -k -s --request GET \
  --header "Authorization: Bearer $access_token" \
  "$base_url/admin/realms/$realm/users?username=${username}")

  # echo "\n"
  # echo $result
  # echo "\n"

  userid=`echo $result | grep -Eo '"id":.*?[^\\]"' | cut -d':'  -f 2 | cut -d','  -f 1 | sed -e 's/"//g'`
  
  msg="$username: lookup "
  #process_result "200" "$result" "$msg"
  return $? #return status from process_result
  
}

kc_set_group_hard() {
  userid="$1"



  result=$(curl --write-out " %{http_code}" -s -k -X POST \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $access_token" \
   "$base_url/admin/realms/$realm/users/$userid/role-mappings/clients/${ph_celcom_uuid}" \
   --data "[${cc_tool_role}]")

   
  msg="$username: group $groupid set"
  process_result "204" "$result" "$msg"
  return $? #return status from process_result
}


kc_logout() {
  result=$(curl --write-out " %{http_code}" -s -k --request POST \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --data "client_id=$client_id&refresh_token=$refresh_token" \
  "$base_url/realms/$realm/protocol/openid-connect/logout")

  msg="Logout"
  process_result "204" "$result" "$msg" #print HTTP status message
  return $? #return status from process_result
}

## Unit tests for helper functions
# Use this to check that the helper functions work
unit_test() {
  echo "Testing normal behaviour. These operations should succeed"
  kc_login
  kc_create_user Jefri Abdullah jefri.abdullah jefri.abdullah@example.com test
  #kc_set_pwd $userid ":Frepsip4"
  kc_set_group_hard $userid 
  kc_delete_user $userid 
  kc_logout

}

## Bulk import accounts
# Reads and creates accounts using a CSV file as the source
# CSV file format: "first name, last name, username, email, password"
import_accts() {
  kc_login

  # Import accounts line-by-line
  while read -r line; do
    IFS=',' read -ra arr <<< "$line"

    kc_create_user "${arr[0]}" "${arr[1]}" "${arr[2]}" "${arr[3]}" "${arr[4]}"

    [ $? -ne 0 ] || kc_set_group_hard "$userid" "${arr[5]}" #skip if kc_create_user failed
  done < "$csv_file"

  #kc_logout
}

delete_accts(){

        kc_login
  while read -r line; do
    IFS=',' read -ra arr <<< "$line"
          kc_lookup_username "${arr[2]}"
          kc_delete_user $userid
  done < "$csv_file"
 
}

#### Main
if [ $# -lt 1 ]; then
  echo "Keycloak account admin script"
  echo "Usage: $0 [--test | --delete | --import csv_file]"
  exit 1
fi

flag=$1

case $flag in
  "--test" )
    unit_test
    ;;
        "--delete" )
    csv_file="$2"
    if [ -z "$csv_file" ]; then
      echo "Error: missing 'csv_file' argument"
      exit 1
    fi
    delete_accts $csv_file
    ;;
        "--lookup" )
          kc_login
                ;;
  "--import")
    csv_file="$2"
    if [ -z "$csv_file" ]; then
      echo "Error: missing 'csv_file' argument"
      exit 1
    fi
    import_accts $csv_file
    ;;
  *)
    echo "Unrecognised flag '$flag'"
    exit 1
    ;;
esac

exit 0