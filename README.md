# conjur-poc-add-host
Script written to add hosts to Conjur POC Environment

# Execution
Intended to be ran after deploying a Conjur POC Environment using the script located at https://github.com/strick-j/conjur-poc
1. Clone the repository
2. Copy the script to your conjur-cli docker container and place withing the /policy folder (e.g. docker cp add-host.sh conjur-cli:/policy/add-host.sh)
3. Execute the script (e.g. ./add-host.sh)

# Notes
Script will prompt user for three inputs:
1. Hostname
2. CI Secret Access (Y/N)
3. CD Secret Access (Y/N)
