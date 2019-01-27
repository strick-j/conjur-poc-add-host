#!/bin/bash

function main(){
  prompt_user
  update_root_policy 
  generate_new_policy
  update_app_permissions
  verify_access
}

# Generic output functions
print_head(){
  local white=`tput setaf 7`
  local reset=`tput sgr0`
  echo ""
  echo "==========================================================================="
  echo "${white}$1${reset}"
  echo "==========================================================================="
  echo ""
}
print_info(){
  local white=`tput setaf 7`
  local reset=`tput sgr0`
  echo "${white}INFO: $1${reset}"
  echo "INFO: $1" >> add-policy.log
}
print_success(){
  local green=`tput setaf 2`
  local reset=`tput sgr0`
  echo "${green}SUCCESS: $1${reset}"
  echo "SUCCESS: $1" >> add-policy.log
}
print_error(){
  local red=`tput setaf 1`
  local reset=`tput sgr0`
  echo "${red}ERROR: $1${reset}"
  echo "ERROR: $1" >> add-policy.log
}
print_warning(){
  local yellow=`tput setaf 3`
  local reset=`tput sgr0`
  echo "${yellow}WARNING: $1${reset}"
  echo "WARNING: $1" >> add-policy.log
}

prompt_user(){
  print_head "Step 1: Gathering user info"
  touch add-policy.log
  # Obtain system name
  done=0
  while : ; do
    read -p 'Please enter the system name to add to Conjur: ' systemvar
    print_info "You entered $systemvar, is this correct (Yes or No)? "
    select yn in "Yes" "No"; do
      case $yn in 
        Yes ) done=1; break;;
        No ) echo ""; break;; 
      esac
    done
    if [[ "$done" -ne 0 ]]; then
	break
    fi
  done
  print_success "Required information gathered"
}

update_root_policy(){
  print_head "Step 2: Updating rool policy"
  echo "" >> root.yml
  echo "- !policy" >> root.yml
  echo "  id: $systemvar" >> root.yml
  echo "  owner: !group admins" >> root.yml
  print_info "Root policy file updated"
  
  # Update Conjur Policy
  conjur policy load --replace root root.yml >> add-policy.log 2>&1
  print_success "Conjur root policy updated"
}

generate_new_policy(){
  print_head "Step 3: Generating new policy"
  # Create new policy file
  touch ${systemvar}.yml 2>&1
  # Update new policy file
  echo "- !layer" >> ${systemvar}.yml
  echo "" >> ${systemvar}.yml
  echo "- !host $systemvar" >> ${systemvar}.yml
  echo "" >> ${systemvar}.yml
  echo "- !grant" >> ${systemvar}.yml
  echo "  role: !layer" >> ${systemvar}.yml
  echo "  member: !host $systemvar" >> ${systemvar}.yml
  # Load new policy
  conjur policy load $systemvar ${systemvar}.yml >> ${systemvar}.identity 2>&1
  print_info "$systemvar name and api information stored in $PWD/${systemvar}.identity file"
  print_success "$systemvar policy generated and loaded"
}

update_app_permissions(){
  print_head "Step 4: Updating app permissions"
  # Determine if system needs access to CI secrets
  print_info "Does $systemvar need access to CI secrets?"
  select yn in "Yes" "No"; do
    case $yn in 
      Yes ) 
        civar=1
        print_info "$systemvar will be able to access CI secrets"
        # echo "" >> apps.yml
        echo "" >> secrets.yml
        echo "- !permit" >> secrets.yml
        echo "  role: !layer /$systemvar " >> secrets.yml
        echo "  privileges:" >> secrets.yml
	      echo "     - read" >> secrets.yml
	      echo "     - execute" >> secrets.yml
        echo "  resource: *ci-secrets" >> secrets.yml
        break
        ;;
      No )
        print_warning "$systemvar will not be able to access CI secrets"
        break
        ;; 
    esac
  done
  echo ""
  # Determine if system needs access to CD Secrets
  print_info "Does $systemvar need access to CD secrets?"
  select yn in "Yes" "No"; do
    case $yn in 
      Yes )
        cdvar=1
	      print_info "$systemvar will be able to access CD secrets"
        echo "" >> secrets.yml
        echo "- !permit" >> secrets.yml
        echo "  role: !layer /$systemvar " >> secrets.yml
        echo "  privileges:" >> secrets.yml
	      echo "     - read" >> secrets.yml
	      echo "     - execute" >> secrets.yml
        echo "  resource: *cd-secrets" >> secrets.yml
        break
        ;;
      No )
        print_warning "$systemvar will not be able to access CD secrets"
        break
        ;; 
    esac
  done
  echo ""
  print_info "Updating $systemvar secrets access policy"
  conjur policy load --replace apps/secrets secrets.yml >> add-policy.log 2>&1
  print_info "Verifying $systemvar secrets access"
  local test=$(conjur resource permitted_roles variable:apps/secrets/ci-variables/puppet_secret read)
  if [[ $civar == 1 ]]; then
    echo $test | grep $systemvar/$systemvar -q
    if [[ $? == 0 ]]; then
       print_success "$systemvar can read CI Secrets"
    else
       print_error "$systemvar can not CI Secrets, exiting..."
       exit 1
    fi
  fi
  local test=$(conjur resource permitted_roles variable:apps/secrets/cd-variables/kubernetes_secret read)
  if [[ $cdvar == 1 ]]; then
    echo $test | grep $systemvar/$systemvar -q
    if [[ $? == 0 ]]; then
       print_success "$systemvar can read CD Secrets"
    else
       print_error "$systemvar can not read CD Secrets, exiting..."
       exit 1
    fi
  fi
  print_success "Secrets access policy updated"
}
verify_access(){
  print_head "Testing secret access based CI/CD choices"
  # Test access to CI Secret
  if [[ $civar == 1 ]]; then
    print_info "Attempting to access CI Secret"
    local conjurCert="/root/conjur-cyberark.pem"
    local hostname=$(cat ~/.netrc | awk '/machine/ {print $2}')
    local hostname=${hostname%/authn}
    local api_key=$(awk '/api_key/ {print $2}' $PWD/${systemvar}.identity)
    local api_key=$(sed -e 's/^"//' -e 's/"$//' <<<"$api_key")
    local secret_name="apps/secrets/ci-variables/chef_secret"
    local auth=$(curl -s --cacert $conjurCert -H "Content-Type: text/plain" -X POST -d "${api_key}" $hostname/authn/cyberark/host%2F$systemvar%2F$systemvar/authenticate)
    local auth_token=$(echo -n $auth | base64 | tr -d '\r\n')
    local secret_retrieve=$(curl --cacert $conjurCert -s -X GET -H "Authorization: Token token=\"$auth_token\"" $hostname/secrets/cyberark/variable/$secret_name)
    echo ""
    print_success "Secret is: $secret_retrieve"
    echo ""
  fi
  # Test access to CD secrets 
  if [[ $cdvar == 1 ]]; then
    print_info "Attempting to access CD Secret"
    local secret_name="apps/secrets/cd-variables/kubernetes_secret"
    local auth=$(curl -s --cacert $conjurCert -H "Content-Type: text/plain" -X POST -d "${api_key}" $hostname/authn/cyberark/host%2F$systemvar%2F$systemvar/authenticate)
    local auth_token=$(echo -n $auth | base64 | tr -d '\r\n')
    local secret_retrieve=$(curl --cacert $conjurCert -s -X GET -H "Authorization: Token token=\"$auth_token\"" $hostname/secrets/cyberark/variable/$secret_name)
    echo ""
    print_success "Secret is: $secret_retrieve"
    echo ""
  fi
}
main
